#!/usr/bin/env bash
# Cases for lib/step-budget.sh — run them from anywhere:
#
#   bash evals/lib/step-budget.sh
#
# The cap follows contextTokens (12 lines per 1k), the paths come from the
# step's own Modify: and Test: lines in the shape /dev-plan writes, a file that
# does not exist weighs nothing, and the verdict line is exact — fits, or OVER
# with the amount and "split if you can", because it is a recommendation.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
budget="$root/lib/step-budget.sh"
[ -f "$budget" ] || { printf 'no step-budget.sh at %s\n' "$budget" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
run() { out="$(cd "$work" && DEV_SKILLS_CONTEXT="${CTX:-}" bash "$budget" "$@" 2>&1)"; rc=$?; }
last() { printf '%s\n' "$out" | tail -1; }

mkdir -p "$work/src" "$work/tests" "$work/.devskills"
seq 1 100 > "$work/src/small.php"
seq 1 900 > "$work/src/big.php"
seq 1 50  > "$work/tests/SmallTest.php"
printf '{\n  "baseBranch": "main",\n  "contextTokens": 50000,\n  "notes": null\n}\n' > "$work/.devskills/profile.json"

cat > "$work/plan.md" <<'EOF'
# A plan

## Steps

1. [ ] A small step
   - Create: `src/New.php`
   - Modify: `src/small.php:10-20 (render)`, `tests/SmallTest.php`
   - Test: `tests/SmallTest.php`
   - Check: `bash run.sh`
2. [x] A big step — landed
   - Create: none
   - Modify: `src/big.php:1-900 (everything)` (rewritten, see the note), `src/small.php`
   - Test: none — covered by step 1
3. [ ] Nothing on disk
   - Modify: none
   - Test: none

## Do not touch
- `src/big.php` in step 1
EOF

# Step 1 with the profile's 50k window: small + test = 150 lines, cap 600. The Create:
# file and the (symbol) suffix are ignored; each file is listed once.
run plan.md 1
[ "$rc" -eq 0 ] || note "step 1: exit $rc, want 0"
[ "$(last)" = 'Budget: 150/600 lines — fits' ] || note "step 1: '$(last)'"
printf '%s\n' "$out" | grep -q '^100 src/small.php$' || note 'step 1: src/small.php not listed with its line count'
printf '%s\n' "$out" | grep -q 'New.php' && note 'step 1: a Create: file was counted'

# The profile's contextTokens is read when the environment does not override:
# 50000 → cap 600; step 2 is 1000 lines → OVER by 400.
CTX="" run plan.md 2
[ "$rc" -eq 1 ] || note "step 2 at 50k: exit $rc, want 1"
[ "$(last)" = 'Budget: 1000/600 lines — OVER by 400, split if you can' ] || note "step 2 at 50k: '$(last)'"

# The environment wins over the profile: at 100k the same step fits.
CTX=100000 run plan.md 2
[ "$rc" -eq 0 ] || note "step 2 at 100k: exit $rc, want 0"
[ "$(last)" = 'Budget: 1000/1200 lines — fits' ] || note "step 2 at 100k: '$(last)'"

# A ticked step is still measurable; a step with nothing on disk is 0.
CTX=100000 run plan.md 3
[ "$(last)" = 'Budget: 0/1200 lines — fits' ] || note "step 3: '$(last)'"

# --paths: the files given, missing ones weigh nothing.
CTX=64000 run --paths src/big.php src/nope.php
[ "$rc" -eq 1 ] || note "--paths at 64k: exit $rc, want 1"
[ "$(last)" = 'Budget: 900/768 lines — OVER by 132, split if you can' ] || note "--paths at 64k: '$(last)'"

# Errors are errors: no such step, no such file, no arguments.
CTX=100000 run plan.md 9;   [ "$rc" -eq 66 ] || note "no such step: exit $rc, want 66"
printf '%s\n' "$out" | grep -q 'N. \[ \] title' || note "no such step: the message should show the step shape, got '$out'"
CTX=100000 run nope.md 1;   [ "$rc" -eq 66 ] || note "no such file: exit $rc, want 66"
CTX=100000 run;             [ "$rc" -eq 64 ] || note "no arguments: exit $rc, want 64"
CTX=100000 run --paths;     [ "$rc" -eq 64 ] || note "--paths with nothing: exit $rc, want 64"

# The cap has to follow the window the machine actually has, now that
# profile.sh detects it rather than assuming 100k. These are the two windows the
# README recommends, and the numbers a planner is sizing steps against.
cap_for() { # cap_for <contextTokens> -> the cap the verdict line reports
  printf '{\n  "baseBranch": "main",\n  "contextTokens": %s,\n  "notes": null\n}\n' "$1" > "$work/.devskills/profile.json"
  CTX='' run --paths "$work/src/small.php"
  printf '%s\n' "$out" | sed -n 's|.*/\([0-9]*\) lines.*|\1|p' | tail -1
}

[ "$(cap_for 65536)"  = 786 ]  || note "a 64k window caps at $(cap_for 65536) lines, want 786"
[ "$(cap_for 131072)" = 1572 ] || note "a 128k window caps at $(cap_for 131072) lines, want 1572"
[ "$(cap_for 32768)"  = 393 ]  || note "a 32k window caps at $(cap_for 32768) lines, want 393"

# The override still beats the detected window, which is what makes it useful
# on a machine whose server is configured differently from its config file.
printf '{\n  "baseBranch": "main",\n  "contextTokens": 131072,\n  "notes": null\n}\n' > "$work/.devskills/profile.json"
CTX=65536 run --paths "$work/src/small.php"
printf '%s\n' "$out" | grep -q '/786 lines' || note "DEV_SKILLS_CONTEXT no longer overrides a detected window: '$(last)'"

# And the same step is over at 32k and fits at 128k — the whole point of
# detecting the window rather than assuming one.
printf '{\n  "baseBranch": "main",\n  "contextTokens": 32768,\n  "notes": null\n}\n' > "$work/.devskills/profile.json"
CTX='' run --paths "$work/src/big.php"
[ "$rc" -eq 1 ] || note "900 lines should be OVER at 32k, exit $rc"
printf '{\n  "baseBranch": "main",\n  "contextTokens": 131072,\n  "notes": null\n}\n' > "$work/.devskills/profile.json"
CTX='' run --paths "$work/src/big.php"
[ "$rc" -eq 0 ] || note "900 lines should fit at 128k, exit $rc"

if [ "$fails" -eq 0 ]; then
  printf 'step-budget: the cap follows the window, the paths follow the step\n'
else
  printf 'step-budget: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
