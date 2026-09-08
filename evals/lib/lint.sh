#!/usr/bin/env bash
# Cases for lib/lint.sh — run them from anywhere:
#
#   bash evals/lib/lint.sh
#
# The one thing a lint step must never do is read as a pass when it did not
# run, so the four outcomes are asserted by their exact first line: no lint
# command, could not determine what changed, nothing lintable, clean — and a
# real failure with the file named, and a file in a new untracked directory is
# linted rather than skipped, and a path holding shell metacharacters is linted
# rather than executed. The profile is written by hand so the
# suite never depends on Docker or on what this machine has installed.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
lint="$root/lib/lint.sh"
[ -f "$lint" ] || { printf 'no lint.sh at %s\n' "$lint" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$work" -c user.email=t@e -c user.name=t "$@"; }
profile() { # profile <lint value, JSON-quoted or null>
  mkdir -p "$work/.devskills"
  printf '{\n  "baseBranch": "main",\n  "lint": %s,\n  "test": null\n}\n' "$1" > "$work/.devskills/profile.json"
}
run() { out="$(cd "$work" && bash "$lint" 2>&1)"; rc=$?; }

# A stub linter: fails on any file containing the word BAD.
printf '#!/bin/sh\ngrep -q BAD "$1" && { echo "syntax error in $1"; exit 1; }\nexit 0\n' > "$work/lintstub.sh"
chmod +x "$work/lintstub.sh"

g init -q -b main .
mkdir -p "$work/src"
printf 'ok\n' > "$work/src/a.php"
g add -A && g commit -qm base

# No lint command: exit 2, and the line says so.
profile null
g switch -qc feature
printf 'more\n' >> "$work/src/a.php"
run
[ "$rc" -eq 2 ] || note "no lint command: exit $rc, want 2"
printf '%s\n' "$out" | grep -q '^NO LINT COMMAND' || note "no lint command: got '$out'"

# On the base branch: changed.sh refuses, so lint reports NOT RUN — never clean.
profile '"bash ./lintstub.sh {file}"'
g stash -q; g switch -q main
run
[ "$rc" -eq 2 ] || note "on the base branch: exit $rc, want 2"
printf '%s\n' "$out" | grep -q '^LINT NOT RUN' || note "on the base branch: got '$out'"
g switch -q feature; g stash pop -q

# Clean: one lintable file changed.
run
[ "$rc" -eq 0 ] || note "clean: exit $rc, want 0"
[ "$out" = 'lint: clean across 1 changed file(s)' ] || note "clean: got '$out'"

# A failure names the file and exits 1.
printf 'BAD\n' >> "$work/src/a.php"
run
[ "$rc" -eq 1 ] || note "failure: exit $rc, want 1"
printf '%s\n' "$out" | grep -q '^LINT FAIL src/a.php' || note "failure: the file is not named: '$out'"
printf '%s\n' "$out" | grep -q 'syntax error in src/a.php' || note 'failure: the linter output is not quoted'

# Nothing lintable among the changes is not a pass.
g checkout -q -- src/a.php
printf 'docs\n' > "$work/NOTES.md"
run
[ "$rc" -eq 0 ] || note "nothing lintable: exit $rc, want 0"
[ "$out" = 'lint: no lintable files among the changes — nothing was checked' ] || note "nothing lintable: got '$out'"

# A deleted file is skipped rather than linted.
profile '"bash ./lintstub.sh {file}"'
rm "$work/NOTES.md"; g rm -q src/a.php
run
[ "$rc" -eq 0 ] || note "deleted file: exit $rc, want 0"
printf '%s\n' "$out" | grep -q 'nothing was checked' || note "deleted file: got '$out'"

# Specific file argument: lints only that file directly
mkdir -p "$work/src"
printf 'ok\n' > "$work/src/a.php"
out="$(cd "$work" && bash "$lint" src/a.php 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || note "specific file clean: exit $rc, want 0"
[ "$out" = 'lint: clean across 1 changed file(s)' ] || note "specific file clean: got '$out'"

printf 'BAD\n' > "$work/src/a.php"
out="$(cd "$work" && bash "$lint" src/a.php 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || note "specific file bad: exit $rc, want 1"
printf '%s\n' "$out" | grep -q '^LINT FAIL src/a.php' || note "specific file bad: got '$out'"

# A file inside a NEW untracked directory is linted, not skipped. git status
# collapses such a directory to a single "?? dir/" entry unless changed.sh asks
# for -uall, and lint.sh then finds nothing to lint and reports it as clean —
# the whole point of the queue fix, asserted from the lint side.
rm -f "$work/src/a.php"          # its deletion is already staged; leave the new directory alone in the queue
mkdir -p "$work/assets/js"
printf 'ok\n' > "$work/assets/js/widget.js"
run
[ "$rc" -eq 0 ] || note "new untracked directory: exit $rc, want 0"
[ "$out" = 'lint: clean across 1 changed file(s)' ] || note "new untracked directory: got '$out'"

# And a bad file in that directory is caught, which is what proves it was
# actually linted rather than merely counted.
printf 'BAD\n' > "$work/assets/js/widget.js"
run
[ "$rc" -eq 1 ] || note "bad file in a new untracked directory: exit $rc, want 1"
printf '%s\n' "$out" | grep -q '^LINT FAIL assets/js/widget.js' || note "bad file in a new untracked directory: got '$out'"

# A filename is not a command. git quotes almost nothing printable, so a path
# like 'a;touch${IFS}PWNED.php' reaches the queue verbatim; spliced into a
# command string and evaluated, it runs — and the run still reports clean.
rm -f "$work/assets/js/widget.js" "$work/PWNED.php"
printf 'BAD\n' > "$work/src/a;touch\${IFS}PWNED.php"
run
[ -f "$work/PWNED.php" ] && note 'a filename executed: the path is being spliced into an evaluated command string'
printf '%s\n' "$out" | grep -qF 'LINT FAIL src/a;touch${IFS}PWNED.php' \
  || note "a path with shell metacharacters was not linted as a path: got '$out'"
rm -f "$work/src/a;touch\${IFS}PWNED.php" "$work/PWNED.php"

# {file} inside single quotes is refused, not linted-and-called-clean. "$1" is
# literal inside single quotes, and substituting a quoted path there would let
# the quotes close the region they sit in, so neither form is safe.
profile '"sh -c '"'"'bash ./lintstub.sh {file}'"'"'"'
printf 'BAD\n' > "$work/src/a.php"
run
[ "$rc" -eq 2 ] || note "single-quoted {file}: exit $rc, want 2"
printf '%s\n' "$out" | grep -q '^NO LINT COMMAND' || note "single-quoted {file}: got '$out'"
printf '%s\n' "$out" | grep -q 'clean across' && note 'single-quoted {file}: reported clean without linting'

# The container shape the profile writes for a project with no compose file:
# ${PWD} must still expand in the command, now that it runs under bash -c.
profile '"bash ./lintstub.sh ${PWD}/{file}"'
printf 'ok\n' > "$work/src/pwd.php"     # a fresh path: src/a.php carries a staged deletion from above
run
[ "$rc" -eq 0 ] || note "expanded \${PWD}: exit $rc, want 0"
[ "$out" = 'lint: clean across 1 changed file(s)' ] || note "expanded \${PWD}: got '$out'"
printf 'BAD\n' > "$work/src/pwd.php"
run
[ "$rc" -eq 1 ] || note "expanded \${PWD}, bad file: exit $rc, want 1"
printf '%s\n' "$out" | grep -q '^LINT FAIL src/pwd.php' || note "expanded \${PWD}, bad file: got '$out'"


if [ "$fails" -eq 0 ]; then
  printf 'lint: says which of the four outcomes happened, never a false clean\n'
else
  printf 'lint: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
