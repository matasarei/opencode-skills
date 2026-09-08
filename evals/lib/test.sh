#!/usr/bin/env bash
# Cases for lib/test.sh — run them from anywhere:
#
#   bash evals/lib/test.sh
#
# The one thing this script must never do is read as a pass when nothing ran, so
# each outcome is asserted by its exact verdict line: pass, fail, missing,
# timeout, and a scoped run. The runner is a stub and the profile is written by
# hand, so the suite never depends on what this machine has installed.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/test.sh"
[ -f "$script" ] || { printf 'no test.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
profile() { # profile <test value> <testScoped value> [timeoutTool]
  mkdir -p "$work/.devskills"
  printf '{\n  "baseBranch": "main",\n  "test": %s,\n  "testScoped": %s,\n  "timeoutTool": %s\n}\n' \
    "$1" "$2" "${3:-null}" > "$work/.devskills/profile.json"
}
run() { out="$(cd "$work" && bash "$script" "$@" 2>&1)"; rc=$?; }
first() { printf '%s\n' "$out" | head -1; }

# A stub runner that prints a PHPUnit-shaped summary and fails only on demand.
printf '#!/bin/sh\nif [ "$1" = fail ]; then echo "some noise"; echo "FAILURES! Tests: 43, Failures: 1."; exit 1; fi\nif [ "$1" = hang ]; then sleep 30; fi\necho "some noise"\necho "OK (43 tests, 118 assertions)"\necho ""\n' > "$work/runner.sh"
chmod +x "$work/runner.sh"

# No test command is MISSING, never a pass.
profile null null
run
[ "$rc" -eq 2 ] || note "no test command: exit $rc, want 2"
case "$(first)" in "TEST MISSING"*) ;; *) note "no test command: '$(first)'" ;; esac

# A pass quotes the runner's own summary, not the last line (which is blank).
profile '"sh ./runner.sh"' null
run
[ "$rc" -eq 0 ] || note "pass: exit $rc, want 0"
case "$(first)" in "TEST PASS | OK (43 tests, 118 assertions)"*) ;; *) note "pass: '$(first)'" ;; esac

# With no timeout tool the verdict says so rather than dropping the bound quietly.
printf '%s\n' "$out" | head -1 | grep -q 'unbounded' || note 'pass: a null timeoutTool is not declared in the verdict'

# A failure quotes the failing summary and exits 1.
profile '"sh ./runner.sh fail"' null
run
[ "$rc" -eq 1 ] || note "fail: exit $rc, want 1"
case "$(first)" in "TEST FAIL | FAILURES! Tests: 43, Failures: 1."*) ;; *) note "fail: '$(first)'" ;; esac
printf '%s\n' "$out" | grep -q 'some noise' || note 'fail: the runner output is not shown below the verdict'

# --scoped uses testScoped with {name} filled in, and the name is an argument.
profile '"sh ./runner.sh"' '"sh ./runner.sh {name}"'
run --scoped fail
[ "$rc" -eq 1 ] || note "scoped: exit $rc, want 1 (the stub fails on 'fail')"
case "$(first)" in "TEST FAIL | FAILURES!"*) ;; *) note "scoped: '$(first)'" ;; esac

# A scope that is not a plain test name is refused, not quoted around.
run --scoped 'x; touch PWNED'
[ "$rc" -eq 2 ] || note "hostile scope: exit $rc, want 2"
[ -f "$work/PWNED" ] && note 'hostile scope: the value executed'

# testScoped null falls back to the whole suite rather than running nothing.
profile '"sh ./runner.sh"' null
run --scoped SomeTest
[ "$rc" -eq 0 ] || note "scoped with no testScoped: exit $rc, want 0"
case "$(first)" in "TEST PASS"*) ;; *) note "scoped with no testScoped: '$(first)'" ;; esac

# A hang is a failure, when the host can bound it.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  t=timeout; command -v timeout >/dev/null 2>&1 || t=gtimeout
  profile '"sh ./runner.sh hang"' null "\"$t\""
  out="$(cd "$work" && DEV_SKILLS_TEST_TIMEOUT=1 bash "$script" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || note "timeout: exit $rc, want 1"
  case "$(first)" in "TEST TIMEOUT"*) ;; *) note "timeout: '$(first)'" ;; esac
else
  printf 'test: no timeout tool on this host, the timeout case was skipped\n' >&2
fi

# The receipt: what was proved, and for which commit. /dev-pr reads it instead
# of taking the model's word that a suite ran.
if command -v git >/dev/null 2>&1; then
  git -C "$work" init -q -b main . 2>/dev/null
  printf 'x\n' > "$work/f"
  git -C "$work" add -A >/dev/null 2>&1
  git -C "$work" -c user.email=t@e -c user.name=t commit -qm base >/dev/null 2>&1
  head_sha="$(git -C "$work" rev-parse HEAD 2>/dev/null)"

  profile '"sh ./runner.sh"' null
  rm -f "$work/.devskills/test-result"
  run
  [ -f "$work/.devskills/test-result" ] || note 'receipt: a pass wrote none'
  [ "$(cut -d' ' -f1 "$work/.devskills/test-result" 2>/dev/null)" = "$head_sha" ] \
    || note 'receipt: the recorded commit is not HEAD'
  cut -d' ' -f2- "$work/.devskills/test-result" 2>/dev/null | grep -q '^TEST PASS' \
    || note "receipt: the verdict was not recorded: '$(cat "$work/.devskills/test-result" 2>/dev/null)'"

  # A failure is a result too, and must not leave the last pass standing.
  profile '"sh ./runner.sh fail"' null
  run
  cut -d' ' -f2- "$work/.devskills/test-result" 2>/dev/null | grep -q '^TEST FAIL' \
    || note 'receipt: a failure did not overwrite the previous pass'

  # No test command writes nothing: there is no result to record.
  rm -f "$work/.devskills/test-result"
  profile null null
  run
  [ -f "$work/.devskills/test-result" ] && note 'receipt: TEST MISSING wrote a receipt'
fi

if [ "$fails" -eq 0 ]; then
  printf 'test: pass, fail, missing, scoped and timeout each get their verdict line\n'
else
  printf 'test: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
