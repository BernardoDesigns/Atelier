## Changelog

### Added

- Build-session guardrails in `guardrails/`, all off by default and installed only by `guardrails/install.sh --enforce`:
  - `conventions-injector.sh`: a PreToolUse hook that adds the numbered items from `conventions.md` and a "check the component manifest first" line to the model's context when it writes a `.tsx`, `.css`, `.svg` or `.html` file. It never blocks a write.
  - `fast-gate.sh`: a PostToolUse hook that runs `tsc --noEmit` and eslint on edited `.ts`, `.tsx`, `.js` and `.jsx` files and returns any errors to the model.
  - `lane-guard.sh`: a PreToolUse hook that blocks writes to paths listed in a repo's `.claude/lane-rules.json`.
  - `lane-guard-deny.json` and `lane-guard-init.sh`: native deny rules for `auth/`, `api/`, `payments/` and `lib/shared/`, applied to one repo's `.claude/settings.json` (project scope, never user scope).
  - `dod-gate.sh`: a Stop hook that keeps a build session open until screenshots, an assumptions list, a passing test run and a reviewed critique exist. It has no override.
  - The conventions injector, fast gate and Stop gate do nothing unless the repo has `.atelier/session.json`. The lane guard does nothing unless the repo has `.claude/lane-rules.json`. Each fails closed if its script goes missing.
- `guardrails/install.sh --relax` removes exactly the four hooks `--enforce` added and nothing else.
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
| Definition-of-done gate | Won't end a build session without screenshots, assumptions, passing tests and a reviewed critique | `--enforce`, `.atelier/session.json` |

Run `bash guardrails/tests/run.sh` to test the hooks and installer.

## Setup

Hooks are off by default. To turn the build-session hooks on, run `bash guardrails/install.sh --enforce` from the main checkout (the hooks run from wherever the installer was last run, and a missing script blocks). To turn them off again, run `bash guardrails/install.sh --relax`. To protect a project's paths, run `bash guardrails/lane-guard-init.sh <path-to-repo>` on the repo root.
