#!/usr/bin/env bash
# Install the dev skills into OpenCode.
#
#   ./install.sh              install from this checkout
#   ./install.sh --project    install into ./.opencode instead of the global config
#
# Skills go to <config>/skills/dev-*/ and the shared scripts to <config>/dev-lib/.
# The scripts live outside the skill directories on purpose: shell injection in a
# SKILL.md runs from the *project* root, not the skill directory, so the skills
# reference the library by an absolute path that is the same on every machine.

set -e

SRC="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--project" ]; then
  TARGET="$(pwd)/.opencode"
else
  TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi

SKILLS="$TARGET/skills"
LIB="$TARGET/dev-lib"

echo "Installing to $TARGET"

mkdir -p "$SKILLS" "$LIB"

# Shared scripts. Every skill calls these; they are the reason the skills are short.
cp "$SRC"/lib/*.sh "$LIB/"
chmod +x "$LIB"/*.sh

# Skills. Removed first so a renamed or deleted file does not linger.
for dir in "$SRC"/skills/*/; do
  name="$(basename "$dir")"
  rm -rf "${SKILLS:?}/$name"
  cp -R "$dir" "$SKILLS/$name"
  echo "  $name"
done

# Agents are optional — only copied if the user has an agents directory or asks for one.
if [ -d "$SRC/agents" ]; then
  mkdir -p "$TARGET/agents"
  cp "$SRC"/agents/*.md "$TARGET/agents/" 2>/dev/null || true
fi

# A version stamp, so a skill can tell you it is stale. There is no marketplace here
# and nothing will pull updates for you.
(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo "unknown") > "$LIB/.version"

echo
echo "Done. Type '/' in OpenCode to see:"
echo "  /dev-init /dev-plan /dev-implement /dev-review /dev-pr-review /dev-pr-resolve /dev-verify"
echo
# The skills hard-code $HOME/.config/opencode/dev-lib as their fallback, because a
# SKILL.md cannot know where it was installed. Any other location — a --project
# install, or a non-default XDG_CONFIG_HOME — needs the override, or every skill
# calls a path that does not exist. Say so exactly when it applies.
if [ "$LIB" != "$HOME/.config/opencode/dev-lib" ]; then
  echo "This is not the default location, so the skills will not find the scripts"
  echo "unless you export the override:"
  echo
  echo "    export DEV_SKILLS_LIB=$LIB"
  echo
  echo "Put that in your shell profile."
  [ "${1:-}" = "--project" ] && echo "Or re-run without --project to install globally instead."
fi

# Non-zero context is a hard requirement for local models, and the single most common
# reason tool calls silently stop working. Worth saying once, at install time.
echo
echo "Local models: set the context window to 64k or higher. Below that, OpenCode's"
echo "tool calling degrades in ways that look like the skills being wrong."
