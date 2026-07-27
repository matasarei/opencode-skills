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

# Get the file list first, and keep changed.sh's exit status. Reading it straight
# into the loop would swallow a failure: on the base branch, or with no diff,
# changed.sh exits non-zero and prints nothing, the loop body never runs, and a
# report of "clean" would mean "nothing was linted" while reading as "nothing was
# wrong". That is the one thing a lint step must never do.
QUEUE="$(bash "$HERE/changed.sh" "${1:-}" 2>&1)"
if [ $? -ne 0 ]; then
  echo "LINT NOT RUN — could not determine what changed:"
  printf '%s\n' "$QUEUE" | head -3
  exit 2
fi

failed=0
linted=0
while read -r rank status file; do
  [ -z "${file:-}" ] && continue
  [ "$status" = "D" ] && continue
  [ -f "$file" ] || continue
  case "$file" in *.php|*.py|*.js|*.ts) ;; *) continue ;; esac

  cmd="${LINT//\{file\}/$file}"
  if ! out="$(eval "$cmd" 2>&1)"; then
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
