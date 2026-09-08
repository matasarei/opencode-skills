#!/usr/bin/env bash
# What /dev-pr needs to know about this branch, computed.
#
# Which base to target, whether a pull request already exists, whether the
# branch is ahead of or behind its remote, and which changed paths no step line
# names — none of it needs a model, and a model working it out will get the
# base wrong on a stacked branch.
#
#   pr-info.sh [<task-file>]     default: .tasks/<slug>.md, from the branch name
#
# Every line is "key: value". A branch named step/<slug>-<n> is a step branch:
# its base is step/<slug>-<n-1> when that exists on origin, else the profile's
# baseBranch. Then, if the task file is found, the step itself is printed after
# a "--- step" line, the way task-step.sh prints it.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
say() { printf '%s: %s\n' "$1" "$2"; }

BRANCH="$(git branch --show-current 2>/dev/null)"
BASEBR="$(sed -n 's/.*"baseBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .devskills/profile.json 2>/dev/null | head -1)"
[ -z "$BASEBR" ] && BASEBR=main

say branch "${BRANCH:-(detached)}"
say detached "$([ -z "$BRANCH" ] && echo yes || echo no)"
say on-base "$([ "$BRANCH" = "$BASEBR" ] && echo yes || echo no)"
say remote "$(git remote get-url origin 2>/dev/null || echo none)"

# A step branch: the slug and the number come from the name.
SLUG=""; STEP=""
case "$BRANCH" in
  step/*-[0-9]*)
    STEP="${BRANCH##*-}"; SLUG="${BRANCH#step/}"; SLUG="${SLUG%-*}"
    case "$STEP" in *[!0-9]*) STEP=""; SLUG="" ;; esac ;;
esac
say slug "${SLUG:-none}"
say step "${STEP:-none}"

# The base: the previous step's branch when it exists on origin (or locally,
# before the first push), else the base branch.
BASE="$BASEBR"; BASE_KIND=base
if [ -n "$STEP" ] && [ "$STEP" -gt 1 ]; then
  PREV="step/$SLUG-$((STEP - 1))"
  if git ls-remote --exit-code --heads origin "$PREV" >/dev/null 2>&1 || git show-ref --verify --quiet "refs/heads/$PREV"; then
    BASE="$PREV"; BASE_KIND=step
  fi
fi
say base "$BASE"
say base-kind "$BASE_KIND"

# gh: signed in, this branch's pull request, the base branch's pull request.
if command -v gh >/dev/null 2>&1; then
  say gh "$(gh auth status 2>&1 | grep -E 'Logged in|not logged' | head -1 | sed 's/^[[:space:]]*//')"
  say pr "$(gh pr view "$BRANCH" --json number,state,url,isDraft,baseRefName,title 2>/dev/null || echo none)"
  if [ "$BASE_KIND" = step ]; then
    say base-pr "$(gh pr view "$BASE" --json number -q .number 2>/dev/null || echo none)"
  else
    say base-pr none
  fi
  say house-style "$(gh pr list --state merged --limit 5 --json title -q '.[].title' 2>/dev/null | tr '\n' ';' | sed 's/;$//')"
else
  say gh "not installed"
  say pr none
  say base-pr none
  say house-style ""
fi

# Model detection: env var, project config, or global config
MODEL="${OPENCODE_MODEL:-${MODEL:-}}"
if [ -z "$MODEL" ]; then
  for cfg in opencode.jsonc opencode.json .opencode.jsonc .opencode.json .opencode/opencode.jsonc .opencode/opencode.json "${HOME}/.config/opencode/opencode.jsonc" "${HOME}/.config/opencode/opencode.json"; do
    if [ -f "$cfg" ]; then
      MODEL="$(sed -n 's/^[[:space:]]*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -1)"
      [ -n "$MODEL" ] && break
    fi
  done
fi
say model "${MODEL:-unknown}"

# The branch against its remote and its base.
if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null 2>&1; then
  say ahead "$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null)"
  say behind "$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null)"
else
  say ahead unpushed
  say behind 0
fi
if git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
  say commits "$(git rev-list --count "$BASE..HEAD" 2>/dev/null)"
else
  say commits "unknown (base '$BASE' not found locally)"
fi
say uncommitted "$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# What was actually proved, and for which commit. test.sh writes the receipt;
# without it /dev-pr can only take the model's word that a suite ran, which is
# how "tests pass" ends up in a body with nothing behind it.
TESTED=none
if [ -r .devskills/test-result ]; then
  T_SHA="$(cut -d' ' -f1 .devskills/test-result 2>/dev/null)"
  T_VERDICT="$(cut -d' ' -f2- .devskills/test-result 2>/dev/null)"
  if [ -n "$T_SHA" ]; then
    if [ "$T_SHA" = "$(git rev-parse HEAD 2>/dev/null)" ]; then
      TESTED="$T_VERDICT (this HEAD)"
    elif git merge-base --is-ancestor "$T_SHA" HEAD 2>/dev/null; then
      BACK="$(git rev-list --count "$T_SHA..HEAD" 2>/dev/null)"
      TESTED="$T_VERDICT (at $(git rev-parse --short "$T_SHA" 2>/dev/null), $BACK commit(s) back)"
    else
      TESTED="stale — recorded for $(git rev-parse --short "$T_SHA" 2>/dev/null), which is not behind HEAD"
    fi
  fi
fi
say tested "$TESTED"

# The task file and the step, when there is one: the diff's paths that no
# Create:/Modify:/Test: line of this step names are the coherence check.
TASK="${1:-}"
[ -z "$TASK" ] && [ -n "$SLUG" ] && [ -f ".tasks/$SLUG.md" ] && TASK=".tasks/$SLUG.md"
if [ -n "$TASK" ] && [ -f "$TASK" ] && [ -n "$STEP" ]; then
  say task-file "$TASK"
  PLANNED="$(bash "$HERE/task-step.sh" "$TASK" --paths "$STEP" 2>/dev/null)"
  CHANGED="$(git diff --name-only "$BASE...HEAD" 2>/dev/null)"
  UNPLANNED="$(printf '%s\n' "$CHANGED" | grep -v '^$' | while IFS= read -r p; do
    printf '%s\n' "$PLANNED" | grep -qxF -- "$p" || printf '%s ' "$p"
  done)"
  say unplanned "${UNPLANNED:-none}"
  echo "--- step"
  bash "$HERE/task-step.sh" "$TASK" "$STEP" 2>&1
else
  say task-file "${TASK:-none}"
  say unplanned "(no task file or not a step branch — nothing to compare against)"
fi
