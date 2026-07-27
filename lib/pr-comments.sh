#!/usr/bin/env bash
# Fetch a pull request's review comments as a flat, stable ledger.
#
# Collecting comments is three gh calls, two JSON shapes and a pile of filtering.
# None of it needs a model, and a model doing it will miss a page or invent an id.
#
#   pr-comments.sh <pr-url | pr-number> [--repo owner/name]
#
# Output: one comment per line, tab-separated, oldest first —
#
#   <id> <TAB> <author> <TAB> <path>:<line> <TAB> <first line of the body>
#
# Only comments that can actually be replied to are listed: inline review comments
# carry an id, bot summary reviews do not. Anything the PR author has already
# replied to is dropped, so re-running never re-offers finished work.
#
# Exit 0 with output, 0 with "(no actionable comments)", or non-zero on a real error.

set -u

ARG="${1:-}"
[ -z "$ARG" ] && { echo "usage: pr-comments.sh <pr-url|pr-number> [--repo owner/name]" >&2; exit 64; }

REPO=""
[ "${2:-}" = "--repo" ] && REPO="${3:-}"

# A URL is authoritative and works from any directory. A bare number needs a
# repository to mean anything, and guessing one is how a fix lands in the wrong place.
case "$ARG" in
  http*://*/pull/*)
    REPO="$(printf '%s' "$ARG" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')"
    NUM="$(printf '%s' "$ARG" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
    ;;
  *[!0-9]*)
    echo "not a pull request number or URL: $ARG" >&2; exit 64 ;;
  *)
    NUM="$ARG"
    [ -z "$REPO" ] && REPO="$(git remote get-url origin 2>/dev/null \
      | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
    [ -z "$REPO" ] && { echo "a bare number needs --repo, or a git remote to resolve against" >&2; exit 64; }
    ;;
esac

command -v gh >/dev/null 2>&1 || { echo "gh is not installed" >&2; exit 69; }

AUTHOR="$(gh pr view "$NUM" --repo "$REPO" --json author -q .author.login 2>/dev/null)"
[ -z "$AUTHOR" ] && { echo "cannot read pull request $REPO#$NUM — check 'gh auth status'" >&2; exit 69; }

STATE="$(gh pr view "$NUM" --repo "$REPO" --json state -q .state 2>/dev/null)"
echo "# $REPO#$NUM by $AUTHOR ($STATE)"

# Inline review comments. in_reply_to_id identifies replies; a thread whose latest
# reply is from the PR author has already been dealt with.
gh api --paginate "/repos/$REPO/pulls/$NUM/comments" --jq '
  [ .[] ] as $all
  | ($all | map(select(.in_reply_to_id != null and .user.login == "'"$AUTHOR"'") | .in_reply_to_id)) as $answered
  | $all
  | map(select(.in_reply_to_id == null))
  | map(select(.id as $i | ($answered | index($i)) | not))
  | .[]
  | [ (.id|tostring), .user.login, ((.path // "?") + ":" + ((.line // .original_line // 0)|tostring)),
      (.body | split("\n") | .[0] | .[0:160]) ]
  | @tsv
' 2>/dev/null

# Review bodies that carry a finding of their own. These have no repliable id, so
# they are marked REVIEW and the verdict on them goes in the report, not a thread.
gh api --paginate "/repos/$REPO/pulls/$NUM/reviews" --jq '
  .[]
  | select(.body != null and (.body | length) > 0)
  | select(.state != "APPROVED" or (.body | length) > 40)
  | [ ("REVIEW-" + (.id|tostring)), .user.login, "(summary)",
      (.body | split("\n") | .[0] | .[0:160]) ]
  | @tsv
' 2>/dev/null
