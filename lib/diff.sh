#!/usr/bin/env bash
# Print the diff against the base branch, capped.
#
# Capped on purpose: a 30B-class model handed 4000 lines of diff stops following
# instructions long before it runs out of context. Truncation is announced rather
# than silent, so the review can say what it did not see.
#
#   diff.sh [base] [max-lines]     default max: 6 lines per 1k of context

set -u

BASE="${1:-}"
[ -z "$BASE" ] && BASE="$(sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null)"
[ -z "$BASE" ] && BASE=main
# The cap follows the window, the way step-budget.sh's does. This block is the
# largest thing any skill injects -- 600 lines is roughly 24,000 bytes, five
# times the prompt it arrives in -- and a fixed cap spends a sixth of a 32k
# session on it while leaving a 128k one half empty.
#
# Six lines per 1k, half of step-budget.sh's 12: the diff a review reads costs
# about what the step that produced it was budgeted. 128k gives 786, 64k 393,
# 32k 196 -- and the 100k fallback gives exactly the 600 this script has always
# used, so a repository that declares no window sees no change.
MAX="${2:-}"
if [ -z "$MAX" ]; then
  CTX="${DEV_SKILLS_CONTEXT:-}"
  [ -z "$CTX" ] && CTX="$(sed -n 's/.*"contextTokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
  case "$CTX" in ''|*[!0-9]*) CTX=100000 ;; esac
  MAX=$(( CTX * 6 / 1000 ))
fi
case "$MAX" in ''|*[!0-9]*|0) MAX=600 ;; esac

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
