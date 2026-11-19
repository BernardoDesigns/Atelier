## Changelog

### Fixed

- The build-session hooks (`conventions-injector.sh`, `fast-gate.sh`, `dod-gate.sh`, `pr-gate.sh`) now act only in the session that opened the build. Before, `.atelier/session.json` armed them for every Claude Code session whose cwd was that checkout, so an unrelated session in the same checkout could be stopped by the definition-of-done gate or blocked from `gh pr create` for as long as someone else's build was open.

### Changed

- The marker now carries a third field: `{"spec": "<path>", "branch": "<name>", "sessionId": "<id>"}`. A hook acts only when the marker's `sessionId` equals the hook input's `session_id`. A marker bound to another session, a marker with no `sessionId` (old format or hand-made), unreadable hook input, and input with no `session_id` all mean the hook does nothing: exit 0, no output. That includes the two that used to fail closed (unreadable input in a build session), because a real session always supplies `session_id`. The decision lives in one function, `atelier_is_build_session` in `guardrails/session-lib.sh`, shared by all four hooks.
- `/build` opens the marker itself, before the Builder starts, by running `guardrails/session-open.sh <spec> <branch>`, then reads it back and stops if `sessionId` is missing. The Builder no longer writes the marker; it checks it (a marker for a different SPEC still means stop and ask) and uses the marker's branch name.
- `/wrap` checks ownership with `guardrails/session-close.sh --check` and closes with `guardrails/session-close.sh`. Run from a session that doesn't own the build, it says so and closes nothing. The closed file `.atelier/session.closed.json` keeps the `sessionId`.
- Diverge mode: no marker in the main checkout, as before. The Builder opens each option worktree's marker with `session-open.sh <spec> <option branch> <worktree>`; a subagent's hooks carry the parent session's id, so all option markers are bound to the session that ran `/build`.

### Added

- `guardrails/session-open.sh`, `guardrails/session-close.sh`, `guardrails/session-claim.sh`, `guardrails/session-lib.sh`. A script can't see its caller's session id, a hook can, so `pr-gate.sh` (already the PreToolUse hook on Bash) notes the caller of exactly those two scripts in `.atelier/session-claim`, and the script reads and deletes it. Only a bare call of the script counts: a mention inside a longer command, a string, a comment, an echo or a pipeline records nothing. A session can claim an unowned marker or its own, never one owned by another session.
- `guardrails/tests/session-scripts.sh` (34 checks: claim, re-claim, refusal, mention-only commands, close, ownership) and `other-session` / `marker-without-session-id` / `malformed-stdin-with-marker` fixtures for each of the four hooks. Existing build-session fixtures now carry a matching `session_id` in the input and the marker.

## README

The build-session guardrails are scoped to one session, not one checkout.

| Marker state | Hook behaviour |
|---|---|
| no `.atelier/session.json` | silent |
| `sessionId` equals the hook's `session_id` | gates act as before |
| `sessionId` is a different id | silent, exit 0 |
| no `sessionId` | silent, exit 0 |
| hook input unreadable or without `session_id` | silent, exit 0 |

`/build` opens the session through `session-open.sh`, which needs the `--enforce` hooks installed to learn the caller's session id. Without them it refuses, and `/build` stops with a message.

Run `bash guardrails/tests/run.sh` and `bash agents/tests/check.sh`.

## Setup

None: the hooks call the scripts in place. No `settings.json` change is needed, and re-running `guardrails/install.sh --enforce` is not required. The new `.sh` files must stay next to the hooks (they are sourced and called by path). A build opened before this change has a marker with no `sessionId` and is now inert; open it again with `/build`, or add the `sessionId` by hand.
