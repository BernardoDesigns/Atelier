## Changelog

### Fixed

- `bash skills/taste-review/tests/check.sh` no longer fails on `main`. The first `/wrap` learning PR added T37 and F25 to F28 with free-text `Source:` lines and without regenerating `taste-review/state.json`. The five items now carry valid source tags, and `state.json` is the generator's output with the five added as pending.
- `/wrap` step 4 now produces a valid learning PR every time. It names the item format of each contract file with a filled F, C and T example, says new items take the next free number and `Status: draft`, regenerates `taste-review/state.json` with the generator, runs `skills/taste-review/tests/check.sh` and holds the commit until it passes, and stages the changed files by name.
- `/wrap` step 4 now says where the learning worktree lives: `~/.claude/atelier/.claude/worktrees/learn-<yyyy-mm-dd>-<slug>`, never a temp or scratch folder, which left a dangling worktree entry once cleaned.

### Added

- A new valid `Source:` form for items born from a `/wrap` verdict: `wrap:<yyyy-mm-dd>`, optionally followed by ` finding <n>` or ` assumption A<n>`, for example `wrap:2026-11-19 finding 7`. The taste-review check accepts it and still rejects free text. The valid forms are now listed in `skills/taste-review/SKILL.md`.

## README

None.

## Setup

None.
