## Changelog

### Fixed

- A new build no longer starts with the previous build's artefacts in place. `.atelier/` kept the earlier build's screenshots, `assumptions.md`, `critique.md` and passing `tests.json` after `/wrap`, so when `/build` opened the next build in the same checkout the Stop gate and the PR gate were already satisfied before anything had been rendered, tested or critiqued, and the Builder found an `assumptions.md` that wasn't its own.

### Changed

- `guardrails/session-open.sh` now archives a finished build's artefacts before it opens a new one. When there is no `.atelier/session.json` and `.atelier/` holds anything, every entry except `archive/` is moved with `mv` (nothing is deleted) into `.atelier/archive/<UTC timestamp>-<branch of the closed build, or unknown>/`, slugged to letters, digits, `-`, `_` and `.`, with a numeric suffix if the name exists. It prints `archived the previous build's artefacts to .atelier/archive/<name>/` before the `opened:` line. Refreshing your own marker for the same spec, and every refusal, archive nothing. If any move fails the script exits non-zero and writes no marker. Diverge mode gets the same rule per option worktree.
- The gates read nothing under `.atelier/archive/`. `commands/build.md` says the archive happens on open, and `agents/builder.md` tells the Builder not to read it.

## README

When `/build` opens a build, whatever an earlier build left in `.atelier/` moves to `.atelier/archive/<timestamp>-<branch>/`. The definition-of-done gates only look at the live `.atelier/` files, so an old build can't satisfy them. The archive is yours to keep or delete.

Run `bash guardrails/tests/run.sh` and `bash agents/tests/check.sh`.

## Setup

None.
