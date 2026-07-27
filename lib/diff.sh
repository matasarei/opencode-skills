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
total="$(git diff "$BASE"...HEAD -- $EXCLUDE 2>/dev/null | wc -l | tr -d ' ')"

git diff "$BASE"...HEAD -- $EXCLUDE 2>/dev/null | head -n "$MAX"
git diff --cached -- $EXCLUDE 2>/dev/null | head -n 200
git diff -- $EXCLUDE 2>/dev/null | head -n 200

if [ "$total" -gt "$MAX" ]; then
  echo ""
  echo "[TRUNCATED: showed $MAX of $total diff lines. Read the remaining files individually.]"
fi
