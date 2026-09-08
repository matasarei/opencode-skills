---
name: dev-review
description: Review your own changes before /dev-pr — twelve yes/no checks per file, worst-risk first, every finding a quoted line verified by a script. Review only; never edits, commits or pushes.
---

# Review your own work

Review only. Never edit, commit, push, or post. You list; `/dev-fix` applies.

## How to run this

**First, empty `.devskills/findings.md`** (`: > .devskills/findings.md`) — it is appended to, and a leftover file would be reported as this run's.

Then work the queue at the bottom **one file per step**. Do not batch, do not skim ahead. For each file, in queue order: read it; answer the checks below, yes or no, about that file only; for every YES append one line to `.devskills/findings.md`; next file.

Read at most the **top 3 files** in full. Judge the rest from the diff, and name them in the report as judged-from-diff.

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

For every renamed or removed symbol, grep the files the current step names first — `bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/task-step.sh <task-file> --paths <n>` lists them — then the tree:

```
grep -rn "<oldname>" --exclude-dir=vendor --exclude-dir=node_modules .
```

Any surviving caller in code, tests/ or views/ is a BLOCKER. Do not reason about whether it is reachable — report what grep found.

## The output line

One line per finding in `.devskills/findings.md`, exactly this shape:

```
SEVERITY | path:line | one sentence on what breaks | EVIDENCE: <the exact line from the file>
```

**EVIDENCE is copied, character for character.** If you cannot copy a line that proves the finding, do not write the finding — an unverifiable one is deleted below. One sentence; no diff dumps.

## Finish

1. Lint: `bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/lint.sh` — a failure is a BLOCKER, quoted verbatim. `NO LINT COMMAND` → report the review as **unlinted**.
2. Verify: `bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/findings-check.sh .devskills/findings.md`
3. **Report only what step 2 printed.**

Lead with one line — `Ready to push` / `N blockers first` / `Ready, with N warnings` — then the surviving findings, blockers first, the files judged from the diff alone, and whether lint ran. A report file only on a blocker, or when asked: `.devskills/reports/review-<branch-slug>-<UTC timestamp>.md`, path printed. Then: `Next: /dev-fix` when anything survived; `Next: /dev-pr` when nothing did.

## Rules

- Absolute paths. English or Ukrainian; quote code in its original language.
- No tests in the repository at all → say it once, never per file, never as "tests pass".

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Queue — rank 1 is highest risk, read top-down:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/changed.sh`

Diff:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/diff.sh`
