#!/usr/bin/env bash
# Cases for lib/task-step.sh (and, through it, lib/steps.awk) — run from anywhere:
#
#   bash evals/lib/task-step.sh
#
# What is asserted is what a builder is handed: exactly one step, with the
# criteria and the Do-not-touch list around it; the first unticked step under
# --next, and only steps under "## Steps" outside code fences count — a
# template step in the design section is the mistake this exists to catch.
# --count, --paths, PLAN DONE and the error exits round it off.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/task-step.sh"
[ -f "$script" ] || { printf 'no task-step.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
run() { out="$(cd "$work" && bash "$script" "$@" 2>&1)"; rc=$?; }

cat > "$work/plan.md" <<'EOF'
# Export by indicator

**Type:** feature
**Asked:** the export

## Summary
- one

## Design

The step shape:

```markdown
9. [ ] <a template step, not a real one>
   - Modify: `template/only.php`
```

## Acceptance criteria
- [ ] rows stay separate
- [ ] numbers are numbers

## Steps

1. [x] Add the generator — landed as `classes/export/Csv.php`
   - Create: `classes/export/Csv.php`
   - Modify: none
   - Test: `tests/CsvTest.php`
2. [ ] Wire it into the page
   - Create: none
   - Modify: `pages/export.php:40-60 (render)`, `lang/en/local_x.php:12`
   - Test: none — covered by step 1
   - Check: `vendor/bin/phpunit --filter Csv`
   - Budget: 120/1200 lines — fits
<!-- postponed by /dev-fix -->
3. [ ] NIT `pages/export.php:88` — rename
   - Modify: `pages/export.php`

## How to check it
- `vendor/bin/phpunit`

## Do not touch
- `db/` — no schema change
EOF

# --count sees three real steps, one ticked; the template is not a step.
run plan.md --count
[ "$rc" -eq 0 ] || note "--count: exit $rc, want 0"
[ "$out" = '1 of 3 done' ] || note "--count: got '$out'"

# --next is step 2, wrapped in what the builder needs, and nothing of step 1 or 3.
run plan.md --next
[ "$rc" -eq 0 ] || note "--next: exit $rc, want 0"
[ "$(printf '%s\n' "$out" | head -1)" = '# Export by indicator' ] || note '--next: the title is not the first line'
printf '%s\n' "$out" | grep -q '^\*\*Task file:\*\* .*plan\.md$' || note '--next: the task file path is not printed, so the builder has nothing to pass to the scripts'
printf '%s\n' "$out" | grep -q '^\*\*Type:\*\* feature$'      || note '--next: the Type line is missing'
printf '%s\n' "$out" | grep -q '^## Acceptance criteria$'   || note '--next: acceptance criteria missing'
printf '%s\n' "$out" | grep -q 'numbers are numbers'        || note '--next: a criterion is missing'
printf '%s\n' "$out" | grep -q '^## Do not touch$'          || note '--next: Do not touch missing'
printf '%s\n' "$out" | grep -q 'no schema change'           || note '--next: the Do not touch line is missing'
printf '%s\n' "$out" | grep -q '^## Step 2 of 3 (1 done)$'  || note '--next: the step header is wrong'
printf '%s\n' "$out" | grep -q '^2\. \[ \] Wire it into the page$' || note '--next: step 2 line missing'
printf '%s\n' "$out" | grep -q 'Budget: 120/1200'           || note '--next: the indented lines did not travel with the step'
printf '%s\n' "$out" | grep -q 'Add the generator'          && note '--next: step 1 leaked in'
printf '%s\n' "$out" | grep -q 'NIT'                        && note '--next: step 3 leaked in (the comment line should end the block)'
printf '%s\n' "$out" | grep -q 'template'                   && note '--next: the template step in the design section leaked in'
printf '%s\n' "$out" | grep -q 'How to check'               && note '--next: a later section leaked in'

# What $ARGUMENTS carries: no mode and --continue mean --next; --step n means n.
run plan.md
printf '%s\n' "$out" | grep -q '^## Step 2 of 3' || note 'no mode: should behave as --next'
run plan.md --continue
printf '%s\n' "$out" | grep -q '^## Step 2 of 3' || note '--continue: should behave as --next'
run plan.md --step 1
printf '%s\n' "$out" | grep -q '^## Step 1 of 3' || note '--step 1: should print step 1'
run plan.md --step x;  [ "$rc" -eq 64 ] || note "--step x: exit $rc, want 64"

# A number picks that step, ticked or not.
run plan.md 1
[ "$(printf '%s\n' "$out" | grep -c '^1\. \[x\] Add the generator')" -eq 1 ] || note 'step 1: not printed'
printf '%s\n' "$out" | grep -q '^## Step 1 of 3' || note 'step 1: header wrong'

# --paths: the Create/Modify/Test paths of a step, one per line, once each,
# suffixes and symbols cut, "none" and prose ignored.
run plan.md --paths 2
[ "$out" = "$(printf 'lang/en/local_x.php\npages/export.php')" ] || note "--paths 2: got '$out'"
run plan.md --paths 1
[ "$out" = "$(printf 'classes/export/Csv.php\ntests/CsvTest.php')" ] || note "--paths 1: got '$out'"

# Errors: no such step, no such file, bad arguments.
run plan.md 7;         [ "$rc" -eq 66 ] || note "no such step: exit $rc, want 66"
run nope.md --next;    [ "$rc" -eq 66 ] || note "no such file: exit $rc, want 66"
run plan.md --paths x; [ "$rc" -eq 64 ] || note "--paths x: exit $rc, want 64"

# Every step ticked: PLAN DONE, exit 4.
sed 's/^2\. \[ \]/2. [x]/; s/^3\. \[ \]/3. [x]/' "$work/plan.md" > "$work/done.md"
run done.md --next
[ "$rc" -eq 4 ] || note "plan done: exit $rc, want 4"
[ "$out" = 'PLAN DONE — 3 of 3 steps ticked' ] || note "plan done: got '$out'"

# No steps at all: exit 3.
printf '# Empty\n\n## Steps\n\nnothing yet\n' > "$work/empty.md"
run empty.md --next
[ "$rc" -eq 3 ] || note "no steps: exit $rc, want 3"

# A brief with no "## Steps" heading is scanned whole.
printf '# Loose\n\n1. [ ] first\n   - Modify: `a/b.php`\n2. [ ] second\n' > "$work/loose.md"
run loose.md --count
[ "$out" = '0 of 2 done' ] || note "no Steps heading: got '$out'"

# A manual plan carries "**Mode:** manual" and /dev-implement has to see it —
# a step handed over without the marker is one it will build for the developer
# who asked to write it themselves. The marker travels beside the Type line.
sed 's/^\*\*Type:\*\* feature/**Type:** feature\n**Mode:** manual/' "$work/plan.md" > "$work/manual.md"
run manual.md --next
[ "$rc" -eq 0 ] || note "manual: exit $rc, want 0"
printf '%s\n' "$out" | grep -q '^\*\*Mode:\*\* manual$' || note 'manual: the Mode line did not travel with the step'
printf '%s\n' "$out" | grep -q '^\*\*Type:\*\* feature$' || note 'manual: the Type line went missing beside it'
printf '%s\n' "$out" | grep -q '^## Step 2 of 3 (1 done)$' || note 'manual: the step header is wrong'

# Any other mode travels too, verbatim: the script reports what the file says
# and leaves "is this one manual?" to the skill reading it, so a mode nobody has
# invented yet does not need a change here.
sed 's/^\*\*Type:\*\* feature/**Type:** feature\n**Mode:** paired/' "$work/plan.md" > "$work/other.md"
run other.md --next
printf '%s\n' "$out" | grep -q '^\*\*Mode:\*\* paired$' || note 'other mode: the Mode line was not printed verbatim'

# And a plan without one is untouched: no blank line, no stray label, nothing
# for a model to read as a mode it does not have.
run plan.md --next
printf '%s\n' "$out" | grep -q 'Mode:' && note 'no marker: a Mode line appeared anyway'
[ "$(printf '%s\n' "$out" | sed -n '2p')" = '**Type:** feature' ] || note 'no marker: the Type line moved'
[ "$(printf '%s\n' "$out" | sed -n '3p')" = '' ] || note 'no marker: the blank line after Type is gone'

if [ "$fails" -eq 0 ]; then
  printf 'task-step: one step at a time, only real steps, with what the builder needs\n'
else
  printf 'task-step: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
