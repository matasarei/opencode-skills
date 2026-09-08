# opencode-skills

Development skills for OpenCode engineered for local ~30B coding models (Prism Bonsai 27B, Qwen3 Coder 30B). Skills compute facts before prompts run, replace scoring with binary checks, and advance work one step at a time.

## Commands

| What | Command |
|---|---|
| Install | `./install.sh` (global) or `./install.sh --project` |
| Test | `bash evals/run-all.sh` |
| Lint | `shellcheck --severity=warning lib/*.sh install.sh evals/*.sh evals/*/*.sh` |
| Build | none (no build system — pure scripts + markdown) |
| Run | `bash .devskills/` (invoked via OpenCode, not directly) |

Scripts run on the host. No container runtime is used here; commands target this machine's toolchain (Bash, shellcheck, node).

## This project specifically

- **Installation targets**: global `~/.config/opencode/` or local `./.opencode/`. Skills hard-code `$HOME/.config/opencode/dev-lib`; override with `export DEV_SKILLS_LIB=<path>` otherwise.
- **The guard**: `lib/dev-guard.js` is an OpenCode plugin that blocks, before they run: force pushes, commit amendments (`--amend`), `--no-verify`, pushes to the base branch, `gh pr merge`, `gh pr review --approve`, and `gh release`.
- **Skill invocation**: Skills are accessed via the `/skills` picker in OpenCode, not root `/`. They do not autocomplete on the default slash.
- **Context requirement**: Local models require 64k+ context window. Below that, tool calling degrades or loops silently.
- **Shared scripts**: All shell logic lives in `lib/` (copied to `<target>/dev-lib/`) and is referenced by absolute path from every skill. Skills themselves are just `SKILL.md` files in `skills/`.
- **Non-commit files**: `.tasks/*.md`, `plans/**/*.md`, and `.devskills/learned.md` are generated during work sessions and are not committed to git.
