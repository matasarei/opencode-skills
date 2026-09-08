#!/usr/bin/env bash
# Cases for lib/pr-comments.sh — run them from anywhere:
#
#   bash evals/lib/pr-comments.sh
#
# Two things are asserted. First the argument handling, which decides *which*
# repository a fix lands in: a URL is authoritative, a bare number needs a remote
# or --repo, and anything else is refused rather than guessed at. Then the
# filtering, with gh stubbed: a thread the author has already answered must not
# be re-offered, or every re-run hands back finished work.
#
# The filtering runs inside gh's --jq, so those cases need jq on the host and
# skip themselves with a word when it is missing rather than passing quietly.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/lib/pr-comments.sh"
[ -f "$script" ] || { printf 'no pr-comments.sh at %s\n' "$script" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
repo="$work/repo"; mkdir -p "$repo"

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$repo" -c user.email=t@e -c user.name=t "$@"; }
run() { out="$(cd "$repo" && PATH="$stub:$PATH" bash "$script" "$@" 2>&1)"; rc=$?; }

g init -q -b main . && printf 'x\n' > "$repo/f" && g add -A && g commit -qm base
g remote add origin https://github.com/acme/widget.git

stub="$work/bin"; mkdir -p "$stub"

# --- gh missing entirely -----------------------------------------------------
printf '#!/bin/sh\nexit 127\n' > "$stub/gh"; chmod +x "$stub/gh"
noghdir="$work/nogh"; mkdir -p "$noghdir"
out="$(cd "$repo" && PATH="$noghdir:/usr/bin:/bin" bash "$script" 7 2>&1)"; rc=$?
[ "$rc" -eq 69 ] || note "gh missing: exit $rc, want 69"
printf '%s\n' "$out" | grep -q 'gh is not installed' || note "gh missing: '$out'"

# --- argument handling, before any network -----------------------------------
run
[ "$rc" -eq 64 ] || note "no argument: exit $rc, want 64"
run 'not-a-pr'
[ "$rc" -eq 64 ] || note "garbage argument: exit $rc, want 64"
printf '%s\n' "$out" | grep -q 'not a pull request number or URL' || note "garbage argument: '$out'"

# A bare number with no remote and no --repo is refused, never guessed.
bare="$work/bare"; mkdir -p "$bare"; git -C "$bare" init -q -b main .
out="$(cd "$bare" && PATH="$stub:$PATH" bash "$script" 7 2>&1)"; rc=$?
[ "$rc" -eq 64 ] || note "bare number, no remote: exit $rc, want 64"
printf '%s\n' "$out" | grep -q 'needs --repo' || note "bare number, no remote: '$out'"

if ! command -v jq >/dev/null 2>&1; then
  printf 'pr-comments: no jq on this host, the filtering cases were skipped\n' >&2
else
  # A gh that answers from fixtures and runs --jq through the real jq.
  cat > "$stub/gh" <<'GH'
#!/bin/sh
# gh pr view <n> --repo <r> --json <f> -q <expr>
if [ "$1" = pr ] && [ "$2" = view ]; then
  case "$*" in
    *author*) echo alice ;;
    *state*)  echo OPEN ;;
  esac
  exit 0
fi
# gh api --paginate <path> --jq <expr>
if [ "$1" = api ]; then
  path="$3"; expr="$5"
  case "$path" in
    */comments) file="$FIXTURES/comments.json" ;;
    */reviews)  file="$FIXTURES/reviews.json" ;;
    *) exit 1 ;;
  esac
  jq -r "$expr" < "$file"
  exit 0
fi
exit 1
GH
  chmod +x "$stub/gh"

  mkdir -p "$work/fx"
  cat > "$work/fx/comments.json" <<'JSON'
[
  {"id": 101, "in_reply_to_id": null, "user": {"login": "bob"},
   "path": "src/Loop.php", "line": 7, "body": "this loop never ends\nmore text"},
  {"id": 102, "in_reply_to_id": null, "user": {"login": "carol"},
   "path": "src/Money.php", "line": 12, "body": "rounding is wrong"},
  {"id": 103, "in_reply_to_id": 102, "user": {"login": "alice"},
   "path": "src/Money.php", "line": 12, "body": "fixed in abc123"}
]
JSON
  cat > "$work/fx/reviews.json" <<'JSON'
[
  {"id": 900, "user": {"login": "bot"}, "state": "APPROVED", "body": "LGTM"},
  {"id": 901, "user": {"login": "dave"}, "state": "CHANGES_REQUESTED",
   "body": "The export drops departments that share a name, which loses rows silently."}
]
JSON
  out="$(cd "$repo" && PATH="$stub:$PATH" FIXTURES="$work/fx" bash "$script" 7 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || note "fixtures: exit $rc, want 0"
  printf '%s\n' "$out" | grep -q '^# acme/widget#7 by alice (OPEN)$' || note "fixtures: header is '$(printf '%s\n' "$out" | head -1)'"

  # 101 is unanswered and must be offered.
  printf '%s\n' "$out" | grep -q '^101	bob	src/Loop.php:7	this loop never ends$' \
    || note 'fixtures: comment 101 is missing, or its body was not cut to the first line'

  # 102 was answered by the author in 103, so neither may appear.
  printf '%s\n' "$out" | grep -q '^102	' && note 'fixtures: an answered thread was re-offered'
  printf '%s\n' "$out" | grep -q '^103	' && note 'fixtures: a reply was listed as a comment of its own'

  # A short approval carries no finding; a substantive review does, with no repliable id.
  printf '%s\n' "$out" | grep -q 'LGTM' && note 'fixtures: a bare approval was listed as a finding'
  printf '%s\n' "$out" | grep -q '^REVIEW-901	dave	(summary)' || note 'fixtures: the substantive review is missing'
fi

if [ "$fails" -eq 0 ]; then
  printf 'pr-comments: the right repository, and never an answered thread twice\n'
else
  printf 'pr-comments: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
