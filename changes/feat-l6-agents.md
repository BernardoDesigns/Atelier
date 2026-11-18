## Changelog

### Added
- Builder agent (`agents/builder.md`, Sonnet): fresh-session builder that reads a SPEC, keeps an assumptions log, renders every state, and supports diverge mode.
- Critic agent (`agents/critic.md`, Opus, read-only): scores the ten rubric gates and five principles, leads with the core tension, ranks options in diverge mode.
- `/wrap` command: five-step close sequence with a one-line verdict grammar, learning proposals and the PR at step 5.
- Output templates `templates/assumptions.md` and `templates/critique.md`.
- `agents/tests/check.sh`: frontmatter, tool-list, verdict-parser and critique-fixture checks.

## README

| Path | What |
|---|---|
| `agents/builder.md` | Builds a SPEC on a branch, logs assumptions, runs the render loop |
| `agents/critic.md` | Read-only critic, scores a build against the rubric and principles |
| `commands/wrap.md` | `/wrap`: Critic review, assumptions, verdict line, learning proposals, PR |

Run `bash agents/tests/check.sh` to check the agents and `/wrap`.

## Setup

Link `agents/builder.md` and `agents/critic.md` into `~/.claude/agents/` file by file, beside the existing files. Do not replace the directory. `commands/wrap.md` is picked up through the existing `commands/` link.
