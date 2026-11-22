---
description: Close a session. Critic review, assumption check, one-line verdict, learning proposals, then the PR.
---
# /wrap

Close the session in five steps, in order. The review happens here in the session. The PR is the result of the review, never the place for it.

## Opening check

Run exactly this, as the only command on the line:

```
~/.claude/atelier/guardrails/session-close.sh --check
```

It prints one word. `none`: there is no `.atelier/session.json`, so nothing was built in this session: skip steps 1 to 3 and go straight to step 4. `mine` or `unowned`: this session's build (or an old marker with no `sessionId`): start at step 1. `other`: the open build belongs to a different session. Say so plainly ("the build open here belongs to another session; run /wrap there, I haven't closed it"), skip steps 1 to 3 and step 5's close, and do only step 4. Never close or edit another session's marker. `unknown`: tell the user the guardrail hook that identifies this session isn't running (`guardrails/install.sh --enforce`) and stop.

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

List them numbered, then ask the user to pick. Parse the reply with the grammar below. A reply that is not a pick is never read as "none".

Before you ask, write the numbered proposals to `.atelier/learning-proposals.md`, each with its target file and the exact quoted line, so they outlive the session. This file is scratch, like `critique.md`: never stage or commit it. If there is no `.atelier/` folder (the opening check said `none`), or the build belongs to another session (`other`), skip the file and say so. Do not write into another session's folder.

### Pick grammar

Tokens are separated by commas. Whitespace around a token is ignored. Words are lowercase.

| Reply | Meaning | Action |
|---|---|---|
| `keep <n>, <n>, ...` or bare numbers (`1, 3`) | Keep those proposals | Apply them below. Proposals not listed are dropped. |
| the same, with new wording for a proposal (`keep 1, 3, 3 becomes "<line>"`) | Keep those, with the edit | Apply them with the edited line. |
| `none` | Keep nothing | Do nothing below. |

Rules:

- Anything else is not an answer. That means silence on the question, a reply about something else, "continue", "ok", "ship it", or a number that is not on the list. Ask once more, and say plainly that nothing has been kept or dropped yet.
- If the second reply is still not an answer, do not ask a third time and do not treat it as `none`. Mark the proposals undecided. Put them verbatim in the build PR description under the heading "Learning proposals, undecided" (in the closing report if there is no build PR), and say so in the closing report. Do nothing below.
- Write "none accepted" or "no learning PR" only when the user said `none`.

Example: `keep 1, 3` keeps proposals 1 and 3 and drops the rest. `ok` is not an answer.

Never write accepted lines into the working tree of `~/.claude/atelier`. That checkout is live config and its `main` branch changes only through pull requests. Instead:

1. In `~/.claude/atelier`, create a branch `learn/<yyyy-mm-dd>-<short-slug>` in a new git worktree (`git worktree add`). The worktree lives at `~/.claude/atelier/.claude/worktrees/learn-<yyyy-mm-dd>-<slug>` (that path is git-ignored locally in the Atelier checkout), never under a temp or scratch directory: a worktree in a folder that later gets cleaned leaves a dangling entry. Call it `WT` below.
2. Apply the accepted lines in `WT`, in the item format each file documents in its own header and in `skills/taste-review/SKILL.md` ("What an item is"). A new item takes the next free number in its file (one above the highest `### F<n>`, `### C<n>` or `### T<n>` there, gaps from cut items are never reused) and `Status: draft`. It goes at the end of the file. In `taste.md` that is under the heading `## From builds`; if an older checkout lacks that heading, add it first. Every item carries a `Source:` line, and the check rejects free text. For an item born from a verdict in this session use the wrap form: `Source: wrap:<yyyy-mm-dd> finding <n>` or `Source: wrap:<yyyy-mm-dd> assumption A<n>`. One filled example per file:

```
### F<n>
Name: Flag gates the control, not the layout
Trap: A feature flag hides the button but the column built for it still renders.
Shows up as: An empty column in production while the feature ships dark.
Instead: Derive the layout from the flag, and test the flag-off render.
Source: wrap:2026-11-19 finding 1
Status: draft
```

```
### C<n>
In a segmented control, the default option is the first segment.
Source: wrap:2026-11-19 finding 3
Check: Is the default the first segment in every segmented control?
Status: draft
```

```
### T<n>
A blocked row action keeps its trigger visible, and the dialog explains the block.
Source: wrap:2026-11-19 finding 10
Status: draft
Applied as: Don't flag a visible-but-blocked trigger as an extra round trip when the SPEC asks for it.
```

3. Regenerate the review state from the generator, so every new item enters `taste-review/state.json` as pending, and check the result:

```
python3 -I -B WT/skills/taste-review/tests/gen-state.py WT > WT/taste-review/state.json
bash WT/skills/taste-review/tests/check.sh
```

Do not commit until the check passes. If the diff of `state.json` removes or changes any existing entry, stop: a review has started, so do not overwrite the file. Run `python3 -I -B WT/skills/taste-review/tests/gen-state.py --sync WT` instead, which only appends the new keys as pending.
4. Commit by file name: the changed contract file or files and `taste-review/state.json`, each staged by name, never `git add -A`. Push the branch and open a PR in the Atelier repo:

```
gh pr create --title "<title>" --body "<accepted lines and why>"
```

5. Report the PR URL. The build's own PR in step 5 links to it.

This is the only way those four files change.

## Step 5. Pull request

If this session had no build, there is no host PR: stop here.

Only now create the PR for the build, in the host repo. Check the branch is not `main` first. The description holds the critique summary, the user's verdicts (findings and assumptions), the deferred findings under "Deferred", any findings with no token under "Not addressed", and a link to the learning PR from step 4 if there is one, and any proposals the user left undecided, verbatim, under "Learning proposals, undecided".

```
gh pr create --title "<title>" --body "<description>"
```

Last act of step 5, once the PR exists: close the session by renaming the marker. The script does the rename (never a delete), refuses if the build belongs to another session, and keeps the file's contents, `sessionId` included, in `.atelier/session.closed.json`. Run it as the only command on the line:

```
~/.claude/atelier/guardrails/session-close.sh
```

If it exits non-zero, tell the user what it printed. The marker means a build session is open, and the guardrail hooks key off it, and only for the session whose id it carries. A marker left behind is inert for other sessions but would keep gating its own. In diverge mode there is no marker in the main checkout; close the one in each option worktree you wrapped with `~/.claude/atelier/guardrails/session-close.sh <worktree path>`.
