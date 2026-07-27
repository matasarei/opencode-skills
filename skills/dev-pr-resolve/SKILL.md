---
name: dev-pr-resolve
description: Work through the review comments on your own pull request from any directory — one comment at a time, each gets a verdict (agree, disagree with evidence, or ask) before any code is touched, then fixes land one commit per finding, get pushed, and each thread gets a reply. Never fixes blindly.
---

# Act on the comments on your pull request

The one skill here that **writes code and pushes**, and only ever on **your own** pull request.

**The rule that matters: never fix blindly.** An automated reviewer is tuned to sound confident and is regularly wrong about whether something is a problem *in this codebase*. Fixing a confidently-worded false positive is how you introduce a real bug.

## Step 1 — Resolve the target first

Before assuming anything about the current directory:

- **A URL** (`https://github.com/owner/repo/pull/42`) gives you owner, repo and number. **Parse it and ignore `origin` entirely** — the URL is authoritative, and you may be standing in an unrelated project. This form works from anywhere.
- **A bare number** is only meaningful relative to a repository. Take `owner/repo` from `--repo`, or from `git remote get-url origin`. Not in a git repository and no `--repo` → **stop and ask for a URL.**

```bash
gh pr view <n> --repo <owner>/<repo> --json number,state,headRefName,baseRefName,author,url,headRefOid,isCrossRepository
```

**Refuse** if it is not open. **Refuse** if the author is not you — for someone else's PR use `/dev-pr-review`.

## Step 2 — Collect every finding

```bash
gh api /repos/<owner>/<repo>/pulls/<n>/comments   # inline, with ids
gh api /repos/<owner>/<repo>/pulls/<n>/reviews    # review bodies, including bot summaries
gh api /repos/<owner>/<repo>/issues/<n>/comments  # general discussion
```

Sort each into one bucket:

- **actionable** — names a file or proposes a concrete change, not yet resolved
- **question** — asks something without proposing a change. Gets a reply, not a commit
- **nit** — marked optional or non-blocking. Fix only if it is one line
- **skip** — emoji, "looks good", bot summaries with no specific finding, anything already replied to

Bot summaries **cannot** be replied to; only inline comments carry ids. Record verdicts on summaries in the final report instead.

Write the list to `.devskills/pr-<n>-findings.md`, one per line, with its id and bucket. **This file is the state** — work from it, tick it as you go, so an interrupted run resumes.

## Step 3 — One verdict per comment, before any edit

Work the list **one comment at a time.** Do not read them all and decide in a batch.

For each actionable and nit:

1. **Restate the claim** in one sentence — what is said to be wrong, and what would happen if that were true?
2. **Check it against the code.** Read the cited location and enough context to judge: the callers, the guard the reviewer may not have noticed, the test that already covers it.
3. **Decide exactly one of:**
   - **agree** — it holds. Note the smallest fix.
   - **disagree** — it does not hold here. False positive, already handled elsewhere, or the suggestion makes things worse. **No code change.** Draft a short respectful reply with the file and line that answers it.
   - **unclear** — genuinely ambiguous, or a trade-off that is not yours alone to make. Do not guess in either direction.
4. Write the verdict and a one-line reason into the findings file, then move to the next.

**Ask about all the unclear ones at once**, after everything is analysed — one batched question, not an interruption per comment. Offer: fix as suggested / push back / leave it.

With `--dry-run` in the arguments, stop here and report.

## Step 4 — Get a working copy

Not whatever you currently have open.

- **A. Current directory is a clone of the target** — the common case:
  ```bash
  git fetch origin <headRefName>
  git worktree add ../<repo>-pr-<n> <headRefName>
  ```
- **B. A clone exists elsewhere** — check the obvious neighbours before cloning again. Confirm by its `origin` remote, not its directory name, then worktree from it as in A.
- **C. No clone anywhere** — `gh repo clone <owner>/<repo> <path> -- --branch <headRefName>`. `gh` supplies credentials, so private repositories work. No worktree needed.

Where it goes: `--in <path>` if given; else a sibling of the current repository root; else `<repo>-pr-<n>` here. **Say the absolute path before creating it** — a new checkout appearing outside the project you are standing in should never be a surprise.

If the target path exists: right repository on the right branch → offer to reuse after fetching. Anything else → stop and ask.

**Record which case applied.** Cleanup differs: a worktree you added and a clone you created are offered for removal; a pre-existing clone from case B is never touched.

## Step 5 — Fix, one finding per commit

Everything from here runs in the working copy. **Read the target repository's profile** — if the PR belongs to a different project than the one you started in, the profile you already have is the wrong one.

For each **agree**, in order:

1. Read the cited file and its surroundings.
2. Apply **the smallest change that resolves it.** Do not refactor nearby code. Do not bundle two findings into one commit even in the same file — one commit per finding is what makes any of it revertible.
3. Commit: `Fix: <one-line description of the finding>`
4. Run the scoped test or lint **through `exec.prefix`**. A failure means the fix is wrong; fix the fix before continuing.

A compose service mounts the *primary* checkout, not this worktree — either mount the worktree in a one-off container, or record the fix as unverified. Do not run the check against the wrong tree and call it passed.

**If a commit hook fails, that finding is skipped and reported as skipped.** Never `--no-verify`.

## Step 6 — Push

```bash
git -C <working-copy> push origin <headRefName>
```

**Never `--force`, `--force-with-lease`, or `--amend`.** If the remote branch moved because someone else pushed, rebase **only your own new commits** onto it and re-verify any fix that overlapped theirs. A conflict there needs a human — stop and hand it back.

If the *base* moved and the PR now needs a rebase, leave it. That is a human decision.

## Step 7 — Reply to each thread

```bash
gh api -X POST /repos/<owner>/<repo>/pulls/<n>/comments/<comment_id>/replies -f body='...'
```

- **agree, fixed** — `Fixed in <sha>: <one sentence on what changed>.`
- **disagree** — the evidence-backed reply from step 3. **Do not resolve the thread**; the reviewer decides whether they accept it.
- **question** — answer it, or say what you need in order to answer.
- **skipped, hook failed** — say that, and say what failed.

**Resolve only threads you actually fixed.**

## Step 8 — Report

A short table: every finding, its verdict, and what happened — fixed with a sha, pushed back with the reason, skipped with the cause, or awaiting your decision. Then the push result and the PR link.

Offer to clean up what **this run** created, by absolute path. A clone that already existed is left alone. **Never remove anything without asking.**

## Rules

- **Verdict before edit, always.**
- **One finding, one commit.**
- **Only your own pull requests.**
- **The URL wins over the current directory.**
- **Push back politely and with evidence.** Being confident is not the same as being right — if the evidence is thin, treat it as unclear and ask.

## Edge cases

- **Every finding is a false positive** — a legitimate outcome. Push back on all, push nothing, say so.
- **A finding points at code the PR did not change** — out of scope. Reply saying so, suggest a separate change.
- **Two findings contradict each other** — unclear, ask.
- **A fix needs a schema change or version bump** — do it, and say so prominently.
- **The PR has no comments yet** — say so and stop.
- **From a fork** (`isCrossRepository`) — the head branch is not on the target's origin, so pushing fails. Say so and stop.

---

## This repository

!`git remote get-url origin 2>/dev/null || echo "(not in a git repository — a URL argument is required)"`

!`gh auth status 2>&1 | head -3`
