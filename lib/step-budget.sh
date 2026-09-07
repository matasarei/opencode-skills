#!/usr/bin/env bash
# Is this step small enough for one context?
#
# A step's whole cycle — build, review, fix, pull request — has to fit the
# window the profile's contextTokens assumes. The rule of thumb, measured on
# this repository at ~10 tokens a line and with the prompt, the diff and the
# review's re-read taken out: 12 lines of source per 1k tokens of window.
#
#   step-budget.sh <task-file> <n>      the files named by step n's Modify: and Test: lines
#   step-budget.sh --paths <path>...    the files given
#
# Prints one "<lines> <path>" line per file that exists, then the verdict:
#
#   Budget: 640/1200 lines — fits
#   Budget: 1900/1200 lines — OVER by 700, split if you can
#
# The cap is a recommendation, not a limit: the planner splits an OVER step when
# a split exists and otherwise keeps it and says why. Nothing refuses on it.
# Exit 0 fits, 1 over, 64 usage, 66 no such file or step.

set -u

usage() { echo "usage: step-budget.sh <task-file> <n> | --paths <path>..." >&2; exit 64; }

# The window: the environment wins, then the cached profile, then the default.
CTX="${DEV_SKILLS_CONTEXT:-}"
[ -z "$CTX" ] && CTX="$(sed -n 's/.*"contextTokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
case "$CTX" in ''|*[!0-9]*) CTX=100000 ;; esac
CAP=$(( CTX * 12 / 1000 ))

# Candidate paths from a step block: the Modify: and Test: lines, split on
# commas, backticks and brackets stripped, the "path:lines (symbol)" suffix cut.
# A token is a path only if it looks like one — it has a slash or a dot — and
# it counts only if it exists: a Create: file or a prose fragment weighs nothing.
paths_of_step() { # paths_of_step <file> <n>
  awk -v n="$2" '
    /^[0-9]+\. \[[ x]\]/ { inside = ($1 == n ".") }
    /^## / { inside = 0 }
    inside && /^[[:space:]]+- (Modify|Test):/ { sub(/^[[:space:]]+- (Modify|Test):[[:space:]]*/, ""); print }
  ' "$1" \
  | tr ',' '\n' | tr -d '`()' | sed 's/^[[:space:]]*//' | awk 'NF {print $1}' \
  | sed 's/:[0-9][0-9,-]*$//; s/:.*$//' \
  | grep -E '/|\.' | grep -v '^none$' | sort -u
}

case "${1:-}" in
  --paths)
    shift; [ $# -gt 0 ] || usage
    LIST="$(printf '%s\n' "$@")"
    ;;
  ''|-*) usage ;;
  *)
    FILE="$1"; N="${2:-}"
    [ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }
    case "$N" in ''|*[!0-9]*) usage ;; esac
    grep -qE "^$N\. \[[ x]\]" "$FILE" || { echo "no step $N in $FILE" >&2; exit 66; }
    LIST="$(paths_of_step "$FILE" "$N")"
    ;;
esac

used=0
while IFS= read -r p; do
  [ -n "$p" ] && [ -f "$p" ] || continue
  n="$(wc -l < "$p" | tr -d ' ')"
  printf '%s %s\n' "$n" "$p"
  used=$(( used + n ))
done <<EOF
$LIST
EOF

if [ "$used" -le "$CAP" ]; then
  printf 'Budget: %s/%s lines — fits\n' "$used" "$CAP"
  exit 0
fi
printf 'Budget: %s/%s lines — OVER by %s, split if you can\n' "$used" "$CAP" "$(( used - CAP ))"
exit 1
