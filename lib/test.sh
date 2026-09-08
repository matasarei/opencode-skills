#!/usr/bin/env bash
# Run this project's tests and say in one line what happened.
#
# Every skill used to spell this out as prose: pick `test` or `testScoped`, wrap
# it in `timeoutTool`, run it, then quote "the runner's result line". That is
# four judgement calls, and a model that drops any one of them reports "tests
# pass" with nothing behind it. They are decided here instead.
#
#   test.sh                    the profile's `test`
#   test.sh --scoped <name>    the profile's `testScoped`, with {name} filled in
#
# The first line of output is always the verdict, carrying the runner's own
# summary so it can be quoted as evidence:
#
#   TEST PASS | OK (43 tests, 118 assertions)
#   TEST FAIL | FAILURES! Tests: 43, Assertions: 118, Failures: 1.
#   TEST MISSING — no test command in the profile; this repository may have none
#   TEST TIMEOUT — no result after 600s; a hang is a failure, not a slow pass
#
# On anything but PASS the runner's last 20 lines follow, so the failure can be
# read without running it again. Exit 0 pass, 1 fail or timeout, 2 nothing ran.
#
# The verdict is also written to .devskills/test-result as "<HEAD sha> <verdict>",
# so /dev-pr can tell whether anything was actually run for the code it is about
# to propose, instead of taking the model's word for it.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

SECS="${DEV_SKILLS_TEST_TIMEOUT:-600}"
case "$SECS" in ''|*[!0-9]*) SECS=600 ;; esac

[ -f .devskills/profile.json ] || bash "$HERE/profile.sh" >/dev/null 2>&1

field() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\(.*\)\",\{0,1\}$/\1/p" .devskills/profile.json 2>/dev/null | head -1 | sed 's/",\{0,1\}$//; s/\\"/"/g'; }

SCOPED=""
case "${1:-}" in
  --scoped)
    SCOPED="${2:-}"
    # A filter name reaches a command line. Anything but a plain test identifier
    # is refused here rather than quoted around later; see lib/lint.sh for why a
    # value spliced into a command string is not made safe by quoting it.
    case "$SCOPED" in
      ''|*[!A-Za-z0-9_.:/-]*) echo "TEST MISSING — '--scoped $SCOPED' is not a plain test name"; exit 2 ;;
    esac ;;
  "") ;;
  *) echo "usage: test.sh [--scoped <name>]" >&2; exit 64 ;;
esac

if [ -n "$SCOPED" ]; then
  CMD="$(field testScoped)"
  [ -z "$CMD" ] || [ "$CMD" = null ] && CMD="$(field test)"
else
  CMD="$(field test)"
fi

if [ -z "$CMD" ] || [ "$CMD" = null ]; then
  echo "TEST MISSING — no test command in the profile; this repository may have none"
  exit 2
fi

TIMEOUT="$(field timeoutTool)"
[ "$TIMEOUT" = null ] && TIMEOUT=""

CMD="${CMD//\{name\}/\"\$1\"}"

# $0 for the runner shell. It was "test.sh", so an absent toolchain came back as
# "test.sh: go: command not found" — which reads as this script being broken
# rather than the project's runner being missing. Deriving the runner's own name
# gives "go: go: ...", so say plainly whose command it is.
RUNNER="project test command"

out="$(
  if [ -n "$TIMEOUT" ]; then
    "$TIMEOUT" "$SECS" bash -c "$CMD" "$RUNNER" "$SCOPED" 2>&1
  else
    bash -c "$CMD" "$RUNNER" "$SCOPED" 2>&1
  fi
)"
rc=$?

# The runner's own summary, searched for from the end: the last line is often a
# blank or a coverage footer, and "tests pass" is not evidence of anything.
# node --test prints its counts on separate lines, so neither alone is a summary
# and the generic search below picks up "duration_ms" on a pass and a stray brace
# on a failure. Field-based, because the marker it prefixes them with is
# multibyte and matching it by regex is locale-dependent.
summary="$(printf '%s\n' "$out" | awk '
  NF >= 2 && $(NF-1) == "pass" && $NF ~ /^[0-9]+$/ { p = $NF }
  NF >= 2 && $(NF-1) == "fail" && $NF ~ /^[0-9]+$/ { f = $NF }
  END { if (p != "" && f != "") printf "pass %s, fail %s", p, f }
')"

[ -z "$summary" ] && summary="$(printf '%s\n' "$out" | grep -E \
  '^(OK|FAILURES!|ERRORS!|PASS|FAIL|ok|--- FAIL)\b|Tests:[[:space:]]*[0-9]|test result:|[0-9]+ (passed|failed|error)|=+ .*(passed|failed|error)' \
  | tail -1 | sed 's/^[[:space:]]*//')"
[ -z "$summary" ] && summary="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1 | sed 's/^[[:space:]]*//')"
[ -z "$summary" ] && summary="(the runner printed nothing)"

# The receipt: what was proved, and for which commit. A verdict with no commit
# behind it is what "tests pass" in a pull request body has always been.
receipt() {
  sha="$(git rev-parse HEAD 2>/dev/null)" || return 0
  [ -n "$sha" ] || return 0
  mkdir -p .devskills 2>/dev/null || return 0
  printf '%s %s\n' "$sha" "$1" > .devskills/test-result 2>/dev/null || true
}

if [ -n "$TIMEOUT" ] && [ "$rc" -eq 124 ]; then
  verdict="TEST TIMEOUT — no result after ${SECS}s; a hang is a failure, not a slow pass"
  printf '%s\n' "$verdict"
  receipt "$verdict"
  printf '%s\n' "$out" | tail -20
  exit 1
fi

if [ "$rc" -eq 0 ]; then
  verdict="TEST PASS | $summary$([ -z "$TIMEOUT" ] && printf ' [unbounded: no timeout tool on this host]')"
  printf '%s\n' "$verdict"
  receipt "$verdict"
  exit 0
fi

verdict="TEST FAIL | $summary"
printf '%s\n' "$verdict"
receipt "$verdict"
printf '%s\n' "$out" | tail -20
exit 1
