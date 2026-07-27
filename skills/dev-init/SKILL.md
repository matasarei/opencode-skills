---
name: dev-init
description: Write this repository's AGENTS.md — the detected build, test and run commands plus the conventions and security rules for its family (Moodle plugin, PHP app, CMS, Python). Leaves CLAUDE.md as an import stub so Claude Code reads the same file. Writes those two files and nothing else.
---

# Give this repository an AGENTS.md

`AGENTS.md` is loaded at the start of every session. It is where the build and test commands and the handful of rules that actually get broken here belong.

## AGENTS.md is the real file. CLAUDE.md is a stub.

This direction is not a preference — it is required:

- OpenCode reads `AGENTS.md`, and falls back to `CLAUDE.md` **only when `AGENTS.md` is absent**. First match wins. A stub `AGENTS.md` pointing at a real `CLAUDE.md` means OpenCode reads the stub and **stops** — every rule silently invisible, with no error.
- OpenCode does not resolve file references inside `AGENTS.md`. A markdown link is not followed.

So: content in `AGENTS.md`, and `CLAUDE.md` containing exactly this, which Claude Code *does* resolve as an import:

```markdown
@AGENTS.md
```

One copy, both tools, no drift. If the repository already has content in `CLAUDE.md` and none in `AGENTS.md`, **move** it rather than duplicating.

## Step 1 — Map the family to a template

Take `family` from the profile below:

| Profile family | Template | Note |
|---|---|---|
| `moodle-plugin` | `moodle-plugin` | |
| `cms` | `cms` | |
| `php-app` | `php-app` | |
| `php-library` | `php-app` | Skip its request-handling sections; style and bulk-write rules still apply |
| `python-app` | `python-app` | |
| `node`, `other` | — | No template. Write the commands section, skip the family block, and say so |

`--family <name>` in the arguments overrides this and takes a **template** name.

Templates live in `templates/` beside this file.

## Step 2 — Read what is there first

**No `AGENTS.md` → go to step 3.** Otherwise read it and judge it. Someone wrote it, and it may already be right.

- **Are the commands still true?** Compare each against the profile. A command that no longer exists is the most damaging kind of staleness, because it will be tried.
- **Is anything contradicted by the code?** A rule saying output is escaped automatically, in a project whose templates do not escape, is worse than no file at all.
- **Is the family block present and current?**

Report one of three outcomes, and **do not write without saying which**:

- **Already fine** — one line, nothing written. This is a real and common result.
- **Needs a refresh** — show what would change, and ask. `--refresh` means the answer is already yes.
- **Needs attention you should not apply yourself** — a stale command, or a claim the code contradicts. List these for the developer. Correcting a factual claim about the project is not a mechanical edit.

**A hand-written `AGENTS.md` is never overwritten.** Show the family block and ask whether to insert it, and where.

## Step 3 — Write it

```markdown
# <Repository name>

<One or two sentences: what this project is, and anything structural a newcomer would get
wrong. For a Moodle plugin, that the repo root is the plugin root and it cannot run standalone.>

## Commands

| What | Command |
|---|---|
| Install | `<profile.install>` |
| Test | `<profile.test>` |
| Lint | `<profile.lint>` |
| Build | `<profile.build>` |
| Run | `<profile.runtime.how>` |

<If exec.kind is compose or image: say these run inside the container, and why — the project
targets a specific version and the host's may differ. If it fell back to host, say that, and
name the version mismatch if there is one.>

<the family template, verbatim>

## This project specifically

<Anything true here and nowhere else — see step 4.>
```

**A `null` command is written as "none" with a word of why** — "no test command: this repository has no test suite". Never invented. A made-up command is worse than an absent one, because the next reader will try it.

**Do not pad.** This file is loaded into every session; length is a running cost. If a rule is generic enough that any competent developer already follows it, leave it out.

## Step 4 — Fill in what only this repository knows

The template cannot know these, and they are the highest-value lines in the file. **Look, then write what you find** — do not assume:

- **Does the template layer escape automatically?** Read a view and the render path before writing the rule. Stating it backwards is worse than omitting it, because a reviewer will trust it. Cannot tell → say so in the file and mark it to be confirmed.
- **Is there a CSRF helper?** Name it, or record that there is none.
- **How is authorisation actually checked** — middleware, base controller, per-action call?
- **Which files hold credentials**, and are they git-ignored? Say where they live; **never quote their contents.**
- **What is generated** and must not be hand-edited.
- **What breaks only in production** — a cache to clear, a version to bump, a migration to run.

## Step 5 — The CLAUDE.md stub

Write `CLAUDE.md` containing only `@AGENTS.md`, unless it already holds real content — in which case that is the step 2 conflict and needs the developer's decision first. An existing stub is left alone.

## Step 6 — Report

Which family was detected and why, the absolute paths written, whether `CLAUDE.md` was created or left alone, and which commands came out `null`. Anything step 4 left unresolved is listed as a question, not a guess.

`--dry-run` prints the file and writes nothing.

## Rules

- **Only ever write `AGENTS.md` and a stub `CLAUDE.md`.** No source files, no config, no commits.
- **Never invent a command.** Detected, or "none" with the reason.
- **Never copy secrets into the file** — describe where configuration lives, never what is in it.
- **Under ~120 lines** including the family block. Past that, the surplus belongs in the repository's own documentation, read on demand rather than every session.
- English or Ukrainian, matching the repository's existing documentation.

## Edge cases

- **Monorepo** — write for the root, and note which sub-directory each command applies to. Not one file per package.
- **A good `CONTRIBUTING.md` exists** — do not restate it. Link it.
- **Family detected but the template does not fit** — write the commands, include the block, and flag the mismatch rather than silently trimming rules.
- **Already correct** — say so and stop. Do not reformat, reorder, or rewrite prose to match the template's phrasing; none of that is an improvement and all of it produces a diff someone has to read.

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Existing instruction files:

!`for f in AGENTS.md CLAUDE.md CONTRIBUTING.md; do [ -f "$f" ] && echo "== $f ($(wc -l < "$f" | tr -d ' ') lines)" && head -15 "$f"; done; echo "(end)"`
