#!/usr/bin/env bash
# Every reader of a task file, run over every plan a model actually wrote:
#
#   bash evals/lib/fixtures.sh
#
# The evals for steps.awk, task-step.sh, plan-check.sh, step-budget.sh and
# tick.sh each use a plan their author wrote, in the shape the author expected.
# Two plans a local model wrote in 2026-09 were invisible to all five scripts
# for a word the parser had not been told about, and every suite was green.
# So the plans a model produces are kept under evals/fixtures/plans/, with the
# project's paths made generic, and this suite runs the readers over each one.
#
# A fixture is <name>.md beside <name>.expect, which holds what the readers
# must agree on:
#
#   steps=<N>                every step, ticked or not
#   done=<k>                 how many are ticked
#   paths1=<a>,<b>           task-step.sh --paths 1, sorted as it prints them, comma-joined
#   paths<n>=<...>           the same for any other step worth pinning
#
# A plan that a model wrote in a shape the parser missed goes here, never into
# a one-off case: the fixture is the regression, and the sidecar is its claim.
#
# Exits 0 when every fixture reads as its sidecar says, 1 otherwise, naming
# each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
lib="$root/lib"
plans="$root/evals/fixtures/plans"
for f in steps.awk task-step.sh plan-check.sh step-budget.sh tick.sh; do
  [ -f "$lib/$f" ] || { printf 'no %s at %s\n' "$f" "$lib" >&2; exit 1; }
done
[ -d "$plans" ] || { printf 'no fixtures at %s\n' "$plans" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { sed -n "s/^$2=//p" "$1" | head -1; }
same() { # same <got> <want> <what>
  [ "$1" = "$2" ] || note "$3: got '$1', want '$2'"
}

count=0
for plan in "$plans"/*.md; do
  name="$(basename "$plan" .md)"
  side="$plans/$name.expect"
  [ -f "$side" ] || { note "$name: no .expect sidecar beside the fixture"; continue; }
  count=$((count + 1))
  steps="$(expect "$side" steps)"; done_="$(expect "$side" 'done')"
  next=$((done_ + 1))

  # Each fixture gets its own directory, with every Modify: and Test: path
  # present and holding the symbol its line names, so plan-check has nothing
  # to complain about but the shape.
  dir="$work/$name"; mkdir -p "$dir"; cp "$plan" "$dir/plan.md"
  any=0; grep -q '^## Steps' "$dir/plan.md" || any=1
  for n in $(awk -v mode=list -v anywhere="$any" -f "$lib/steps.awk" "$dir/plan.md" | cut -d'|' -f1); do
    awk -v mode=paths -v n="$n" -v kinds="Modify Test" -v anywhere="$any" -f "$lib/steps.awk" "$dir/plan.md" \
      | while IFS='|' read -r _ p sym; do
          [ -n "$p" ] || continue
          # A fixture is repository-controlled, but a placeholder is only ever
          # written inside the scratch directory: a path that climbs out is a
          # fixture author's mistake, and it is named rather than followed.
          case "$p" in /*|../*|*/../*) note "$name: path '$p' leaves the fixture directory"; continue ;; esac
          mkdir -p "$dir/$(dirname "$p")" && printf '%s\n' "$sym" >> "$dir/$p"
        done
  done

  # steps.awk: the count and the ticks.
  list="$(awk -v mode=list -v anywhere="$any" -f "$lib/steps.awk" "$dir/plan.md")"
  same "$(printf '%s\n' "$list" | grep -c '^[0-9]')" "$steps" "$name: steps.awk step count"
  same "$(printf '%s\n' "$list" | grep -c '^[0-9]*|x|')" "$done_" "$name: steps.awk ticked count"

  # plan-check.sh: reads the same steps, and the paths above satisfy it.
  out="$(cd "$dir" && bash "$lib/plan-check.sh" plan.md 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || note "$name: plan-check exit $rc: $out"
  printf '%s\n' "$out" | grep -q "^plan-check: $((steps - done_)) step(s) checked" \
    || note "$name: plan-check checked the wrong number of steps: '$(printf '%s\n' "$out" | tail -1)'"

  # task-step.sh: the first unticked step, its path line, and its paths.
  out="$(cd "$dir" && bash "$lib/task-step.sh" plan.md --next 2>&1)"
  printf '%s\n' "$out" | grep -q "^## Step $next of $steps ($done_ done)$" \
    || note "$name: task-step --next did not hand over step $next of $steps: '$(printf '%s\n' "$out" | grep -m1 '^## Step')'"
  printf '%s\n' "$out" | grep -q '^\*\*Task file:\*\* /' || note "$name: task-step --next has no absolute Task file line"
  for key in $(sed -n 's/^\(paths[0-9]*\)=.*/\1/p' "$side"); do
    n="${key#paths}"
    same "$(cd "$dir" && bash "$lib/task-step.sh" plan.md --paths "$n" 2>&1 | paste -sd, -)" "$(expect "$side" "$key")" "$name: task-step --paths $n"
  done
  same "$(cd "$dir" && bash "$lib/task-step.sh" plan.md --count 2>&1)" "$done_ of $steps done" "$name: task-step --count"

  # step-budget.sh: a verdict line for the next step.
  out="$(cd "$dir" && DEV_SKILLS_CONTEXT=100000 bash "$lib/step-budget.sh" plan.md "$next" 2>&1 | tail -1)"
  printf '%s\n' "$out" | grep -q '^Budget: ' || note "$name: step-budget gave no verdict for step $next: '$out'"

  # tick.sh: ticks the next step in place, and the readers see it.
  ( cd "$dir" && bash "$lib/tick.sh" plan.md "$next" "landed" >/dev/null 2>&1 ) || note "$name: tick.sh could not tick step $next"
  same "$(cd "$dir" && bash "$lib/task-step.sh" plan.md --count 2>&1)" "$next of $steps done" "$name: task-step --count after tick"
done

[ "$count" -gt 0 ] || note 'no fixtures found under evals/fixtures/plans/'

if [ "$fails" -eq 0 ]; then
  printf 'fixtures: %s plan(s) a model wrote read the same by every script\n' "$count"
else
  printf 'fixtures: %s mismatch(es)\n' "$fails" >&2
fi
exit $((fails > 0))
