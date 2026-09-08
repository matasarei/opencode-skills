#!/usr/bin/env bash
# Cases for lib/plan-input.sh — run them from anywhere:
#
#   bash evals/lib/plan-input.sh
#
# The script exists so the model never decides whether an argument is a file,
# an issue or a sentence. So each shape is asserted by its first line: FILE,
# ISSUE (through a fake gh), TEXT, MISSING FILE for a path-shaped argument that
# is not there — never silently a sentence — and EMPTY for nothing at all.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/plan-input.sh"
[ -f "$script" ] || { printf 'no plan-input.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
run() { out="$(cd "$work" && bash "$script" "$@" 2>&1)"; rc=$?; }
first() { printf '%s\n' "$out" | head -1; }

printf '# A brief\n\nBuild the thing.\n' > "$work/brief.md"

# A file: FILE, then its content.
run brief.md
[ "$rc" -eq 0 ] || note "file: exit $rc, want 0"
[ "$(first)" = 'FILE brief.md' ] || note "file: first line '$(first)'"
printf '%s\n' "$out" | grep -q '^Build the thing\.$' || note 'file: the content is not printed'

# Quotes around the argument are stripped, whitespace too.
run '  "brief.md" '
[ "$(first)" = 'FILE brief.md' ] || note "quoted file: first line '$(first)'"

# A sentence: TEXT, then the sentence as typed.
run the export merges departments that share a name
[ "$rc" -eq 0 ] || note "sentence: exit $rc, want 0"
[ "$(first)" = 'TEXT' ] || note "sentence: first line '$(first)'"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = 'the export merges departments that share a name' ] || note 'sentence: not printed as typed'

# A sentence with a bare number is a sentence, not an issue.
run fix 12 rows
[ "$(first)" = 'TEXT' ] || note "bare number: first line '$(first)'"

# Path-shaped but absent: MISSING FILE, exit 66 — never a sentence.
run .tasks/nope.md
[ "$rc" -eq 66 ] || note "missing file: exit $rc, want 66"
[ "$(first)" = 'MISSING FILE .tasks/nope.md' ] || note "missing file: first line '$(first)'"
run nope.md
[ "$rc" -eq 66 ] || note "missing .md at the root: exit $rc, want 66"

# Nothing: EMPTY, exit 65.
run
[ "$rc" -eq 65 ] || note "empty: exit $rc, want 65"
[ "$(first)" = 'EMPTY' ] || note "empty: first line '$(first)'"
run '   '
[ "$rc" -eq 65 ] || note "blank: exit $rc, want 65"

# An issue, through a fake gh that records what it was asked and answers.
stub="$work/bin"; mkdir -p "$stub"
cat > "$stub/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$(dirname "$0")/gh.args"
printf '# Export loses departments\n\nTwo departments share a name.\n'
EOF
chmod +x "$stub/gh"
( cd "$work" && git init -q . && git remote add origin https://github.com/o/r.git )
out="$(cd "$work" && PATH="$stub:$PATH" bash "$script" '#12' 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || note "issue #12: exit $rc, want 0"
[ "$(first)" = 'ISSUE o/r#12' ] || note "issue #12: first line '$(first)'"
grep -q 'issue view 12 --repo o/r' "$stub/gh.args" || note "issue #12: gh was asked '$(cat "$stub/gh.args")'"
printf '%s\n' "$out" | grep -q '^# Export loses departments$' || note 'issue #12: the title is not printed'

out="$(cd "$work" && PATH="$stub:$PATH" bash "$script" https://github.com/other/repo/issues/7 2>&1)"; rc=$?
[ "$(first)" = 'ISSUE other/repo#7' ] || note "issue URL: first line '$(first)'"
grep -q 'issue view 7 --repo other/repo' "$stub/gh.args" || note "issue URL: gh was asked '$(cat "$stub/gh.args")'"

# gh that fails: exit 69 with the reason, not a sentence.
printf '#!/bin/sh\necho "not logged in" >&2\nexit 1\n' > "$stub/gh"
out="$(cd "$work" && PATH="$stub:$PATH" bash "$script" '#12' 2>&1)"; rc=$?
[ "$rc" -eq 69 ] || note "gh failing: exit $rc, want 69"
printf '%s\n' "$out" | grep -q 'gh auth status' || note 'gh failing: the reason does not point at gh auth status'

# No gh at all: exit 69. A PATH of only the tools the script needs.
nogh="$work/nogh"; mkdir -p "$nogh"
for t in bash sed cat git grep; do
  for c in /bin/$t /usr/bin/$t; do [ -x "$c" ] && ln -sf "$c" "$nogh/$t" && break; done
done
if [ -x "$nogh/sed" ]; then
  out="$(cd "$work" && PATH="$nogh" bash "$script" '#12' 2>&1)"; rc=$?
  [ "$rc" -eq 69 ] || note "no gh: exit $rc, want 69"
  printf '%s\n' "$out" | grep -q 'gh is not installed' || note "no gh: got '$out'"
fi

# A file of review findings is named FINDINGS, not FILE, and its content is not
# reprinted: /dev-fix injects this script and findings-check.sh with the same
# arguments, so printing it here made the same list arrive twice — once as a
# brief to plan from, once as the verified list to apply.
printf 'BLOCKER | src/a.php:12 | it breaks | EVIDENCE: $x = 1;\n' > "$work/findings.md"
printf 'WARNING | src/b.php:3 | it might | EVIDENCE: $y = 2;\n' >> "$work/findings.md"
run findings.md
[ "$(first)" = "FINDINGS findings.md" ] || note "a findings file: first line is '$(first)', want FINDINGS"
printf '%s\n' "$out" | grep -q 'EVIDENCE:' && note 'a findings file: its lines were reprinted as a brief'

# A brief that merely mentions a severity word is still a brief.
printf '# Fix the BLOCKER in the export\n\nIt is wrong.\n' > "$work/brief.md"
run brief.md
[ "$(first)" = "FILE brief.md" ] || note "a prose brief: first line is '$(first)', want FILE"

if [ "$fails" -eq 0 ]; then
  printf 'plan-input: file, issue, sentence, missing and empty each get their first line\n'
else
  printf 'plan-input: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
