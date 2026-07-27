#!/usr/bin/env bash
# List what changed against the base branch, ranked by risk, one file per line.
#
# The ranking is the part that matters. A small model asked to "decide what to
# read" will read the first thing it sees; handed an ordered queue it reads the
# right thing. Risk order is computed here from paths and diff content, so the
# model never makes that call.
#
#   changed.sh [base]   default: baseBranch from .devskills/profile.json, else main
#
# Output: "<rank> <status> <path>" — rank 1 is highest risk. Read top-down and
# stop when the budget is spent.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE="$(sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null)"
fi
[ -z "$BASE" ] && BASE="$(bash "$HERE/profile.sh" >/dev/null 2>&1; sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null)"
[ -z "$BASE" ] && BASE=main

if ! git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
  echo "ERROR: base branch '$BASE' does not exist" >&2
  exit 1
fi

CURRENT="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ "$CURRENT" = "$BASE" ]; then
  echo "ERROR: you are on '$BASE' — switch to your branch first" >&2
  exit 2
fi

# Committed changes plus anything not yet committed. Reviewing only what is
# committed misses the half you were about to commit.
# A rename reaches us in two different shapes, and both used to yield a string that
# is not a path — "old.php -> new.php". Everything downstream then quietly skipped
# it: lint.sh tests [ -f "$file" ], and the model was told to read a file that does
# not exist. Moving a class is precisely the change that most needs reviewing, so
# both shapes are normalised to the destination path here.
#
#   git diff --name-status   R100 <tab> old <tab> new
#   git status --porcelain   "R  old -> new"
{
  git diff --name-status "$BASE"...HEAD 2>/dev/null \
    | awk -F'\t' '{ if ($1 ~ /^[RC]/ && NF >= 3) print substr($1,1,1) "\t" $3; else if (NF >= 2) print $1 "\t" $2 }'
  git status --porcelain 2>/dev/null \
    | sed 's/^ *//; s/^\([A-Z?]*\)[[:space:]]*/\1\t/; s/^\([A-Z?]*\)\t.* -> /\1\t/'
} | awk -F'\t' 'NF>=2 && $2!="" {print $1"\t"$2}' | sort -u -k2 > /tmp/devskills-changed.$$

if [ ! -s /tmp/devskills-changed.$$ ]; then
  echo "ERROR: no changes against '$BASE'" >&2
  rm -f /tmp/devskills-changed.$$
  exit 3
fi

rank_of() {
  file="$1"; status="$2"
  case "$file" in
    .devskills/*|.devskills) echo 99; return ;;   # our own cache, never part of the change
    vendor/*|node_modules/*|*/vendor/*|*/node_modules/*|*.min.js|*.min.css|amd/build/*) echo 9; return ;;
    *.lock|composer.lock|package-lock.json|yarn.lock) echo 6; return ;;
    *.md|*.txt|*.json|*.yml|*.yaml|lang/*) echo 7; return ;;
  esac

  # 1 — schema, money, grades, auth, downloads. Failures here are not recoverable.
  case "$file" in
    db/install.xml|db/upgrade.php|db/*.php|*migrations/*|*schema.sql|*/migrations/*) echo 1; return ;;
    *auth*|*permission*|*capabilit*|*login*|*password*|*token*) echo 1; return ;;
    *grade*|*payment*|*invoice*|*money*|*export*|*download*) echo 1; return ;;
  esac

  # 2 — modifications to code that already existed, which is where regressions live.
  if [ "$status" != "A" ] && [ "$status" != "??" ]; then
    case "$file" in *.php|*.py|*.js|*.ts|*.go) echo 2; return ;; esac
  fi

  # 3 — new loops, queries, or parsing of external input.
  if git show ":$file" >/dev/null 2>&1 || [ -f "$file" ]; then
    if grep -qsE 'foreach|while |for \(|SELECT |INSERT |UPDATE |DELETE |\$_(GET|POST|REQUEST)|json_decode|preg_match' "$file" 2>/dev/null; then
      echo 3; return
    fi
  fi

  # 5 — tests: read enough to judge what they actually prove.
  case "$file" in *test*|*Test*|*spec*) echo 5; return ;; esac

  echo 4
}

while IFS=$'\t' read -r status file; do
  [ -z "$file" ] && continue
  rank="$(rank_of "$file" "$status")"
  [ "$rank" = "99" ] && continue
  printf '%s %s %s\n' "$rank" "$status" "$file"
done < /tmp/devskills-changed.$$ | sort -n

rm -f /tmp/devskills-changed.$$
