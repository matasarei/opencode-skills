---
name: dev-verify
description: Prove a change actually works — run the project's test suite, quote the runner's real result line, then drive the actual command, page or function and check the effect. Reports a verdict and says honestly what could not be checked and why. Local only; never touches a live system.
---

# Prove it works

"The tests pass" and "the feature works" are different claims. Make both, separately, and say which one you can actually support.

## Step 1 — Preflight

Report all of these together, in one block, before running anything:

- Is there a test command? (`test` in the profile — `null` means the project has none)
- Is the execution environment up? (`exec.note` in the profile says if it is not)
- Is `timeoutTool` null? If so, a hang cannot be bounded — say so rather than dropping the timeout quietly.
- Does the runtime need something you do not have — a host application, a credential, an external service?

Every blocker gets one of these categories and one line on how to clear it:

| Category | Means |
|---|---|
| `SETUP` | environment not ready — container down, dependencies missing |
| `MISSING` | the project has no such thing — no tests at all |
| `HOSTED` | needs a host application — a Moodle plugin cannot run standalone |
| `EXTERNAL` | needs something off this machine |
| `DATA` | no suitable local data, and none can be safely invented |
| `PRE-EXISTING` | already broken before this change — prove it on the base branch |

A `SETUP` blocker you can clear in under a minute: clear it and say you did. Anything else: record it, skip that check, **carry on with the rest**. Only abandon the run if the code cannot be obtained.

## Step 2 — Build the check list

One row per acceptance criterion, per command or page the change touches, and per schema change. Each row ends `passed`, `failed`, or `skipped:<CATEGORY>`.

**A criterion with no row is a gap, and the report must say so.** Silence is not coverage.

## Step 3 — Run the tests

Run the profile's `test`, wrapped in `timeoutTool` if there is one. Prefer `testScoped` first, then widen.

- **Quote the runner's actual output line.** `OK (43 tests, 118 assertions)` is evidence. "Tests pass" is not.
- A timeout is a **failure**. Say what it was doing when it hung.
- Something failing that also fails on the base branch is `PRE-EXISTING` — run the same command there before blaming this change.
- No tests → `MISSING`. Never report an absence of tests as tests passing.

## Step 4 — Drive the real thing

Use `runtime.kind` from the profile:

- **`cli`** — run it twice. Once with bad input: expect a clear error **and** a non-zero exit code, checked directly (a pipe hides it). Once for real, then check the effect — the row written, the file produced.
- **`http`** — request the route from the **host** at the published port, not through `exec`. Check the status, then the effect. Say in the report that the check was request-level, not user-level.
- **`library`** — call the public API with ordinary and edge inputs.
- **`hosted`** — record `HOSTED`. Do what can be done: lint every changed file, confirm `version.php` was bumped if `classes/` or `db/` changed, confirm new classes sit where their namespace says. **State clearly that behaviour was not verified.**

Then the adversarial pass the change makes relevant: run it twice, on an empty result, on an already-processed record, on nulls. Anything writing in bulk: run it in dry-run and confirm nothing changed, then twice and confirm the second run is a no-op.

## Step 5 — Restore

**Do this even if the run failed halfway.** A half-restored environment is the worst outcome.

Undo data changes in reverse order. Return the checkout to its original branch. Clear caches you invalidated. **Ask before removing a worktree.**

## Step 6 — Verdict

Lead with exactly one:

- **Works** — the checks that matter passed, and the change was actually exercised.
- **Works, with notes**
- **Does not work** — a specific, reproducible failure.
- **Cannot tell** — too much was blocked to claim anything.

Then the check list with evidence per row, the failures with how to reproduce, the skipped rows with categories, and anything you changed and restored.

**"Cannot tell" is a real verdict.** A confident "works" resting on three skipped checks is worse than no answer.

## Rules

- Local only. Never a live system, never production data, never a write to a pull request.
- Evidence or it did not happen — every passed row quotes something real.
- One failure never cancels the rest of the list.

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Changed, by risk:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/changed.sh`
