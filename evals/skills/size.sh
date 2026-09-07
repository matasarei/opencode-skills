#!/usr/bin/env bash
# The prompt-size cap, asserted — run it from anywhere:
#
#   bash evals/skills/size.sh
#
# Every SKILL.md is re-sent on every turn of a local model, and every skill's
# description is loaded into every session. So each is capped: at most 90
# lines and 4,500 bytes (about 1,100 tokens), a description on one line of at
# most 200 characters. Rationale belongs in the README, not in the prompt.
#
# SIZE_TODO names the skills a plan has not rewritten yet; they are reported,
# not failed, until their step lands and removes them from the list.
#
# Exits 0 when every skill outside the list fits, 1 otherwise, naming each.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
skills="$root/skills"
[ -d "$skills" ] || { printf 'no skills at %s\n' "$skills" >&2; exit 1; }

MAX_LINES=90
MAX_BYTES=4500
MAX_DESC=200
SIZE_TODO="dev-implement dev-review dev-verify dev-init dev-pr-review dev-pr-comment"

fails=0
checked=0
todo=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

for dir in "$skills"/*/; do
  s="$(basename "$dir")"
  f="$dir/SKILL.md"
  [ -f "$f" ] || continue
  lines="$(wc -l < "$f" | tr -d ' ')"
  bytes="$(wc -c < "$f" | tr -d ' ')"
  desc="$(sed -n '2,/^---$/p' "$f" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  dlen="${#desc}"

  if in_list "$s" "$SIZE_TODO"; then
    todo=$((todo + 1))
    printf 'todo  %s: %s lines, %s bytes, description %s chars — not rewritten yet\n' "$s" "$lines" "$bytes" "$dlen"
    continue
  fi
  checked=$((checked + 1))
  [ "$lines" -le "$MAX_LINES" ] || note "$s: $lines lines, cap $MAX_LINES"
  [ "$bytes" -le "$MAX_BYTES" ] || note "$s: $bytes bytes, cap $MAX_BYTES"
  [ "$dlen" -le "$MAX_DESC" ]   || note "$s: description is $dlen chars, cap $MAX_DESC"
  [ "$dlen" -gt 0 ]             || note "$s: no description"
done

if [ "$checked" -eq 0 ] && [ "$todo" -eq 0 ]; then
  printf 'no SKILL.md under %s\n' "$skills" >&2
  exit 1
elif [ "$fails" -eq 0 ]; then
  printf 'size: %s skill(s) within %s lines / %s bytes, %s still to rewrite\n' "$checked" "$MAX_LINES" "$MAX_BYTES" "$todo"
else
  printf 'size: %s over the cap\n' "$fails" >&2
fi
exit $((fails > 0))
