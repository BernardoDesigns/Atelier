## Changelog

### Added

- Build-session guardrails in `guardrails/`, all off by default and installed only by `guardrails/install.sh --enforce`:
  - `conventions-injector.sh`: a PreToolUse hook that, when the model writes a `.tsx`, `.css`, `.svg` or `.html` file, adds one compact `C<n>: <rule>` line per item of `conventions.md` once per session, then a one-line reminder on later edits. It never blocks a write.
  - `fast-gate.sh`: a PostToolUse hook that runs `tsc --noEmit` and eslint on edited `.ts`, `.tsx`, `.js` and `.jsx` files and returns any errors to the model.
  - `lane-guard.sh`: a PreToolUse hook that blocks writes to paths listed in a repo's `.claude/lane-rules.json`.
  - `lane-guard-deny.json` and `lane-guard-init.sh`: four project-root-anchored deny rules (`Edit(/auth/**)`, `Edit(/api/**)`, `Edit(/payments/**)`, `Edit(/lib/shared/**)`), applied to one repo's `.claude/settings.json` (project scope, never user scope). The init script also removes the unanchored rules an earlier draft wrote.
  - `dod-gate.sh`: a Stop hook that refuses to stop a build session while screenshots, an assumptions list, a passing test run or a reviewed critique is missing. It is a nudge: it refuses once, then yields, so the Builder can stop to ask a question. `pr-gate.sh` is the hard gate: a PreToolUse hook on Bash that blocks `gh pr create` until the same four artefacts exist (shared check in `dod-check.sh`). Neither has an override.
  - The conventions injector, fast gate, Stop gate and PR gate do nothing unless the repo has `.atelier/session.json`. The lane guard does nothing unless the repo has `.claude/lane-rules.json`. PreToolUse hooks fail closed if their script goes missing; the Stop hook and fast gate fail open (a warning and a non-blocking exit), so a missing file can't trap a session.
- `guardrails/install.sh --relax` removes exactly the five hooks `--enforce` added and nothing else.
- `guardrails/VETTING.md`: read every script before installing any third-party skill, mod or MCP server.
- `guardrails/tests/run.sh`: fixture-driven hook tests (recorded tool-call JSON in, decision out), plus `guardrails/tests/installer.sh` and `guardrails/tests/lane-init.sh`. All of them run against temp directories.

### Changed

- `guardrails/install.sh` takes `--enforce` or `--relax` (not both). With no flag it behaves exactly as before.

## README

| Guardrail | What it does | Needs |
|---|---|---|
| Conventions injector | Adds `conventions.md` to context before UI file edits | `--enforce`, `.atelier/session.json` |
| Fast gate | Typecheck and lint on the files just edited | `--enforce`, `.atelier/session.json` |
| Lane guard | Blocks writes to protected paths | `--enforce` for the hook, `lane-guard-init.sh` for the deny rules, `.claude/lane-rules.json` for per-repo extras |
| Definition-of-done gates | Stop nudges once; the PR gate blocks `gh pr create` until screenshots, assumptions, passing tests and a reviewed critique exist | `--enforce`, `.atelier/session.json` |

Run `bash guardrails/tests/run.sh` to test the hooks and installer.

## Setup

Hooks are off by default. To turn the build-session hooks on, run `bash guardrails/install.sh --enforce` from the main checkout (the hooks run from wherever the installer was last run, and a missing script blocks). To turn them off again, run `bash guardrails/install.sh --relax`. To protect a project's paths, run `bash guardrails/lane-guard-init.sh <path-to-repo>` on the repo root.
