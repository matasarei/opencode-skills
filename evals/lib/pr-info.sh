#!/usr/bin/env bash
# Cases for lib/pr-info.sh — run them from anywhere:
#
#   bash evals/lib/pr-info.sh
#
# A fixture with a bare origin, two stacked step branches and a task file. What
# is asserted: the base is the previous step's branch when it exists on origin
# and the base branch otherwise; the branch's own pull request comes from gh
# (faked here); ahead/behind, the commit count and the coherence check — the
# paths in the diff that no step line names — follow the fixture.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/pr-info.sh"
[ -f "$script" ] || { printf 'no pr-info.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
repo="$work/repo"; mkdir -p "$repo"
g() { git -C "$repo" -c user.email=t@e -c user.name=t "$@"; }
row() { printf '%s\n' "$out" | sed -n "s/^$1: //p" | head -1; }
want() { [ "$(row "$1")" = "$2" ] || note "$3: $1 = '$(row "$1")', want '$2'"; }

# A fake gh: no pull request for any branch, signed in, two merged titles.
stub="$work/bin"; mkdir -p "$stub"
cat > "$stub/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth status") echo "  ✓ Logged in to github.com account t (keyring)" ;;
  "pr view") [ "$3" = "step/x-1" ] && [ "$4" = "--json" ] && { echo 11; exit 0; }; exit 1 ;;
  "pr list") printf 'feat: earlier\nfix: before that\n' ;;
esac
EOF
chmod +x "$stub/gh"
mkdir -p "$work/home"
run() { out="$(cd "$repo" && HOME="$work/home" PATH="$stub:$PATH" bash "$script" "$@" 2>&1)"; }

# The fixture: main, a bare origin, step 1 pushed, step 2 cut from it.
git init -q --bare "$work/origin.git"
g init -q -b main .
mkdir -p "$repo/src" "$repo/.tasks" "$repo/.devskills"
printf '{ "baseBranch": "main" }\n' > "$repo/.devskills/profile.json"
printf 'a\n' > "$repo/src/a.php"
cat > "$repo/.tasks/x.md" <<'EOF'
# X

**Type:** feature

## Acceptance criteria
- [ ] it works

## Steps

1. [x] One — landed
   - Modify: `src/a.php`
2. [ ] Two
   - Create: `src/b.php`
   - Modify: `src/a.php:1 (a)`
   - Test: none

## Do not touch
- nothing
EOF
g add -A && g commit -qm base
g remote add origin "$work/origin.git"
g push -q -u origin main


g switch -qc step/x-1
printf 'b\n' >> "$repo/src/a.php"; g commit -qam 'step 1'
g push -q -u origin step/x-1

# Step 1: its base is main, its pull request comes from gh, it is pushed.
run
want branch 'step/x-1' 'step 1'
want slug 'x' 'step 1'
want step '1' 'step 1'
want base 'main' 'step 1'
want base-kind 'base' 'step 1'
want base-pr 'none' 'step 1'
want ahead '0' 'step 1'
want behind '0' 'step 1'
want commits '1' 'step 1'
want on-base 'no' 'step 1'
printf '%s\n' "$out" | grep -q '^pr: 11$' || note "step 1: pr = '$(row pr)', want the fake gh's answer"
want house-style 'feat: earlier;fix: before that' 'step 1'
want model 'unknown' 'default model when no config present'

# Model detected from local opencode.jsonc
printf '{\n  "model": "qwen3-coder-30b"\n}\n' > "$repo/opencode.jsonc"
run
want model 'qwen3-coder-30b' 'model detected from opencode.jsonc'
rm -f "$repo/opencode.jsonc"

# Step 2, cut from step 1, unpushed, with one planned and one unplanned change.
g switch -qc step/x-2
printf 'c\n' >> "$repo/src/a.php"
printf 'new\n' > "$repo/src/b.php"
printf 'stray\n' > "$repo/src/stray.php"
g add -A && g commit -qm 'step 2'
printf 'wip\n' > "$repo/wip.txt"

run
want base 'step/x-1' 'step 2'
want base-kind 'step' 'step 2'
want base-pr '11' 'step 2'
want pr 'none' 'step 2'
want ahead 'unpushed' 'step 2'
want commits '1' 'step 2'
want uncommitted '1' 'step 2'
want task-file '.tasks/x.md' 'step 2'
want unplanned 'src/stray.php ' 'step 2'
printf '%s\n' "$out" | grep -q '^--- step$' || note 'step 2: the step block is not appended'
printf '%s\n' "$out" | grep -q '^2\. \[ \] Two$' || note 'step 2: the step line is missing after --- step'
printf '%s\n' "$out" | grep -q 'it works' || note 'step 2: the criteria are missing after --- step'

# Once the predecessor is merged it is not a base any more. A branch that has
# landed still exists on origin, so "does it exist" cannot tell the two apart —
# and stacking on a merged branch opens the pull request against a base nobody
# will merge again, which is how work goes missing.
g switch -q main
g merge -q --no-ff step/x-1 -m 'merge step 1'
g push -q origin main
g switch -q step/x-2
run
want base 'main' 'predecessor already merged'
want base-kind 'base' 'predecessor already merged'
want base-pr 'none' 'predecessor already merged'

# The task file may be given explicitly; a missing previous branch falls back to main.
run .tasks/x.md
want task-file '.tasks/x.md' 'explicit task file'
g switch -qc step/x-9
run
want base 'main' 'no previous step branch'
want base-kind 'base' 'no previous step branch'

# On the base branch, or not a step branch at all.
g switch -q main
run
want on-base 'yes' 'on main'
want step 'none' 'on main'
printf '%s\n' "$out" | grep -q '^unplanned: (no task file' || note "on main: unplanned = '$(row unplanned)'"

# tested:, the line /dev-pr stops on. Three states have to be distinguishable:
# nothing was run, something was run for this code, and something was run for
# code that is no longer what this branch proposes.
say_tested() { printf '%s\n' "$out" | sed -n 's/^tested: //p'; }

rm -f "$repo/.devskills/test-result"
run
[ "$(say_tested)" = "none" ] || note "tested with no receipt: '$(say_tested)'"

printf '%s TEST PASS | OK (3 tests)\n' "$(g rev-parse HEAD)" > "$repo/.devskills/test-result"
run
case "$(say_tested)" in
  "TEST PASS | OK (3 tests) (this HEAD)") ;;
  *) note "tested at HEAD: '$(say_tested)'" ;;
esac

# A commit after the run: still evidence, but it must say which commit it was.
printf 'later\n' > "$repo/later.txt"; g add -A; g commit -qm later
run
case "$(say_tested)" in
  "TEST PASS | OK (3 tests) (at "*"1 commit(s) back)") ;;
  *) note "tested one commit back: '$(say_tested)'" ;;
esac

# A receipt for a commit that is not behind HEAD is stale, never a pass.
printf '%s TEST PASS | OK\n' "0000000000000000000000000000000000000000" > "$repo/.devskills/test-result"
run
case "$(say_tested)" in
  stale*) ;;
  *) note "tested with an unrelated sha: '$(say_tested)'" ;;
esac
rm -f "$repo/.devskills/test-result"

# Which forge, from the remote. gh only speaks GitHub, and `gh auth status`
# says "Logged in to github.com" whatever the remote is — so a GitLab project
# got a cheerful auth line and a compare URL for a repository that does not
# exist. The host decides.
forge_case() { # forge_case <remote or empty> <want forge> <want url contains>
  d="$work/forge-$2-$RANDOM"; mkdir -p "$d/.devskills"
  printf '{\n  "baseBranch": "main"\n}\n' > "$d/.devskills/profile.json"
  git -C "$d" init -q -b main . 2>/dev/null
  printf 'x\n' > "$d/f"
  git -C "$d" -c user.email=t@e -c user.name=t add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@e -c user.name=t commit -qm base >/dev/null 2>&1
  git -C "$d" -c user.email=t@e -c user.name=t switch -qc feat 2>/dev/null
  printf 'y\n' > "$d/f"
  git -C "$d" -c user.email=t@e -c user.name=t add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@e -c user.name=t commit -qm work >/dev/null 2>&1
  [ -n "$1" ] && git -C "$d" remote add origin "$1"
  o="$(cd "$d" && bash "$script" 2>/dev/null)"
  got="$(printf '%s\n' "$o" | sed -n 's/^forge: //p')"
  url="$(printf '%s\n' "$o" | sed -n 's/^compare-url: //p')"
  [ "$got" = "$2" ] || note "forge for '${1:-no remote}': got '$got', want $2"
  case "$url" in *"$3"*) ;; *) note "compare-url for '${1:-no remote}': '$url' does not contain '$3'" ;; esac
}

forge_case "https://github.com/acme/widget.git"    github    "github.com/acme/widget/compare/"
forge_case "git@github.com:acme/widget.git"        github    "github.com/acme/widget/compare/"
forge_case "git@gitlab.example.com:team/proj.git"  gitlab    "gitlab.example.com/team/proj/-/merge_requests/new"
forge_case "git@bitbucket.org:t/p.git"             bitbucket "bitbucket.org/t/p/pull-requests/new"
forge_case "git@git.example.org:x/y.git"           other     "open the change on"
forge_case "https://codeberg.org/acme/widget.git"  gitea     "codeberg.org/acme/widget/compare/"
# The host decides, not the path: a repository merely named after GitLab, on a
# host that is not GitLab, must not be handed a merge-request URL. Every case
# above has the forge in its host, which is why matching the whole remote passed.
forge_case "git@git.company.com:team/gitlab-migration.git" other "open the change on"
forge_case "https://github.com/acme/gitlab-tools.git"      github "github.com/acme/gitlab-tools/compare/"
forge_case ""                                      none      "no remote"

# A GitHub URL must never be printed for a remote that is not GitHub — that is
# the whole defect: it points at a repository which does not exist.
for r in "git@gitlab.example.com:team/proj.git" "git@git.example.org:x/y.git"; do
  d="$work/nogh-$RANDOM"; mkdir -p "$d/.devskills"
  printf '{\n  "baseBranch": "main"\n}\n' > "$d/.devskills/profile.json"
  git -C "$d" init -q -b main . 2>/dev/null
  printf 'x\n' > "$d/f"; git -C "$d" -c user.email=t@e -c user.name=t add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@e -c user.name=t commit -qm base >/dev/null 2>&1
  git -C "$d" remote add origin "$r"
  printf '%s\n' "$(cd "$d" && bash "$script" 2>/dev/null | sed -n 's/^compare-url: //p')" \
    | grep -q 'github.com' && note "compare-url for $r points at github.com"
done

if [ "$fails" -eq 0 ]; then
  printf 'pr-info: base, pull request, counts and unplanned paths follow the fixture\n'
else
  printf 'pr-info: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
