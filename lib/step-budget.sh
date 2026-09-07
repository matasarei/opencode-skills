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
HERE="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "usage: step-budget.sh <task-file> <n> | --paths <path>..." >&2; exit 64; }

# The window: the environment wins, then the cached profile, then the default.
CTX="${DEV_SKILLS_CONTEXT:-}"
[ -z "$CTX" ] && CTX="$(sed -n 's/.*"contextTokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
case "$CTX" in ''|*[!0-9]*) CTX=100000 ;; esac
CAP=$(( CTX * 12 / 1000 ))

# The paths a step's Modify: and Test: lines name — what counts as a step and a
# path is lib/steps.awk. A path counts only if it exists: a Create: file or a
# prose fragment weighs nothing.
paths_of_step() { # paths_of_step <file> <n>
  any=0; grep -q '^## Steps' "$1" || any=1
  awk -v mode=paths -v n="$2" -v kinds="Modify Test" -v anywhere="$any" -f "$HERE/steps.awk" "$1" \
  | cut -d'|' -f2 | sort -u
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
    any=0; grep -q '^## Steps' "$FILE" || any=1
    awk -v mode=list -v anywhere="$any" -f "$HERE/steps.awk" "$FILE" | grep -q "^$N|" || { echo "no step $N in $FILE" >&2; exit 66; }
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
