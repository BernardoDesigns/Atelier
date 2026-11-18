---
description: Close a session. Critic review, assumption check, one-line verdict, learning proposals, then the PR.
---
# /wrap

Close the session in five steps, in order. The review happens here in the session. The PR is the result of the review, never the place for it.

## Opening check

Look for `.atelier/session.json`. If it is absent, nothing was built in this session: skip steps 1 to 3 and go straight to step 4. If it is there, start at step 1.

Steps 1 to 4 never create or push a PR.

## Step 1. Critic

Run the `critic` subagent. Give it the SPEC path from `.atelier/session.json`, the render manifest path, and the branch diff. Save its reply, unchanged, to `.atelier/critique.md`.

Post the ranked findings in the session. Each finding keeps its number, severity, one-line reason and screenshot path. If the reply has no `Verdict:` line, or a finding has no screenshot path, send it back to the Critic once.

## Step 2. Assumptions

Read `.atelier/assumptions.md`. List every entry with its id (`A1`, `A2`, ...), its choice, and its kind. The user marks each one right or wrong in step 3. Entries not mentioned count as right.

## Step 3. Verdict line

Ask for the verdict in one line. Parse it with the grammar below, apply the actions, re-render, and have the Critic re-check only the items that were fixed. Append the final verdicts to `.atelier/assumptions.md` (the `Verdict:` line of each entry).

### Verdict grammar

Tokens are separated by commas. Whitespace around a token is ignored. Words are lowercase.

| Token | Meaning | Action |
|---|---|---|
| `<n> fix` | Finding `<n>` is right | Fix it, re-render, Critic re-checks it |
| `<n> disagree` | Finding `<n>` is wrong | Record the disagreement, drop the finding |
| `<n> later` | Finding `<n>` is real but not now | List it in the PR as deferred |
| `A<n> right` | Assumption `A<n>` is fine | Keep it |
| `A<n> wrong` | Assumption `A<n>` is wrong | Fix it, re-render, Critic re-checks it |

Rules:

- A finding with no token gets no action. An assumption with no token counts as right.
- An unknown id, a repeated id, an unknown word or an empty line is unparseable. Ask once for the line again. Do not guess.

Example: `1 fix, 2 disagree, 3 later, A2 wrong` gives these actions, in this order:

- Finding 1: fix, re-render, re-check
- Finding 2: record the disagreement, drop it
- Finding 3: list as deferred in the PR
- Assumption A2: fix, re-render, re-check

## Step 4. Learning proposals

Draw proposals only from the user's verdicts and corrections in this session. Never from your own opinion, and never from the Critic. Each proposal names its target file and quotes the exact line it would add:

- `failures.md`: a trap that bit this build. Low bar.
- `conventions.md`: the user set an exact, yes-or-no standard. Medium bar.
- `taste.md`: a judgment that generalizes, or the user says it should be kept. High bar.

List them numbered. The user picks which to keep. Write only the accepted ones, to the named file. If none are accepted, write nothing. This is the only way those four files change.

## Step 5. Pull request

Only now create the PR. Check the branch is not `main` first. The description holds the critique summary, the user's verdicts (findings and assumptions), the deferred findings, and the accepted learning edits.

```
gh pr create --title "<title>" --body "<description>"
```

If this session had no build, there is no critique to summarize: describe the accepted learning edits only, or skip the PR if there are none.
