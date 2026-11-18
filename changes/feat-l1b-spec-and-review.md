## Changelog

- Added `failures.md`: 24 known traps, each with the trap, how it shows up and what to do instead, all marked draft until reviewed.
- Added `templates/SPEC.md`: the SPEC template with the eight contract headings, the standard states and the four protected paths.
- Added the `spec` skill (`skills/spec/`): an interview that refuses to write a SPEC.md while acceptance criteria or states are missing, then writes it into the current repo.
- Added the `taste-review` skill (`skills/taste-review/`): reviews every draft item one at a time, keeps its state on a long-lived `taste-review` branch, and finishes with one pull request. Added `taste-review/state.json` with every item pending.

## README

| Path | What it is |
|---|---|
| `failures.md` | Known traps and how to avoid them, read by the Critic and the Builder |
| `templates/SPEC.md` | SPEC template, eight headings |
| `skills/spec/` | `spec` skill: interview that produces a SPEC.md |
| `skills/taste-review/` | `taste-review` skill: one-item-at-a-time review of the contract files |
| `taste-review/state.json` | Review state, resumable on any machine |

## Setup

Setup must link `skills/spec` and `skills/taste-review` into the `~/.claude/skills/` folder by folder, beside what is already there. Never replace that directory: it holds other tools' skills.
