---
name: dev-review
description: Review your own changes before you push — risk-ranked, one file at a time, with every finding backed by a line quoted from the file and verified against it. Runs the project's linter over what changed. Review only; never edits, commits or pushes.
---

# Review your own work

Review only. Never edit, commit, push, or post a comment. You list; the developer decides.

## How to run this

**First, empty `.devskills/findings.md`** (`: > .devskills/findings.md`). It is appended to
below, so a leftover file from an earlier run would be reported as if it were this one's.

Then work the queue at the bottom **one file per step**. Do not batch, do not skim ahead.

For each file, in queue order:

1. Read the file.
2. Answer the checks below, yes or no, about that file only.
3. For every YES, append one line to `.devskills/findings.md`.
4. Next file.

Read at most the **top 3 files** of the queue in full. Judge the rest from the diff, and name them in the report as judged-from-diff.

## The checks

Answer yes or no. Do not weigh, rank, or reconsider — just answer.

- **C1 SECRET** — does the diff add a password, key, token or credential?
- **C2 SCOPE** — does it write to the database without bounded scope (an explicit id set or range)?
- **C3 DRYRUN** — is it a script that writes in bulk, with no dry-run as the default?
- **C4 RERUN** — would a second run duplicate rows or double-apply the change?
- **C5 CALLER** — does it rename or remove a function, method or class?
- **C6 ESCAPE** — does user input reach SQL, HTML or a spreadsheet cell unescaped?
- **C7 AUTHZ** — does it add, remove or change a permission or capability check?
- **C8 VERSION** — *(moodle-plugin only)* does it touch `classes/`, `db/`, caches or tasks with no `version.php` bump?
- **C9 NULL** — does it use a value that can be null without checking?
- **C10 LOOP** — does it add a loop, cursor or search that may not terminate on empty, duplicate or gapped data?
- **C11 TEST** — does it add logic with no test, or a test whose assertion proves nothing?
- **C12 ERROR** — does it add a throw, guard or error return that nothing tests?

**Severity is decided by which check fired. Do not choose it yourself:**

| Fired | Severity |
|---|---|
| C1–C8 | `BLOCKER` |
| C9–C12 | `WARNING` |

## C5 is grep, not judgement

For every renamed or removed symbol:

```
grep -rn "<oldname>" --exclude-dir=vendor --exclude-dir=node_modules .
```

Any surviving caller is a BLOCKER. Do not reason about whether it is still reachable — grep it and report what grep found.

## The output line

One line per finding in `.devskills/findings.md`, exactly this shape:

```
SEVERITY | path:line | one sentence on what breaks | EVIDENCE: <the exact line from the file>
```

- **EVIDENCE is copied, character for character.** Never paraphrase it.
- **If you cannot copy a line that proves the finding, do not write the finding.**
- One sentence. No diff dumps.

Findings whose evidence is not found in the file are deleted automatically in step 2 below, so an invented one costs you the finding rather than the review.

## Finish

1. Lint: `bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/lint.sh` — a failure is a BLOCKER, quoted verbatim. If it says there is no lint command, report the review as **unlinted**.
2. Verify: `bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/findings-check.sh .devskills/findings.md`
3. **Report only what step 2 printed.** Nothing that it dropped.

Lead with one line — `Ready to push` / `N blockers first` / `Ready, with N warnings` — then the surviving findings, blockers first. Close with the files you judged from the diff alone, and whether lint ran.

Write `REVIEW.md` only when there is a blocker, or when the arguments asked for it.

## Rules

- Absolute paths, so they are clickable.
- Never suggest `--no-verify`, `--force`, or `git push --force`.
- English or Ukrainian, matching the developer. Quote code in its original language.
- If the repository has no tests at all, say it once — never once per file, and never as "tests pass".

---

## This repository

If the two blocks below are empty, you were loaded as a skill rather than run as
`/dev-review`; run those two scripts yourself before continuing.

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Queue — rank 1 is highest risk, read top-down:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/changed.sh`

Diff:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/diff.sh`
