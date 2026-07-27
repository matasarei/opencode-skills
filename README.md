# opencode-skills

Skills for [OpenCode](https://opencode.ai) covering an ordinary development day: work out what
to build, build it, check your own work, review a colleague's pull request, deal with the
comments on yours, and prove the result actually works.

They work in any repository — nothing here is tied to a particular project, language or
framework.

**These are tuned for local models.** The sibling `claude-skills` and `antigravity-skills`
assume a frontier model and spend their instructions on judgement. This port assumes a
30B-class model running on your own hardware, and spends its instructions on *not needing
judgement*. That is a different design, not a translation.

MIT licensed.

---

## Install

```bash
git clone https://github.com/matasarei/opencode-skills.git
cd opencode-skills
./install.sh              # or .\install.ps1 on Windows
```

Installs to `~/.config/opencode/skills/dev-*/` and `~/.config/opencode/dev-lib/`.
`./install.sh --project` installs into `./.opencode` instead, for one repository.

Update with `git pull && ./install.sh`. There is no marketplace and nothing pulls updates for
you, so `install.sh` writes a commit stamp to `dev-lib/.version`.

### Requirements

- **git**, and **`gh`** for the two pull-request skills (`gh auth login` once).
- **bash.** The shared scripts are bash. On Windows that means Git Bash, which ships with Git
  for Windows.
- **Docker**, strongly recommended. The skills run the project's own commands *inside its
  container* by default — not for convenience, for correctness. A plugin written for PHP 7.4
  linted by a host PHP 8.4 will accept syntax that breaks in production. Without Docker they
  fall back to the host and say so.
- **A context window of 64k or more.** Below that OpenCode's tool calling degrades in ways
  that look like the skills being broken.

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

`/dev-review` on its own, before every push, is already worth it.

The `dev-` prefix is not decoration: OpenCode ships built-in `/init` and `/review` commands,
and a custom command with the same name **silently replaces them**.

---

## How this differs from the Claude version, and why

A 30B-class model can read a diff and spot a null dereference. What it cannot do is hold
"here are eight severity criteria, seven blocker categories, a five-file budget and a
three-round retry cap — now decide." Every design choice here follows from that.

### Facts are computed, not derived

The Claude version carries 292 lines of prose telling the model how to work out the repo's
test command, lint command, container prefix and base branch. That is ~15 tool calls, each one
a decision, each one a chance to skip a step and assert a plausible answer instead.

Here it is [`lib/profile.sh`](lib/profile.sh). It runs once, caches to `.devskills/profile.json`, and
the skill receives JSON:

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
questions about one file, and the severity is a lookup on *which* question fired. Small models
answer "does this rename a function?" reliably and assign severities badly.

### Evidence is verified mechanically

Every finding must carry a line copied from the file. Then
[`lib/findings-check.sh`](lib/findings-check.sh) checks that the quoted text is actually there,
and deletes the finding if it is not.

This is the hallucination filter, and it is the part that does not depend on model quality:

```
BLOCKER | db/upgrade.php:3  | user input reaches the cell unescaped | EVIDENCE: $sheet->setCellValue($col, $dept);
BLOCKER | db/upgrade.php:12 | invented, line does not exist         | EVIDENCE: $db->execute("DROP TABLE users");
→ findings: 1 verified, 1 dropped as unverifiable
```

### One file per step, one step per run

The queue from [`lib/changed.sh`](lib/changed.sh) is risk-ranked in shell, so the model never
chooses what to read — it reads top-down. `/dev-implement` does **one step per invocation** and
ticks it off in the task file. A long build in a single context drifts; a drifting build is
worse than a slow one, and resuming is free.

### Rationale lives here, not in the prompts

Each `SKILL.md` is roughly a third the size of its Claude counterpart. What was cut is the
*why* — the paragraphs that make a frontier model exercise better judgement and make a 30B
pay tokens for nothing. It is in this README instead, for you.

---

## Recommended configuration

Set the temperature explicitly. **OpenCode defaults Qwen models to 0.55**, which makes the same
diff produce different findings on different runs:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/qwen3-coder:30b",
  "agent": {
    "build": { "temperature": 0 },
    "plan":  { "temperature": 0 }
  }
}
```

Qwen3-Coder-30B is the model these were written against — A3B, so it is fast enough for a
one-file-at-a-time loop, and tuned for code reading plus tool calling, which is the whole
workload here.

---

## Known limits

Said plainly, because a tool that overstates what it checked is worse than one that checks less.

- **`/dev-pr-review` is a checklist, not a review.** Races, subtle design problems and
  "this abstraction will force the next change to touch five files" are frontier-model work.
  It says so in its own verdict.
- **`/dev-plan` follows existing patterns rather than designing.** It is told to match
  something already in the repository and cite it. For a genuinely novel design, plan it
  yourself.
- **Shell injection only fires on the slash command.** When a model loads a skill through the
  `skill` tool instead, the ``!`…` `` blocks arrive empty. Each skill says so and tells it to
  run the scripts itself.
- **`profile.sh` guesses images for repositories with no compose file.** It verifies the bind
  mount before trusting one, and falls back to the host with a recorded reason — but the image
  choice itself is an inference.

---

## Layout

```
lib/                  shared scripts — installed to <config>/dev-lib/
  profile.sh          detect and cache the repo's toolchain
  changed.sh          risk-ranked queue of changed files
  diff.sh             capped diff against the base branch
  lint.sh             lint every changed file through exec.prefix
  findings-check.sh   delete findings whose evidence is not in the code
skills/dev-*/         one directory per skill, SKILL.md inside
agents/               optional subagents (read-only, temperature 0)
```

Contributions should keep the shape: **if a skill needs a fact, compute it in `lib/` rather
than asking the model to work it out.**

## Licence

MIT — see [LICENSE](LICENSE).
