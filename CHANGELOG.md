# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The five benchmark tickets say the new flag defaults to on, as a kill switch, and that a test turning it off with the host's `overrideFlags` proves the flag-off behaviour. Flags are fixed at build time, so a default-off flag would hide the feature from the e2e build and the render harness. Their G9 lines also gain the split clause from `quality.md` ("or a split is proposed in the PR").
- Ticket 02 (inventory table) is checked against the host and tightened: the shelf location it asked for is now the day rate, the category filter is cut (the ticket keeps the status filter), sort is links with a defined order, the stacked layout and the flag are specified, every state has a URL, and the item name truncates at 768 instead of stacking.

## [2.0.0] - 2026-11-19

Atelier now has a working make, render, judge loop. `/build` runs a Builder agent, a render harness and a Critic agent over a SPEC, and `/wrap` closes the session. The Decision Log debrief is retired. The loop is proven end to end on one benchmark ticket.

**Drafts.** Every item in `taste.md`, `conventions.md` and `failures.md` and every threshold in `quality.md` is marked draft until the owner's review, which happens in v2.0.x. Treat them as working rules, not settled standards.

### Breaking changes

- `setup.sh` now installs the enforcing hooks (`guardrails/install.sh --enforce`). Undo them with `bash guardrails/install.sh --relax`, which removes exactly those five hooks and nothing else. What they do, and where:
  - In a session that opened a build with `/build` (the marker `.atelier/session.json`, bound to that session), the conventions are injected before UI file edits, the fast gate runs after each Write or Edit, a Bash command that writes a file into the repo is blocked with a pointer to Write and Edit, the Stop gate nudges once while artefacts are missing, and `gh pr create` is blocked until screenshots, assumptions, a recorded passing test run, a reviewed critique and a clean lane (no changed file under a protected path) exist.
  - Other sessions in the same checkout are not affected.
  - The lane guard denies edits to `auth/`, `api/`, `payments/` and `lib/shared/` only in a repo where you ran `guardrails/lane-guard-init.sh`.
- The Decision Log debrief is retired from `/design-director`, `/eames` and `/rand`. They no longer read memory files at session start, run a Session Debrief, consolidate a Decision Log or call `figma_execute`. The contract files (`quality.md`, `taste.md`, `conventions.md`, `failures.md`) and `/wrap` replace it: `/wrap` proposes learnings, and they reach the contract files only through a pull request. Existing memory files and `next-session-starter.md` are no longer read or written; nothing deletes them.
- An existing claude.ai upload of Eames or Rand must be re-uploaded (see Changed).

### Added

- The build loop:
  - Builder agent (`agents/builder.md`, Sonnet): reads a SPEC in a fresh session, keeps an assumptions log, renders every state, supports diverge mode. It creates and changes files only with Write and Edit, runs its tests through `guardrails/run-tests.sh`, and before every hand-back reports source lines and total lines. Over about 400 lines of source it hands back a split proposal instead of continuing.
  - Critic agent (`agents/critic.md`, Opus, read-only): scores the ten gates and five principles, leads with the core tension, cites evidence for every finding, ranks options in diverge mode.
  - `/build <SPEC>`: opens the build session, runs the Builder, then the Critic, and repeats on `revise` for at most 3 Builder passes, then reports. It never creates a PR.
  - `/wrap`: a five-step close. Critic review, assumption check, a one-line verdict grammar, learning proposals, then the build PR. Learning proposals go to a pull request in the Atelier repo, never into the working tree. The PR carries valid source tags, regenerated `taste-review/state.json` and runs `skills/taste-review/tests/check.sh` before the commit. The learning worktree lives under `~/.claude/atelier/.claude/worktrees/`. The session marker is renamed to `.atelier/session.closed.json` at the end.
  - Output templates `templates/assumptions.md` and `templates/critique.md`, and `agents/tests/check.sh`.
- `render/`, a self-contained render harness. It reads `.atelier/render-plan.json` and writes every target in 2 themes at 3 breakpoints (375, 768, 1280) as PNGs, plus `manifest.json` and `axe.json`, under `.atelier/renders/<slug>/`.
  - Runs axe on every shot and exits 1 when any serious or critical violation exists, naming the shot.
  - Shoots at exactly the requested width, at full document height. A page that overflows horizontally is reported as a fact: each shot carries `overflowX` (and `overflowBy`, naming the element that reaches furthest) in the manifest, the manifest has a top-level `overflow` count, and each overflowing shot prints an `OVERFLOW` line. Overflow is information for the Critic, not a failure.
  - A `storybook` subcommand turns a Storybook `index.json` into a render plan, skipping docs and test entries. Storybook targets pick the theme through the `globals=theme:dark|light` URL global, fail the shot if `<html>` does not end up with the matching `dark` class, wait for the story's `finished` phase, and fail a shot when the render is aborted or Storybook reports a play or render error.
  - Motion is settled, not removed. Hover states use a real pointer move; the harness never clicks before shooting. Each run clears its own slug's earlier PNGs, manifest and axe.json.
  - It never starts a server. With nothing at the base URL it exits 2 with one line.
- Build-session guardrails in `guardrails/`, installed only by `guardrails/install.sh --enforce` and acting only in the session that opened the build (`atelier_is_build_session` in `session-lib.sh`: the marker's `sessionId` must equal the hook input's `session_id`; a marker bound to another session, with no `sessionId`, or unreadable hook input all mean the hook does nothing):
  - `conventions-injector.sh`: a PreToolUse hook that, when the model writes a `.tsx`, `.css`, `.svg` or `.html` file, adds one compact `C<n>: <rule>` line per item of `conventions.md` once per session, then a one-line reminder. It never blocks a write.
  - `fast-gate.sh`: a PostToolUse hook that runs `tsc --noEmit` and eslint on edited `.ts`, `.tsx`, `.js` and `.jsx` files and returns any errors to the model.
  - `dod-gate.sh`: a Stop hook that refuses to stop while the definition of done is unmet. A nudge: it refuses once, then yields, and stays silent while the Builder or Critic subagent is still running.
  - `pr-gate.sh`: a PreToolUse hook on Bash and the hard gate. It blocks `gh pr create` until five things exist, checked by one shared script (`dod-check.sh`): screenshots, assumptions, a passing test run recorded by `run-tests.sh` (a hand-written `tests.json` does not count), a reviewed critique, and a clean lane (no changed file under `auth/`, `api/`, `payments/`, `lib/shared/` or a `protected` pattern in `.claude/lane-rules.json`, read from git so it holds however the file was written). No override.
  - The same hook blocks Bash commands that write into the repo: `>` and `>>` redirects, `tee`, `sed -i`, `perl -i`, and inline scripts (`python3 -`, `python3 -c`, `node -e`, `ruby -e`, `perl -e`) that call a file write. Git, gh, npm, npx, node, the render harness, `.atelier/`, temp paths and anything outside the repo pass. It is a nudge; the lane check is the backstop.
  - `lane-guard.sh`: a PreToolUse hook that blocks writes to paths in a repo's `.claude/lane-rules.json`, sharing its matching with the lane check through `lane-lib.sh`. `lane-guard-init.sh` applies four project-root-anchored deny rules (`auth/`, `api/`, `payments/`, `lib/shared/`) to one repo's `.claude/settings.json`, and removes the unanchored rules an earlier draft wrote.
  - `session-open.sh`, `session-close.sh`, `session-claim.sh`: `/build` and `/wrap` bind and close the marker through these. Opening a new build archives the previous build's artefacts (nothing is deleted) to `.atelier/archive/<timestamp>-<branch>/`, so an old build can't satisfy the gates. The gates read nothing under `archive/`.
  - `run-tests.sh <command>` runs the test command and records `.atelier/tests.json`.
  - PreToolUse hooks fail closed if their script goes missing. The Stop hook and fast gate fail open.
- `guardrails/install.sh --enforce` and `--relax` (not both). With no flag it behaves as before. Their backups carry their own label (`-guardrails-enforce`, `-guardrails-relax`). `lane-guard-init.sh` names its backup `-lane-guard`.
- `guardrails/VETTING.md`: read every script before installing any third-party skill, mod or MCP server.
- `packaging/tests/retire-check.sh`: fails if `commands/` still mentions the Decision Log, a debrief, `update_doc`, a token budget, `figma_execute`, `next-session-starter` or consolidation, if a design command refers to memory files, or if `eames.md` or `rand.md` does not point at `~/.claude/atelier/taste.md`.
- A `wrap:<yyyy-mm-dd>` source tag (optionally ` finding <n>` or ` assumption A<n>`) for contract items born from a `/wrap` verdict. The taste-review check accepts it and still rejects free text.
- Tests: `guardrails/tests/run.sh` (hook fixtures, installer, lane init, session scripts, loop gaps), `agents/tests/check.sh`, all run against temp directories.
- `setup.sh` links `agents/builder.md` and `agents/critic.md` into `~/.claude/agents/` file by file, beside whatever is there. A link that already points at the right file is left alone, and a real file or a link elsewhere is skipped with a warning. Like the other links, it skips this from a git worktree. It also runs the render harness install (`npm install` and a Chromium download inside `render/` only) when `npm` exists, and prints the two commands to run otherwise. Before it starts, it announces the download (about 150MB) and the `--no-render` flag that skips it; it does not prompt or wait.

### Changed

- The three design commands name the contract files (`taste.md`, `conventions.md`, `quality.md`) and point at `/wrap` for session close. Figma write guidance in `/eames` and `/rand` names the Figma MCP `use_figma` tool in place of `figma_execute`.
- Packaging for claude.ai now translates `commands/eames.md` and `commands/rand.md` instead of copying them. The Contract files sentence names `taste.md` and `conventions.md` as bare file names, the `quality.md` mention is stripped (it is the bar for the Claude Code build loop and is not bundled), and the Closing a Session section, the trailing `$ARGUMENTS` section and the `figma-use` line are dropped. The bundled `taste.md` and `conventions.md` are copies minus the sentence "Every item is a draft until `/taste-review` approves it.". Re-upload `dist/eames.zip` and `dist/rand.zip` (rebuild with `bash packaging/build.sh`) to pick this up; each zip still holds exactly `SKILL.md`, `taste.md` and `conventions.md`. The build fails with a clear message if a translation finds nothing to change or a built file still holds `~/.claude/`, `figma-use`, `.atelier/session.json`, `$ARGUMENTS` or a Claude Code slash command. `packaging/tests/check.sh` asserts all of it, including negative builds.
- The five benchmark tickets now fit the proving ground host. No ticket asks for a hosted preview URL: the render shots under `.atelier/renders/<slug>/` (every state, light and dark, at 375, 768 and 1280), listed or linked in the PR description, are the preview. Each ticket says how its Playwright e2e test is met through the host's own e2e script, and that the feature ships behind a flag read with `isEnabled` from the host's `lib/flags.ts`. With the flag off, a ticket that changes an existing screen leaves that screen exactly as it was, and a ticket that adds something new renders nothing of it. Tickets 01 (settings form), 02 (inventory table) and 05 (notification preferences) are rewritten as changes to existing screens, so every acceptance criterion is something the screen does not already do.
- `quality.md` G4 says `.atelier/tests.json` is recorded by `run-tests.sh`, never written by hand. G9 counts source lines only (tests, stories and fixtures don't count), accepts the render shots as the preview until preview deployments arrive, and adds the flag-off rule. IDs, order and format are unchanged. `agents/builder.md` and `commands/build.md` report source lines and total lines.

### Removed

- Session Debrief Protocol, entry format and consolidation pass from `commands/design-director.md`.
- Session Debrief sections from `commands/eames.md` and `commands/rand.md`.
- Session-start memory reads and the 25-entry consolidation prompt from all three commands.

### What's next

- v2.0.x: the remaining four benchmark tickets run through the loop, a Critic calibration run against the seeded defects, and the owner's `/taste-review` of the draft rules.
- v2.1 (planned): hosted preview deployments, a feature-flag provider, and a `NEXT.md` handoff note written by `/wrap` (where the session stopped, the first command for next time, any open question).

## [1.2.1] - 2026-11-18

This release fixes how `setup.sh` backs up your settings. Nothing new is installed.

### Fixed

- `setup.sh` could lose the backup of your original `~/.claude/settings.json`. It edits that file in two steps, and each step saved a backup named with the time down to the second. When both steps ran in the same second, the second backup replaced the first, so the newest backup was the file as it stood halfway through setup, not as you had it before.
- Now no backup ever replaces another one. Each step puts its own label on the end of the name, and if a name is somehow taken, a number is added (`-2`, `-3`). The names look like this:
  - `settings.json.bak.20261118-101530-aurora-mods` (the step that wires in the Aurora billboard and Sketchpad)
  - `settings.json.bak.20261118-101530-guardrails` (the guardrails step; `settings.local.json` gets the same label)
  - `commands.bak.<date>-<time>-commands` and `.dev-aliases.sh.bak.<date>-<time>-aliases` for the two other things `setup.sh` can move aside
- Every backup still starts with `.bak.` and the date and time, so the undo commands from 1.1.0 work as written.
- `setup.sh` prints each backup path as it makes it. At the end it lists, under "Your files as they were before this run", the backup that holds each file as it was before the run.
- Restoring one of those backups puts back that file's contents only. For `commands` and `.dev-aliases.sh`, which are links into the repo after setup, remove the link first and then move the backup back.
- Running `guardrails/install.sh` on its own uses the same names and prints the backup path for each file it changes. The end-of-run list is only printed by `setup.sh`.
- If a backup can't be made, the file is left untouched. `setup.sh` skips that step and lists it at the end, and `guardrails/install.sh` stops with an error.
- What gets installed has not changed.

## [1.2.0] - 2026-11-18

Everything in this release is opt-in. Nothing changes how Claude Code behaves unless you use it.

### Added

- `failures.md`: 24 known traps, each with the trap, how it shows up and what to do instead, all marked draft until reviewed.
- `templates/SPEC.md`: the SPEC template with the eight contract headings, the standard states and the four protected paths.
- `spec` skill (`skills/spec/`): an interview that refuses to write a SPEC.md while acceptance criteria or states are missing, then writes it into the current repo. It runs only when you type `/spec`, ask for a spec in so many words, or Eames hands off to it. It does not start on its own.
- `taste-review` skill (`skills/taste-review/`): reviews every draft item one at a time, keeps its state on a long-lived `taste-review` branch, and finishes with one pull request. Ships `taste-review/state.json` with every item pending. It runs only when you type `/taste-review` or ask for a taste review, never on its own.
- `setup.sh` links `skills/spec` and `skills/taste-review` into `~/.claude/skills/` one folder at a time, beside whatever is already there. A real folder or a link to somewhere else with the same name is left alone with a warning. Like the `~/.claude/atelier` link, it skips this from a git worktree. Linking makes `/spec` and `/taste-review` available in every session, and both run only when asked.
- `packaging/build.sh`: builds `dist/eames.zip` and `dist/rand.zip` as claude.ai skill uploads. Each zip holds one folder with `SKILL.md`, `taste.md` and `conventions.md`, and two runs give identical bytes. `dist/` is git-ignored.
- `packaging/tests/check.sh`: checks the model frontmatter on the three commands, the zip contents and build determinism.
- `evals/tickets/`: five standing benchmark tickets (settings form, data table, onboarding, destructive confirm, notification preferences), each a SPEC in the gear desk domain.
- `evals/metrics/`: a JSON Schema for one row per benchmark run, a sample row and an empty append-only log. Each row records the first-try CI result, invented components, axe violations, the Critic's score (the Critic arrives in a later release), review minutes, how many Critic findings were agreed, plus `cost_usd` (an estimate) and `accepted` (whether the PR merged). Cost per accepted PR is derived from those two fields, not stored; runs that were not accepted keep their cost in the total.
- `evals/calibration/`: fifteen seeded defects across gates G1 to G10 and principles P1 to P5, each tagged `critic-screenshot` (6), `critic-diff` (5) or `script` (4), so the Critic's recall, once the Critic exists in a later release, is measured over the 11 it can see. Three decoys (`X01` to `X03`) that look wrong but aren't, to measure noise. A scoring sheet (`SCORING.md`) with the matching rule and the recall and precision formulas.
- `evals/tests/check.sh`: stdlib-only checks for the tickets, the metrics schema and the calibration set.

## [1.1.0] - 2026-11-18

### Added

- `quality.md`: ten production-grade gates (G1 to G10) with checkable pass bars, and five design principles (P1 to P5).
- `taste.md`: numbered judgment items, each source-tagged and marked draft until reviewed.
- `conventions.md`: numbered literal standards, each with a yes/no Check line and marked draft until reviewed.
- `global/CLAUDE.md`: shared rules for the Atelier agents (verb ownership, ask vs ship and the contract files). Import it from your own CLAUDE.md with one `@` line; personal rules stay in your own file.
- `setup.sh` links `~/.claude/atelier` to the main checkout (it skips this from a git worktree), so agents and commands can reach Atelier's files from any repo. It also gains a helper that links single files or folders into `~/.claude/agents/` and `~/.claude/skills/` beside whatever is already there; nothing calls it yet.
- `model: opus` frontmatter on `commands/design-director.md`, `commands/eames.md` and `commands/rand.md`. It routes the turn that runs the command, not the rest of the conversation.
- Network guardrail (`guardrails/net-host-guard.py`): a PreToolUse hook on Bash that parses the real host of every curl/wget URL and asks unless it's `localhost`, `127.0.0.1`, `[::1]` or a `*.trycloudflare.com` quick tunnel. It also asks on variables, scheme-less targets and flags that reroute traffic (`--proxy`, `--resolve`, `--connect-to`, `-K`, wget `-e`/`-i`). It never approves anything, and blocks if the script is missing or crashes.
- Host-scoped curl allow rules in user scope (`guardrails/permissions-allow.json`), and `pip3 install` as an ask rule.
- Guardrails (`guardrails/`): user-scope `permissions.ask` rules for destructive commands (`rm`, force pushes, `git reset --hard`, `git clean`, `git branch -D`, `git restore`, `git checkout --`, stash drop/clear, `find -delete`), plus a PreToolUse hook that asks before Write, Edit or NotebookEdit touch anything outside the current git repo or worktree. Claude's own scratchpad is exempt. If the hook script goes missing, writes are blocked instead of slipping through. `setup.sh` merges both into `~/.claude/settings.json` without touching other keys.
- Aurora threshold profiles: `aurora profile [name]` switches between `default` (today's lines) and `fable-run` (5h 70/85, 7d 45/75, and a 7d note: "Fable cap may be near: check /usage"). Profiles live in `aurora-usage/profiles.json`, and `setup.sh` links `aurora` into `~/.local/bin`.

### Changed

- **Behaviour change for anyone who runs `setup.sh`:** the network hook is a `python3` script, so if `python3` is missing, every Bash tool call is blocked until you install it or remove the hook. The message shown is "Atelier network guardrail failed, so this is blocked. Check python3, or re-run guardrails/install.sh". `setup.sh` now also edits `~/.claude/settings.json`:
  - It adds ask rules for destructive commands, a few allow rules for curl to local hosts only, and two PreToolUse hooks: one for writes outside the current repo (blocks if its script is missing), and the network hook for curl or wget to hosts that are not local.
  - It removes the broad allow rules listed in `guardrails/permissions-retired.json` from `~/.claude/settings.json`, and from `~/.claude/settings.local.json` along with any rule that now lives in user scope.
  - A file is backed up only when it actually changes, beside the original, as `<file>.bak.YYYYmmdd-HHMMSS`. No backup means that file was not changed.
  - To undo, restore the newest backup, then start a new Claude Code session:

    ```bash
    ls -t ~/.claude/settings.json.bak.* | head -1
    cp "$(ls -t ~/.claude/settings.json.bak.* | head -1)" ~/.claude/settings.json
    # only if a settings.local.json backup exists:
    cp "$(ls -t ~/.claude/settings.local.json.bak.* | head -1)" ~/.claude/settings.local.json
    ```

    Open the backup first: if it still mentions `net-host-guard`, take the next one down (it came from a later re-run). Restoring puts back the permission rules and hooks only. The symlinks `setup.sh` made (`~/.claude/commands`, `~/.claude/atelier`, `~/.dev-aliases.sh`, `~/.local/bin/aurora`) and the Aurora and Sketchpad entry in `env.CLAUDE_CODE_PLUGIN_DIRS` stay.
- `guardrails/install.sh` now also removes retired rules (`guardrails/permissions-retired.json`: `Bash(curl:*)`, the broad python3 allows, `Bash(cloudflared tunnel *)`) and clears rules that moved to user scope out of `~/.claude/settings.local.json`, which only applies to sessions started from `~`.
- Aurora pause points: past one, the band and the HUD say `⏸ Time to stop` in words, a stop toast fires once, and snoozes or an Off line can't hide it.

## [1.0.1] - 2026-11-17

### Added

- MIT license.

### Changed

- Renamed the repo from `bernardo-claude-config` to `Atelier`. The old GitHub URL redirects, and the local checkout folder keeps its name so existing symlinks still resolve.

## [1.0.0] - 2026-11-17

### Added

#### Agents

- `/design-director` router that shows a triage card (how Eames and Rand would each approach the brief) and lets you pick the lead lens.
- `/eames` product design specialist: components, states, edge cases, flows, engineering handoff, with a 7-phase process and five design principles.
- `/rand` brand design specialist: brand styling framework, multi-brand "cartridges" loaded from Figma, default palette fallback.
- Cross-discipline awareness: Eames surfaces brand questions, Rand respects interaction states and engineering limits.
- Session debrief protocol: agents propose learnings, you approve which ones get saved to memory, tagged by agent.
- Consolidation pass that rolls the decision log into evolved principles at about 30 entries.
- Output format guidance per agent (Markdown, SVG, React, HTML), with diagrams defaulting to HTML.

#### Dev tooling

- `cc` wrapper: brings the dev server and a Cloudflare tunnel up, launches Claude Code, tears both down on `/exit`. Works with `--resume` and `--continue`.
- `devup` / `devdown` / `tunnel` for starting, stopping and printing the preview stack by port.
- Port auto-detection from `package.json` (3000 for Next, 5173 for Vite, 8000 for static).
- Tunnels always run over `--protocol http2`, detached and PID-tracked so teardown never touches another project's tunnel.
- Tunnel dials whichever loopback (`127.0.0.1` or `::1`) the server answers on.
- Public URL copied to the clipboard and opened in the browser; `DEV_OPEN=local|none` to change that.
- Static mode serves both loopbacks, 404s dotfiles, refuses to serve `$HOME`, warns on `.env`.
- `setup.sh` idempotent installer: symlinks commands and aliases, wires `.zshrc`, merges mod dirs into `settings.json`, builds the HUD, backs up anything it replaces.
- Multi-machine sync: everything is symlinked or loaded from the repo, so `git pull` updates every machine.

#### Status line and usage

- Aurora billboard mod: one thin line above the prompt with 5h and 7d plan limits, reset countdowns, model context fill and session cost.
- Position-colored bar cells and `/billboard` themes (aurora, ember, tide, mono) plus block bars.
- Low-fuel behavior: limits stay hidden until one crosses its own line (5h at 75%, 7d at 90%), adjustable with `/billboard show`.
- Snoozing with `/billboard hide`, toasts at the line and at 95%, `⚡ using credits` past 100%.
- Width-aware layout that drops segments on narrow windows.
- Aurora HUD: native macOS floating panel (one Swift file, AppKit only) that shows while the Claude desktop app is open.
- HUD refresh button, collapsible pill, right-click menu for lines, theme and snoozes, starts at login.
- Shared `~/.claude/aurora-usage.json` keeps the billboard and HUD in agreement. No network calls, no login token, no third-party code.
- Replaces the earlier `statusline.sh`; `setup.sh` removes the old link and settings entry.

#### Sketchpad

- `/sketch` side conversation docked next to the session for shaping a prompt before it hits the build.
- Refine turns the sketch into a structured prompt; Send to prompt drops it in the prompt box.
- Model switcher (Sonnet, Opus, Haiku) and an optional read-only view of the build session.

[2.0.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v2.0.0
[1.2.1]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.2.1
[1.2.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.2.0
[1.1.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.1.0
[1.0.1]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.1
[1.0.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.0
