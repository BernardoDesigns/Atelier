## Changelog

- Packaging: the claude.ai skill build now translates `commands/eames.md` and `commands/rand.md` instead of copying them verbatim. The Contract files sentence is rewritten to name `taste.md` and `conventions.md` as bare file names (the `quality.md` mention is stripped, since it is the production bar for the Claude Code build loop and is not bundled). The "Closing a Session" section (it points at `/wrap`, which only exists in Claude Code) and the trailing "User Request" section (a literal `$ARGUMENTS` placeholder) are dropped, and the Figma line no longer tells the model to load the `figma-use` Claude Code skill.
- Packaging: the build fails with a clear message if the Contract files sentence changes shape, if a command names any other `~/.claude/atelier/` file that is not bundled, if a translation finds nothing to change, or if a built `SKILL.md` still holds `~/.claude/`, `/wrap`, `/build`, `figma-use`, "Closing a Session", `.atelier/session.json` or `$ARGUMENTS`.
- Tests: `packaging/tests/check.sh` asserts the above on the built zips, scans the bundled `taste.md` and `conventions.md` for `~/.claude/`, `/wrap`, `/build` and `.atelier/`, reports every failure at once, and adds negative builds from reworded sources. `design-director` is not packaged and is untouched.

## README

An existing claude.ai upload of Eames or Rand must be re-uploaded to pick this up. Each zip still holds exactly `SKILL.md`, `taste.md` and `conventions.md`; `quality.md` is not shipped. Rebuild with `bash packaging/build.sh` and upload `dist/eames.zip` and `dist/rand.zip`.

## Setup

No change. `setup.sh` is not affected, and nothing new is installed.
