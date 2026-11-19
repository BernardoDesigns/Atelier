## Changelog

### Fixed

- The first dry run of the build loop showed three gaps, fixed together.
- Writes through Bash skipped the write hooks. The Builder made one Edit call and about 52 file writes through heredocs, `python3 - <<EOF` and `sed -i`, so the conventions arrived late, the fast gate ran once and the lane guard never saw a protected path. `agents/builder.md` now says to create and change files only with Write and Edit (formatters, `npm run` scripts and the render harness are fine), the definition of done checks it from git, and `pr-gate.sh` blocks obvious Bash file writes.
- The Stop gate nudged while the session was only waiting for its own Builder or Critic subagent. `dod-gate.sh` now stays silent while the Stop input's `background_tasks` has an in-flight task.
- The Builder went past the 400-line split rule (about 590 changed lines over three passes) and only logged an assumption. The rule now has a moment and a number: before every hand-back it runs `git diff --shortstat <base>...HEAD` (plus uncommitted changes), reports the count, and over 400 it hands back a split proposal instead of continuing, revise passes included.

### Added

- A fifth definition-of-done requirement, `lane`, in `guardrails/dod-check.sh`, so both the Stop gate and the PR gate use it. No file under a protected path may be changed on the branch (`git diff --name-only <base>...HEAD`, base is `main`, else `master`, else `origin/HEAD`) or in the working tree (staged, unstaged, untracked). Protected paths are the four defaults (`auth/`, `api/`, `payments/`, `lib/shared/`) plus the `protected` patterns in `.claude/lane-rules.json`. The message names each file and says to revert it and tell the user. `gh pr create` is blocked while one exists, however the file was written.
- `guardrails/lane-lib.sh`, the rule matching `lane-guard.sh` already used, now shared by `lane-guard.sh` and `dod-check.sh`. No behaviour change for the lane guard.
- A Bash write nudge in `pr-gate.sh`, build session only. It blocks `>` and `>>` redirects and `tee` into the repo, `sed -i` and `perl -i`, and lets through git, gh, npm, npx, node and the render harness, fd duplication (`2>&1`), `/dev/null`, `.atelier/`, temp paths, variables and `mktemp`, and anything outside the repo. It is a nudge: the exact patterns are in the script header, and the `lane` requirement is the real backstop.
- The write nudge also reads inline scripts. `python3 - <<EOF`, `python3 -c`, `node -e`, `node --eval`, `ruby -e` and `perl -e` (or a heredoc on stdin) are blocked when the script text calls a file write: Python `open(` with a w, a or x mode, `.write_text(`, `.write_bytes(`; Node `writeFileSync(`, `writeFile(`, `appendFileSync(`, `appendFile(`, `createWriteStream(`; Ruby `File.write(` and `File.open(` with a write mode; Perl `open(` with `>`. A write whose first argument is a plain string literal under `.atelier/` or `/tmp` is allowed; anything the check can't read statically is blocked. Interpreters running a script file, and inline scripts that only read or print, are never blocked.
- `guardrails/run-tests.sh <command> [args...]` runs the test command, passes its output through, writes `.atelier/tests.json` as `{"pass": <exit 0>, "command": "...", "ranAt": "<UTC time from date>", "exitCode": <n>}` (temp file, then mv) and exits with the command's exit code. It needs `.atelier/` in the current directory and no session marker. The Builder runs its tests through it and never writes `tests.json` by hand.
- The `tests` requirement now treats a `tests.json` with no numeric `exitCode` as not recorded ("was not written by run-tests.sh"). A passing file written by hand, as before, no longer counts.
- `guardrails/tests/loop-gaps.sh` (124 checks) for the lane requirement through both gates, the write nudge (redirects and inline scripts), `run-tests.sh` and the recorded-tests check, and the Stop gate with and without background tasks. `agents/tests/check.sh` asserts the new Builder rules and the changed-line reporting. Existing passing fixtures carry `exitCode: 0`.

## README

Build-session guardrails now check a fifth thing and watch for one more habit.

| Requirement | Met when |
|---|---|
| screenshots, assumptions, tests, critique | as before |
| lane | no changed file (branch diff against `main`/`master`/`origin/HEAD`, plus working tree) is under `auth/`, `api/`, `payments/`, `lib/shared/` or a `protected` pattern in `.claude/lane-rules.json` |

The Builder writes files with Write and Edit only. A Bash command that redirects, tees or `sed -i`s into the repo is blocked in the build session with a message saying so. Redirects under `.atelier/` and temp dirs are allowed.

The Stop gate is silent while a background task (the Builder or Critic subagent) is running. The PR gate is not.

The Builder reports its changed-line count at every hand-back; over 400 it hands back a split proposal (PR 1, and what stacks on it) instead of continuing. `/build` includes the count in its final report.

## Setup

None for the hooks: they call the scripts in place, and `lane-lib.sh` must stay next to `lane-guard.sh` and `dod-check.sh` (both source it). No `settings.json` change, no need to re-run `guardrails/install.sh`. Open builds pick up the new checks on their next hook call.
