# opencode-skills

Skills for [OpenCode](https://opencode.ai) covering an ordinary development day: work out what
to build, build it, check your own work, review a colleague's pull request, deal with the
comments on yours, and prove the result actually works.

They work in any repository — nothing here is tied to a particular project, language or
framework.

**These are tuned for local models.** They assume a 30B-class model running on your own
hardware, and they spend their instructions on *not needing judgement* — facts are computed by
scripts before the model is asked anything, and its output is verified mechanically afterwards.
That is a different design from the frontier-model versions, not a translation of them.

MIT licensed.

---

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Point OpenCode at a local model](#point-opencode-at-a-local-model)
- [The skills](#the-skills)
- [A worked example](#a-worked-example-start-to-finish)
- [Getting the best results](#getting-the-best-results)
- [Writing a task file](#writing-a-task-file)
- [How this differs from the frontier-model versions](#how-this-differs-from-the-frontier-model-versions)
- [Known limits](#known-limits)
- [Troubleshooting](#troubleshooting)
- [Layout and contributing](#layout-and-contributing)

---

## Requirements

- **OpenCode**, recent enough to support skills (`.opencode/skills/`).
- **git.** And **`gh`** for the two pull-request skills — `gh auth login` once, then check with
  `gh auth status`.
- **bash.** The shared scripts are bash. On Windows that means **Git Bash**, which ships with
  [Git for Windows](https://git-scm.com/download/win). WSL works too and behaves like Linux.
- **A context window of 64k or more.** This is not a nice-to-have. Below it, OpenCode's tool
  calling degrades in ways that look like the skills being broken — calls get truncated, the
  model loops, blocks of injected context go missing.
- **Docker**, strongly recommended on every platform.

### Why Docker matters here

The skills run the project's own commands **inside its container** by default. That is not about
convenience, it is about being right. A plugin written for PHP 7.4 and linted by a host PHP 8.4
will happily accept syntax that breaks in production, and a suite that passes against the wrong
runtime has proven nothing.

It also means you do not need PHP, Composer, Python or Node on the host at all, and the same
commands work on macOS, Linux, WSL and Windows.

Without Docker the skills still work — they fall back to the host toolchain and **say so in the
report**, with the version mismatch named. Treat a green run in that state with suspicion.

---

## Install

```bash
git clone https://github.com/matasarei/opencode-skills.git
cd opencode-skills
./install.sh
```

On Windows, from PowerShell: `.\install.ps1`

This installs:

| What | Where |
|---|---|
| Skills | `~/.config/opencode/skills/dev-*/` |
| Shared scripts | `~/.config/opencode/dev-lib/` |
| Optional subagent | `~/.config/opencode/agents/dev-check.md` |

### Check it worked

Start OpenCode in any git repository, type `/`, and you should see the seven `dev-` commands.

To confirm the scripts are reachable, run this from inside a repository:

```bash
bash ~/.config/opencode/dev-lib/profile.sh
```

You should get a JSON block describing that repository. If you get "No such file or directory",
see [Troubleshooting](#troubleshooting).

### Installing for one project only

```bash
./install.sh --project      # installs into ./.opencode
```

The skills fall back to `$HOME/.config/opencode/dev-lib` when looking for the scripts, because a
`SKILL.md` cannot know where it was installed. A project install therefore **needs the
override**, which `install.sh` prints for you:

```bash
export DEV_SKILLS_LIB=/path/to/project/.opencode/dev-lib
```

Put it in your shell profile. The same applies if your `XDG_CONFIG_HOME` is not the default.

### Updating

```bash
git pull && ./install.sh
```

There is no marketplace and **nothing pulls updates for you**. `install.sh` writes the commit it
installed to `dev-lib/.version` so you can tell how old your copy is.

---

## Point OpenCode at a local model

Put this in `~/.config/opencode/opencode.json`. Pick the provider block that matches your setup.

### Ollama

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/qwen3-coder:30b",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": {
        "qwen3-coder:30b": { "name": "Qwen3-Coder 30B" }
      }
    }
  },
  "agent": {
    "build": { "temperature": 0 },
    "plan":  { "temperature": 0 }
  }
}
```

**Ollama's default context is 4096 tokens** — sixteen times smaller than these skills need, and
small enough that a single injected diff will blow past it. Raise it before you start:

```bash
OLLAMA_CONTEXT_LENGTH=65536 ollama serve
```

You can also set it per session with `/set parameter num_ctx 65536` inside `ollama run`, but the
environment variable is the one that survives a restart.

### LM Studio

Same shape, with `"baseURL": "http://127.0.0.1:1234/v1"`. Set the context length to 64k+ in the
model's load settings — LM Studio defaults far below that.

### llama.cpp

```json
"llama.cpp": {
  "npm": "@ai-sdk/openai-compatible",
  "name": "llama-server (local)",
  "options": { "baseURL": "http://127.0.0.1:8080/v1" },
  "models": {
    "qwen3-coder:a3b": {
      "name": "Qwen3-Coder 30B",
      "limit": { "context": 128000, "output": 65536 }
    }
  }
}
```

### Two settings that matter more than the model choice

**Set `temperature` to 0 explicitly.** OpenCode defaults Qwen models to **0.55**. At that
setting the same diff produces different findings on different runs, which makes a review
useless — you cannot tell a fixed problem from a problem that was not re-rolled this time.

**Set the context window to 64k or more**, at the *server*, not just in the config. This is the
single most common cause of "the skills don't work".

### Which model

**Qwen3-Coder-30B** is what these were written against: A3B, so it is fast enough for a
one-file-at-a-time loop, and tuned for code reading plus tool calling, which is the entire
workload here.

gpt-oss-20b works but needs high reasoning effort to stay agentic at all, and is weaker on code.
Since the design deliberately strips out the reasoning-heavy stages, that is the wrong trade.

---

## The skills

```
   /dev-init ──▶ /dev-plan ──▶ /dev-implement ──▶ /dev-review ──▶ open a pull request
(once per repo)
                                                    │
                                  ┌─────────────────┴──────────────────┐
                                  ▼                                    ▼
                            /dev-pr-review                       /dev-pr-resolve
                        (someone else's PR)                    (comments on yours)
                                  │                                    │
                                  └─────────────▶ /dev-verify ◀────────┘
```

| Command | What it does | Changes your code? |
|---|---|---|
| `/dev-init` | Writes this repository's `AGENTS.md` — commands plus its family's rules | **Yes** (two files) |
| `/dev-plan` | Turns a request into a concrete plan, checked against the real code | No |
| `/dev-implement` | Builds the plan, one step per run, ticking off progress | **Yes** |
| `/dev-review` | Checks your own changes before you push them | No |
| `/dev-pr-review` | Reviews someone else's pull request against a checklist | No |
| `/dev-pr-resolve` | Works through the review comments on *your* pull request | **Yes** |
| `/dev-verify` | Runs the tests and drives the real thing to prove it works | No |

You do not have to use all of them, or use them in order. **`/dev-review` on its own, before
every push, is already worth it.**

Arguments are plain text — nothing is shell-parsed, so quotes are optional and apostrophes are
fine. Quotes only help when a flag follows prose: `/dev-implement "add CSV export" --continue`.

> The `dev-` prefix is not decoration. OpenCode ships built-in `/init` and `/review` commands,
> and a custom command with the same name **replaces them silently**.

---

## A worked example, start to finish

Say someone reports: *the statistics export merges two departments that happen to share a name.*

**1. Set the repository up (once).**

```
/dev-init
```

Detects the project family, writes `AGENTS.md` with the real build and test commands plus that
family's conventions, and leaves `CLAUDE.md` as a one-line `@AGENTS.md` import so Claude Code
reads the same file. OpenCode loads `AGENTS.md` at the start of every session from then on.

**2. Work out what is actually wrong.**

```
/dev-plan the statistics export merges departments that share a name
```

It asks you to confirm whether this is a bug, a feature, a question or a data fix — that one
answer drives everything downstream, and it is cheaper to ask than to guess. Then it finds the
export code, reads it, checks the database to see whether same-named departments really exist,
and writes `.tasks/export-department-collision.md`.

**Read the plan.** If it is wrong, say so now — fixing a plan costs far less than fixing a
half-built change.

**3. Build it, one step at a time.**

```
/dev-implement .tasks/export-department-collision.md
```

It creates a branch, does **one step**, ticks it off in the task file, and stops. Run it again
for the next step. When you come back tomorrow:

```
/dev-implement .tasks/export-department-collision.md --continue
```

It resumes at the first unticked step. Nothing is rebuilt.

**4. Check your own work.**

```
/dev-review
```

Twelve yes/no checks per file, worst-risk file first, every finding carrying a line quoted from
the code — then a script deletes any finding whose quote is not actually there. You get
blockers, warnings and nits, and an explicit note of which files were judged from the diff alone.

**5. Prove it works.**

```
/dev-verify
```

Runs the suite and quotes the runner's actual output line, then drives the real export and
checks the effect. Says plainly what it could not check and why.

**6. Deal with review comments.**

```
/dev-pr-resolve 42
```

Every comment gets a verdict — agree, disagree with evidence, or ask you — **before any code is
touched**. Then one commit per fix, and one reply per thread.

---

## Getting the best results

Ordered by how much difference they make.

**1. Set the context window to 64k+ and temperature to 0.** Nothing else on this list matters if
these are wrong. See [above](#two-settings-that-matter-more-than-the-model-choice).

**2. Run `/dev-init` once per repository.** Every other skill reads `AGENTS.md` for the
project's conventions. Without it they fall back to whatever documentation exists, or nothing.
This is the cheapest quality improvement available.

**3. Start a fresh session between unrelated tasks.** Context accumulates and is re-sent with
every message. An unrelated hour of history does not just cost tokens — it actively degrades a
30B model's instruction-following. New task, new session.

**4. One step per `/dev-implement` run — let it stop.** This is deliberate. A long build in a
single context drifts, and a drifting build is worse than a slow one. Resuming is free, so let
it finish a step, read what it did, and run it again.

**5. Write a task file for anything bigger than a sentence.** A written brief gets it right the
first time far more often, and a redo costs more than the five minutes of writing.

**6. Keep changes small.** `/dev-review` reads the top 3 files of its risk-ranked queue in full
and judges the rest from the diff. A 40-file branch will be reviewed honestly but shallowly, and
it will tell you so. Two small branches beat one large one.

**7. Let the profile cache do its job.** The repository's toolchain is detected once into
`.devskills/profile.json` and reused. Delete that file (or run
`bash ~/.config/opencode/dev-lib/profile.sh --reprofile`) when the project's commands change.

**8. Add `.devskills/` to your `.gitignore`.** It holds machine-specific paths and working
state, not project content.

**9. Start Docker before `/dev-verify`.** Otherwise it records a `SETUP` blocker and verifies
much less than it could.

**10. Type the slash command; do not ask the model to load the skill.** The pre-computed context
blocks only fire on `/dev-review`. When a model loads the same skill through OpenCode's `skill`
tool, those blocks arrive empty and it has to run the scripts itself — which mostly works, but
it is the slower and less reliable path.

---

## Writing a task file

For anything bigger than a sentence, write it down and pass the path. There is no required
format — a model reads it, so clear prose works. A useful shape:

```markdown
# Individual plan export by indicator

## What we need
A background xlsx export of individual plan statistics, with two sheets:
one per indicator, one with the scientific-work detail.

## Why
Faculty administrators currently count this by hand every semester.

## Details
- Reuse the existing background export mechanism — no new infrastructure.
- Rows group by indicator, then faculty, then department.
- Departments in different faculties can share a name; they must not be merged.

## Done when
- [ ] An administrator can request the export from the statistics page
- [ ] The file has both sheets, with numbers as numbers (sortable in Excel)
- [ ] Same-named departments in different faculties stay separate
```

Keep them in `.tasks/`. `/dev-plan` writes there and `/dev-implement` reads and updates them.

**Be specific about "done".** That list becomes the acceptance criteria, which is what
`/dev-implement` builds against and what `/dev-verify` checks. Vague criteria produce vague work.

---

## How this differs from the frontier-model versions

A 30B-class model can read a diff and spot a null dereference. What it cannot do is hold "here
are eight severity criteria, seven blocker categories, a five-file budget and a three-round retry
cap — now decide." Every design choice here follows from that.

### Facts are computed, not derived

The frontier-model version carries 292 lines of prose telling the model how to work out the
repo's test command, lint command, container prefix and base branch. That is ~15 tool calls, each
one a decision, each one a chance to skip a step and assert a plausible answer instead.

Here it is [`lib/profile.sh`](lib/profile.sh). It runs once, caches to `.devskills/profile.json`,
and the skill receives JSON:

```markdown
!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`
```

OpenCode substitutes ``!`command` `` into the prompt *before the model sees it*. Zero decisions,
zero round trips, and about 4k tokens of context handed back.

The point is not speed. **A script can be tested and prose cannot.** You can run `profile.sh`
against your repositories and check the JSON. You cannot test whether 292 lines of English will
be followed — you find out when a review lints a 7.4 plugin against host PHP 8.4 and calls it
clean.

### Binary checks instead of severity judgement

`/dev-review` does not ask the model to weigh a finding and label it. It asks twelve yes/no
questions about one file, and severity is a lookup on *which* question fired. Small models answer
"does this rename a function?" reliably, and assign severities badly.

### Evidence is verified mechanically

Every finding must carry a line copied from the file. Then
[`lib/findings-check.sh`](lib/findings-check.sh) checks the quoted text is really there and at
roughly the claimed line, and deletes the finding if it is not:

```
BLOCKER | db/upgrade.php:3  | user input reaches the cell unescaped | EVIDENCE: $sheet->setCellValue($col, $dept);
BLOCKER | db/upgrade.php:12 | invented, line does not exist         | EVIDENCE: $db->execute("DROP TABLE users");
→ findings: 1 verified, 1 dropped as unverifiable
```

This is the hallucination filter, and it is the part that does not depend on model quality. It
gets better as the format gets stricter, not as the model gets bigger.

### Nothing reports success it did not earn

`lint.sh` distinguishes `lint: clean across 4 changed file(s)`, `lint: no lintable files among
the changes — nothing was checked`, and `LINT NOT RUN — could not determine what changed`. `diff.sh` announces exactly how many lines it
truncated. `/dev-verify` treats "cannot tell" as a valid verdict. A tool that overstates what it
checked is worse than one that checks less.

### Rationale lives here, not in the prompts

Each `SKILL.md` is roughly a third the size of its frontier-model counterpart. What was cut is
the *why* — paragraphs that make a large model exercise better judgement and make a 30B pay
tokens for nothing. It is in this README instead, for you.

---

## Known limits

- **`/dev-pr-review` is a checklist, not a review.** Races, subtle design problems and "this
  abstraction will force the next change to touch five files" are frontier-model work. It says so
  in its own verdict rather than implying full coverage.
- **`/dev-plan` follows existing patterns rather than designing.** It is told to match something
  already in the repository and cite it. For a genuinely novel design, plan it yourself and pass
  the brief to `/dev-implement`.
- **Shell injection only fires on the slash command.** Loaded through the `skill` tool, the
  ``!`…` `` blocks arrive empty. Each skill detects this and tells the model to run the scripts
  itself, but the slash command is the better path.
- **`profile.sh` infers an image** for repositories with no compose file. It proves the bind
  mount works before trusting one and falls back to the host with a recorded reason — but the
  image choice itself is a guess.
- **Not yet validated against a real local model.** Every script here is tested against fixtures.
  Whether the binary-check design holds up on Qwen3-Coder-30B in practice is still an open
  question, and feedback on that is the most useful thing you could send.

---

## Troubleshooting

**The `/dev-*` commands do not appear.**
Restart OpenCode. Check the skills landed: `ls ~/.config/opencode/skills/`. Each directory must
contain a `SKILL.md` in capitals, and the `name:` in its frontmatter must match the directory
name exactly.

**A skill runs but the profile/queue/diff blocks are empty.**
Either the scripts are not where the skills expect, or you loaded the skill through the `skill`
tool instead of typing `/dev-review`. Check the first case with:

```bash
bash ~/.config/opencode/dev-lib/profile.sh
```

If that fails, set `DEV_SKILLS_LIB` to wherever `install.sh` actually put the scripts.

**`bash: command not found` on Windows.**
OpenCode is not using Git Bash. Install [Git for Windows](https://git-scm.com/download/win) and
point OpenCode's shell at it.

**Tool calls get truncated, or the model loops.**
Context window below 64k. Fix it at the server — `OLLAMA_CONTEXT_LENGTH=65536 ollama serve`, or
the model load settings in LM Studio. This is by far the most common cause.

**The same diff gives different findings each run.**
Temperature is not 0. See [the config above](#two-settings-that-matter-more-than-the-model-choice).

**`/dev-review` says "you are on `main` — switch to your branch first".**
Working as intended: there is nothing to compare against. Make a branch.

**Lint says `LINT NOT RUN`.**
It could not work out what changed — usually the same base-branch situation. It reports this
rather than printing "clean", because a lint that did not run must never read as a pass.

**Findings were "dropped as unverifiable".**
That is the filter working: the model quoted a line that is not in the file. If real findings are
being dropped, the model is paraphrasing evidence instead of copying it — lower the temperature
and check the context window.

**A skill got the test command wrong.**
The profile is cached. `rm .devskills/profile.json`, or run
`bash ~/.config/opencode/dev-lib/profile.sh --reprofile`. If the real command lives somewhere
unusual, put it in `AGENTS.md` — the skills read that.

**A skill says it fell back to the host instead of Docker.**
The daemon is not running, or the bind mount could not be proven. Start Docker and re-profile.
Worth doing: on the host you are testing against whatever versions your machine happens to have.

**The diff came back truncated.**
Expected on a large branch — it tells you how many lines it withheld. Review the remaining files
individually, or split the branch.

**A skill name collides with another toolkit.**
OpenCode also loads skills from `~/.claude/skills/` and `~/.agents/skills/`. Names must be unique
across all of them. Rename or remove the duplicate.

---

## Layout and contributing

```
lib/                  shared scripts — installed to <config>/dev-lib/
  profile.sh          detect and cache the repo's toolchain
  changed.sh          risk-ranked queue of changed files
  diff.sh             capped diff against the base branch, truncation announced
  lint.sh             lint changed files through exec.prefix, honest about not running
  findings-check.sh   delete findings whose evidence is not in the code
skills/dev-*/         one directory per skill, SKILL.md inside
  dev-init/templates/ family rule blocks (moodle-plugin, php-app, cms, python-app)
agents/               optional subagents (read-only, temperature 0)
install.sh            global, or --project
install.ps1           the same for Windows PowerShell
```

The rule that keeps this working on small models:

> **If a skill needs a fact, compute it in `lib/` rather than asking the model to work it out.**

Corollaries worth keeping:

- Prefer a yes/no question over a judgement call; derive severity from which check fired.
- Anything the model asserts about the code must be verifiable against the code by a script.
- Never let a step that did not run report as a step that passed.
- Keep each `SKILL.md` short. Rationale belongs in this README; the prompt gets instructions.

## Licence

MIT — see [LICENSE](LICENSE).
