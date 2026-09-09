#!/usr/bin/env bash
# Put this step on its own stacked branch.
#
# /dev-implement carried this as a two-branch fallback for the model to type:
#
#   git switch -c step/<slug>-<n> step/<slug>-<n-1> 2>/dev/null || \
#   git switch -c step/<slug>-<n> <baseBranch>
#
# The slug, the step number and the base are all derivable, pr-info.sh already
# derives them, and a model retyping a || chain gets the base wrong on exactly
# the branch where it matters — the stacked one.
#
#   branch.sh <task-file> <n>
#
# One line out:
#
#   BRANCH step/<slug>-3 — cut from step/<slug>-2
#   BRANCH step/<slug>-1 — cut from main
#   BRANCH step/<slug>-3 — already on it
#   BRANCH step/<slug>-3 — switched to it (it already existed)
#
# Exit 0 on the branch, 3 refused (uncommitted work that a switch would carry
# across), 64 usage, 66 no such file, 69 not a git repository.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"; N="${2:-}"
usage() { echo "usage: branch.sh <task-file> <n>" >&2; exit 64; }
[ -n "$FILE" ] || usage
case "$N" in ''|*[!0-9]*) usage ;; esac
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 69; }

SLUG="$(basename "$FILE")"; SLUG="${SLUG%.md}"
WANT="step/$SLUG-$N"

CURRENT="$(git branch --show-current 2>/dev/null)"
if [ "$CURRENT" = "$WANT" ]; then
  echo "BRANCH $WANT — already on it"
  exit 0
fi

# Switching carries uncommitted work to the new branch. That is how half of one
# step ends up in another step's pull request, so it is refused rather than
# resolved: the developer decides whether it belongs here.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "BRANCH refused — uncommitted changes would follow the switch to $WANT:" >&2
  git status --short 2>/dev/null | head -10 >&2
  echo "commit them, stash them, or say they belong to this step." >&2
  exit 3
fi

[ -f .devskills/profile.json ] || bash "$HERE/profile.sh" >/dev/null 2>&1
BASE="$(sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
[ -z "$BASE" ] && BASE=main

# Already cut on an earlier run: switch, never re-cut, or the step's own commits
# would be left behind on a branch nothing points at.
if git show-ref --verify --quiet "refs/heads/$WANT"; then
  git switch -q "$WANT" || exit 66
  echo "BRANCH $WANT — switched to it (it already existed)"
  exit 0
fi

# The previous step's branch is the base when there is one and it has not landed
# yet, so the pull requests stack; otherwise the repository's base branch.
#
# Existence is not enough. A merged step branch is not deleted, so it answers yes
# to "does it exist" while being exactly the wrong place to cut from: the new
# step starts behind the base, and its pull request opens against a branch nobody
# will merge again. That happened three times in one plan before this check.
FROM="$BASE"; WHY=""
if [ "$N" -gt 1 ]; then
  PREV="step/$SLUG-$((N - 1))"
  PREV_REF=""
  if git show-ref --verify --quiet "refs/heads/$PREV"; then
    PREV_REF="$PREV"
  elif git show-ref --verify --quiet "refs/remotes/origin/$PREV"; then
    PREV_REF="origin/$PREV"
  fi

  if [ -n "$PREV_REF" ]; then
    # Both refs, because either can be the one that is ahead: the local base
    # branch on a machine that has pulled, its remote-tracking copy on one that
    # has not.
    MERGED=no
    for base_ref in "$BASE" "origin/$BASE"; do
      git rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1 || continue
      if git merge-base --is-ancestor "$PREV_REF" "$base_ref" 2>/dev/null; then
        MERGED=yes
        break
      fi
    done

    if [ "$MERGED" = no ]; then
      FROM="$PREV"
    else
      # Say why, or the developer reads "cut from main" on step 5 as a bug.
      WHY=" ($PREV has already been merged)"
    fi
  fi
fi

git switch -q -c "$WANT" "$FROM" 2>/dev/null || {
  echo "BRANCH refused — could not cut $WANT from '$FROM'; does it exist?" >&2
  exit 66
}
echo "BRANCH $WANT — cut from $FROM$WHY"
