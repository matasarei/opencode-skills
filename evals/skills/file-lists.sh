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

# /dev-implement is handed the step by task-step.sh, which prints NO STEPS when
# the plan is not in the shape steps.awk reads. The skill has to stop on that
# line — a run that went on once rewrote the plan's headings with sed and lost
# fifteen steps — and the rule sits a few bytes under the size cap, where the
# next trim can take it.
impl="$skills/dev-implement/SKILL.md"
flat "$impl" | grep -q 'NO STEPS → print Next: /dev-plan <task-file> and stop' || note 'dev-implement: NO STEPS must print the Next: line and stop, nothing else'
# The three sentences the 2026-09-11 runs lacked: an unlisted branch.sh answer
# let a run commit on master; a bare "scoped test" and a bare script name each
# sent the model to read scripts instead of running them.
flat "$impl" | grep -q 'any other answer (no such file, no step, usage:) → quote it and stop' || note 'dev-implement: no rule for a branch.sh answer other than BRANCH'
flat "$impl" | grep -q 'test.sh --scoped <name>' || note 'dev-implement: the scoped test command is not spelled out'
flat "$impl" | grep -q 'never cat them' || note 'dev-implement: no rule against reading the dev-lib scripts'

# /dev-fix's Mode B names its lint and scoped-test commands in full: a bare
# "lint.sh <path>" and a bare "testScoped" sent a model to read scripts.
fix="$skills/dev-fix/SKILL.md"
grep -q 'dev-lib}/lint.sh <path>' "$fix" || note 'dev-fix: Mode B does not spell the lint command'
grep -q 'dev-lib}/test.sh --scoped <name>' "$fix" || note 'dev-fix: Mode B does not spell the scoped test command'

# The same omission in three more skills: a script named without its path, or
# a rule left out, is what a byte-cap trim removes first.
pr="$skills/dev-pr/SKILL.md"; manual="$skills/dev-plan-manual/SKILL.md"
grep -q 'dev-lib}/verify-clean.sh' "$pr" || note 'dev-pr: verify-clean.sh is named without its invocation'
grep -q 'dev-lib}/plan-check.sh <file>' "$manual" || note 'dev-plan-manual: plan-check.sh is named without its invocation'
grep -q 'dev-lib}/step-budget.sh <file> <n>' "$manual" || note 'dev-plan-manual: step-budget.sh is named without its invocation'
flat "$plan" | grep -q 'never cat them' || note 'dev-plan: no rule against reading the dev-lib scripts'

# The manual plan keeps the same step shape — task-step.sh, step-budget.sh and
# plan-check.sh parse it the same way — plus the two lines that are only its:
# the commit the developer owes, and the walkthrough that is not written yet.
manual="$skills/dev-plan-manual/SKILL.md"
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

if [ "$fails" -eq 0 ]; then
  printf 'file-lists: the plan template keeps the shape the scripts parse\n'
else
  printf 'file-lists: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
