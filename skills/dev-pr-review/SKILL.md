---
name: dev-pr-review
description: Review someone else's pull request in an isolated worktree against a fixed checklist — blast radius, data safety, error paths, dishonest tests, claim-versus-code. Deduplicates against the bot's comments. Read-only; never edits, pushes or posts.
---

# Review someone else's pull request

Read-only. Never edit, commit, push, or post a comment. You paste what you want to say yourself.

For your *own* changes before pushing, use `/dev-review`.

## What this is, honestly

This is a **checklist**, not the kind of open-ended hunt a frontier model does. It covers the failure classes that can be checked mechanically or by reading one thing at a time. It will miss subtle design problems. Say so in the verdict rather than implying the PR was fully examined.

**Skip** what the automated reviewer already covered — formatting, import order, naming, docblocks. Mention a basic only when it is the visible tip of a real defect: report the wrong value produced, not the style rule broken.

## Step 1 — Fetch

Repository from `--repo` in the arguments, else from `git remote get-url origin`.

```bash
gh pr view <n> --repo <owner/name> --json number,title,state,author,headRefName,baseRefName,headRefOid,isCrossRepository,url,body,additions,deletions,changedFiles
```

Note the state. A merged or closed PR is still worth reading — frame it as after-the-fact. Stop with one line if it changes no files.

## Step 2 — Isolate

```bash
git fetch origin pull/<n>/head          # works for forks too
git worktree add ../<repo>-pr-<n> <headRefOid>   # detached; never a local branch
```

If the path exists, **ask before reusing it.** Never overwrite silently.

Work inside the worktree. Capture the primary repository path first (`git rev-parse --show-toplevel`) — any report goes there, not into the worktree.

**If `exec.kind` is `compose`, it mounts the primary checkout, not this worktree.** Anything run through it exercises the wrong code. Fine for a static read; if verifying a finding needs code to run, either mount the worktree in a one-off container or mark the finding `[unverified]`. Do not run a check against the wrong tree and report the result.

## Step 3 — Read, in order

Run `changed.sh` inside the worktree for the risk-ranked queue. **Read the top 3 in full**, plus the unchanged code immediately around them. Everything else is judged from the diff, and the review says so.

## Step 4 — The checklist

One file at a time. Answer yes or no.

- **P1 CALLERS** — does the diff rename, move or remove a symbol? `grep -rn "<oldname>"` the worktree. Every surviving caller is a BLOCKER.
- **P2 SCHEMA** — does it drop a column or table, add a `NOT NULL` with no backfill, or remove an index with no replacement?
- **P3 VERSION** — *(moodle-plugin)* `classes/`, `db/`, caches or tasks changed with no `version.php` bump?
- **P4 BULK** — a mass update with no bounded scope, a batch script with no dry-run default, or a fix script that duplicates on a second run?
- **P5 HALFWAY** — can it fail between two writes and leave a half-updated record, an open transaction, or a retry that duplicates work?
- **P6 LOOP** — does a new loop, cursor or search terminate on gapped ids, empty sets, duplicates and nulls? Walk it; mocked tests prove nothing here.
- **P7 DOUBLE** — check-then-act, a form submitted twice, a scheduled task overlapping its previous run, a unique constraint that deduplicates the row but not the action?
- **P8 TESTS** — tests deleted, skipped, weakened, or mocking away exactly what changed?
- **P9 CLAIM** — does the diff do what the description promises? Look for quietly dropped requirements and behaviour changes hidden inside a "refactor".

## Step 5 — Two severities

- **BLOCKER** — every one carries a **concrete failure scenario**: the inputs or state that trigger it, and what goes wrong. **No scenario, no blocker** — it becomes a smell.
- **SMELL** — will not break tomorrow but will hurt.

There is no NIT here. Nits are the bot's job.

Empty `.devskills/findings.md` first (`: > .devskills/findings.md`) — it is appended to, and a
leftover file from an earlier run would be reported as belonging to this pull request.

Write findings to `.devskills/findings.md` in the shared line format, then run
`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/findings-check.sh .devskills/findings.md` and report only what survives.

## Step 6 — Deduplicate

```bash
gh api /repos/<owner>/<repo>/pulls/<n>/reviews
gh api /repos/<owner>/<repo>/pulls/<n>/comments
```

- **Drop any finding the bot already made** — the author has been told.
- A human raised the same thing → add *(also raised by @name)*.
- A human caught something you missed → say so and credit them.
- **A bot's approval is not evidence of anything.** It is tuned for precision on style and approves changes containing infinite loops and broken permissions. Never let it soften your verdict.

## Step 7 — Say it

> **Approve** — or — **Approve with notes** — or — **Request changes — 2 blockers**

Each blocker in two or three sentences: what breaks, when, the direction of the fix, an absolute `path:line`. Smells get one line. Add a short note on what is done well. Close with which checklist items you ran, and state that this was a checklist review.

Write `PR_REVIEW_<n>.md` in the **primary** repository only when there is a blocker, four or more findings, or the arguments asked for it.

## Step 8 — Clean up

Ask once, with the absolute path:

> Worktree left at `<path>`. Remove it? (`git worktree remove <path>`)

**Never remove it without asking.**

## Edge cases

- **Fork PR** — `git fetch origin pull/<n>/head` handles it; `origin/<branch>` will not exist.
- **Stacked PR** — review works, but say in the header it is only meaningful once the parent lands.
- **Conflicts with base** — review anyway, and lead with the fact that it cannot merge as-is.
- **No tests in the repository at all** — mention it once as context, not as a finding on this PR.

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Origin and gh auth:

!`git remote get-url origin 2>/dev/null; gh auth status 2>&1 | head -3`
