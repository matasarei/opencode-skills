---
name: dev-implement
description: Build a task step by step in the current session — from a plan file, a brief, or a sentence. Does one step per run and ticks it off in the task file, so an interrupted build resumes exactly where it stopped instead of starting over.
---

# Build it, one step at a time

Sequential, in this working tree. No agent fleets, nothing hidden — you can watch every edit and stop at any point.

**One step per run.** This is deliberate: a long build in one context drifts, and a drifting build is worse than a slow one. Finish a step, tick it, report, stop. Run the command again for the next one.

## Arguments

Whatever follows the command is at the end of this message.

- **A path** → the task file. If it does not exist, **stop with "no such file"** — never treat it as a sentence and build something invented. That mistake is expensive here, because this skill writes code.
- **A sentence** → plan it inline first (step 2).
- **Nothing** → ask what to build. Never fall back to a leftover file.
- `--continue` → resume at the first unticked step.
- `--step <n>` → that step only.
- `--all` → work through every remaining step in one run. Use only for a short task.

## Step 1 — Set up

From the profile below: the test, lint and build commands, and the base branch.

- **Uncommitted changes you did not make** → stop and ask. Do not build on someone else's half-finished work.
- **On the base branch** → create a branch first: `feature/<slug>` or `fix/<slug>`.

Read the task file and echo the goal back in one sentence before touching anything.

**Everything touching the project's toolchain runs through `exec.prefix`.** Anything you compose yourself — a one-off script, a query, a single-file lint — gets the prefix too. `git`, file edits and HTTP to a published port stay on the host. If `exec.kind` is `host`, say so when reporting test results: you tested against this machine's versions, not the project's.

## Step 2 — Make sure there is a plan

Already has acceptance criteria and ordered steps → use them.

A sentence or loose brief → work out the plan now and **write it into the task file**, so `--continue` has something to resume from. For anything substantial or unfamiliar, stop and suggest `/dev-plan` first.

## Step 3 — Build one step

1. **Read** the files it touches, and enough around them not to break something.
2. **Make the change.** Match the file you are editing — its naming, structure, comment style. Consistency with the neighbours beats consistency with a style guide.
3. **Check it now** — lint the changed file, run the scoped test if one covers this. A mistake found now is far cheaper than one found four steps later.
4. **Tick it in the task file**, with one line on what landed:

   ```markdown
   - [x] Add the CSV generator — `classes/export/generator/CsvExporter.php` (new)
   ```

5. **Commit.** One commit per step.

**Stay inside the task.** Something unrelated and broken that you notice gets mentioned at the end, not fixed silently.

## Step 4 — Tests, once the steps are done

Cover the main path with a real assertion, the **error paths** (bad input, missing record, failed write, empty result), and the **edges** (null, empty, zero, one, duplicates). Copy the shape of a neighbouring test file.

No tests and no test command → say so plainly, and write the first one anyway if the profile shows a usable framework. Do not invent a harness that does not exist.

## Step 5 — Prove it

Run the profile's test command, wrapped in `timeoutTool`. **A hang is a failure.** Quote the runner's actual result line, not "tests pass".

Something fails → fix and re-run, **up to three rounds**. After three, stop and report what is still failing and what you think it is.

Then check the change does something, using `runtime`. A green suite for code that was never executed is not evidence. For `hosted`, say plainly that runtime checking needs the host application, and stop at lint plus tests.

## Step 6 — Finish

- **Moodle plugin** — bump `$plugin->version` in `version.php` if you added or moved anything under `classes/`, or changed `db/`, caches or tasks. Without it the live site will not see your code.
- **Front-end sources touched** → run the build command.
- **Dependencies** → commit the lock file with the manifest.

Then report: what landed, criteria ticked or explicitly not met, files changed, the quoted test result, anything you noticed and left alone, and the next command — `/dev-review`, or this one again for the next step.

**Never report success when tests fail or a criterion is unmet.**

## Rules

- **Local only.** Never push, never open a pull request. Pushing is a person's decision, after `/dev-review`.
- **The task file is the progress log.** Tick each step as it lands.
- **Data safety** (when `hasDatabase` is true): anything writing in bulk needs dry-run by default, safe re-runs, and bounded scope with an expected row count. Each missing one is a blocker, not a style note.
- **Never `--no-verify`, `--force`, or `--amend`.** A failing hook means fix the code.
- **Never weaken or delete a test to get to green.** If a test now fails and changing it is right, say so and explain why.
- Identifiers and commit messages in English. User-facing strings follow whatever the file already does.

## Edge cases

- **A step turns out wrong** — stop, say why, propose the correction, wait.
- **A step is already done** — tick it, note it, move on.
- **It needs a decision you cannot make** — build everything that does not depend on it, then ask one specific question with the options.
- **Much larger than described** — say so early and propose splitting it, before building half of it.

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Branch and working tree:

!`git status --short --branch 2>/dev/null | head -30`

Task files present:

!`ls -1 .tasks/*.md 2>/dev/null || echo "(no .tasks/ directory)"`
