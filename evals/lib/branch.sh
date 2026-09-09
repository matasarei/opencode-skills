#!/usr/bin/env bash
# Cases for lib/branch.sh — run them from anywhere:
#
#   bash evals/lib/branch.sh
#
# The base is the part that matters: step 1 comes off the repository's base
# branch and every later step comes off its predecessor, because that is what
# makes the pull requests stack. Getting it wrong points a step's PR at main and
# shows every earlier step's diff in it. Also asserted: an existing branch is
# switched to rather than re-cut, and a switch never carries uncommitted work.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/branch.sh"
[ -f "$script" ] || { printf 'no branch.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
repo="$work/repo"; mkdir -p "$repo"

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$repo" -c user.email=t@e -c user.name=t "$@"; }
run() { out="$(cd "$repo" && bash "$script" "$@" 2>&1)"; rc=$?; }
on() { g branch --show-current; }

g init -q -b main .
mkdir -p "$repo/.devskills" "$repo/.tasks"
printf '{\n  "baseBranch": "main"\n}\n' > "$repo/.devskills/profile.json"
printf 'x\n' > "$repo/README.md"
printf '# T\n\n## Steps\n\n1. [ ] one\n\n2. [ ] two\n\n3. [ ] three\n' > "$repo/.tasks/mytask.md"
g add -A && g commit -qm base

# Step 1 comes off the base branch.
run .tasks/mytask.md 1
[ "$rc" -eq 0 ] || note "step 1: exit $rc, want 0"
[ "$(on)" = "step/mytask-1" ] || note "step 1: on '$(on)', want step/mytask-1"
printf '%s\n' "$out" | grep -q 'cut from main' || note "step 1: '$out'"

# A commit on it, so the stack has something to carry.
printf 'one\n' > "$repo/one.txt"; g add -A && g commit -qm one

# Step 2 comes off step 1, not off main. This is the whole point.
run .tasks/mytask.md 2
[ "$(on)" = "step/mytask-2" ] || note "step 2: on '$(on)', want step/mytask-2"
printf '%s\n' "$out" | grep -q 'cut from step/mytask-1' || note "step 2: '$out'"
[ -f "$repo/one.txt" ] || note 'step 2: step 1 commit is missing, so it was not cut from step 1'

# Already on it: a no-op that says so, not a re-cut.
run .tasks/mytask.md 2
[ "$rc" -eq 0 ] || note "already on it: exit $rc, want 0"
printf '%s\n' "$out" | grep -q 'already on it' || note "already on it: '$out'"

# An existing branch is switched to, never re-cut: re-cutting would strand the
# commits already made on it.
printf 'two\n' > "$repo/two.txt"; g add -A && g commit -qm two
g switch -q main
run .tasks/mytask.md 2
[ "$(on)" = "step/mytask-2" ] || note "existing branch: on '$(on)'"
printf '%s\n' "$out" | grep -q 'already existed' || note "existing branch: '$out'"
[ -f "$repo/two.txt" ] || note 'existing branch: it was re-cut and the commit was stranded'

# A switch must not carry uncommitted work into another step's branch.
g switch -q main
printf 'wip\n' > "$repo/wip.txt"
run .tasks/mytask.md 3
[ "$rc" -eq 3 ] || note "dirty tree: exit $rc, want 3"
[ "$(on)" = "main" ] || note "dirty tree: it switched anyway, to '$(on)'"
printf '%s\n' "$out" | grep -q 'uncommitted' || note "dirty tree: '$out'"

# But a dirty tree on the branch already wanted is fine — that is resuming.
rm -f "$repo/wip.txt"
run .tasks/mytask.md 2
printf 'wip\n' > "$repo/wip.txt"
run .tasks/mytask.md 2
[ "$rc" -eq 0 ] || note "dirty tree, already on it: exit $rc, want 0"
rm -f "$repo/wip.txt"

# A predecessor that has already been merged is not a base any more. It is still
# a local branch, so "does it exist" says yes and the step gets cut from a branch
# that has landed -- four commits behind, and its pull request opens against a
# base nobody will merge again. This happened three times in one plan before the
# check existed.
g switch -q main
g merge -q --no-ff step/mytask-2 -m 'merge step 2'
run .tasks/mytask.md 3
[ "$rc" -eq 0 ] || note "merged predecessor: exit $rc, want 0"
[ "$(on)" = "step/mytask-3" ] || note "merged predecessor: on '$(on)', want step/mytask-3"
printf '%s\n' "$out" | grep -q 'cut from main' \
  || note "merged predecessor: should come off the base branch, got '$out'"
# And it has to say why, or "cut from main" on step 5 reads as a bug.
printf '%s\n' "$out" | grep -q 'step/mytask-2 has already been merged' \
  || note "merged predecessor: the line should name why it fell back, got '$out'"

# Usage and missing input.
run .tasks/nope.md 1; [ "$rc" -eq 66 ] || note "missing task file: exit $rc, want 66"
run .tasks/mytask.md x; [ "$rc" -eq 64 ] || note "bad step number: exit $rc, want 64"

if [ "$fails" -eq 0 ]; then
  printf 'branch: step 1 off the base, later steps off their predecessor, no re-cutting\n'
else
  printf 'branch: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
