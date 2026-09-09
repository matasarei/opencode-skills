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
#
# Exit 0 listed something, 1 no such base branch, 2 you are on the base branch,
# 3 nothing changed against it, 73 the scratch file could not be created. The
# last one was 1 until it had its own code, which made "the base branch does not
# exist" and "TMPDIR is not writable" indistinguishable to a caller.

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

# The scratch file: mktemp under TMPDIR, and a trap, matching verify-clean.sh.
# The old name was hardcoded to /tmp and derived from the process id, so the
# environment could not move it and anyone could guess it. The trap is also what
# makes the refusals below clean up: they each carried their own rm before, and
# an interrupted run carried none at all.
TMP="$(mktemp "${TMPDIR:-/tmp}/devskills-changed.XXXXXX" 2>/dev/null)" \
  || { echo "ERROR: cannot create a scratch file in '${TMPDIR:-/tmp}'" >&2; exit 73; }
trap 'rm -f "$TMP"' EXIT INT TERM

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
#
# -uall, because porcelain otherwise collapses an untracked directory to a single
# "?? dir/" entry. That entry is not a path either: lint.sh tests [ -f "$file" ]
# and skips it, the review is told to read a directory, and the guard refuses
# that read. A step whose files all land in a new directory was reviewed and
# linted as though it had changed nothing.
#
# core.quotePath=false on both calls, because git otherwise C-quotes any path
# holding a non-ASCII byte — "src/\347\256\200\345\216\206.php" for 简历.php — and
# that string is not a path either, so the file is dropped from the queue in
# silence. A path holding a literal quote, backslash or newline is still quoted;
# only -z would cover those, and it would cost the rename parsing below.
{
  git -c core.quotePath=false diff --name-status "$BASE"...HEAD 2>/dev/null \
    | awk -F'\t' '{ if ($1 ~ /^[RC]/ && NF >= 3) print substr($1,1,1) "\t" $3; else if (NF >= 2) print $1 "\t" $2 }'
  git -c core.quotePath=false status --porcelain -uall 2>/dev/null \
    | sed 's/^ *//; s/^\([A-Z?]*\)[[:space:]]*/\1\t/; s/^\([A-Z?]*\)\t.* -> /\1\t/'
} | awk -F'\t' 'NF>=2 && $2!="" {print $1"\t"$2}' | sort -u -k2 > "$TMP"

if [ ! -s "$TMP" ]; then
  echo "ERROR: no changes against '$BASE'" >&2
  exit 3
fi

rank_of() {
  file="$1"; status="$2"
  case "$file" in
    .devskills/*|.devskills) echo 99; return ;;   # our own cache, never part of the change
    vendor/*|node_modules/*|*/vendor/*|*/node_modules/*|*.min.js|*.min.css|amd/build/*) echo 9; return ;;
    # Build output. callers.sh already excludes these directories as noise; the
    # queue was still ranking them 4, so 300 generated files outranked the one
    # source file that changed and pushed it past the cap below.
    build/*|*/build/*|dist/*|*/dist/*|out/*|coverage/*|target/debug/*|target/release/*) echo 9; return ;;
    .next/*|.nuxt/*|.turbo/*|__pycache__/*|*.pyc|*.map) echo 9; return ;;
    *.lock|package-lock.json|pnpm-lock.yaml) echo 6; return ;;
    # Dependency manifests and CI, before the documentation rule below can claim
    # them: a changed dependency is somebody else's code entering the build, and
    # a changed workflow decides whether anything gets checked at all.
    package.json|composer.json|go.mod|go.sum|Cargo.toml|pyproject.toml|requirements.txt) echo 3; return ;;
    pom.xml|build.gradle|build.gradle.kts|Gemfile|mix.exs|*.csproj|Makefile) echo 3; return ;;
    .github/workflows/*|.gitlab-ci.yml|Jenkinsfile|Dockerfile|docker-compose*.y*ml|compose.y*ml) echo 3; return ;;
    *.md|*.txt|*.json|*.yml|*.yaml|lang/*) echo 7; return ;;
  esac

  # 1 — schema, money, grades, auth, downloads. Failures here are not recoverable.
  case "$file" in
    db/install.xml|db/upgrade.php|db/*.php|*migrations/*|*schema.sql) echo 1; return ;;
    *auth*|*permission*|*capabilit*|*login*|*password*|*token*) echo 1; return ;;
    *grade*|*payment*|*invoice*|*money*|*export*|*download*) echo 1; return ;;
  esac

  # 2 — modifications to code that already existed, which is where regressions live.
  if [ "$status" != "A" ] && [ "$status" != "??" ]; then
    case "$file" in
      *.php|*.py|*.js|*.ts|*.jsx|*.tsx|*.vue|*.svelte) echo 2; return ;;
      *.go|*.rs|*.rb|*.java|*.kt|*.kts|*.cs|*.swift|*.scala|*.ex|*.exs) echo 2; return ;;
      *.c|*.h|*.cc|*.cpp|*.hpp|*.m|*.mm|*.sh|*.bash|*.pl|*.lua|*.dart) echo 2; return ;;
    esac
  fi

  # 3 — new loops, queries, or parsing of external input.
  if git show ":$file" >/dev/null 2>&1 || [ -f "$file" ]; then
    # Loops and queries are near enough universal; the request-reading idioms are
    # not, and a PHP-only list quietly ranked every other stack's entry points 4.
    if grep -qsE 'foreach|while |for \(|for [a-zA-Z_]+ :?=|SELECT |INSERT |UPDATE |DELETE ' "$file" 2>/dev/null \
    || grep -qsE '\$_(GET|POST|REQUEST)|json_decode|preg_match|unserialize' "$file" 2>/dev/null \
    || grep -qsE 'request\.(args|form|GET|POST|body|query|params)|req\.(query|body|params)|JSON\.parse' "$file" 2>/dev/null \
    || grep -qsE 'r\.URL\.Query|r\.FormValue|os\.Getenv|json\.Unmarshal|params\[|@RequestParam' "$file" 2>/dev/null; then
      echo 3; return
    fi
  fi

  # 5 — tests: read enough to judge what they actually prove.
  case "$file" in *test*|*Test*|*spec*) echo 5; return ;; esac

  echo 4
}

# The queue is read into a prompt, so it needs the same discipline diff.sh has:
# capped, and the truncation announced rather than silent. An un-ignored build
# or vendor directory takes it from three lines to three hundred, and a 30B model
# handed three hundred lines of queue stops following the instructions above it.
#
# Rank 9 is vendored and build output — never part of the change — so a handful
# is listed and a pile is counted. Everything else is capped last-first, because
# the queue is ordered by risk and the tail is what matters least.
# The cap follows the context window, as diff.sh's does -- but at its own rate.
# A queue entry is one short line where a diff line is a line of source, so
# diff.sh's 6 per 1k would treble this queue rather than scale it. 2 per 1k keeps
# the 200 this script has always used at the 100k fallback, and gives 262 at
# 128k, 131 at 64k, 65 at 32k. DEV_SKILLS_QUEUE_CAP still wins over both.
CAP="${DEV_SKILLS_QUEUE_CAP:-}"
if [ -z "$CAP" ]; then
  CTX="${DEV_SKILLS_CONTEXT:-}"
  [ -z "$CTX" ] && CTX="$(sed -n 's/.*"contextTokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
  case "$CTX" in ''|*[!0-9]*) CTX=100000 ;; esac
  CAP=$(( CTX * 2 / 1000 ))
fi
case "$CAP" in ''|*[!0-9]*|0) CAP=200 ;; esac

while IFS=$'\t' read -r status file; do
  [ -z "$file" ] && continue
  rank="$(rank_of "$file" "$status")"
  [ "$rank" = "99" ] && continue
  printf '%s %s %s\n' "$rank" "$status" "$file"
done < "$TMP" | sort -n | awk -v cap="$CAP" '
  { line[NR] = $0; rank[NR] = $1; if ($1 == 9) nine++ }
  END {
    for (i = 1; i <= NR; i++) {
      if (rank[i] == 9 && nine > 5) { collapsed++; continue }
      if (++shown <= cap) print line[i]; else over++
    }
    if (collapsed) printf "[%d vendored or build file(s) not listed — rank 9, not part of the change]\n", collapsed
    if (over) printf "[TRUNCATED: %d more file(s) not listed. The queue is ordered by risk, so these are the lowest.]\n", over
  }
'

