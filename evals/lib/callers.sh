#!/usr/bin/env bash
# Cases for lib/callers.sh — run them from anywhere:
#
#   bash evals/lib/callers.sh
#
# Exits 0 when every case matches, 1 otherwise.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
callers="$root/lib/callers.sh"
[ -f "$callers" ] || { printf 'no callers.sh at %s\n' "$callers" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# Bad usage: exit 2
out="$(bash "$callers" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || note "bad usage: exit $rc, want 2"

mkdir -p "$work/src" "$work/tests" "$work/vendor" "$work/node_modules" "$work/.git" "$work/.devskills" "$work/.tasks"
printf 'oldFunction();\n' > "$work/src/app.php"
printf 'testOldFunction(); oldFunction();\n' > "$work/tests/AppTest.php"
printf 'oldFunction();\n' > "$work/vendor/lib.php"
printf 'oldFunction();\n' > "$work/node_modules/pkg.js"
printf 'oldFunction();\n' > "$work/.devskills/notes.md"
printf 'oldFunction();\n' > "$work/.tasks/task.md"

# Finds callers in src and tests, excludes vendor, node_modules, .devskills, .tasks
out="$(cd "$work" && bash "$callers" "oldFunction")"; rc=$?
[ "$rc" -eq 1 ] || note "callers found: exit $rc, want 1"
printf '%s\n' "$out" | grep -q 'src/app.php' || note 'caller in src/app.php missing'
printf '%s\n' "$out" | grep -q 'tests/AppTest.php' || note 'caller in tests/AppTest.php missing'
printf '%s\n' "$out" | grep -qv 'vendor/' || note 'vendor was not excluded'
printf '%s\n' "$out" | grep -qv 'node_modules/' || note 'node_modules was not excluded'
printf '%s\n' "$out" | grep -qv '\.devskills/' || note '.devskills was not excluded'
printf '%s\n' "$out" | grep -qv '\.tasks/' || note '.tasks was not excluded'

# Scoped paths
out="$(cd "$work" && bash "$callers" "oldFunction" tests)"; rc=$?
[ "$rc" -eq 1 ] || note "scoped path: exit $rc, want 1"
printf '%s\n' "$out" | grep -q 'tests/AppTest.php' || note 'scoped search missing tests/AppTest.php'
printf '%s\n' "$out" | grep -qv 'src/app.php' || note 'scoped search should not search src/app.php'

# Clean: no callers
out="$(cd "$work" && bash "$callers" "nonExistentSymbol")"; rc=$?
[ "$rc" -eq 0 ] || note "clean: exit $rc, want 0"
[ -z "$out" ] || note "clean: expected empty output, got '$out'"

if [ "$fails" -eq 0 ]; then
  printf 'callers: finds surviving callers and respects exclusions\n'
else
  printf 'callers: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
