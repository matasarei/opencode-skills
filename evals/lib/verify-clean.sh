#!/usr/bin/env bash
# Cases for lib/verify-clean.sh — run them from anywhere:
#
#   bash evals/lib/verify-clean.sh
#
# The whole reason this script exists is that it must NOT see the working tree:
# it is standing in for the CI a repository does not have, and a check that
# quietly inherits your uncommitted files is not that. So the central case is a
# failing test that exists only in the tree, which test.sh must fail on and this
# must not. The rest is the cleanup, which matters because it runs on a path
# where things go wrong.
#
# The runner is a committed stub, so the suite needs no node, php or network.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/verify-clean.sh"
[ -f "$script" ] || { printf 'no verify-clean.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
repo="$work/repo"; mkdir -p "$repo"

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$repo" -c user.email=t@e -c user.name=t "$@"; }
run() { out="$(cd "$repo" && bash "$script" 2>&1)"; rc=$?; }
first() { printf '%s\n' "$out" | head -1; }
strays() { ls -d "${TMPDIR:-/tmp}"/verify-clean.* 2>/dev/null | wc -l | tr -d ' '; }

before="$(strays)"

g init -q -b main .
mkdir -p "$repo/.devskills"
# As a real repository does (.gitignore:1 here): the profile and the receipts are
# generated per machine, and `add -A` below would otherwise commit them.
printf '.devskills/\n' > "$repo/.gitignore"
# A runner that fails when the file BAD exists — committed, so the clone has it.
printf '#!/bin/sh\nif [ -f BAD ]; then echo "FAILURES! Tests: 1, Failures: 1."; exit 1; fi\necho "OK (1 test, 1 assertion)"\n' > "$repo/runner.sh"
printf '{\n  "baseBranch": "main",\n  "test": "sh ./runner.sh",\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"
printf 'x\n' > "$repo/f"
g add -A && g commit -qm base

# A clean HEAD passes, and the verdict carries the runner's own line.
run
[ "$rc" -eq 0 ] || note "clean HEAD: exit $rc, want 0"
case "$(first)" in "CLEAN PASS | OK (1 test, 1 assertion)"*) ;; *) note "clean HEAD: '$(first)'" ;; esac

# The case this exists for: a break that is only in the working tree. test.sh
# must see it; this must not, because HEAD is what a reviewer will get.
printf 'x\n' > "$repo/BAD"
out2="$(cd "$repo" && bash "$root/lib/test.sh" 2>&1 | head -1)"
case "$out2" in "TEST FAIL"*) ;; *) note "uncommitted break: test.sh did not fail, got '$out2'" ;; esac
run
[ "$rc" -eq 0 ] || note "uncommitted break: verify-clean exit $rc, want 0 — it read the working tree"
case "$(first)" in "CLEAN PASS"*) ;; *) note "uncommitted break: '$(first)'" ;; esac

# Committed, it fails there too — otherwise the check proves nothing at all.
g add -A && g commit -qm break
run
[ "$rc" -eq 1 ] || note "committed break: exit $rc, want 1"
case "$(first)" in "CLEAN FAIL | FAILURES! Tests: 1, Failures: 1."*) ;; *) note "committed break: '$(first)'" ;; esac
printf '%s\n' "$out" | grep -q 'FAILURES!' || note 'committed break: the runner output is not shown below the verdict'

# It checks HEAD, not the branch the clone would land on by default.
g rm -q BAD && g commit -qm fixed
g switch -q -c side && printf 'x\n' > "$repo/BAD" && g add -A && g commit -qm "broken on side"
run
[ "$rc" -eq 1 ] || note "on a branch: exit $rc, want 1 — it checked out main instead of HEAD"

g switch -q main   # the case above ends on `side`, where BAD is committed

# A clone has no vendor/ or node_modules/, so the profile's install command runs
# first — otherwise the check fails every project whose dependencies are ignored,
# which is the mirror image of the false pass it exists to prevent.
printf '.devskills/\ndeps/\n' > "$repo/.gitignore"
printf '#!/bin/sh\nif [ ! -d deps ]; then echo "Error: dependencies not installed"; exit 1; fi\nif [ -f BAD ]; then echo "FAILURES! Tests: 1, Failures: 1."; exit 1; fi\necho "OK (1 test, 1 assertion)"\n' > "$repo/runner.sh"
mkdir -p "$repo/deps"; printf 'x\n' > "$repo/deps/lib.txt"
printf '{\n  "baseBranch": "main",\n  "install": "mkdir -p deps",\n  "test": "sh ./runner.sh",\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"
g add -A && g commit -qm deps
run
[ "$rc" -eq 0 ] || note "gitignored dependencies: exit $rc, want 0 — install did not run in the clone"
case "$(first)" in "CLEAN PASS"*) ;; *) note "gitignored dependencies: '$(first)'" ;; esac

# An install that fails is not a test failure: nothing ran, so it exits 2.
# (No commit: the profile is ignored, and verify-clean.sh copies it into the clone.)
printf '{\n  "baseBranch": "main",\n  "install": "exit 3",\n  "test": "sh ./runner.sh",\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"
run
[ "$rc" -eq 2 ] || note "failing install: exit $rc, want 2"
case "$(first)" in "CLEAN SETUP FAIL"*) ;; *) note "failing install: '$(first)'" ;; esac
printf '%s\n' "$out" | grep -q 'printed nothing' || note "failing install: a silent installer has no reason line: '$(first)'"

# Back to something that works, so the cases below start from a known state.
printf '{\n  "baseBranch": "main",\n  "install": "mkdir -p deps",\n  "test": "sh ./runner.sh",\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"

# No test command is MISSING, never a pass.
printf '{\n  "baseBranch": "main",\n  "test": null,\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"
run
[ "$rc" -eq 2 ] || note "no test command: exit $rc, want 2"
case "$(first)" in "CLEAN MISSING"*) ;; *) note "no test command: '$(first)'" ;; esac

# Not a git repository at all.
plain="$work/plain"; mkdir -p "$plain"
out="$(cd "$plain" && bash "$script" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || note "not a repository: exit $rc, want 2"

# Nothing left behind, across every path above including the failing ones.
[ "$(strays)" = "$before" ] || note "temporary clones left behind: $before before, $(strays) after"

# The receipt. test.sh writes one so /dev-pr cannot take the model's word that a
# suite ran; without the same from here, a repository whose only check is this
# script has nothing /dev-pr can refuse on.
printf '{\n  "baseBranch": "main",\n  "install": "mkdir -p deps",\n  "test": "sh ./runner.sh",\n  "testScoped": null,\n  "timeoutTool": null\n}\n' > "$repo/.devskills/profile.json"
rm -f "$repo/.devskills/clean-result"
( cd "$repo" && bash "$script" >/dev/null 2>&1 )
[ -r "$repo/.devskills/clean-result" ] || note 'no receipt was written to .devskills/clean-result'
r_sha="$(cut -d' ' -f1 "$repo/.devskills/clean-result" 2>/dev/null)"
r_verdict="$(cut -d' ' -f2- "$repo/.devskills/clean-result" 2>/dev/null)"
[ "$r_sha" = "$(git -C "$repo" rev-parse HEAD)" ] \
  || note "the receipt names '$r_sha', want this HEAD"
case "$r_verdict" in
  "CLEAN PASS | "*) ;;
  *) note "the receipt carries '$r_verdict', want a CLEAN verdict in test.sh's shape" ;;
esac

if [ "$fails" -eq 0 ]; then
  printf 'verify-clean: checks HEAD and not the working tree, and cleans up after itself\n'
else
  printf 'verify-clean: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
