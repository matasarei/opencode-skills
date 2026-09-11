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
# steps.awk does the ticking (mode=tick), so whatever shape the parser accepts
# is ticked the way the parser reads it: the box right after the number becomes
# "[x]", a header with no box there ("**3.** title", "### Step 3 — title",
# "1. Add [ ] rendering") gets " [x]" put after its number, and a box later in
# the title is left alone.
#
# Exit 0 ticked, 3 already ticked (not an error — say so and move on),
# 64 usage, 66 no such file or step.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"; N="${2:-}"; NOTE="${3:-}"
usage() { echo "usage: tick.sh <task-file> <n> [<what landed>]" >&2; exit 64; }
[ -n "$FILE" ] || usage
case "$N" in ''|*[!0-9]*) usage ;; esac
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }

# The step header, by line number, so the note is appended to the right line even
# when a later step's title repeats the words.
ANY=0; grep -q '^## Steps' "$FILE" || ANY=1
LNO="$(awk -v mode=lineno -v n="$N" -v anywhere="$ANY" -f "$HERE/steps.awk" "$FILE")"
[ -n "$LNO" ] || { echo "no step $N in $FILE" >&2; exit 66; }

TMP="$FILE.tick.$$"
awk -v mode=tick -v n="$N" -v note="$NOTE" -v anywhere="$ANY" -f "$HERE/steps.awk" "$FILE" > "$TMP"
case $? in
  0) mv "$TMP" "$FILE" || { rm -f "$TMP"; echo "could not write $FILE" >&2; exit 66; } ;;
  3) rm -f "$TMP"; echo "step $N was already ticked — nothing to do"; exit 3 ;;
  *) rm -f "$TMP"; echo "no step $N in $FILE" >&2; exit 66 ;;
esac

sed -n "${LNO}p" "$FILE"
