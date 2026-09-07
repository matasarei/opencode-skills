#!/usr/bin/env bash
# Cases for lib/plan-check.sh — run them from anywhere:
#
#   bash evals/lib/plan-check.sh
#
# The plan-side hallucination filter: a Modify: path that is not there, a
# symbol that is not in the file, a Create: path that already exists — each is
# one line, and the exit code says whether any fired. A path an earlier step
# creates is fine; a ticked step is not checked; prose inside parentheses does
# not turn into paths.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/plan-check.sh"
[ -f "$script" ] || { printf 'no plan-check.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
run() { out="$(cd "$work" && bash "$script" "$@" 2>"$work/err")"; rc=$?; }
has() { printf '%s\n' "$out" | grep -qF -- "$1" || note "$2: missing line '$1'"; }
hasnt() { printf '%s\n' "$out" | grep -qF -- "$1" && note "$2: unexpected line '$1'"; }

mkdir -p "$work/src" "$work/tests"
printf '<?php\nfunction render() {}\n' > "$work/src/page.php"
printf '<?php\n' > "$work/src/exists.php"
printf '<?php\n' > "$work/tests/OldTest.php"

cat > "$work/plan.md" <<'EOF'
# A plan

**Type:** feature

## Steps

1. [x] Done already
   - Create: `src/exists.php`
   - Modify: `src/gone.php` (was there then)
2. [ ] Good step
   - Create: `src/new.php`
   - Modify: `src/page.php:2 (render)`, `tests/OldTest.php` (extend the fixture, see step 1)
   - Test: `tests/OldTest.php`
3. [ ] Bad step
   - Create: `src/exists.php`
   - Modify: `src/missing.php:1-5`, `src/page.php:2 (nothere)`
   - Test: none
4. [ ] Uses what step 2 creates
   - Modify: `src/new.php:1 (init)`, `src/page.php`
5. [ ] Nothing to check
   - Modify: none
   - Test: none — covered by step 2
EOF

run plan.md
[ "$rc" -eq 1 ] || note "plan with problems: exit $rc, want 1"
has 'STEP 3 | src/exists.php | Create: path already exists' 'step 3'
has "STEP 3 | src/missing.php | Modify: path does not exist, and no earlier step creates it" 'step 3'
has "STEP 3 | src/page.php | Modify: symbol 'nothere' not found in the file" 'step 3'
hasnt 'STEP 2' 'step 2 is clean'
hasnt 'STEP 4' 'step 4 modifies a file step 2 creates'
hasnt 'STEP 1' 'ticked steps are not checked'
hasnt 'STEP 5' 'a step with none has nothing to check'
[ "$(printf '%s\n' "$out" | grep -c '^STEP')" -eq 3 ] || note "expected exactly 3 problem lines, got $(printf '%s\n' "$out" | grep -c '^STEP')"
grep -q '^plan-check: 4 step(s) checked, 3 problem(s)$' "$work/err" || note "summary: '$(cat "$work/err")'"

# --step limits the check to one step.
run plan.md --step 2
[ "$rc" -eq 0 ] || note "--step 2: exit $rc, want 0"
grep -q '1 step(s) checked, 0 problem(s)' "$work/err" || note "--step 2: '$(cat "$work/err")'"
run plan.md --step 3
[ "$rc" -eq 1 ] || note "--step 3: exit $rc, want 1"

# A clean plan exits 0 with its summary; a plan with every step ticked has nothing to check.
sed '/^3\. /,/^4\. /{/^4\. /!d;}' "$work/plan.md" > "$work/clean.md"
run clean.md
[ "$rc" -eq 0 ] || note "clean plan: exit $rc, want 0: $out"
sed 's/^\([0-9]\)\. \[ \]/\1. [x]/' "$work/plan.md" > "$work/ticked.md"
run ticked.md
[ "$rc" -eq 0 ] || note "all ticked: exit $rc, want 0"
grep -q 'no unticked step to check' "$work/err" || note "all ticked: '$(cat "$work/err")'"

# Errors.
run nope.md;            [ "$rc" -eq 66 ] || note "no such file: exit $rc, want 66"
run;                    [ "$rc" -eq 64 ] || note "no arguments: exit $rc, want 64"
run plan.md --step x;   [ "$rc" -eq 64 ] || note "--step x: exit $rc, want 64"

if [ "$fails" -eq 0 ]; then
  printf 'plan-check: names every path a plan gets wrong, and nothing else\n'
else
  printf 'plan-check: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
