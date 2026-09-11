#!/usr/bin/env bash
# Cases for lib/findings-check.sh — run them from anywhere:
#
#   bash evals/lib/findings-check.sh
#
# The filter is the hallucination gate, so what is asserted is exactly what it
# keeps and what it drops: evidence present → kept; evidence present far from
# the claimed line → kept with the line corrected; evidence absent, path absent,
# evidence missing, or a line not in the format → dropped or ignored. Whitespace
# inside the evidence is normalised, and only whitespace.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
check="$root/lib/findings-check.sh"
[ -f "$check" ] || { printf 'no findings-check.sh at %s\n' "$check" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A fixture file with a known line at a known number, and one far down.
mkdir -p "$work/src"
{
  printf '<?php\n'
  for i in $(seq 2 19); do printf '// filler %s\n' "$i"; done
  printf '$sheet->setCellValue($col, $dept);\n'          # line 20
  for i in $(seq 21 39); do printf '// filler %s\n' "$i"; done
  printf '    $db->execute("DELETE FROM x");\n'           # line 40, indented
} > "$work/src/Export.php"

cat > "$work/findings.md" <<'EOF'
BLOCKER | src/Export.php:20 | user input reaches the cell unescaped | EVIDENCE: $sheet->setCellValue($col, $dept);
BLOCKER | src/Export.php:3 | far from the claimed line | EVIDENCE: $db->execute("DELETE FROM x");
WARNING | src/Export.php:20 | invented line | EVIDENCE: $db->execute("DROP TABLE users");
WARNING | src/Missing.php:1 | file does not exist | EVIDENCE: anything
NIT | src/Export.php:20 | no evidence at all |
this line is not a finding and must be ignored
SMELL | src/Export.php | no line number | EVIDENCE: $sheet->setCellValue($col, $dept);
EOF

out="$(cd "$work" && bash "$check" findings.md 2>"$work/err")"
err="$(cat "$work/err")"

# Kept: the exact line at the right place.
printf '%s\n' "$out" | grep -qF 'BLOCKER | src/Export.php:20 | user input' || note 'a true finding with exact evidence was dropped'

# Kept, corrected: evidence present (spacing normalised) but 37 lines away.
printf '%s\n' "$out" | grep -F 'far from the claimed line' | grep -q '\[line corrected to 40\]' \
  || note 'evidence far from the claimed line should be kept with the line corrected to 40'

# Dropped: invented evidence, missing file, empty evidence, no line number.
printf '%s\n' "$out" | grep -q 'invented line'        && note 'an invented evidence line survived'
printf '%s\n' "$out" | grep -q 'file does not exist'  && note 'a finding on a missing file survived'
printf '%s\n' "$out" | grep -q 'no evidence at all'   && note 'a finding with empty evidence survived'
printf '%s\n' "$out" | grep -q 'no line number'       && note 'a finding without a line number survived (path = loc)'
printf '%s\n' "$out" | grep -q 'not a finding'        && note 'a non-finding line was printed as a finding'

# The audit line counts what happened: 2 kept, 4 dropped, the prose line ignored.
printf '%s\n' "$err" | grep -q '^findings: 2 verified, 4 dropped as unverifiable$' \
  || note "audit line wrong: '$err' (want 'findings: 2 verified, 4 dropped as unverifiable')"

# No findings file at all is not an error — nothing to check, exit 0, says so.
( cd "$work" && bash "$check" nope.md >/dev/null 2>"$work/err2" ); rc=$?
[ "$rc" -eq 0 ] || note "a missing findings file exited $rc, want 0"
grep -q 'no findings file' "$work/err2" || note 'a missing findings file should say so on stderr'

# /dev-fix injects this script with its $ARGUMENTS, which is a sentence when the
# brief is one: stdout stays empty, stderr says so once, and the sentence is
# not echoed back as a filename into the block the model reads.
out3="$(cd "$work" && bash "$check" "the export blows up when a department has no head" 2>"$work/err3")"; rc=$?
[ "$rc" -eq 0 ] || note "a sentence argument: exit $rc, want 0"
[ -z "$out3" ] || note "a sentence argument: stdout should be empty, got '$out3'"
[ "$(wc -l < "$work/err3" | tr -d ' ')" = 1 ] || note "a sentence argument: stderr should be one line"
grep -q 'department' "$work/err3" && note 'a sentence argument: the sentence was echoed back as a path'
grep -q 'no findings file' "$work/err3" || note "a sentence argument: stderr should still say no findings file, got '$(cat "$work/err3")'"
# An issue URL is a brief too — /dev-fix accepts one — and it has slashes and dots.
( cd "$work" && bash "$check" "https://github.com/o/r/issues/3" >/dev/null 2>"$work/err4" )
grep -q 'github' "$work/err4" && note 'a URL argument: the URL was echoed back as a path'
grep -q 'brief' "$work/err4" || note "a URL argument: should be named a brief, got '$(cat "$work/err4")'"

if [ "$fails" -eq 0 ]; then
  printf 'findings-check: keeps what the file proves, drops the rest\n'
else
  printf 'findings-check: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
