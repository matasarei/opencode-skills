#!/usr/bin/env bash
# Run this project's tests on a clean clone of HEAD.
#
# This is what a repository without CI is missing, and only that. The local
# cycle already proves the code — test.sh before the commit, lint.sh on the
# changed files — but it proves it *here*, and a run passes for reasons that do
# not travel: an uncommitted file, a stale install, a cached artefact, a tool
# that exists on this machine and nowhere else. One of this repository's own
# suites passed on macOS and failed on Ubuntu for exactly that last reason.
#
# So: clone HEAD somewhere empty, run the same command there, and report what
# happened. It needs no network, no forge and no remote, which is the point —
# `verification: local-only` in the profile is who this is for.
#
#   verify-clean.sh
#
# One verdict line, in test.sh's shape and carrying its output:
#
#   CLEAN PASS | OK (43 tests, 118 assertions)
#   CLEAN FAIL | FAILURES! Tests: 43, Failures: 1.
#   CLEAN MISSING — no test command in the profile
#   CLEAN SETUP FAIL | <the installer's last line>
#
# The profile's install command runs first, because a clone has no vendor/ or
# node_modules/ — that is a clone's whole point, and it is what CI does too.
#
# Exit 0 pass, 1 fail, 2 nothing ran (no test command, or install failed). Slower than test.sh by a clone, so it is
# not automatic: run it before a pull request, or when the profile says nothing
# else ever will.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "CLEAN MISSING — not a git repository" >&2; exit 2; }
SHA="$(git rev-parse HEAD 2>/dev/null)"
[ -n "$SHA" ] || { echo "CLEAN MISSING — no commit to check out" >&2; exit 2; }

[ -f .devskills/profile.json ] || bash "$HERE/profile.sh" >/dev/null 2>&1
PROFILE="$PWD/.devskills/profile.json"
[ -f "$PROFILE" ] || { echo "CLEAN MISSING — no profile to take the test command from" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify-clean.XXXXXX")"
# Even when the clone fails, even when the suite hangs and is killed.
trap 'rm -rf "$TMP"' EXIT INT TERM

# A local clone, then the exact commit: `git clone <path>` checks out whatever
# the source's HEAD points at, which on a step branch is not this commit.
if ! git clone -q --no-hardlinks "$PWD" "$TMP/repo" 2>/dev/null; then
  echo "CLEAN MISSING — could not clone this repository" >&2
  exit 2
fi
if ! git -C "$TMP/repo" checkout -q --detach "$SHA" 2>/dev/null; then
  echo "CLEAN MISSING — the clone does not have $SHA" >&2
  exit 2
fi

# The profile travels with it. Re-detecting inside the clone would be a second
# detection to explain when the two disagree, and the point here is the tree
# being clean, not the profile being rediscovered.
mkdir -p "$TMP/repo/.devskills"
cp "$PROFILE" "$TMP/repo/.devskills/profile.json"

# A clone carries committed files and nothing else, so vendor/, node_modules/
# and every other ignored directory is absent. Without this the check reports a
# failure for a project that is fine, which is the mirror image of the false
# pass it exists to prevent — and a CI workflow runs `npm ci` before `npm test`
# for the same reason. Skipped when the profile has no install command.
INSTALL="$(sed -n 's/.*"install"[[:space:]]*:[[:space:]]*"\(.*\)",$/\1/p' "$PROFILE" 2>/dev/null | head -1 | sed 's/\\"/"/g')"
if [ -n "$INSTALL" ] && [ "$INSTALL" != null ]; then
  if ! setup="$(cd "$TMP/repo" && bash -c "$INSTALL" install 2>&1)"; then
    reason="$(printf '%s\n' "$setup" | grep -v '^[[:space:]]*$' | tail -1)"
    [ -n "$reason" ] || reason="(the installer printed nothing)"
    printf 'CLEAN SETUP FAIL | %s\n' "$reason"
    printf '%s\n' "$setup" | tail -20
    exit 2
  fi
fi

out="$(cd "$TMP/repo" && bash "$HERE/test.sh" 2>&1)"
rc=$?

verdict="$(printf '%s\n' "$out" | head -1)"
case "$verdict" in
  "TEST PASS | "*)  printf 'CLEAN PASS | %s\n' "${verdict#TEST PASS | }" ;;
  "TEST FAIL | "*)  printf 'CLEAN FAIL | %s\n' "${verdict#TEST FAIL | }" ;;
  "TEST MISSING"*)  printf 'CLEAN MISSING%s\n' "${verdict#TEST MISSING}" ;;
  "TEST TIMEOUT"*)  printf 'CLEAN TIMEOUT%s\n' "${verdict#TEST TIMEOUT}" ;;
  *)                printf 'CLEAN FAIL | %s\n' "$verdict" ;;
esac
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | tail -20
exit "$rc"
