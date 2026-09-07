#!/usr/bin/env bash
# Do the paths a plan names exist? The plan-side twin of findings-check.sh.
#
# A local model writing a plan will name a file that is not there, or a symbol
# that is not in it, with the same confidence as a real one. Rather than trust
# it, every unticked step's lines are checked against the tree: a Modify: path
# must exist — or be created by an earlier step — and its (symbol) must be in
# the file; a Create: path must not exist yet. Ticked steps are skipped: their
# files have moved on. What counts as a step and a path is lib/steps.awk.
#
#   plan-check.sh <task-file> [--step <n>]
#
# One line per problem:  STEP <n> | <path> | <problem>
# then "plan-check: N step(s) checked, M problem(s)" on stderr.
# Exit 0 clean, 1 problems, 64 usage, 66 no such file.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"
usage() { echo "usage: plan-check.sh <task-file> [--step <n>]" >&2; exit 64; }
[ -n "$FILE" ] || usage
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }
ONLY=""
if [ "${2:-}" = "--step" ]; then
  ONLY="${3:-}"; case "$ONLY" in ''|*[!0-9]*) usage ;; esac
fi

ANY=0; grep -q '^## Steps' "$FILE" || ANY=1
steps() { awk -v mode="$1" -v n="${2:-}" -v kinds="${3:-}" -v anywhere="$ANY" -f "$HERE/steps.awk" "$FILE"; }

LIST="$(steps list)"
total="$(printf '%s\n' "$LIST" | grep -c '^[0-9]')"
[ "$total" -gt 0 ] || { echo "NO STEPS in $FILE — steps are numbered lines under ## Steps: N. [ ] title" >&2; exit 3; }

problems=0
checked=0
problem() { printf 'STEP %s | %s | %s\n' "$1" "$2" "$3"; problems=$((problems + 1)); }

# Every Create: path of every step, with the step that creates it, so a later
# step may Modify: a file that is not there yet.
CREATED="$(for k in $(steps list | cut -d'|' -f1); do steps paths "$k" Create | cut -d'|' -f2 | sed "s/^/$k /"; done)"
created_by() { printf '%s\n' "$CREATED" | awk -v p="$1" -v n="$2" '$2 == p && $1 + 0 < n + 0 { print $1; exit }'; }

for n in $(steps list | grep '^[0-9]*| |' | cut -d'|' -f1); do
  [ -n "$ONLY" ] && [ "$n" != "$ONLY" ] && continue
  checked=$((checked + 1))

  while IFS='|' read -r _ p sym; do
    [ -n "$p" ] || continue
    [ -e "$p" ] && problem "$n" "$p" "Create: path already exists"
  done <<EOF
$(steps paths "$n" Create)
EOF

  while IFS='|' read -r _ p sym; do
    [ -n "$p" ] || continue
    if [ -f "$p" ]; then
      [ -n "$sym" ] && ! grep -qF -- "$sym" "$p" && problem "$n" "$p" "Modify: symbol '$sym' not found in the file"
    elif [ -z "$(created_by "$p" "$n")" ]; then
      problem "$n" "$p" "Modify: path does not exist, and no earlier step creates it"
    fi
  done <<EOF
$(steps paths "$n" Modify)
EOF
done

[ "$checked" -gt 0 ] || { echo "plan-check: no unticked step to check" >&2; exit 0; }
echo "plan-check: $checked step(s) checked, $problems problem(s)" >&2
exit $((problems > 0))
