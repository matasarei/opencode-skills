#!/usr/bin/env bash
# Cases for lib/changed.sh — run them from anywhere:
#
#   bash evals/lib/changed.sh
#
# The queue's order is the decision a small model must not make, so the ranks
# are asserted one by one against a fixture branch, along with the two refusals
# (on the base branch, nothing changed), that uncommitted work is in the queue,
# that a rename yields the destination path rather than "old -> new", and that a
# new directory of untracked files arrives as its files and never as a directory.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
changed="$root/lib/changed.sh"
[ -f "$changed" ] || { printf 'no changed.sh at %s\n' "$changed" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
# The repository sits one level down, so stderr captures in $work are not untracked files in it.
repo="$work/repo"; mkdir -p "$repo"

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$repo" -c user.email=t@e -c user.name=t "$@"; }
rank_of() { printf '%s\n' "$out" | awk -v f="$1" '$3 == f {print $1}'; }
status_of() { printf '%s\n' "$out" | awk -v f="$1" '$3 == f {print $2}'; }
want_rank() { [ "$(rank_of "$1")" = "$2" ] || note "$1: rank '$(rank_of "$1")', want $2"; }

# The base: a few files that already exist, so "modified" and "added" differ.
g init -q -b main .
mkdir -p "$repo/src" "$repo/db" "$repo/tests" "$repo/vendor"
printf '<?php\n// app\n' > "$repo/src/app.php"
printf '<?php\n// old\n' > "$repo/src/old.php"
printf 'x\n' > "$repo/README.md"
g add -A && g commit -qm base

# Refusal 1: on the base branch there is nothing to compare against.
( cd "$repo" && bash "$changed" main >/dev/null 2>"$work/err" ); rc=$?
[ "$rc" -eq 2 ] || note "on the base branch: exit $rc, want 2"
grep -q "you are on 'main'" "$work/err" || note 'on the base branch: the message should name the branch'

# Refusal 2: a branch with no changes.
g switch -qc feature
( cd "$repo" && bash "$changed" main >/dev/null 2>"$work/err" ); rc=$?
[ "$rc" -eq 3 ] || note "no changes: exit $rc, want 3"

# One file of each rank, committed on the branch.
printf '<?php\n// schema\n' > "$repo/db/upgrade.php"                       # 1: schema
printf '<?php\n// app changed\n' > "$repo/src/app.php"                     # 2: existing code modified
printf '<?php\nforeach ($a as $b) {}\n' > "$repo/src/loop.php"             # 3: new code with a loop
printf '<?php\n// plain\n' > "$repo/src/plain.php"                         # 4: new code, nothing risky
printf '<?php\n// test\n' > "$repo/tests/PlainTest.php"                    # 5: a test
printf '{}\n' > "$repo/composer.lock"                                      # 6: a lock file
printf 'y\n' > "$repo/README.md"                                           # 7: docs
printf '<?php\n' > "$repo/vendor/lib.php"                                  # 9: vendored
g mv src/old.php src/renamed.php                                        # a pure rename
g add -A && g commit -qm change

# And one uncommitted, untracked file: it must be in the queue too.
printf '<?php\n// wip\n' > "$repo/src/wip.php"

# And a whole new directory of untracked files. Porcelain collapses these to a
# single "?? assets/js/" entry unless -uall is passed, and then neither file is
# ever linted or reviewed.
mkdir -p "$repo/assets/js"
printf 'export const a = 1\n' > "$repo/assets/js/widget.js"
printf 'export const b = 2\n' > "$repo/assets/js/helper.js"

out="$(cd "$repo" && bash "$changed" main 2>&1)"

want_rank db/upgrade.php 1
want_rank src/app.php 2
want_rank src/loop.php 3
want_rank src/plain.php 4
want_rank tests/PlainTest.php 5
want_rank composer.lock 6
want_rank README.md 7
want_rank vendor/lib.php 9
want_rank src/wip.php 4
[ "$(status_of src/wip.php)" = "??" ] || note "an untracked file should carry status ??, got '$(status_of src/wip.php)'"

# The new directory: both of its files are in the queue, and the directory
# itself is never a queue entry — a path ending in "/" is not a path.
want_rank assets/js/widget.js 4
want_rank assets/js/helper.js 4
printf '%s\n' "$out" | grep -qE ' [^ ]+/$' && note 'a directory reached the queue; the status call needs -uall'

# The rename: destination path, status R, and no "->" anywhere in the queue.
[ -n "$(rank_of src/renamed.php)" ] || note 'a renamed file is missing from the queue under its new path'
printf '%s\n' "$out" | grep -q -- '->' && note 'a rename leaked through as "old -> new"'
printf '%s\n' "$out" | grep -q 'src/old.php' && note 'the old path of a rename is still in the queue'

# Sorted by rank: the first line is rank 1, the last is rank 9.
[ "$(printf '%s\n' "$out" | head -1 | cut -d' ' -f1)" = 1 ] || note 'the queue does not start at rank 1'
[ "$(printf '%s\n' "$out" | tail -1 | cut -d' ' -f1)" = 9 ] || note 'the queue does not end at rank 9'

# .devskills/ is never part of the change.
mkdir -p "$repo/.devskills"; printf '{}\n' > "$repo/.devskills/profile.json"
out="$(cd "$repo" && bash "$changed" main 2>&1)"
printf '%s\n' "$out" | grep -q '\.devskills' && note '.devskills/ files were listed as changes'

# A base that does not exist is refused, not treated as empty.
( cd "$repo" && bash "$changed" nope >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 1 ] || note "a missing base exited $rc, want 1"

if [ "$fails" -eq 0 ]; then
  printf 'changed: every rank follows its fixture, renames and untracked files included\n'
else
  printf 'changed: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
