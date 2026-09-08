#!/usr/bin/env bash
# Tick one step of a task file, and say what landed.
#
# /dev-implement used to do this by hand: find "N. [ ] title", rewrite it as
# "N. [x] title — what landed". It is the smallest edit in the cycle and the
# easiest to get subtly wrong, and when it goes wrong nothing complains — the
# step simply stays unticked, and the next run rebuilds what was just built.
#
#   tick.sh <task-file> <n> [<what landed>]
#
# Only the canonical shape is ticked: "N. [ ] title" under ## Steps, which is
# what /dev-plan writes and what steps.awk, task-step.sh, plan-check.sh and
# step-budget.sh all parse. A different shape is reported, not guessed at.
#
# Exit 0 ticked, 3 already ticked (not an error — say so and move on),
# 64 usage, 66 no such file or step.

set -u

FILE="${1:-}"; N="${2:-}"; NOTE="${3:-}"
usage() { echo "usage: tick.sh <task-file> <n> [<what landed>]" >&2; exit 64; }
[ -n "$FILE" ] || usage
case "$N" in ''|*[!0-9]*) usage ;; esac
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }

# The step header, by line number, so the note is appended to the right line even
# when a later step's title repeats the words.
HIT="$(grep -n "^${N}\. \[[ xX]\]" "$FILE" | head -1)"
if [ -z "$HIT" ]; then
  if grep -q "^${N}\. " "$FILE"; then
    echo "step $N in $FILE is not in the '$N. [ ] title' shape, so it was not ticked" >&2
    grep -n "^${N}\. " "$FILE" | head -1 >&2
  else
    echo "no step $N in $FILE" >&2
  fi
  exit 66
fi

LNO="${HIT%%:*}"
case "$HIT" in
  *"[x]"*|*"[X]"*)
    echo "step $N was already ticked — nothing to do"
    exit 3 ;;
esac

TMP="$FILE.tick.$$"
awk -v n="$LNO" -v note="$NOTE" '
  NR == n {
    sub(/\[ \]/, "[x]")
    if (note != "") $0 = $0 " — " note
  }
  { print }
' "$FILE" > "$TMP" && mv "$TMP" "$FILE" || { rm -f "$TMP"; echo "could not write $FILE" >&2; exit 66; }

sed -n "${LNO}p" "$FILE"
