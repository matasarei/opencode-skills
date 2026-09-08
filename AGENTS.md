# opencode-skills

Development skills for OpenCode, engineered for local ~30B models. These scripts compute facts before prompts run and advance work one discrete step at a time.

## Commands

| What | Command |
|---|---|
| Install | `./install.sh` or `./install.sh --project` |
| Test | `bash evals/run-all.sh` |
| Test Scoped | `bash evals/lib/<script>.sh` (e.g. `bash evals/lib/http-check.sh`) |
| Lint | `shellcheck --severity=warning lib/*.sh install.sh evals/*.sh evals/*/*.sh` |
| Size Check | `bash evals/skills/size.sh` |
| Verify Loaded | `opencode debug skill` (or `opencode debug skill --print-logs`) |
| Build | none — no build system; just shell scripts and SKILL.md files |
| Run | none — not a runtime application; skills load via OpenCode |

Commands run on the host system (no container). Ensure you have `gh`, Docker, and an OpenCode model server at 128k context.

## Skill Development & Testing Workflow

When developing, updating, or debugging skills in this repository:

1. **Prompt & Script Edits**:
   - Skills live in `skills/<skill-name>/SKILL.md`.
   - Reusable scripts live in `lib/<script>.sh`, plugin in `lib/dev-guard.js`, templates in `skills/dev-init/templates/`.
2. **Invariants to Check**:
   - **Size cap**: Run `bash evals/skills/size.sh` — every `SKILL.md` must remain under 90 lines and 4,500 bytes (description under 200 chars).
   - **Lint**: Run `shellcheck --severity=warning lib/*.sh install.sh evals/*.sh evals/*/*.sh` — 0 warnings allowed.
   - **Cycles & Frontmatter**: Run `bash evals/skills/cycle.sh` and `bash evals/skills/frontmatter.sh` to confirm skill handoffs hold.
3. **Evals**:
   - Every file under `lib/` must have test cases in `evals/lib/`: `<script>.sh` for a shell script, and `steps.sh` for `steps.awk`. The plugin has `evals/guard/cases.sh`.
   - Run the target test during iteration (`bash evals/lib/<script>.sh`), then run the full suite: `bash evals/run-all.sh` (all 20 suites must pass).
4. **Sync Local Installation (Dogfooding)**:
   - **Crucial step**: Always run `./install.sh` after editing skills or scripts so `~/.config/opencode/` is updated. OpenCode executes installed files, not the working repo directly.
5. **Verify Loaded in OpenCode CLI**:
   - Testing is not only running evals — verify that OpenCode actually boots, parses, and loads the skill.
   - Run `opencode debug skill` to confirm the skill parses cleanly and appears in the catalog (`opencode debug skill | grep '"name": "<skill-name>"'`).
   - Run `opencode debug skill --print-logs` to confirm plugins (`lib/dev-guard.js`) and configs bootstrap with 0 runtime errors (`level=ERROR`).
6. **PR & Guard Rules**:
   - The guard (`lib/dev-guard.js`) forbids `git push --force`, `git commit --amend`, `--no-verify`, and pushing to `main`/`master`. Make new commits instead.
   - Clean up any generated files (`.tasks/`, `plans/`, stray `.md` files) before creating or updating PRs.
   - Always open PRs as draft (`--draft`) using `/dev-pr` or `gh pr create --draft`.

## This project specifically

- **Skills picker**: In OpenCode, skills load via the `/skills` picker (not the root slash autocomplete).
- **Step cycle:** `/dev-init` → `/dev-plan` → `/dev-implement` → `/dev-review` → `/dev-pr`. Each step runs on a stacked branch (`step/<slug>-<n>`).
- **Learned facts** persist across sessions in `.devskills/learned.md`.
- **Model config:** `opencode.jsonc` sets reasoning OFF by default (`reasoning_effort: none`) to avoid local model latency in agent loops. Toggle via `/variant on`.
