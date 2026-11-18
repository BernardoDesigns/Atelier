## Changelog

### Added
- Builder agent (`agents/builder.md`, Sonnet): fresh-session builder that reads a SPEC, keeps an assumptions log, renders every state, and supports diverge mode.
- Critic agent (`agents/critic.md`, Opus, read-only): scores the ten rubric gates and five principles, leads with the core tension, ranks options in diverge mode.
- `/build` command: runs the loop for a SPEC (Builder, Critic, revise), at most 3 Builder passes, then reports.
- `/wrap` command: five-step close sequence with a one-line verdict grammar. Learning edits go to a PR in the Atelier repo, the build PR is created at step 5, and the session marker is renamed to `.atelier/session.closed.json` at the end.
- Output templates `templates/assumptions.md` and `templates/critique.md`.
- `agents/tests/check.sh`: frontmatter, tool-list, path, verdict-parser and critique-fixture checks.

## README

| Path | What |
|---|---|
| `agents/builder.md` | Builds a SPEC on a branch, logs assumptions, runs the render loop |
| `agents/critic.md` | Read-only critic, scores a build against the rubric and principles |
| `commands/build.md` | `/build <SPEC>`: Builder and Critic loop, then report |
| `commands/wrap.md` | `/wrap`: Critic review, assumptions, verdict line, learning proposals, PR |

Run `bash agents/tests/check.sh` to check the agents and the commands.

## Setup

- Link `agents/builder.md` and `agents/critic.md` into `~/.claude/agents/` file by file, beside the existing files. Do not replace the directory. `commands/build.md` and `commands/wrap.md` are picked up through the existing `commands/` link.
- setup must create the `~/.claude/atelier` symlink to the checkout. The agents and commands read the rule files, templates and render harness through that path.
