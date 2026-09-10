#!/usr/bin/env bash
# The hint install.sh prints, against the skills it installs — run it from anywhere:
#
#   bash evals/skills/install-hint.sh
#
# install.sh copies every skills/*/ directory, but the closing hint that tells
# people what to type is written by hand, in cycle order, because the order is
# the thing worth teaching. A hand-written list goes stale silently: this one
# still advertised eight commands after dev-plan-manual made nine, and nothing
# failed. So the order stays hand-written and the set is asserted here.
#
# Exits 0 when every installed skill is named, 1 otherwise, naming each gap.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/install.sh"
skills="$root/skills"
[ -f "$script" ] || { printf 'no install.sh at %s\n' "$script" >&2; exit 1; }
[ -d "$skills" ] || { printf 'no skills at %s\n' "$skills" >&2; exit 1; }

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# The hint: the echo line listing slash commands, whatever line it sits on.
hint="$(grep -m1 'echo "  /dev-' "$script")"
[ -n "$hint" ] || { printf 'FAIL  install.sh prints no /dev- hint line at all\n'; exit 1; }

checked=0
for dir in "$skills"/*/; do
  s="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || continue
  checked=$((checked + 1))
  case "$hint" in
    *"/$s "*|*"/$s\""*) ;;
    *) note "$s: installed, but install.sh never names /$s" ;;
  esac
done

# And the reverse: a command named after a skill that is gone sends people to a
# picker entry that does not exist.
for named in $(printf '%s\n' "$hint" | tr ' ' '\n' | sed -n 's|^/\(dev-[a-z-]*\).*|\1|p'); do
  [ -d "$skills/$named" ] || note "$named: named in the hint, but there is no skills/$named"
done

[ "$checked" -gt 0 ] || { printf 'no SKILL.md under %s\n' "$skills" >&2; exit 1; }
if [ "$fails" -eq 0 ]; then
  printf 'install-hint: names all %s installed skill(s)\n' "$checked"
else
  printf 'install-hint: %s gap(s)\n' "$fails" >&2
fi
exit $((fails > 0))
