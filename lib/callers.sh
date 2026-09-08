#!/usr/bin/env bash
# Search for surviving callers of a renamed, moved or removed symbol across the project.
#
#   callers.sh <symbol> [path...]
#
# Exits 0 if no callers found (clean), 1 if surviving callers found, 2 on bad usage.

set -u

SYM="${1:-}"
if [ -z "$SYM" ]; then
  echo "usage: callers.sh <symbol> [path...]" >&2
  exit 2
fi
shift

EXCLUDES=(
  --exclude-dir=vendor
  --exclude-dir=node_modules
  --exclude-dir=.git
  --exclude-dir=.devskills
  --exclude-dir=.tasks
  --exclude-dir=.opencode
)

if [ "$#" -gt 0 ]; then
  matches="$(grep -rn "${EXCLUDES[@]}" -F -- "$SYM" "$@" 2>/dev/null || true)"
else
  matches="$(grep -rn "${EXCLUDES[@]}" -F -- "$SYM" . 2>/dev/null || true)"
fi

if [ -n "$matches" ]; then
  printf '%s\n' "$matches"
  exit 1
fi
exit 0
