#!/usr/bin/env bash
# Cases for lib/steps.awk — run them from anywhere:
#
#   bash evals/lib/steps.sh
#
# Four scripts read a task file through this one parser — task-step.sh hands
# /dev-implement its step, step-budget.sh sizes it, plan-check.sh checks its
# paths, tick.sh finds the line to tick — so they agree only as far as it does.
# What is asserted is where a step counts (under ## Steps, never inside a fenced
# example) and what counts as a path (not "none", not prose, not a slash command).
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
awkf="$root/lib/steps.awk"
[ -f "$awkf" ] || { printf 'no steps.awk at %s\n' "$awkf" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
steps() { awk -v mode="$1" -v n="${2:-}" -v kinds="${3:-}" -v anywhere="${4:-0}" -f "$awkf" "$plan"; }
same() { # same <got> <want> <what>
  [ "$1" = "$2" ] || note "$3: got '$1', want '$2'"
}

plan="$work/plan.md"
cat > "$plan" <<'PLAN'
# A task

## Design

The template a step follows looks like this:

```markdown
9. [ ] not a real step, it is inside a fence
   - Modify: fenced/decoy.php
```

And this line — 7. [ ] also not a step — sits outside ## Steps.

## Steps

1. [x] first thing — landed as abc123
   - Create: none
   - Modify: lib/one.sh:10-20 (rank_of), lib/two.sh
   - Test: evals/lib/one.sh
   - Check: `bash evals/lib/one.sh`

2. [ ] second thing
   - Create: lib/new.sh, evals/lib/new.sh
   - Modify: none
   - Test: none — covered by step 1
   - Check: `bash evals/run-all.sh`

3. [ ] third thing
   - Modify: skills/dev-plan/SKILL.md (plan-check.sh)
   - Test: "quoted things are prose", run /dev-review afterwards

## Evidence

- **Code:** lib/notastep.sh — evidence is not a step
PLAN

# The list: three steps, and neither decoy.
same "$(steps list | wc -l | tr -d ' ')" "3" 'list: step count'
same "$(steps list | head -1)" "1|x|first thing — landed as abc123" 'list: a ticked step keeps its note'
same "$(steps list | sed -n 2p)" "2| |second thing" 'list: an unticked step'
steps list | grep -q '^9|' && note 'list: a step inside a fenced block was counted'
steps list | grep -q '^7|' && note 'list: a numbered line outside ## Steps was counted'

# The block: only that step's lines.
same "$(steps block 2 | head -1)" "2. [ ] second thing" 'block: starts at the header'
steps block 2 | grep -q 'third thing' && note 'block: ran on into step 3'
steps block 2 | grep -q 'first thing' && note 'block: included step 1'

# Paths: the kinds asked for, with symbols, and nothing that is not a path.
same "$(steps paths 1 'Modify')" "Modify|lib/one.sh|rank_of
Modify|lib/two.sh|" 'paths: line numbers stripped, symbol kept, comma split'
same "$(steps paths 1 'Create')" "" 'paths: "none" is not a path'
same "$(steps paths 2 'Create')" "Create|lib/new.sh|
Create|evals/lib/new.sh|" 'paths: two created files'
same "$(steps paths 2 'Test')" "" 'paths: "none — covered by step 1" is not a path'
same "$(steps paths 3 'Modify')" "Modify|skills/dev-plan/SKILL.md|plan-check.sh" 'paths: a dotted symbol'
steps paths 3 'Test' | grep -q 'quoted' && note 'paths: quoted prose was taken as a path'
steps paths 3 'Test' | grep -q 'dev-review' && note 'paths: a slash command was taken as a path'
steps paths 1 'Modify Test' | grep -q 'evals/lib/one.sh' || note 'paths: several kinds at once'
steps paths 1 'Modify' | grep -q 'Check' && note 'paths: a Check line was read as a path'

# A file with no ## Steps heading at all is scanned whole, on request.
cat > "$work/bare.md" <<'BARE'
# No headings here

1. [ ] a step all the same
   - Modify: lib/bare.sh
BARE
plan="$work/bare.md"
same "$(steps list 2>/dev/null | wc -l | tr -d ' ')" "0" 'no ## Steps: nothing without anywhere=1'
same "$(steps list '' '' 1 | head -1)" "1| |a step all the same" 'no ## Steps: anywhere=1 scans the file'

if [ "$fails" -eq 0 ]; then
  printf 'steps: a step is a step only under ## Steps, and a path is only a path\n'
else
  printf 'steps: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
