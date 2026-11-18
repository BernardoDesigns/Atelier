---
description: Close a session. Critic review, assumption check, one-line verdict, learning proposals, then the PR.
---
# /wrap

Close the session in five steps, in order. The review happens here in the session. The PR is the result of the review, never the place for it.

## Opening check

Look for `.atelier/session.json`. If it is absent, nothing was built in this session: skip steps 1 to 3 and go straight to step 4. If it is there, start at step 1.

Steps 1 to 3 never create or push a PR. Step 4 may open one PR in the Atelier repo for learning edits. The PR for the build, in the host repo, is created only in step 5.

## Step 1. Critic

First check for a reusable critique. If `.atelier/critique.md` exists, has a `Verdict:` line, and no commits were made on the branch after it was written, reuse it and do not run the Critic again. To tell: compare the file's modification time with the last commit time (`git log -1 --format=%ct`, against `stat -f %m .atelier/critique.md` on macOS). If you are unsure, ask the user.

Otherwise run the `critic` subagent. Give it the SPEC path from `.atelier/session.json`, the render manifest path, and the branch diff. Save its reply, unchanged, to `.atelier/critique.md`.

Post the ranked findings in the session. Each finding keeps its number, severity, one-line reason and evidence line (`Screenshot:` or `Diff:`). If the reply has no `Verdict:` line, or a finding has no evidence line, send it back to the Critic once.

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

- A finding with no token is not dropped. It gets no fix, and it is listed in the PR description under "Not addressed". An assumption with no token counts as right.
- An unknown id, a repeated id, an unknown word or an empty line is unparseable. Ask once for the line again. Do not guess.

Example: `1 fix, 2 disagree, 3 later, A2 wrong` gives these actions, in this order:

- Finding 1: fix, re-render, re-check
- Finding 2: record the disagreement, drop it
- Finding 3: list as deferred in the PR
- Assumption A2: fix, re-render, re-check

If the critique also had a finding 4, it was not mentioned, so it goes under "Not addressed" in the PR.

## Step 4. Learning proposals

Draw proposals only from the user's verdicts and corrections in this session. Never from your own opinion, and never from the Critic. Each proposal names its target file and quotes the exact line it would add:

- `~/.claude/atelier/failures.md`: a trap that bit this build. Low bar.
- `~/.claude/atelier/conventions.md`: the user set an exact, yes-or-no standard. Medium bar.
- `~/.claude/atelier/taste.md`: a judgment that generalizes, or the user says it should be kept. High bar.

List them numbered. The user picks which to keep. If none are accepted, do nothing.

Never write accepted lines into the working tree of `~/.claude/atelier`. That checkout is live config and its `main` branch changes only through pull requests. Instead:

1. In `~/.claude/atelier`, create a branch `learn/<yyyy-mm-dd>-<short-slug>` in a new git worktree (`git worktree add`).
2. Apply the accepted lines in that worktree.
3. Commit by file name, push the branch, and open a PR in the Atelier repo:

```
gh pr create --title "<title>" --body "<accepted lines and why>"
```

4. Report the PR URL. The build's own PR in step 5 links to it.

This is the only way those four files change.

## Step 5. Pull request

If this session had no build, there is no host PR: stop here.

Only now create the PR for the build, in the host repo. Check the branch is not `main` first. The description holds the critique summary, the user's verdicts (findings and assumptions), the deferred findings under "Deferred", any findings with no token under "Not addressed", and a link to the learning PR from step 4 if there is one.

```
gh pr create --title "<title>" --body "<description>"
```

Last act of step 5, once the PR exists: close the session by renaming the marker. Use `mv`, never `rm`.

```
mv .atelier/session.json .atelier/session.closed.json
```

The marker means a build session is open, and the guardrail hooks key off it. A marker left behind would trap later, unrelated sessions in this repo. In diverge mode there is no marker in the main checkout; rename the one in each option worktree you wrapped.
