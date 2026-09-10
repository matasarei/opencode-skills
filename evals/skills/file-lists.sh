#!/usr/bin/env bash
# The step shape, asserted — run it from anywhere:
#
#   bash evals/skills/file-lists.sh
#
# /dev-plan writes five indented lines under every step and three scripts read
# them: task-step.sh hands /dev-implement the step, step-budget.sh sizes it,
# plan-check.sh checks its paths. The template in the skill has to keep the
# shape the parser expects — each line its own, indented, in the same words —
# or the lists become decoration nothing reads. Later steps add the readers.
#
# Exits 0 when the shape holds, 1 otherwise, naming each gap.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
skills="$root/skills"
[ -d "$skills" ] || { printf 'no skills at %s\n' "$skills" >&2; exit 1; }

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
flat() { tr '\n' ' ' < "$1" | tr -d '`' | tr -s ' '; }

plan="$skills/dev-plan/SKILL.md"
for part in 'Create:' 'Modify:' 'Test:' 'Check:' 'Budget:'; do
  grep -qE "^ +- $part" "$plan" || note "dev-plan: the step template has no indented '$part' line of its own"
done
grep -qE '^[0-9]+\. \[ \] <' "$plan" || note 'dev-plan: the template step is not a numbered "N. [ ]" line'
flat "$plan" | grep -q 'never - \[ \]' || note 'dev-plan: does not warn that "- [ ]" is not a step'

for tool in plan-input.sh plan-check.sh step-budget.sh learned.md; do
  grep -q "$tool" "$plan" || note "dev-plan: never names $tool"
done
grep -q '^!`.*plan-input.sh \$ARGUMENTS' "$plan" || note 'dev-plan: the brief is not injected through plan-input.sh $ARGUMENTS'
flat "$plan" | grep -q 'OVER — kept:' || note 'dev-plan: an unsplittable OVER step has no wording to keep it'
flat "$plan" | grep -q '\[assumed\]' || note 'dev-plan: unanswered questions are not tagged [assumed]'
flat "$plan" | grep -q 'Shell before reading' || note 'dev-plan: the CLI-first block is missing'
grep -q -- '--review' "$plan" && note 'dev-plan: --review is back; judging a proposal is judgement work'

# The manual plan keeps the same step shape — task-step.sh, step-budget.sh and
# plan-check.sh parse it the same way — plus the two lines that are only its:
# the commit the developer owes, and the walkthrough that is not written yet.
manual="$skills/dev-plan-manual/SKILL.md"
if [ -f "$manual" ]; then
  for part in 'Create:' 'Modify:' 'Test:' 'Check:' 'Budget:' 'Commit:'; do
    grep -qE "^ +- $part" "$manual" || note "dev-plan-manual: the step template has no indented '$part' line of its own"
  done
  grep -qE '^[0-9]+\. \[ \] <' "$manual" || note 'dev-plan-manual: the template step is not a numbered "N. [ ]" line'
  grep -qE '^ +Walkthrough:' "$manual" || note 'dev-plan-manual: no placeholder line for the walkthrough written later'
  # The walkthrough sits inside a step block, where steps.awk reads Create:,
  # Modify: and Test: as path lists wherever they appear. Its labels must not
  # collide with those three, and the skill has to say so.
  flat "$manual" | grep -q 'Never Create:, Modify: or Test: in a walkthrough' \
    || note 'dev-plan-manual: does not warn that the walkthrough labels must avoid the path kinds'
  flat "$manual" | grep -q 'No implementation' \
    || note 'dev-plan-manual: does not forbid a finished implementation in the plan'
else
  note 'dev-plan-manual: no SKILL.md'
fi

if [ "$fails" -eq 0 ]; then
  printf 'file-lists: the plan template keeps the shape the scripts parse\n'
else
  printf 'file-lists: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
