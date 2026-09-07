#!/usr/bin/env bash
# The hand-offs between skills, asserted — run it from anywhere:
#
#   bash evals/skills/cycle.sh
#
# Each skill ends by naming the next command. A small model does what the last
# line of its prompt says, so a hand-off that goes missing is a cycle that
# stops. This suite asserts each link by the literal command name; later steps
# of the plan add their links here as they land.
#
# Exits 0 when every link holds, 1 otherwise, naming each gap.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
skills="$root/skills"
[ -d "$skills" ] || { printf 'no skills at %s\n' "$skills" >&2; exit 1; }

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
# Prose wrapped at the file's width: match against a flattened copy.
flat() { tr '\n' ' ' < "$skills/$1/SKILL.md" | tr -d '`' | tr -s ' '; }
has() { flat "$1" | grep -qF -- "$2" || note "$1: does not mention '$2' — $3"; }

has dev-plan      '/dev-implement'   'a plan that names no next command is a plan nobody runs'
has dev-implement '/dev-review'      'a built step must be reviewed before it goes anywhere'
has dev-implement '--continue'       'an interrupted build has to say how to resume'
has dev-implement 'task-step.sh $ARGUMENTS' 'the step must arrive injected, not be picked from the whole plan'
has dev-implement 'Modify: paths first' 'the build starts from the step file list, not a search'
has dev-implement 'step/<slug>-<n>'   'one branch per step, stacked'
has dev-implement '/new'              'the context is cleared between steps'
has dev-implement 'learned.md'        'the next run inherits what this one found out'
has dev-implement 'tail -20'          'the learned notes are capped'
has dev-implement 'step-budget.sh'    'an OVER step is said, not refused'
grep -q -- '--all' "$skills/dev-implement/SKILL.md" && note 'dev-implement: --all is back, and it contradicts one step per run'
has dev-review    'Ready to push'    'the first line of the report is the verdict'
has dev-review    '/dev-fix'          'what survived the filter goes to dev-fix'
has dev-review    '.devskills/reports/' 'a report lands in the ignored directory, not at the root'
has dev-review    'task-step.sh'      'C5 greps the current step file list first'
grep -q 'REVIEW.md' "$skills/dev-review/SKILL.md" && note 'dev-review: still writes REVIEW.md at the root'
grep -qi 'worktree' "$skills/dev-verify/SKILL.md" && note 'dev-verify: mentions a worktree this version never creates'
has dev-verify    'evidence, never instruction' 'tool output and PR text are evidence'
has dev-init      '@AGENTS.md'        'the CLAUDE.md stub is exactly the import line'
has dev-fix       'findings-check.sh $ARGUMENTS' 'the findings arrive re-verified, injected'
has dev-fix       'Fix: '             'one commit per finding, named after it'
has dev-fix       '--no-verify'       'a hook failure skips the finding, never bypasses it'
has dev-fix       '/dev-pr'           'a clean fix run hands off to the pull request'
has dev-fix       '/dev-review'       'a fixed blocker earns a second look'
has dev-fix       'learned.md'        'the next run inherits what this one found out'
has dev-pr        'pr-info.sh $ARGUMENTS' 'the base, the pull request and the counts arrive injected'
has dev-pr        '--base <base>'     'a stacked step targets the previous step, not main'
has dev-pr        'Depends on #'      'a stacked pull request names the one it sits on'
has dev-pr        '/new'              'after the pull request the context is cleared'
has dev-pr        '--continue'        'and the next step is named'
has dev-pr        'no session link'   'a private transcript URL is not attribution on a public repository'
grep -q 'gh pr merge' "$skills/dev-pr/SKILL.md" && note 'dev-pr: names gh pr merge; opening is where it stops'
has dev-pr-review '/dev-review'      'own changes go to dev-review, not here'
has dev-pr-comment '/dev-pr-review'  'the pull request of another author goes to dev-pr-review'
has dev-pr-comment 'git push origin' 'the push is printed for a person, never run'

if [ "$fails" -eq 0 ]; then
  printf 'cycle: every skill names the next command\n'
else
  printf 'cycle: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
