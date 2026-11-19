## Changelog

- Packaging: the claude.ai skill build now translates `commands/eames.md` and `commands/rand.md` instead of copying them verbatim. `~/.claude/atelier/<file>` becomes the bare file name, the "Closing a Session" section (it points at `/wrap`, which only exists in Claude Code) is dropped, and the Figma line no longer tells the model to load the `figma-use` Claude Code skill.
- Packaging: each skill zip now bundles `quality.md` next to `taste.md` and `conventions.md`, and the appended note names all three.
- Packaging: the build fails with a clear message if a command names a `~/.claude/atelier/` file that is not bundled, if a translation finds nothing to change, or if a built `SKILL.md` still holds `~/.claude/`, `/wrap`, `/build`, `figma-use`, "Closing a Session" or `.atelier/session.json`.
- Tests: `packaging/tests/check.sh` asserts the above on the built zips and adds negative builds from reworded sources. `design-director` is not packaged and is untouched.

## README

An existing claude.ai upload of Eames or Rand must be re-uploaded to pick this up. Each zip now carries `quality.md` as well as `taste.md` and `conventions.md`, so the uploaded skill has three bundled files. Rebuild with `bash packaging/build.sh` and upload `dist/eames.zip` and `dist/rand.zip`.

## Setup

No change. `setup.sh` is not affected, and nothing new is installed.
