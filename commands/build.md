---
description: Run the build loop for a SPEC. Builder makes it, Critic judges it, up to 3 passes, then report.
---
# /build

Usage: `/build <path to SPEC.md>`. Add "diverge" and a number (4 to 6) to get options instead of one build.

This command runs the loop in the parent session. It never creates a PR, never starts a server or tunnel, and never edits `~/.claude/atelier/quality.md`, `taste.md`, `conventions.md` or `failures.md`.

## Open the build session

Before the Builder starts, bind a marker to this session. Skip this in diverge mode: there the main checkout gets no marker and each option worktree gets its own (see Diverge mode).

1. Pick the branch name: the current branch (`git branch --show-current`) unless it is `main` or `master`, then `build/<short-slug-from-the-SPEC-name>`. The Builder will use that name.
2. Run exactly this, as the only command on the line (no `&&`, no pipe, no quotes around the whole thing), with the SPEC path and the branch name filled in:

```
~/.claude/atelier/guardrails/session-open.sh <SPEC path> <branch>
```

   The guardrail hook notes which session runs it, and the script writes `.atelier/session.json` as `{"spec":...,"branch":...,"sessionId":...}`. The `sessionId` is what makes the gates apply to this session and no other. If an earlier build left artefacts in `.atelier/`, the script moves them to `.atelier/archive/` when it opens the new build, so nothing from an earlier build can satisfy the gates. It also records the commit the build started from and a baseline of the repo's existing type errors (one `baseline:` line says how many), so the fast gate reports only errors the Builder adds. If the baseline couldn't be taken the build still opens and the gate reports every error in changed files.
3. If it exits non-zero, stop and tell the user what it printed. "Already open ... belongs to another session" means someone else's build is open in this checkout: do not touch it. "Couldn't tell which session is calling" means the enforce hooks aren't installed (`guardrails/install.sh --enforce`).
4. Read the marker back: `jq -r '.sessionId // empty' .atelier/session.json`. If that prints nothing, stop and tell the user the build session is not bound to this session, so the gates would not apply. Do not start the Builder.

## Loop

1. Run the `builder` subagent with the SPEC path. Wait for its hand-back.
   - If it reports nothing answering at the base URL, stop. Ask the user to start the server and give the base URL. Do not start one.
   - If it stops on a big decision or a split proposal (its hand-back reports a source-line count over 400 with PR 1 and what stacks on it), pass that to the user and stop. This includes a revise pass: do not send the Builder back in to keep going past the cap.
2. Run the `critic` subagent. Give it the SPEC path, the render manifest path from the Builder's hand-back, and the branch diff (`git diff main...HEAD`), as text or saved under `.atelier/`. Save its reply, unchanged, to `.atelier/critique.md`.
3. Read the `Verdict:` line. If it is `revise`, send the ranked findings back to the Builder and go to step 2 again after it hands back. At most 3 Builder passes in total. After the third, stop even if the verdict is still `revise`.
4. Report to the user:
   - the verdict, and how many passes it took
   - the top findings, each with its evidence line (screenshot path or diff location)
   - the assumptions count from `.atelier/assumptions.md`
   - the source lines and the total lines from the Builder's last hand-back (the numbers it ran `git diff --shortstat` for; tests, stories and fixtures do not count as source), and a note if the source lines are over 400
   - the line "Run /wrap to close."

## Diverge mode

Only on request. Run the Builder in diverge mode with N options. No marker for the main checkout. The Builder opens each option worktree's marker itself with `session-open.sh <SPEC> <option branch> <worktree path>`; the Builder is a subagent of this session, so its hooks carry this session's id and every option marker is bound to it. After the Builder hands back, read each option's marker (`jq -r '.sessionId // empty' <worktree>/.atelier/session.json`); if one has no `sessionId`, tell the user which option and stop. Then make one Critic call with all the option worktree paths, so it returns one critique per option and a ranking. Save the reply to `.atelier/critique.md` in the main checkout. Report the top 2 or 3 options with their branches and worktree paths. The 3-pass cap does not apply to options: report after one Builder run and one Critic call.
