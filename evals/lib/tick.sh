#!/usr/bin/env bash
# Cases for lib/tick.sh — run them from anywhere:
#
#   bash evals/lib/tick.sh
#
# Ticking is the smallest edit in the cycle and the one that fails silently:
# a step left unticked is a step the next run builds again. So what is asserted
# is that the right line changed, that nothing else did, that task-step.sh then
# advances, and that a second tick is a no-op rather than a double edit.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
tick="$root/lib/tick.sh"
step="$root/lib/task-step.sh"
[ -f "$tick" ] || { printf 'no tick.sh at %s\n' "$tick" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

plan="$work/t.md"
fresh() {
  cat > "$plan" <<'PLAN'
# A task

**Type:** feature

## Acceptance criteria

- [ ] the thing works

## Steps

1. [ ] do the thing
   - Create: none
   - Modify: none

2. [ ] do the thing
   - Create: none
   - Modify: none

3. [ ] do a third thing
   - Create: none

## Evidence
PLAN
}

# The named step is ticked, with the note appended.
fresh
out="$(bash "$tick" "$plan" 1 'landed as abc123' 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || note "tick: exit $rc, want 0"
grep -q '^1\. \[x\] do the thing — landed as abc123$' "$plan" || note "tick: step 1 line is '$(grep -m1 '^1\.' "$plan")'"
printf '%s\n' "$out" | grep -q '^1\. \[x\]' || note 'tick: the new line is not printed back'

# Steps 2 and 3 share step 1's title. Neither may have moved.
grep -q '^2\. \[ \] do the thing$' "$plan" || note 'tick: a later step with the same title was touched'
grep -q '^3\. \[ \] do a third thing$' "$plan" || note 'tick: step 3 was touched'
[ "$(grep -c '\[x\]' "$plan")" = 1 ] || note "tick: $(grep -c '\[x\]' "$plan") lines are ticked, want 1"

# The acceptance criteria are "- [ ]" lines and must not be confused for steps.
grep -q '^- \[ \] the thing works$' "$plan" || note 'tick: an acceptance criterion was ticked'

# task-step.sh now hands over the next one, which is the point of ticking.
printf '%s' "$(bash "$step" "$plan" --count)" | grep -q '^1 of 3 done$' || note "tick: --count says '$(bash "$step" "$plan" --count)'"
bash "$step" "$plan" --next 2>&1 | grep -q '^## Step 2 of 3' || note 'tick: --next did not advance to step 2'

# A second tick is a no-op, not a second note.
out="$(bash "$tick" "$plan" 1 'again' 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || note "second tick: exit $rc, want 3"
printf '%s\n' "$out" | grep -q 'already ticked' || note "second tick: '$out'"
grep -q 'again' "$plan" && note 'second tick: the note was appended twice'

# No note is allowed: the tick still happens.
fresh
bash "$tick" "$plan" 2 >/dev/null 2>&1
grep -q '^2\. \[x\] do the thing$' "$plan" || note 'tick with no note: the line is wrong'

# A step that is not there, and a file that is not there.
bash "$tick" "$plan" 9 >/dev/null 2>&1; [ $? -eq 66 ] || note 'missing step: want exit 66'
bash "$tick" "$work/nope.md" 1 >/dev/null 2>&1; [ $? -eq 66 ] || note 'missing file: want exit 66'
bash "$tick" "$plan" x >/dev/null 2>&1; [ $? -eq 64 ] || note 'bad step number: want exit 64'

# A header without a box is ticked by putting one after its number; the other
# shapes a model writes are ticked in place.
printf '# T\n\n## Steps\n\n1. **Do it**\n   - Create: none\nStep 2. [ ] the favourite\n### Step 3 — dash title\n' > "$work/odd.md"
out="$(bash "$tick" "$work/odd.md" 1 "done" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || note "odd shape: exit $rc, want 0 ($out)"
grep -q '^1\. \[x\] \*\*Do it\*\* — done$' "$work/odd.md" || note "odd shape: line is '$(grep -m1 '^1\.' "$work/odd.md")'"
bash "$tick" "$work/odd.md" 2 >/dev/null 2>&1 || note 'Step-word shape: not ticked'
grep -q '^Step 2\. \[x\] the favourite$' "$work/odd.md" || note "Step-word shape: line is '$(grep -m1 '^Step 2' "$work/odd.md")'"
bash "$tick" "$work/odd.md" 3 "ok" >/dev/null 2>&1 || note 'heading shape: not ticked'
grep -q '^### Step 3 \[x\] — dash title — ok$' "$work/odd.md" || note "heading shape: line is '$(grep -m1 '^### Step 3' "$work/odd.md")'"
[ "$(bash "$step" "$work/odd.md" --count)" = "3 of 3 done" ] || note "odd shapes: --count says '$(bash "$step" "$work/odd.md" --count)'"

# A box inside the title is not the status box: the tick goes after the number
# and the title keeps its box, and "[X]" in a title does not mean already ticked.
printf '# T\n\n## Steps\n\n1. Add [ ] checkbox rendering\n2. Support [X] as a tick\n' > "$work/box.md"
bash "$tick" "$work/box.md" 1 "done" >/dev/null 2>&1 || note 'box in title: not ticked'
grep -q '^1\. \[x\] Add \[ \] checkbox rendering — done$' "$work/box.md" || note "box in title: line is '$(grep -m1 '^1\.' "$work/box.md")'"
out="$(bash "$tick" "$work/box.md" 2 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || note "[X] in title: exit $rc, want 0 ($out)"
grep -q '^2\. \[x\] Support \[X\] as a tick$' "$work/box.md" || note "[X] in title: line is '$(grep -m1 '^2\.' "$work/box.md")'"
[ "$(bash "$step" "$work/box.md" --count)" = "2 of 2 done" ] || note "box in title: --count says '$(bash "$step" "$work/box.md" --count)'"

if [ "$fails" -eq 0 ]; then
  printf 'tick: the right line, only that line, and the next step follows\n'
else
  printf 'tick: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
