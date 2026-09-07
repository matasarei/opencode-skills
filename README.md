# opencode-skills

<p>
  <a href="https://opencode.ai"><img src="https://img.shields.io/badge/OpenCode-1B1B1B?style=for-the-badge" alt="OpenCode" /></a>
  <img src="https://img.shields.io/badge/Local_models-6E56CF?style=for-the-badge&logo=ollama&logoColor=white" alt="Local models" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-3DA639?style=for-the-badge" alt="License: MIT" /></a>
</p>

Development skills for [OpenCode](https://opencode.ai) engineered specifically for **local ~30B models** (such as **Qwen3 Coder 30B** and **Prism Bonsai 27B**).

Instead of relying on fragile multi-variable reasoning and prompt guesswork, these skills compute facts before prompts run, replace subjective scoring with binary yes/no checks, verify code quotes mechanically, and advance work one discrete step at a time.

---

## Recommended Models

These skills are optimized for ~30B parameter local coding models:

1. **[Prism Bonsai 27B](https://lmstudio.ai/models/prism-ml/bonsai-27b)** (`prism-ml/bonsai-27b`) — Strong general coding, reasoning, and instruction-following.
2. **[Qwen3 Coder 30B](https://lmstudio.ai/models/qwen/qwen3-coder-30b)** (`qwen/qwen3-coder-30b`) — Tuned specifically for code generation, diff analysis, and fast tool calling.

> **Crucial Server Requirement**: Set your model server's context window (LM Studio, Ollama, or llama.cpp) to **64k or 128k**. Local tool calling will degrade or loop if the context window is left at the default 4k/8k.

---

## Installation & Setup

```bash
git clone https://github.com/matasarei/opencode-skills.git
cd opencode-skills

# Install globally (to ~/.config/opencode)
./install.sh

# Or install for current project only (to ./.opencode)
./install.sh --project
```

### Requirements
* **OpenCode** with skills support.
* **Git** and **Bash** (macOS, Linux, or WSL on Windows. Native Windows Git Bash is unsupported).
* **GitHub CLI (`gh`)** for pull request skills (`gh auth login`).
* **Docker** (recommended — skills run tests inside project containers by default).

> **Invoking Skills**: In OpenCode, skills installed in `skills/` are accessed via the **`/skills`** picker (type `/skills` in the prompt or use the TUI picker), or loaded as agent tools. They do not autocomplete directly on the root `/` slash (which OpenCode reserves for custom commands).

---

## Configuration

A complete, recommended configuration is provided in [**`opencode.jsonc`**](opencode.jsonc). Copy it to `~/.config/opencode/opencode.jsonc` or your project's `.opencode/opencode.jsonc`.

### 1. Model Configuration

Local models perform best in agentic loops when **reasoning is turned OFF by default** and the **output ceiling is capped at 16k tokens**:

```jsonc
"models": {
  "prism-ml/bonsai-27b": {
    "name": "Prism Bonsai 27B",
    "attachment": false,
    "reasoning": false,
    "tool_calling": true,
    "limit": {
      "context": 131072,  // 128k context window
      "output": 16384     // 16k output ceiling
    },
    "options": {
      "reasoning_effort": "none"  // Disables thinking tokens by default
    },
    "variants": {
      "off": { "reasoning_effort": "none" },
      "on":  { "reasoning_effort": "medium" }
    }
  }
}
```

* **Why 16k output?** In local inference, thinking tokens share the output budget. 16k gives ample headroom for large diffs, database migrations, and plans without truncation (`finish_reason: length`), while preventing runaway infinite loops.
* **Why reasoning OFF?** In agent loops, local models spend 30–90 seconds generating `<think>` tokens before *every single tool call*, often simulating imaginary tool output instead of calling the tool. Disabling reasoning reduces tool call latency to 1–3 seconds, allowing real tool output (compilers, linters, tests) to ground the model.
* **On-the-Fly Toggle**: The `variants` block lets you switch reasoning `on` whenever you need deep architectural planning (switch via `/variant` or `Ctrl+M` / `Cmd+M` in the OpenCode TUI).

### 2. Permissions & Agent Configuration

```jsonc
"permission": {
  "external_directory": {
    "/tmp/**": "allow",
    "/private/tmp/**": "allow"
  }
},
"agent": {
  "build": {
    "temperature": 0
  },
  "plan": {
    "temperature": 0,
    "permission": {
      "edit": {
        "*.md": "allow",
        "**/*.md": "allow",
        ".tasks/**": "allow",
        "plans/**": "allow"
      }
    }
  }
}
```

* **Scratch Permissions (`/tmp`)**: OpenCode defaults `external_directory` to `ask`. Allowing `/tmp/**` and `/private/tmp/**` lets models write temporary scripts, diffs, and test outputs without stalling autonomous runs, while keeping sensitive paths outside the workspace protected.
* **`temperature: 0`**: OpenCode defaults Qwen models to `0.55`. Zero temperature is required for deterministic code reviews and consistent tool use.
* **Plan Mode Permissions**: OpenCode's native `plan` agent blocks file edits by default. Adding permissions for `.tasks/**` and `*.md` allows `/dev-plan` to write and update actionable task files.

---

## The Skills & The Step Cycle

| Command | Purpose | Code Modified? |
|---|---|---|
| `/dev-init` | Detects project stack and writes repo conventions to `AGENTS.md` | Yes (`AGENTS.md`) |
| `/dev-plan <request>` | Investigates code, sizes steps against budget, writes `.tasks/*.md` | No |
| `/dev-implement <task>` | Builds one discrete step from the task file, ticks it off, and stops | Yes |
| `/dev-review` | Runs 12 yes/no checks on changed files with mechanical quote verification | No |
| `/dev-fix` | Applies verified findings from `/dev-review`, landing one commit each | Yes |
| `/dev-pr` | Pushes the step branch, opens stacked PR with `Depends on #` | No |
| `/dev-verify` | Runs test suites and exercises runtime behaviour inside Docker containers | No |
| `/dev-pr-review <pr>` | Reviews an external PR against a structured checklist | No |
| `/dev-pr-comment <pr>` | Addresses one review comment on your PR as a verified local commit | Yes (local commit) |

### The Step Cycle

```
   /dev-init ──▶ /dev-plan ──▶ /dev-implement ──▶ /dev-review ──▶ /dev-fix ──▶ /dev-pr
(once per repo)                       │                                           │
                                      └─────────── (next step: /compact or /new) ─┘
```

1. **Initialize (once per repo)**: `/dev-init` inspects the project, writes build/test/lint commands and stack conventions to `AGENTS.md`.
2. **Plan**: `/dev-plan` resolves input via `plan-input.sh`, validates referenced paths with `plan-check.sh`, and sizes each step using `step-budget.sh` against `contextTokens` (default 100k, overridden by `DEV_SKILLS_CONTEXT`). Shared parsing is handled by `steps.awk`.
3. **Build**: `/dev-implement` injects exactly one step via `task-step.sh` onto a stacked branch named `step/<slug>-<n>`.
4. **Review & Fix**: `/dev-review` finds blockers/warnings, and `/dev-fix` applies verified findings.
5. **Push & PR**: `/dev-pr` pushes the branch and opens the PR (annotated with `Depends on #` for stacked dependencies).
6. **Next Step**: Proceed to the next step. For closely-coupled steps, continue in the same session or run `/compact` to prune raw bash/diff outputs while preserving conversational context and architectural decisions. When context balloons (>60k–80k tokens) or when switching to an unrelated task, use `/new` for a clean slate. Inter-step repository discoveries persist in `.devskills/learned.md`.

---

## Mechanics & Guardrails

* **The Guard (`lib/dev-guard.js`)**: An OpenCode plugin that intercepts bash commands and blocks dangerous actions: force pushes, amended commits, skipped git hooks, pushes to `main`/`master`, and unauthorized `gh pr merge`. Verified against 43 test cases in `evals/guard/cases.sh`.
* **Mechanical Evidence Verification**: `lib/findings-check.sh` validates quoted code against current files on disk, discarding hallucinated findings.
* **Size Cap**: Each `SKILL.md` is strictly capped at 90 lines and `4,500 bytes` (enforced by `evals/skills/size.sh`) to prevent context bloat.
* **Testing & Evals**: The entire toolkit is covered by fixture suites. Run `bash evals/run-all.sh` to execute all 16 test suites.

---

## Troubleshooting

* **Skills not showing up on `/`**: In OpenCode, skills are accessed via the **`/skills`** picker, not root `/` command autocomplete. Type `/skills` in OpenCode to select a skill. If `/skills` is empty, check `ls ~/.config/opencode/skills/` and verify each directory has a valid `SKILL.md`.
* **Tool calls truncate or loop**: Server context window is below 64k. Increase context length in LM Studio or set `OLLAMA_CONTEXT_LENGTH=65536`.
* **Model stuck in a retry loop or context bloated**: Repeated failed tool calls (e.g. failing edits or syntax errors) can fill the context with identical failure traces, trapping `temperature: 0` models in repetitive retry loops:
  * **Fresh Session (`--continue`)**: Exit OpenCode and start a fresh session, then run `/dev-implement .tasks/<task>.md --continue`. Progress is tracked on disk in `.tasks/` and git branch commits, instantly clearing out thousands of poisoned context tokens.
  * **`/compact`**: If staying in the active session, run `/compact` to prune verbose tool error outputs while retaining high-level instructions and decisions, then resume with `/dev-implement .tasks/<task>.md --continue`.
* **Plan mode refuses to write to `.tasks/`**: Ensure `agent.plan.permission.edit` allows `.tasks/**` in `opencode.jsonc`.
* **Guard blocked a command**: The guard refused a destructive git command (force-push, commit amend, or base branch push). Commit changes normally and use `/dev-pr`.
* **Findings dropped as unverifiable**: The model quoted code that did not exist in the file. Ensure `temperature: 0`.

---

## License

[MIT](LICENSE)
