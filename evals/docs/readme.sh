#!/usr/bin/env bash
# The README against the mechanics it describes — run it from anywhere:
#
#   bash evals/docs/readme.sh
#
# Rationale lives in the README, not in the prompts, so a mechanism the README
# does not mention is one a reader does not know exists. Each token below is a
# thing the skills rely on; the README has to name every one.
#
# Exits 0 when it does, 1 otherwise, naming each gap.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
readme="$root/README.md"
[ -f "$readme" ] || { printf 'no README.md at %s\n' "$readme" >&2; exit 1; }

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

for token in \
  '/dev-fix' \
  '/dev-pr' \
  'contextTokens' \
  'DEV_SKILLS_CONTEXT' \
  'step-budget.sh' \
  'plan-check.sh' \
  'task-step.sh' \
  'plan-input.sh' \
  'steps.awk' \
  'dev-guard.js' \
  'evals/run-all.sh' \
  'evals/guard/cases.sh' \
  'evals/skills/size.sh' \
  'learned.md' \
  '/new' \
  'step/<slug>-<n>' \
  'Depends on #' \
  'http-check.sh' \
  'test.sh' \
  'TEST PASS' \
  'tick.sh' \
  '4,500 bytes'
do
  grep -qF -- "$token" "$readme" || note "README never mentions $token"
done

# Claims that are no longer true must be gone.
grep -q 'seven `dev-` commands' "$readme" && note 'README still counts seven commands'
grep -q 'REVIEW.md' "$readme" && note 'README still names REVIEW.md at the root'

if [ "$fails" -eq 0 ]; then
  printf 'readme: describes every mechanic the skills rely on\n'
else
  printf 'readme: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
