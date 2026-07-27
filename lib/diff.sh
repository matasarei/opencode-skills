#!/usr/bin/env bash
# Print the diff against the base branch, capped.
#
# Capped on purpose: a 30B-class model handed 4000 lines of diff stops following
# instructions long before it runs out of context. Truncation is announced rather
# than silent, so the review can say what it did not see.
#
#   diff.sh [base] [max-lines]     default max: 600

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

BASE="${1:-}"
[ -z "$BASE" ] && BASE="$(sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null)"
[ -z "$BASE" ] && BASE=main
MAX="${2:-600}"

git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || { echo "base '$BASE' not found"; exit 1; }

EXCLUDE=". :(exclude)vendor :(exclude)node_modules :(exclude)*.lock :(exclude).devskills"

# Committed on this branch, then staged, then unstaged. Reviewing only what is
# committed misses the half you were about to commit.
#
# All three are measured together. Capping each separately and counting only the
# committed range meant an entirely uncommitted change — the ordinary case when
# reviewing before a commit — was truncated with nothing said about it.
ALL="$( { git diff "$BASE"...HEAD -- $EXCLUDE
          git diff --cached -- $EXCLUDE
          git diff -- $EXCLUDE
        } 2>/dev/null )"

if [ -z "$ALL" ]; then
  echo "[no diff against $BASE, staged or unstaged]"
  exit 0
fi

total="$(printf '%s\n' "$ALL" | wc -l | tr -d ' ')"
printf '%s\n' "$ALL" | head -n "$MAX"

if [ "$total" -gt "$MAX" ]; then
  echo ""
  echo "[TRUNCATED: showed $MAX of $total diff lines. $(( total - MAX )) not shown —"
  echo " read the remaining files from the queue individually, and say in the review"
  echo " which ones were judged from a partial diff.]"
fi
