---
name: dev-pr-comment
description: Address ONE review comment on your own pull request per run — restate the claim, check it against the code, give a verdict (agree, disagree with evidence, or ask), and apply at most the smallest fix as a local commit. Never pushes, never posts. Run it again for the next comment.
---

# Address one review comment

One comment per run. Not a batch.

This is deliberate, and it is the whole difference from a skill that works through every comment
in one go:

- **A batch drifts.** By the eighth comment the verdicts stop being grounded in the code and
  start being grounded in the previous seven verdicts.
- **A batch hides its mistakes.** One bad fix in a run of twelve is invisible until later.
- **Reviewers are often wrong.** An automated reviewer is tuned to sound confident and is
  regularly wrong about whether something is a problem *in this codebase*. Fixing a
  confidently-worded false positive is how you introduce a real bug — and that judgement
  deserves a whole context, not a twelfth of one.

**This skill never pushes and never posts a comment.** It commits locally and hands you the
exact commands. Those are decisions a person makes.

## Arguments

- `<pr-url>` — works from any directory.
- `<pr-number>` — only inside a clone of the repository that owns it.
- `--repo owner/name` — pair with a bare number.
- `--id <comment_id>` — address that specific comment instead of the next pending one.
- `--list` — print the ledger and stop. Changes nothing.

## Step 1 — Refuse early if it is not yours

The ledger below carries the author and state. **Stop** if the pull request is not open. **Stop**
if the author is not you — for someone else's, use `/dev-pr-review` and hand them the findings.

## Step 2 — The ledger

`.devskills/pr-<n>.md` is the state for this pull request. If it does not exist, create it from
the comment list at the bottom of this message, one row per comment:

```markdown
| id | author | location | status | verdict |
|---|---|---|---|---|
| 102 | alice | src/Loop.php:7 | pending | |
```

If it already exists, **read it and keep it** — rows marked anything other than `pending` are
finished, and re-litigating them is exactly the waste this skill exists to avoid. Add any rows
the ledger does not have yet.

With `--list`, print it and stop.

## Step 3 — Pick exactly one

The comment named by `--id`, otherwise the **first `pending` row**. Say which one you picked and
how many remain.

If nothing is pending: say so, and stop. That is the finished state.

## Step 4 — Verdict, before touching anything

1. **Restate the claim in one sentence.** What is said to be wrong, and what would happen if it
   were true?
2. **Read the cited location and enough around it to judge** — the callers, the guard the
   reviewer may not have noticed, the test that already covers it.
3. **Decide exactly one:**

| Verdict | Means | What happens |
|---|---|---|
| `agree` | It holds | The smallest fix that resolves it, one commit |
| `disagree` | It does not hold here | **No code change.** Draft a reply citing the file and line that answers it |
| `unclear` | Ambiguous, or a trade-off that is not yours alone | Ask the developer, offer: fix as suggested / push back / leave it |

**Print the verdict and the reasoning before making any edit.** If the verdict is `disagree` or
`unclear`, there is no edit at all.

Being confident is not the same as being right. If your evidence is thin, the verdict is
`unclear`, not `disagree`.

## Step 5 — Fix, if and only if you agreed

You must be on the pull request's head branch. If you are not, **stop and say so** — do not
check anything out, and do not guess which checkout is the right one:

```bash
git fetch origin <headRefName> && git switch <headRefName>
```

Then:

1. Apply **the smallest change that resolves the finding.** Do not refactor nearby code. Do not
   fix anything the comment did not raise.
2. Lint or run the scoped test **through the profile's `exec.prefix`** — the project's container,
   so the check uses the version the project targets. A failure means the fix is wrong; fix the
   fix before committing.
3. Commit: `Fix: <one-line description of the finding>`

**If a commit hook fails, stop.** Record the row as `skipped` with the reason. Never
`--no-verify`. Never `--force`. Never `--amend`.

## Step 6 — Update the ledger and report

Set the row's status to `fixed` (with the sha), `disagreed`, `unclear` or `skipped`, and write
the one-line reason into the verdict column.

Then report, short:

- the comment, the verdict, and the reasoning;
- what changed, if anything, with `path:line`;
- **the exact commands for the developer** — never run these yourself:

  ```bash
  git push origin <headRefName>
  gh api -X POST /repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies -f body='Fixed in <sha>: <what changed>.'
  ```

- how many rows are still `pending`, and the command for the next one.

For a `disagree`, give the drafted reply text in full so it can be pasted. **Do not resolve a
thread you pushed back on** — the reviewer decides whether they accept it.

## Rules

- **One comment per run.**
- **Verdict before edit, always.**
- **Never push, never post, never resolve a thread.** You prepare; the developer sends.
- **Only your own pull requests.**
- **The URL wins over the current directory.** Never resolve a URL against `origin` in whatever
  directory you happen to be standing in.
- A row that is not `pending` is finished. Do not reopen it.

## Edge cases

- **The comment points at code this pull request did not change** — out of scope. Verdict
  `disagree`, and the drafted reply suggests a separate change.
- **A `REVIEW-` row** is a review summary with no repliable id. Give it a verdict for the record;
  there is no thread to answer.
- **The fix needs a schema change or a version bump** — do it, and say so prominently. For a
  Moodle plugin, a `classes/` or `db/` change without a `version.php` bump will not take effect.
- **The pull request comes from a fork** — its head branch is not on your origin, so the push
  command you print must target their remote. Say that rather than printing one that will fail.
- **Two comments contradict each other** — both are `unclear`. Ask once, with both quoted.

---

## This pull request

If the block below is empty, you were loaded as a skill rather than run as `/dev-pr-comment`;
run the script yourself with the argument the developer gave.

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/pr-comments.sh $ARGUMENTS 2>&1`

Repository profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh 2>/dev/null || echo "(not in a git repository — that is fine for --list)"`

Current branch:

!`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(not in a git repository)"`
