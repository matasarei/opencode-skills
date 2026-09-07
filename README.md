# opencode-skills

<p>
  <a href="https://opencode.ai"><img src="https://img.shields.io/badge/OpenCode-1B1B1B?style=for-the-badge" alt="OpenCode" /></a>
  <img src="https://img.shields.io/badge/Local_models-6E56CF?style=for-the-badge&logo=ollama&logoColor=white" alt="Local models" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-3DA639?style=for-the-badge" alt="License: MIT" /></a>
</p>

Development skills for [OpenCode](https://opencode.ai) engineered specifically for **local ~30B models** (such as **Qwen3 Coder 30B** and **Prism Bonsai 27B**).

Instead of relying on fragile multi-variable reasoning and prompt guesswork, these skills use deterministic shell scripts to compute facts before prompts run, replace subjective scoring with binary yes/no checks, verify code quotes mechanically, and advance work one discrete step at a time.

---

## Recommended Models

These skills are optimized for ~30B parameter local coding models:

1. **[Prism Bonsai 27B](https://huggingface.co/prism-ml/bonsai-27b)** (`prism-ml/bonsai-27b`) — Excellent general coding, reasoning, and instruction-following.
2. **[Qwen3 Coder 30B](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct)** (`qwen/qwen3-coder-30b`) — Tuned specifically for code generation, diff analysis, and fast tool calling.

> **Crucial Server Requirement**: Set your model server's context window (LM Studio, Ollama, or llama.cpp) to **64k or 128k**. Local tool calling will degrade or loop if the context window is left at the default 4k/8k.

---

## Installation

```bash
git clone https://github.com/matasarei/opencode-skills.git
cd opencode-skills

# Install globally (to ~/.config/opencode)
./install.sh

# Or install for current project only (to ./.opencode)
./install.sh --project
```

### Prerequisites
* **OpenCode** with skills support.
* **Git** and **Bash** (macOS, Linux, or WSL on Windows. Native Windows Git Bash is unsupported).
* **Docker** (recommended — skills run tests inside project containers by default).
* **GitHub CLI (`gh`)** for pull request skills (`gh auth login`).

---

## Configuration

A complete, recommended configuration is provided in [**`opencode.jsonc`**](opencode.jsonc). Copy it to `~/.config/opencode/opencode.jsonc` or your project's `.opencode/opencode.jsonc`.

### 1. Model Configuration

Local models perform best in agentic loops when **reasoning is turned OFF by default** and **output ceiling is capped at 16k tokens**:

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

### 2. Agent Configuration

```jsonc
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

* **`temperature: 0`**: OpenCode defaults Qwen models to `0.55`. Zero temperature is required for deterministic code reviews and consistent tool use.
* **Plan Mode Permissions**: OpenCode's native `plan` agent blocks file edits by default. Adding permissions for `.tasks/**` and `*.md` allows `/dev-plan` to write and update actionable task files.

---

## Available Skills

| Command | Purpose | Code Modified? |
|---|---|---|
| `/dev-init` | Detects project stack and writes repo conventions to `AGENTS.md` | Yes (`AGENTS.md`) |
| `/dev-plan <request>` | Investigates code, checks database/environment, writes `.tasks/*.md` | No |
| `/dev-implement <task>` | Builds one discrete step from the task file, ticks it off, and stops | Yes |
| `/dev-review` | Runs 12 yes/no checks on changed files with mechanical quote verification | No |
| `/dev-verify` | Runs test suites and exercises runtime behaviour inside Docker containers | No |
| `/dev-pr-review <pr>` | Reviews an external PR against a structured checklist | No |
| `/dev-pr-comment <pr>` | Addresses one review comment on your PR as a verified local commit | Yes (local commit) |

### The Standard Workflow

```
   /dev-init ──▶ /dev-plan ──▶ /dev-implement ──▶ /dev-review ──▶ open PR
(once per repo)                       │
                                      ▼
                                 /dev-verify
```

1. **Plan first**: Run `/dev-plan <feature or bug>`. It writes a structured task file to `.tasks/`.
2. **One step at a time**: Run `/dev-implement .tasks/<task>.md`. Let it finish a step, inspect the diff, and resume with `--continue`.
3. **Review before push**: Run `/dev-review`. Findings are verified against the real code—hallucinated findings are automatically discarded.
4. **Verify**: Run `/dev-verify` to ensure tests pass inside Docker.

---

## Best Practices

1. **Context Window at 64k–128k**: Set this in your server (LM Studio / Ollama / llama.cpp).
2. **Temperature 0**: Essential for consistent review findings and non-drifting tool calls.
3. **Start Fresh Sessions**: Start a new OpenCode session between unrelated tasks. Long conversation history degrades 30B model precision.
4. **Run Docker**: Start the Docker daemon so `/dev-verify` and `/dev-review` can execute commands in the project's true runtime environment.
5. **One step per `/dev-implement` run**: Let the command stop after each step. Resuming is free and prevents context drift.

---

## Troubleshooting

* **Commands not showing up**: Check `ls ~/.config/opencode/skills/`. Verify each folder has a `SKILL.md`.
* **Tool calls truncate or loop**: Server context window is below 64k. Increase context length in LM Studio or set `OLLAMA_CONTEXT_LENGTH=65536`.
* **Plan mode refuses to write to `.tasks/`**: Ensure `agent.plan.permission.edit` allows `.tasks/**` in `opencode.jsonc`.
* **Findings dropped as unverifiable**: The hallucination filter deleted a finding because the quoted code didn't exist in the file. Ensure `temperature: 0`.

---

## License

[MIT](LICENSE)
