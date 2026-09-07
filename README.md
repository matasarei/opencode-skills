# opencode-skills

<p>
  <a href="https://opencode.ai"><img src="https://img.shields.io/badge/OpenCode-1B1B1B?style=for-the-badge" alt="OpenCode" /></a>
  <img src="https://img.shields.io/badge/Local_models-6E56CF?style=for-the-badge&logo=ollama&logoColor=white" alt="Local models" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-3DA639?style=for-the-badge" alt="License: MIT" /></a>
</p>

> **Built for locally-hosted models, like Qwen Coder 30B.** Not for frontier models that happen
> to run locally: for the ones you can actually keep loaded on your own GPU. Every design
> decision here follows from that constraint.

Skills for [OpenCode](https://opencode.ai) covering an ordinary development day: work out what
to build, build it, check your own work, review a colleague's pull request, deal with the
comments on yours, and prove the result actually works.

They work in any repository — nothing here is tied to a particular project, language or
framework.

## Why "for local models" is the whole point

A 30B-class model can read a diff and spot a null dereference. What it cannot do is hold eight
severity criteria, seven blocker categories, a file budget and a retry cap in its head and then
*decide well*. Prompts written for a frontier model assume that judgement and quietly fall apart
without it — not by failing, but by producing confident, plausible, wrong output.

So these skills are built to **not need judgement**:

- **Facts are computed before the model is asked anything.** Which files changed, in what risk
  order, what the test and lint commands are, what the container prefix is — all resolved by
  shell scripts and injected as data, not derived by the model.
- **Judgement calls are replaced by yes/no checks**, with severity derived from *which* check
  fired rather than chosen.
- **Everything the model claims about the code is verified against the code** by a script, and
  discarded if the evidence is not there.
- **Nothing reports success it did not earn** — a step that could not run says so, instead of
  reading as a step that passed.

That is a different design from the frontier-model versions of these skills, not a translation
of them.

### Which models, concretely

| | |
|---|---|
| **Reference model** | Qwen3-Coder-30B — what these were written and tuned against |
| **Designed ceiling** | ~30B. Larger or cloud models work fine; they just do not need this design |
| **Realistic floor** | Untested below ~14B. Expect tool calling and instruction-following to degrade first |
| **Hard requirement** | A 64k+ context window and `temperature: 0` — see [configuration](#point-opencode-at-a-local-model) |
| **Step sizing** | assumes a 100k window — `contextTokens` in the profile, `DEV_SKILLS_CONTEXT` overrides it. A recommendation the planner follows, not a limit anything enforces — see [One step, one context](#one-step-one-context) |

~30B is the design ceiling, not a promise that anything smaller works. If you run these on a 7B
model and it holds up, that is a genuinely useful thing to report.

---

## Contents

- [Why "for local models" is the whole point](#why-for-local-models-is-the-whole-point)
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
- **git.** And **`gh`** for the three pull-request skills (`/dev-pr`, `/dev-pr-review`,
  `/dev-pr-comment`) — `gh auth login` once, then check with `gh auth status`.
- **node** only to run the eval suite: `evals/guard/cases.sh` loads the guard plugin under node.
  OpenCode runs the plugin itself.
- **bash**, and a Unix-like environment. macOS, Linux and WSL. Native Windows is not
  supported — see [Windows](#windows).
- **A context window of 64k or more.** This is not a nice-to-have. Below it, OpenCode's tool
  calling degrades in ways that look like the skills being broken — calls get truncated, the
  model loops, blocks of injected context go missing.
- **Docker**, strongly recommended on every platform.

### Windows

**Use WSL.** Install OpenCode inside WSL and run `./install.sh` there; everything behaves exactly
as it does on Linux.

Native Windows — Git Bash, MSYS, Cygwin — is deliberately unsupported, and `profile.sh` stops
with a message rather than trying. Those are POSIX *translation layers*, not Linux: programs run
as native Windows processes and paths are rewritten between `/c/...` and `C:\...`. The scripts
would mostly work, and "mostly" is the problem — container mounts land somewhere empty and a
false pass is indistinguishable from a real one. Carrying that risk plus its workarounds, for an
environment WSL already covers properly, is not worth it.

One thing to get right in WSL: **keep repositories in the WSL filesystem** (`~/projects/...`),
not under `/mnt/c/`. Windows drives are reachable but go through a network-style filesystem, and
git operations on a large repo there are slow enough to notice on every skill invocation.

### Why Docker matters here

The skills run the project's own commands **inside its container** by default. That is not about
convenience, it is about being right. A plugin written for PHP 7.4 and linted by a host PHP 8.4
will happily accept syntax that breaks in production, and a suite that passes against the wrong
runtime has proven nothing.

It also means you do not need PHP, Composer, Python or Node on the host at all, and the same
commands work on macOS, Linux and WSL.

Without Docker the skills still work — they fall back to the host toolchain and **say so in the
report**, with the version mismatch named. Treat a green run in that state with suspicion.

---

## Install

```bash
git clone https://github.com/matasarei/opencode-skills.git
cd opencode-skills
./install.sh
```

On Windows, run this inside WSL.

This installs:

| What | Where |
|---|---|
| Skills | `~/.config/opencode/skills/dev-*/` |
| Shared scripts | `~/.config/opencode/dev-lib/` |
| Optional subagent | `~/.config/opencode/agents/dev-check.md` |
| The guard | `~/.config/opencode/plugins/dev-guard.js` — see [The guard](#the-guard) |

### Check it worked

Start OpenCode in any git repository, type `/`, and you should see the nine `dev-` commands.

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
single most common cause of "the skills don't work". 100k+ is what the step sizing assumes;
tell the profile your real window with `DEV_SKILLS_CONTEXT` and steps are sized to it.

### Which model

**Qwen3-Coder-30B** is what these were written against: A3B, so it is fast enough for a
one-file-at-a-time loop, and tuned for code reading plus tool calling, which is the entire
workload here.

gpt-oss-20b works but needs high reasoning effort to stay agentic at all, and is weaker on code.
Since the design deliberately strips out the reasoning-heavy stages, that is the wrong trade.

---

## The skills

```
                              ┌─ one step, one context ───────────────────────────────┐
   /dev-init ──▶ /dev-plan ──▶│ /dev-implement ──▶ /dev-review ──▶ /dev-fix ──▶ /dev-pr │──▶ /new, then --continue
(once per repo)               └───────────────────────────────────────────────────────┘
                                                    │
                                  ┌─────────────────┴──────────────────┐
                                  ▼                                    ▼
                            /dev-pr-review                       /dev-pr-comment
                        (someone else's PR)                    (comments on yours)
                                  │                                    │
                                  └─────────────▶ /dev-verify ◀────────┘
```

| Command | What it does | Changes your code? |
|---|---|---|
| `/dev-init` | Writes this repository's `AGENTS.md` — commands plus its family's rules | **Yes** (two files) |
| `/dev-plan` | Turns a request, a task file or a GitHub issue into measured, PR-sized steps, checked against the real code | No |
| `/dev-implement` | Builds one step per run, on its own stacked branch, ticking it off | **Yes** |
| `/dev-review` | Checks your own changes before they go anywhere | No |
| `/dev-fix` | Applies the verified findings from `/dev-review`, one commit each | **Yes** (local commits) |
| `/dev-pr` | Pushes the step's branch and opens its pull request, stacked on the previous step's | **Pushes** — never merges |
| `/dev-pr-review` | Reviews someone else's pull request against a checklist | No |
| `/dev-pr-comment` | Addresses **one** review comment on *your* pull request, per run | **Yes** (local commit only) |
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
and writes `.tasks/export-department-collision.md`. Every step in it carries five lines scripts
read — `Create`, `Modify`, `Test`, `Check`, `Budget` — and two scripts check the plan before it
is handed over: `plan-check.sh` that every path it names exists, `step-budget.sh` that each
step fits the context window.

**Read the plan.** If it is wrong, say so now — fixing a plan costs far less than fixing a
half-built change.

**3. Build it, one step at a time.**

```
/dev-implement .tasks/export-department-collision.md
```

It cuts `step/export-department-collision-1` from `main`, does **one step** — the step arrives
injected, not the whole plan — ticks it off in the task file, commits, and stops with
`Next: /dev-review`. When you come back tomorrow:

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

**4b. Apply what it found, then open the pull request.**

```
/dev-fix
/dev-pr
```

`/dev-fix` applies each surviving BLOCKER and WARNING as its own smallest commit and proves it
by running the filter again — a finding whose evidence is gone is fixed. `/dev-pr` pushes the
branch and opens the pull request, stacked on the previous step's with `Depends on #n` first,
and ends with the two commands that start the next step in a fresh context:

```
/new
/dev-implement .tasks/export-department-collision.md --continue
```

Step 2 is cut from step 1's branch, so nothing waits for a merge. Merge them in step order.

**5. Prove it works.**

```
/dev-verify
```

Runs the suite and quotes the runner's actual output line, then drives the real export and
checks the effect. Says plainly what it could not check and why.

**6. Deal with review comments.**

```
/dev-pr-comment 42
```

It takes the **first unaddressed comment**, restates the claim, checks it against the code, and
gives a verdict — agree, disagree with evidence, or ask you — **before touching anything**. Only
on `agree` does it make a change, and only the smallest one that resolves the comment, as a local
commit.

Then it stops. Run it again for the next comment.

It **never pushes and never posts a reply.** It prints the exact commands and you send them. An
automated reviewer is confident and regularly wrong about this codebase in particular; fixing a
well-worded false positive is how you introduce a real bug, so that judgement gets a whole
context each time rather than a twelfth of one — and the outward-facing part stays yours.

Progress lives in `.devskills/pr-42.md`, so a comment you have already settled is never reopened.

---

## Getting the best results

Ordered by how much difference they make.

**1. Set the context window to 64k+ and temperature to 0.** Nothing else on this list matters if
these are wrong. See [above](#two-settings-that-matter-more-than-the-model-choice).

**2. Run `/dev-init` once per repository.** Every other skill reads `AGENTS.md` for the
project's conventions. Without it they fall back to whatever documentation exists, or nothing.
This is the cheapest quality improvement available.

**3. `/new` after every step's pull request.** Context accumulates and is re-sent with every
message, and an hour of history actively degrades a 30B model's instruction-following. The task
file and the branch are the state, so a fresh session loses nothing; a small model's `/compact`
summary loses instructions, so keep it for one case — a step that overruns mid-cycle.

**4. One step per `/dev-implement` run — let it stop.** A long build in a single context drifts,
and a drifting build is worse than a slow one. A step is sized to its whole cycle — build,
review, fix, pull request — by `step-budget.sh` against `contextTokens`: 12 lines of source per
1k tokens of window, about 1,200 lines at 100k. That is a recommendation, not a gate:
`/dev-plan` splits when a split exists, and a step it cannot split is kept and labelled
`OVER — kept`. Set `DEV_SKILLS_CONTEXT` to your real window.

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

The reasoning is [at the top](#why-for-local-models-is-the-whole-point). This is what it actually
looks like in the code.

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

### One unit of work per run

The queue from [`lib/changed.sh`](lib/changed.sh) is risk-ranked in shell, so the model never
picks what to read — it reads top-down, one file at a time. `/dev-implement` does **one step per
invocation** and ticks it off in the task file. `/dev-pr-comment` does **one review comment per
invocation** and records the verdict in `.devskills/pr-<n>.md`.

A long run in a single context drifts. By the eighth review comment the verdicts are grounded in
the previous seven rather than in the code, and one bad fix in a batch of twelve is invisible
until much later. Resuming costs nothing, so there is nothing to gain by batching.

That is also why **`/dev-pr-comment` never pushes and never posts a reply** — it prints the
commands and you send them. A confident, well-worded false positive from an automated reviewer is
the most likely way this toolkit could put a real bug into your code, so the step where that gets
caught stays with a person.

### One step, one context

A plan step is what one `/dev-implement` run builds and one pull request carries, and its whole
cycle — build, `/dev-review`, `/dev-fix`, `/dev-pr` — has to fit one context. Measured on this
repository a source line is about 10 tokens; with the prompt, the profile, the diff and the
review's re-read taken out, the rule is **12 lines of source per 1k tokens of window**.
`profile.sh` records the window as `contextTokens` (100000 by default), `step-budget.sh` sums
`wc -l` over the files a step's `Modify:` and `Test:` lines name, and `/dev-plan` pastes the
verdict into the step. Three more scripts take the reading out of the model's hands:
`plan-input.sh` decides whether the argument was a file, an issue or a sentence; `task-step.sh`
hands `/dev-implement` exactly the step it is on; `plan-check.sh` refuses a plan that names a
path that is not there — the plan-side twin of `findings-check.sh`. All four share
`lib/steps.awk`, so they agree on what a step is.

Each step gets its own branch, `step/<slug>-<n>`, cut from the previous step's, and its own pull
request targeting that branch — nothing waits for a merge, and they merge in step order. Between
steps the context is cleared with `/new`, not compacted: the state is on disk. One more file
carries over: `.devskills/learned.md`, where `/dev-implement` and `/dev-fix` append at most one
dated line per run — a trap of the repository, not of the change — and `/dev-plan` and
`/dev-implement` read the last twenty back.

### The guard

`/dev-pr` is the one skill that pushes, and it can only because a plugin refuses everything past
that point. `lib/dev-guard.js` runs before every bash tool call in OpenCode and throws on a
forced push in any spelling, an amended commit, a skipped hook, a push to `main`, `master` or the
profile's base branch in every ref shape, `gh pr merge`, `gh pr review --approve`, `gh release`,
`gh workflow run` and `gh api …/merge`. Quoted text is blanked first, so a commit message may
mention a flag. `install.sh` puts it in `~/.config/opencode/plugins/`; OpenCode has no per-skill
hook, so it is on for every session, and `evals/guard/cases.sh` holds it to a 43-case table.

A second, optional layer is OpenCode's own permission rules in `opencode.json` — the docs do not
say whether flags are visible to these globs, so the plugin is the layer that is tested:

```json
"permission": {
  "bash": {
    "git push --force*": "deny",
    "git push -f *": "deny",
    "git commit --amend*": "deny",
    "gh pr merge*": "deny"
  }
}
```

### Nothing reports success it did not earn

`lint.sh` distinguishes `lint: clean across 4 changed file(s)`, `lint: no lintable files among
the changes — nothing was checked`, and `LINT NOT RUN — could not determine what changed`. `diff.sh` announces exactly how many lines it
truncated. `/dev-verify` treats "cannot tell" as a valid verdict. A tool that overstates what it
checked is worse than one that checks less.

### Rationale lives here, not in the prompts

Each `SKILL.md` is capped: **at most 90 lines and 4,500 bytes** (about 1,100 tokens) and a
one-sentence description, and `evals/skills/size.sh` fails the build past it. What was cut is
the *why* — paragraphs that make a large model exercise better judgement and make a 30B pay
tokens for nothing. It is in this README instead, for you. So are two flags the frontier
versions carry: `--review` (judging a proposal is judgement work) and `--all` (it contradicts
one step per run).

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
- **`/dev-plan` may split more finely than a person would.** The budget is a line count, not a
  judgement of cohesion; a step it cannot split it keeps and labels `OVER — kept`.
- **The guard is a set of patterns, not a policy engine.** It refuses the shapes in its table; a
  new way to spell a forced push is a new case for `evals/guard/cases.sh`.
- **Not yet validated against a real local model.** Every script is fixture-tested —
  `bash evals/run-all.sh`, fifteen suites, run in CI — and the guard against its case table.
  Whether the binary-check design holds up on Qwen3-Coder-30B in practice is still an open
  question, and the 12-lines-per-1k step coefficient is the first number a real run should
  correct. Feedback on either is the most useful thing you could send.

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

**On Windows: `Native Windows (Git Bash / MSYS / Cygwin) is not supported`.**
That message is deliberate, not a bug. Run OpenCode inside WSL and install there — see
[Windows](#windows).

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

**The guard refused a command.**
Working as intended: a forced push, an amended commit, a skipped hook, a push to the base branch
or a merge. Make a new commit and push that; open the pull request with `/dev-pr`. To turn it
off, remove `~/.config/opencode/plugins/dev-guard.js`.

**A skill name collides with another toolkit.**
OpenCode also loads skills from `~/.claude/skills/` and `~/.agents/skills/`. Names must be unique
across all of them. Rename or remove the duplicate.

---

## Layout and contributing

```
lib/                  shared scripts — installed to <config>/dev-lib/
  profile.sh          detect and cache the repo's toolchain, contextTokens included
  changed.sh          risk-ranked queue of changed files
  diff.sh             capped diff against the base branch, truncation announced
  lint.sh             lint changed files through exec.prefix, honest about not running
  findings-check.sh   delete findings whose evidence is not in the code
  pr-comments.sh      flatten a PR's review comments into a stable ledger
  steps.awk           what a task-file step is — shared by the four below
  plan-input.sh       resolve /dev-plan's argument: a file, an issue, a sentence, or missing
  task-step.sh        hand /dev-implement exactly one step
  plan-check.sh       refuse a plan that names a path that is not there
  step-budget.sh      size a step against contextTokens
  pr-info.sh          the base, the pull request and the unplanned paths for /dev-pr
  dev-guard.js        the guard — installed to <config>/plugins/, not dev-lib
skills/dev-*/         one directory per skill, SKILL.md inside, capped by evals/skills/size.sh
  dev-init/templates/ family rule blocks (moodle-plugin, php-app, cms, python-app)
agents/               optional subagents (read-only, temperature 0)
evals/                fixture suites — run-all.sh runs every one; CI runs exactly that
  lib/                one suite per script in lib/
  skills/             frontmatter, size, the step template's shape, the hand-offs between skills
  guard/              the 43-case table the guard is held to
  docs/               this README against the mechanics it describes
install.sh            global, or --project
```

The rule that keeps this working on small models:

> **If a skill needs a fact, compute it in `lib/` rather than asking the model to work it out.**

Corollaries worth keeping:

- Prefer a yes/no question over a judgement call; derive severity from which check fired.
- Anything the model asserts about the code must be verifiable against the code by a script.
- Never let a step that did not run report as a step that passed.
- Keep each `SKILL.md` under 90 lines and 4,500 bytes. Rationale belongs in this README; the
  prompt gets instructions.
- Shell before reading: `wc -l` before a file, `sed -n` for a range, `grep -rn` for a symbol,
  `gh … --json … -q` for GitHub. The same words in every skill.
- Every suite prints one line and exits non-zero when its rule no longer holds; a new script
  lands with its suite.

## Licence

MIT — see [LICENSE](LICENSE).
