# opencode-skills

Development skills for OpenCode, engineered for local ~30B models. These scripts compute facts before prompts run and advance work one discrete step at a time.

## Commands

| What | Command |
|---|---|
| Install | `./install.sh` or `./install.sh --project` |
| Test | `bash evals/run-all.sh` |
| Lint | none — this is a script library, not built code |
| Build | none — no build system; just shell scripts and SKILL.md files |
| Run | none — not a runtime application; skills load via OpenCode |

Commands run on the host system (no container). Ensure you have `gh`, Docker, and an OpenCode model server at 128k context.

## This project specifically

- **Skills are in `skills/`** — each subdirectory holds a `SKILL.md` (capped at 90 lines / 4,500 bytes). OpenCode loads them via the `/skills` picker.
- **The guard** (`lib/dev-guard.js`) blocks force-pushes, amended commits, skipped hooks, and unauthorized `gh pr merge`. Verified against 43 test cases in `evals/guard/cases.sh`.
- **Step cycle:** `/dev-init` → `/dev-plan` → `/dev-implement` → `/dev-review` → `/dev-pr`. Each step runs on a stacked branch (`step/<slug>-<n>`).
- **Learned facts** persist across sessions in `.devskills/learned.md`.
- **Credentials:** none. The `opencode.jsonc` config uses LM Studio at `127.0.0.1:1234/v1` (local). `.gitignore` covers no secrets since there are none.
- **Model config:** `opencode.jsonc` sets reasoning OFF by default (`reasoning_effort: none`) to avoid local model latency in agent loops. Toggle via `/variant on`.
- **Generated files:** none — all content is hand-written. `.tasks/` and `plans/` are runtime artifacts tracked via git branch commits.
