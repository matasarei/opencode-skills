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

failed=0
while read -r rank status file; do
  [ -z "${file:-}" ] && continue
  [ "$status" = "D" ] && continue
  [ -f "$file" ] || continue
  case "$file" in *.php|*.py|*.js|*.ts) ;; *) continue ;; esac

  cmd="${LINT//\{file\}/$file}"
  out="$(eval "$cmd" 2>&1)"
  if [ $? -ne 0 ]; then
    echo "LINT FAIL $file"
    echo "$out" | head -5
    failed=1
  fi
done < <(bash "$HERE/changed.sh" "${1:-}" 2>/dev/null)

[ "$failed" -eq 0 ] && echo "lint: clean across all changed files"
exit "$failed"
