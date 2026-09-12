#!/usr/bin/env bash
# The block the model actually sees, assembled the way OpenCode assembles it:
#
#   bash evals/skills/injected.sh
#
# Every other suite tests a script on its own. Nothing tested what those
# scripts put in front of the model once a skill's "!`…`" lines have run —
# and that is where the 2026-09-11 failures lived: a run got a step with no
# task-file path, invented one, and built with no branch. This suite takes
# each SKILL.md, runs its injected commands in a throwaway project with
# DEV_SKILLS_LIB pointing at this checkout's lib/, substituting $ARGUMENTS
# the way each skill is typically invoked, and asserts what the model reads:
#
#   - no line is a usage message, a "command not found", or a stray
#     "$ARGUMENTS" — each means the model was handed the toolkit's problem;
#   - a skill that injects task-step.sh with a plan gets the step, and its
#     absolute "**Task file:**" line, so the model can pass the path on;
#   - dev-plan's block names the project root, so the plan lands under it;
#   - no SKILL.md mentions $ARGUMENTS outside an injection, where it would
#     reach the model as literal text.
#
# Injections that call gh reach the network and are skipped, named as such.
# Needs git. Exits 0 when the blocks read as they should, 1 otherwise.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
skills="$root/skills"
[ -d "$skills" ] || { printf 'no skills at %s\n' "$skills" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { printf 'injected: git is required — not installed\n' >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A small project: a git repository on main with one commit, a profile, and a
# plan in the canonical shape, so every injected command has something to read.
proj="$work/proj"
mkdir -p "$proj/.tasks" "$proj/.devskills"
git -C "$proj" init -q -b main
printf '{\n  "baseBranch": "main"\n}\n' > "$proj/.devskills/profile.json"
printf 'x\n' > "$proj/README.md"
cat > "$proj/.tasks/plan.md" <<'PLAN'
# Export the roster as CSV

**Type:** feature
**Asked:** add a CSV option to the roster export

## Acceptance criteria
- [ ] `?format=csv` downloads a CSV with the same rows as the XLSX

## Steps
1. [ ] Add the CSV writer
   - Create: classes/export/CsvWriter.php
   - Modify: none
   - Test: tests/export/CsvWriterTest.php
   - Check: `vendor/bin/phpunit tests/export/CsvWriterTest.php`

## Do not touch
- `classes/export/XlsxWriter.php`
PLAN
git -C "$proj" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$proj" -c user.email=t@t -c user.name=t commit -qm base >/dev/null

# How each skill is typically invoked — what replaces $ARGUMENTS.
args_for() {
  case "$1" in
    dev-implement|dev-plan-manual) printf '%s' '.tasks/plan.md' ;;
    dev-plan|dev-fix) printf '%s' 'add a CSV option to the roster export' ;;
    dev-pr-review) printf '%s' '1' ;;
    *) printf '' ;;
  esac
}

for skill in "$skills"/*/SKILL.md; do
  name="$(basename "$(dirname "$skill")")"
  args="$(args_for "$name")"

  # $ARGUMENTS outside an injection reaches the model as literal text.
  stray="$(grep -v '^!`' "$skill" | grep -c '\$ARGUMENTS')"
  [ "$stray" -eq 0 ] || note "$name: \$ARGUMENTS appears $stray time(s) outside an injection"

  block=""; ran=0
  while IFS= read -r line; do
    cmd="${line#\!\`}"; cmd="${cmd%\`}"
    case "$cmd" in gh\ *|*\ gh\ *) continue ;; esac   # reaches the network
    cmd="${cmd//\$ARGUMENTS/$args}"
    out="$(cd "$proj" && DEV_SKILLS_LIB="$root/lib" bash -c "$cmd" 2>&1)"
    block="$block
$out"
    ran=$((ran + 1))
  done <<EOF
$(grep '^!`' "$skill")
EOF
  [ "$ran" -gt 0 ] || continue

  printf '%s\n' "$block" | grep -qi '^usage:' && note "$name: an injection printed a usage line — the model is handed the toolkit's problem: $(printf '%s\n' "$block" | grep -i -m1 '^usage:')"
  printf '%s\n' "$block" | grep -q 'command not found' && note "$name: an injection could not run: $(printf '%s\n' "$block" | grep -m1 'command not found')"
  printf '%s\n' "$block" | grep -q '\$ARGUMENTS' && note "$name: a literal \$ARGUMENTS reached the block"

  if grep -q '^!`.*task-step.sh' "$skill" && [ -n "$args" ]; then
    printf '%s\n' "$block" | grep -q '^\*\*Task file:\*\* /' \
      || note "$name: the step block has no absolute Task file line — the model cannot pass the path to branch.sh, step-budget.sh or tick.sh"
    printf '%s\n' "$block" | grep -q '^## Step 1 of 1' \
      || note "$name: the step block does not hand over step 1: '$(printf '%s\n' "$block" | grep -m1 '^## Step')'"
  fi
  if [ "$name" = dev-plan ]; then
    printf '%s\n' "$block" | grep -qF "$proj" || note "dev-plan: the block does not name the project root, so the plan may land under ~"
  fi
done

if [ "$fails" -eq 0 ]; then
  printf 'injected: every skill hands the model a block it can act on\n'
else
  printf 'injected: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
