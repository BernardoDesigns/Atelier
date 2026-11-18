## Changelog

- Added `packaging/build.sh`, which builds `dist/eames.zip` and `dist/rand.zip` as claude.ai skill uploads. Each zip holds one folder with `SKILL.md`, `taste.md` and `conventions.md`, and two runs give identical bytes.
- Added `packaging/tests/check.sh`, which checks the model frontmatter on the three commands, the zip contents and build determinism.

## README

| Path | What it does |
|---|---|
| `packaging/build.sh` | Builds the claude.ai skill zips for eames and rand into `dist/`. Run `bash packaging/build.sh`; the output is not committed. |

## Setup

Release assembly: add `dist/` to `.gitignore`. The zips from `packaging/build.sh` are build output and must not be committed.
