#!/usr/bin/env bash
# Every eval suite in this repository, in one command:
#
#   bash evals/run-all.sh
#
# Each suite under evals/<area>/ is a standalone script that prints one summary
# line and exits non-zero when what it asserts no longer holds. This runs all of
# them, keeps going after a failure so one broken suite does not hide the others,
# and exits non-zero if any failed. CI runs exactly this.
#
# Ported from claude-skills' evals/run-all.sh — MIT, same author.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
failed=0
ran=0

# find, not a glob: a suite added one level deeper would be skipped without a
# word. run-all.sh itself sits at the top and is not a suite.
while IFS= read -r suite; do
  [ -f "$suite" ] || continue
  name="${suite#"$root/evals/"}"
  ran=$((ran + 1))
  if bash "$suite"; then
    :
  else
    printf '^^ %s failed\n' "$name" >&2
    failed=$((failed + 1))
  fi
done <<EOF
$(find "$root/evals" -mindepth 2 -name '*.sh' | sort)
EOF

[ "$ran" -gt 0 ] || { printf 'no suites found under %s/evals\n' "$root" >&2; exit 1; }

printf '\n%s suite(s) ran, %s failed\n' "$ran" "$failed"
exit $((failed > 0))
