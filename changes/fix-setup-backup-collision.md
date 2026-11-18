## Changelog

### Fixed

- `setup.sh` could lose the backup of your original `~/.claude/settings.json`. It edits that file in two steps, and each step saved a backup named with the time down to the second. When both steps ran in the same second, the second backup replaced the first, so the newest backup was the file as it stood halfway through setup, not as you had it before. Now no backup ever replaces another one. Each step puts its own label on the end of the name, and if a name is somehow taken, a number is added (`-2`, `-3`). The names look like this:
  - `settings.json.bak.20261118-101530-aurora-mods` (the step that wires in the Aurora billboard and Sketchpad)
  - `settings.json.bak.20261118-101530-guardrails` (the guardrails step; `settings.local.json` gets the same label)
  - `commands.bak.<date>-<time>-commands` and `.dev-aliases.sh.bak.<date>-<time>-aliases` for the two other things `setup.sh` can move aside
  Every backup still starts with `.bak.` and the date and time, so the undo commands from 1.1.0 work as written. `setup.sh` also prints each backup path as it makes it, and at the end lists, under "Your files as they were before this run", the backup that holds each file as it was before the run. Restoring one puts back that file's contents only; for `commands` and `.dev-aliases.sh`, which are links into the repo after setup, remove the link first and then move the backup back. Running `guardrails/install.sh` on its own uses the same names and prints the backup path for each file it changes; that end-of-run list is only printed by `setup.sh`. If a backup can't be made, the file is left untouched: `setup.sh` skips that step and lists it at the end, and `guardrails/install.sh` stops with an error. What gets installed has not changed.

## README

The documented commands still work as written, because the `.bak.` prefix and the date-time are unchanged. One optional addition, so the undo path matches what `setup.sh` now prints.

Current line (the sentence after the code block, near "Open the backup first"):

> Open the backup first: if it still mentions `net-host-guard`, take the next one down. This puts back the permission rules and hooks only; the symlinks `setup.sh` made and the Aurora and Sketchpad entry in `env.CLAUDE_CODE_PLUGIN_DIRS` stay.

Optional replacement:

> Open the backup first: if it still mentions `net-host-guard`, take the next one down. To undo a whole `setup.sh` run, restore the backup that `setup.sh` names under "Your files as they were before this run" at the end of the run; that is your file as it was before the run. This puts back the permission rules and hooks only; the symlinks `setup.sh` made and the Aurora and Sketchpad entry in `env.CLAUDE_CODE_PLUGIN_DIRS` stay.

In the CHANGELOG 1.1.0 section, the "Open the backup first" line has the same shape and can take the same addition. The `<file>.bak.YYYYmmdd-HHMMSS` description there is still true as a prefix; the label after it is new.

## Setup

No new steps.
