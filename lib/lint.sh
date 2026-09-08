#!/usr/bin/env bash
# Lint every changed file using the command from the profile, through exec.prefix.
#
# This is the one mechanical check a review can make, and in a repository with no
# tests and no working CI it is the only thing standing between a parse error and
# a white page in production. It is also the one check that must never be reported
# as having run when it did not.
#
#   lint.sh [base]
#
# Exit 0 clean, 1 failures found, 2 no lint command available.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -f .devskills/profile.json ] || bash "$HERE/profile.sh" >/dev/null 2>&1

LINT="$(sed -n 's/.*"lint"[[:space:]]*:[[:space:]]*"\(.*\)",$/\1/p' .devskills/profile.json 2>/dev/null | head -1 | sed 's/\\"/"/g')"
if [ -z "$LINT" ] || [ "$LINT" = "null" ]; then
  echo "NO LINT COMMAND — this review is unlinted. Say so in the report."
  exit 2
fi

# If specific files are given, lint them directly. Otherwise, inspect
# what changed against the base branch using changed.sh.
if [ "$#" -gt 0 ] && [ -f "$1" ]; then
  QUEUE=""
  for f in "$@"; do
    [ -f "$f" ] && QUEUE="${QUEUE:+${QUEUE}
}1 M $f"
  done
else
  if ! QUEUE="$(bash "$HERE/changed.sh" "${1:-}" 2>&1)"; then
    echo "LINT NOT RUN — could not determine what changed:"
    printf '%s\n' "$QUEUE" | head -3
    exit 2
  fi
fi

failed=0
linted=0
while read -r _ status file; do
  [ -z "${file:-}" ] && continue
  [ "$status" = "D" ] && continue
  [ -f "$file" ] || continue
  case "$file" in *.php|*.py|*.js|*.ts) ;; *) continue ;; esac

  # The path travels as an argument, never spliced into the string the shell
  # evaluates. git quotes almost nothing printable, so 'a;touch${IFS}PWNED.php'
  # is a path it hands over verbatim — interpolating that into a command and
  # evaluating it runs it, and the run still reports "clean". {file} becomes
  # "$1", and the path arrives as bash -c's first positional parameter.
  cmd="${LINT//\{file\}/\"\$1\"}"
  if ! out="$(bash -c "$cmd" lint.sh "$file" 2>&1)"; then
    echo "LINT FAIL $file"
    printf '%s\n' "$out" | head -5
    failed=1
  fi
  linted=$((linted+1))
done <<EOF
$QUEUE
EOF

if [ "$failed" -ne 0 ]; then
  exit 1
elif [ "$linted" -eq 0 ]; then
  # Also not a pass. Say which it is rather than implying the linter approved.
  echo "lint: no lintable files among the changes — nothing was checked"
else
  echo "lint: clean across $linted changed file(s)"
fi
exit 0
