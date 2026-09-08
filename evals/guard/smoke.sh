#!/usr/bin/env bash
# End-to-end smoke test for OpenCode startup, plugins, and skills.
# Run it from anywhere:
#
#   bash evals/guard/smoke.sh
#
# Requires `opencode` to be in PATH. Installs the current checkout into an
# isolated temporary XDG_CONFIG_HOME, boots OpenCode, and asserts that plugins
# load without error and all dev-* skills are resolved cleanly.
#
# Exits 0 on success, 1 on failure.

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v opencode >/dev/null 2>&1; then
  if [ "${OPENCODE_SMOKE_REQUIRED:-0}" = "1" ]; then
    printf 'FAIL smoke: opencode is required but not installed\n' >&2
    exit 1
  fi
  printf 'smoke: opencode not installed (skipped)\n'
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

export XDG_CONFIG_HOME="$work/config"
mkdir -p "$XDG_CONFIG_HOME"

# 1. Install skills and dev-guard plugin into isolated config
bash "$root/install.sh" >/dev/null

# 2. Verify OpenCode startup and skill resolution
code=0
output="$(opencode debug skill --print-logs 2>&1)" || code=$?
if [ "$code" -ne 0 ]; then
  printf 'FAIL smoke: opencode debug skill exited with code %s\n%s\n' "$code" "$output" >&2
  exit 1
fi

# 3. Assert no plugin hook failures or runtime errors occurred
if echo "$output" | grep -q 'level=ERROR'; then
  printf 'FAIL smoke: OpenCode logged startup or plugin error\n%s\n' "$output" >&2
  exit 1
fi

# 4. Assert that all 9 dev skills were discovered by OpenCode
for skill in dev-init dev-plan dev-implement dev-review dev-fix dev-pr dev-pr-review dev-pr-comment dev-verify; do
  if ! echo "$output" | grep -q "\"name\": \"$skill\""; then
    printf 'FAIL smoke: OpenCode failed to resolve skill %s\n' "$skill" >&2
    exit 1
  fi
done

printf 'smoke: OpenCode startup, plugin loader, and all 9 skills pass\n'
