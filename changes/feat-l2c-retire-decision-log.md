## Changelog

### Breaking changes

- `/design-director`, `/eames` and `/rand` no longer read memory files at session start, run a Session Debrief, consolidate a Decision Log or call `figma_execute`. Close a session with `/wrap` instead.

### Changed

- The three design commands name the contract files (`taste.md`, `conventions.md`, `quality.md`) and point at `/wrap` for session close.
- Figma write guidance in `/eames` and `/rand` names the Figma MCP `use_figma` tool in place of `figma_execute`.

### Removed

- Session Debrief Protocol, entry format and consolidation pass from `commands/design-director.md`.
- Session Debrief sections from `commands/eames.md` and `commands/rand.md`.
- Session-start memory reads and the 25-entry consolidation prompt from all three commands.

## README

| Path | What |
|---|---|
| `packaging/tests/retire-check.sh` | Fails if `commands/` still mentions the Decision Log, debrief, `update_doc`, token budget or `figma_execute`, or if a design command still refers to memory files |

Run `bash packaging/tests/retire-check.sh` to confirm the retirement.

## Setup

- Nothing to run. `commands/` is linked into `~/.claude`, so this change is live as soon as it merges. Merge at the v2.0.0 switch-on only.
