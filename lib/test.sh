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

out="$(
  if [ -n "$TIMEOUT" ]; then
    "$TIMEOUT" "$SECS" bash -c "$CMD" test.sh "$SCOPED" 2>&1
  else
    bash -c "$CMD" test.sh "$SCOPED" 2>&1
  fi
)"
rc=$?

# The runner's own summary, searched for from the end: the last line is often a
# blank or a coverage footer, and "tests pass" is not evidence of anything.
summary="$(printf '%s\n' "$out" | grep -E \
  '^(OK|FAILURES!|ERRORS!|PASS|FAIL|ok|--- FAIL)\b|Tests:[[:space:]]*[0-9]|test result:|[0-9]+ (passed|failed|error)|=+ .*(passed|failed|error)' \
  | tail -1 | sed 's/^[[:space:]]*//')"
[ -z "$summary" ] && summary="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1 | sed 's/^[[:space:]]*//')"
[ -z "$summary" ] && summary="(the runner printed nothing)"

if [ -n "$TIMEOUT" ] && [ "$rc" -eq 124 ]; then
  echo "TEST TIMEOUT — no result after ${SECS}s; a hang is a failure, not a slow pass"
  printf '%s\n' "$out" | tail -20
  exit 1
fi

if [ "$rc" -eq 0 ]; then
  printf 'TEST PASS | %s%s\n' "$summary" "$([ -z "$TIMEOUT" ] && printf ' [unbounded: no timeout tool on this host]')"
  exit 0
fi

printf 'TEST FAIL | %s\n' "$summary"
printf '%s\n' "$out" | tail -20
exit 1
