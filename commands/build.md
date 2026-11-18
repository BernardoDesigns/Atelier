---
description: Run the build loop for a SPEC. Builder makes it, Critic judges it, up to 3 passes, then report.
---
# /build

Usage: `/build <path to SPEC.md>`. Add "diverge" and a number (4 to 6) to get options instead of one build.

This command runs the loop in the parent session. It never creates a PR, never starts a server or tunnel, and never edits `~/.claude/atelier/quality.md`, `taste.md`, `conventions.md` or `failures.md`.

## Loop

1. Run the `builder` subagent with the SPEC path. Wait for its hand-back.
   - If it reports nothing answering at the base URL, stop. Ask the user to start the server and give the base URL. Do not start one.
   - If it stops on a big decision or a split proposal, pass that to the user and stop.
2. Run the `critic` subagent. Give it the SPEC path, the render manifest path from the Builder's hand-back, and the branch diff (`git diff main...HEAD`), as text or saved under `.atelier/`. Save its reply, unchanged, to `.atelier/critique.md`.
3. Read the `Verdict:` line. If it is `revise`, send the ranked findings back to the Builder and go to step 2 again after it hands back. At most 3 Builder passes in total. After the third, stop even if the verdict is still `revise`.
4. Report to the user:
   - the verdict, and how many passes it took
   - the top findings, each with its screenshot path
   - the assumptions count from `.atelier/assumptions.md`
   - the line "Run /wrap to close."

## Diverge mode

Only on request. Run the Builder in diverge mode with N options. Then make one Critic call with all the option worktree paths, so it returns one critique per option and a ranking. Save the reply to `.atelier/critique.md` in the main checkout. Report the top 2 or 3 options with their branches and worktree paths. The 3-pass cap does not apply to options: report after one Builder run and one Critic call.
