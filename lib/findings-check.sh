#!/usr/bin/env bash
# Drop findings whose evidence does not exist in the code.
#
# This is the hallucination filter. A local model asked for `path:line` and a
# quoted line will sometimes produce a plausible one that is not there. Rather
# than trusting the model to police itself, every finding is checked against the
# file it names, and anything unverifiable is removed before a human sees it.
#
# It gets stricter as the format gets stricter. It does not get better as the
# model gets bigger, and it does not need to.
#
#   findings-check.sh <findings-file>
#
# Expected format, one finding per line:
#   SEVERITY | path:line | one sentence | EVIDENCE: <the exact line of code>
#
# Prints the surviving findings on stdout, and a one-line audit to stderr.

set -u

FILE="${1:-.devskills/findings.md}"
[ -f "$FILE" ] || { echo "no findings file at $FILE" >&2; exit 0; }

kept=0; dropped=0

while IFS= read -r line; do
  case "$line" in
    BLOCKER\ \|*|WARNING\ \|*|NIT\ \|*|SMELL\ \|*) ;;
    *) continue ;;   # anything not in the format is not a finding
  esac

  loc="$(printf '%s' "$line" | awk -F'|' '{print $2}' | tr -d ' ')"
  ev="$(printf '%s' "$line" | sed -n 's/.*EVIDENCE:[[:space:]]*//p')"

  path="${loc%%:*}"
  lineno="${loc##*:}"

  # No quotable evidence, no finding.
  if [ -z "$ev" ] || [ -z "$path" ] || [ "$path" = "$loc" ]; then
    dropped=$((dropped+1)); continue
  fi

  if [ ! -f "$path" ]; then
    dropped=$((dropped+1)); continue
  fi

  # The quoted text must appear in the file. Whitespace is normalised, because a
  # model reproducing indentation exactly is not something worth requiring.
  needle="$(printf '%s' "$ev" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
  [ -z "$needle" ] && { dropped=$((dropped+1)); continue; }

  if tr -s '[:space:]' ' ' < "$path" | grep -qF -- "$needle"; then
    # Present, but is it near the line claimed? Off by a lot usually means the
    # model matched a different occurrence, which changes what the finding means.
    actual="$(grep -nF -- "$needle" <(tr -s '[:space:]' ' ' < "$path") 2>/dev/null | head -1 | cut -d: -f1)"
    if [ -n "$actual" ] && [ -n "$lineno" ] && [ "$lineno" -eq "$lineno" ] 2>/dev/null; then
      diff=$(( actual > lineno ? actual - lineno : lineno - actual ))
      if [ "$diff" -gt 10 ]; then
        printf '%s   [line corrected to %s]\n' "$line" "$actual"
        kept=$((kept+1)); continue
      fi
    fi
    printf '%s\n' "$line"
    kept=$((kept+1))
  else
    dropped=$((dropped+1))
  fi
done < "$FILE"

echo "findings: $kept verified, $dropped dropped as unverifiable" >&2
