#!/usr/bin/env bash
# What was /dev-plan given? Decide it here, not in the prompt.
#
# "Is the argument a file, an issue, or a sentence?" is a decision a small
# model gets wrong in the expensive direction — a mistyped path becomes a
# sentence to plan from. So the argument is resolved to the brief itself, with
# its source on the first line:
#
#   plan-input.sh <arguments as typed>
#
#   FILE <path>            then the file, whole
#   FINDINGS <path>        a file of review findings, named and NOT printed: the
#                          verified copy arrives from findings-check.sh, and
#                          printing it again made /dev-fix plan a task from its
#                          own review
#   ISSUE <owner/repo>#<n> then "# <title>", a blank line, the body   (gh issue view)
#   TEXT                   then the sentence
#   MISSING FILE <path>    a path that does not exist — exit 66, never a sentence
#   EMPTY                  nothing was given — exit 65, ask
#
# An issue is "#<n>", "<n>" is not (a bare number is a sentence), or a GitHub
# issue URL. gh missing or not signed in → exit 69 with the reason.

set -u

ARG="$*"
# Surrounding quotes and whitespace are how people mark where prose ends; the
# text is not shell-parsed, so they arrive as typed.
ARG="$(printf '%s' "$ARG" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/')"

[ -n "$ARG" ] || { echo "EMPTY"; exit 65; }

# A file of review findings is not a brief. /dev-fix injects this script and
# findings-check.sh with the same $ARGUMENTS, so a findings file used to arrive
# twice: once here as a brief to plan a fix *from*, and once there as the
# verified list to apply. Naming the kind decides the mode mechanically.
is_findings() { grep -qE '^(BLOCKER|WARNING|NIT|SMELL)[[:space:]]*\|.*\|[[:space:]]*EVIDENCE:' "$1" 2>/dev/null; }

issue() { # issue <owner/repo or empty> <n>
  command -v gh >/dev/null 2>&1 || { echo "gh is not installed — pass the issue as text or a file" >&2; exit 69; }
  repo="$1"; n="$2"
  [ -z "$repo" ] && repo="$(git remote get-url origin 2>/dev/null | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
  [ -n "$repo" ] || { echo "a bare #$n needs a git remote to resolve against" >&2; exit 69; }
  body="$(gh issue view "$n" --repo "$repo" --json title,body -q '"# " + .title, "", .body' 2>&1)" \
    || { echo "cannot read issue $repo#$n — check 'gh auth status': $body" >&2; exit 69; }
  echo "ISSUE $repo#$n"
  printf '%s\n' "$body"
}

case "$ARG" in
  http*://*/issues/[0-9]*)
    issue "$(printf '%s' "$ARG" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/issues/.*#\1#')" \
          "$(printf '%s' "$ARG" | sed -E 's#.*/issues/([0-9]+).*#\1#')"
    ;;
  \#[0-9]*)
    n="${ARG#\#}"
    case "$n" in *[!0-9]*) echo "TEXT"; printf '%s\n' "$ARG"; exit 0 ;; esac
    issue "" "$n"
    ;;
  *)
    if [ -f "$ARG" ]; then
      if is_findings "$ARG"; then
        echo "FINDINGS $ARG"
        echo "(not printed here — the verified list is in the findings block)"
      else
        echo "FILE $ARG"
        cat "$ARG"
      fi
    elif [ -d "$ARG" ]; then
      echo "MISSING FILE $ARG (a directory)"; exit 66
    else
      # Path-shaped — a slash, or a .md ending, and no spaces — but not there.
      case "$ARG" in
        *' '*) echo "TEXT"; printf '%s\n' "$ARG" ;;
        */*|*.md) echo "MISSING FILE $ARG"; exit 66 ;;
        *) echo "TEXT"; printf '%s\n' "$ARG" ;;
      esac
    fi
    ;;
esac
