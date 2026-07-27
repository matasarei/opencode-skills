---
name: dev-plan
description: Turn a request or a markdown brief into a grounded plan for /dev-implement — classify what is really being asked, find the code, check the facts against real data, and write ordered steps with acceptance criteria. Plans only; writes no production code.
---

# Work out what to build, before building it

Writes **no production code**. The only files it creates are the plan, and at most one throwaway read-only script used to answer a question about the data.

## Step 0 — Classify, and say which

Ask the developer to pick if it is not obvious from their words. **This one branch drives everything downstream, and guessing it wrong wastes the whole plan** — one question here is cheap:

| Type | Signals | What you owe |
|---|---|---|
| **bug** | "wrong", "broken", "should not", a description of what happened | the **cause**, proven, then the fix |
| **feature** | "add", "support", "we need to be able to" | a **design**: where it hooks in, what it touches, in what order |
| **question** | "how many", "why does", "can we" | the **answer**, with evidence. Often nothing needs to change |
| **data fix** | "these records are wrong", "recalculate", "stuck" | how many rows, why, and a **safe** strategy |

An argument that is a path to an existing file is a brief — read the whole thing, it is the specification. A path that does not exist is an error, not a sentence to plan from.

`--review` in the arguments means the brief already proposes a solution: judge that proposal instead of designing a different one (step 5).

## Step 1 — Find the code

Take two to four distinctive terms from the request and grep for them. Read the entry points, the classes involved, the tests already covering the area.

**Check whether the work is already done.** An existing command or function that solves this is the best possible outcome: point at it and stop.

Read the profile's `standardsDoc` for the conventions the plan must follow.

## Step 2 — Check the facts

A cause you have not verified is a guess. Say which one you are stating.

Where a claim rests on data — how many rows, what states exist, whether this actually happens — check it. Run queries and probe scripts **through `exec.prefix`**, inside the project's container.

- **Local data only.** Never point anything at production. If a question can only be answered there, write the read-only script, leave it untracked, and put the exact command in the plan for a person to run.
- **Anything you generate here reads and never writes.**
- **Tag every fact with its source** — `[local database]`, `[from the code]`, `[needs a production run: <script>]`, `[assumed]`. An untagged number gets treated as true by everyone downstream.

## Step 3 — Pick the approach

**Follow a pattern that already exists in this repository, and cite the file it comes from.** That is the rule here — not "design the best solution". A plan that matches how this codebase already does things is worth more than a better idea that fits nothing around it.

If nothing comparable exists, say so, and give **two** options with one line of trade-off each and a recommendation. Not three, not a table of five. Do not spawn agents to argue about it.

The plan must be concrete: real file paths, real function and class names, an order, and an explicit list of what **not** to touch.

## Step 4 — Write it

Save to `.tasks/<slug>.md`. Create `.tasks/` if needed and add it to `.gitignore` unless the project commits briefs deliberately.

```markdown
# <Short title>

**Type:** bug | feature | question | data fix
**Asked:** <the original request, verbatim>

## Summary
<Three bullets at most: the finding, what to do, the biggest risk.>

## <Cause | Design | Answer | Strategy>
<The actual deliverable, with evidence.>

## Acceptance criteria
- [ ] <checkable and specific — this is what /dev-implement builds against and /dev-verify checks>

## Steps
1. <ordered, file-level, buildable one at a time>

## How to check it
- `<the exact command from this project that proves it works>`

## Do not touch
- <files, tables or behaviour that must stay as they are, and why>

## Evidence
- **Code:** <path — one line on why it matters>
- **Data:** <fact — [source tag]>
- **Open questions:** <numbered, each answerable>
```

For a pure question, omit criteria and steps — the answer is the deliverable.

## Step 5 — Judging a proposal (`--review`)

Do **not** design something different. Judge what is proposed:

- **Check every load-bearing claim.** Does the named class exist and behave as described? Is the table shaped the way the brief assumes? A brief resting on a wrong assumption **is** the finding.
- Does it meet every stated criterion, including the easy-to-skip ones?
- Is a simpler approach available that still meets them?
- Does it fit this codebase's conventions?
- What happens when it fails — partial writes, re-runs, unexpected data?

Verdict: **sound** / **sound with changes** / **needs rework** / **cannot judge — need answers first**, with the reasoning, and for anything below "sound", what to change.

## Step 6 — Hand off

In chat: the absolute path to the plan, the summary verbatim, and the next command:

```
/dev-implement .tasks/<slug>.md
```

## Rules

- **No production code.** Only the plan, and at most one read-only script.
- **Evidence over assertion.** An unverified cause is labelled a hypothesis.
- **Production is read-only, and only by a human.**
- **Data-safety rules apply to any strategy you propose** when `hasDatabase` is true: dry-run by default, safe re-runs, bounded scope with an expected row count. Design it here; write it in `/dev-implement`.
- Absolute paths. English or Ukrainian. No essays — someone reading only the summary should be able to act.

## Edge cases

- **Already solved** — a short plan pointing at the existing thing. Do not rewrite it.
- **Nothing here matches** — say so; it may belong in another repository. Name which, if you can tell.
- **A brief contradicts the code** — the code is what runs. That contradiction is the first open question.
- **It is a one-liner** — say so and skip the ceremony.

---

## This repository

Profile:

!`bash ${DEV_SKILLS_LIB:-$HOME/.config/opencode/dev-lib}/profile.sh`

Repository shape:

!`git ls-files 2>/dev/null | head -60; echo "..."; git ls-files 2>/dev/null | wc -l | tr -d ' ' | sed 's/$/ files tracked/'`
