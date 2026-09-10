#!/usr/bin/env bash
# One step of a task file, with what a builder needs around it.
#
# /dev-implement is handed exactly the step it is on — not the whole plan, which
# a small model reads once and then builds whichever step it remembers. Steps
# are numbered "N. [ ] title" under "## Steps" and ticked to "N. [x] title —
# what landed"; the lines indented under a step (Create:, Modify:, Test:,
# Check:, Budget:) travel with it. What counts as a step is lib/steps.awk.
#
#   task-step.sh <task-file> [--next|--continue]   the first unticked step (also with no mode at all)
#   task-step.sh <task-file> <n> | --step <n>       step n, ticked or not
#   task-step.sh <task-file> --count       "k of N done"
#   task-step.sh <task-file> --paths <n>   the Create:/Modify:/Test: paths of step n, one per line
#
# A step is printed as: the title line, the Type line, ## Acceptance criteria,
# ## Do not touch, then "## Step n of N (k done)" and the step's block. The
# arguments are what /dev-implement's $ARGUMENTS carries, verbatim.
# Exit 0; 3 when the file has no steps at all; 4 on --next when every step is
# ticked (prints "PLAN DONE — N of N steps ticked"); 64 usage; 66 no such file or step.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"; MODE="${2:-}"; ARG="${3:-}"
usage() { echo "usage: task-step.sh <task-file> [--next|--continue] | <n> | --step <n> | --count | --paths <n>" >&2; exit 64; }
if [ "$FILE" = "--continue" ] || [ "$FILE" = "--next" ] || [ -z "$FILE" ]; then
  latest="$(ls -t .tasks/*.md 2>/dev/null | head -1)"
  if [ -n "$latest" ] && [ -f "$latest" ]; then
    [ -n "$FILE" ] && MODE="$FILE"
    FILE="$latest"
  fi
fi

[ -n "$FILE" ] || usage
case "$MODE" in ''|--continue) MODE=--next ;; --step) MODE="$ARG" ;; esac
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 66; }

ANY=0; grep -q '^## Steps' "$FILE" || ANY=1
steps() { awk -v mode="$1" -v n="${2:-}" -v kinds="${3:-}" -v anywhere="$ANY" -f "$HERE/steps.awk" "$FILE"; }

LIST="$(steps list)"
total="$(printf '%s\n' "$LIST" | grep -c '^[0-9]')"
done_="$(printf '%s\n' "$LIST" | grep -c '^[0-9]*|x|')"
[ "$total" -gt 0 ] || { echo "NO STEPS in $FILE — steps are numbered lines under ## Steps: N. [ ] title" >&2; exit 3; }
has_step() { printf '%s\n' "$LIST" | grep -q "^$1|"; }

section() { # section <heading text> — the lines under "## <heading>" up to the next "## "
  awk -v h="## $1" '$0 == h { on = 1; print; next } /^## / { on = 0 } on { print }' "$FILE"
}

case "$MODE" in
  --count)
    echo "$done_ of $total done"; exit 0 ;;
  --paths)
    case "$ARG" in ''|*[!0-9]*) usage ;; esac
    has_step "$ARG" || { echo "no step $ARG in $FILE" >&2; exit 66; }
    steps paths "$ARG" | cut -d'|' -f2 | sort -u; exit 0 ;;
  --next)
    N="$(printf '%s\n' "$LIST" | grep '^[0-9]*| |' | head -1 | cut -d'|' -f1)"
    [ -n "$N" ] || { echo "PLAN DONE — $total of $total steps ticked"; exit 4; } ;;
  *[!0-9]*|'')
    usage ;;
  *)
    N="$MODE"
    has_step "$N" || { echo "no step $N in $FILE" >&2; exit 66; } ;;
esac

grep -m1 '^# ' "$FILE"
grep -m1 '^\*\*Type:\*\*' "$FILE"
# "**Mode:** manual" marks a plan the developer implements by hand, and it has
# to reach whoever is handed the step: /dev-implement refuses such a plan rather
# than building it for them. Printed only when the file has one, so an ordinary
# plan's output is unchanged.
grep -m1 '^\*\*Mode:\*\*' "$FILE" || :
echo
section 'Acceptance criteria'
echo
section 'Do not touch'
echo
echo "## Step $N of $total ($done_ done)"
steps block "$N"

paths="$(steps paths "$N" | cut -d'|' -f2 | sort -u)"
if [ -n "$paths" ]; then
  echo
  echo "### Step paths status (disk / git):"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    status="untouched"
    if [ -f "$p" ]; then
      if git status --porcelain "$p" 2>/dev/null | grep -q '^[ MADRCU?!]'; then
        status="modified in working tree"
      elif git log -1 --name-only 2>/dev/null | grep -q "^$p$"; then
        status="committed on current branch"
      else
        status="exists on disk"
      fi
    elif [ ! -e "$p" ]; then
      status="does not exist yet"
    fi
    printf '  - %s: %s\n' "$p" "$status"
  done <<EOF
$paths
EOF
fi
