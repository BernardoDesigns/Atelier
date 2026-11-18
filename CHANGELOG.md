# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[1.1.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.1.0
[1.0.1]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.1
[1.0.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.0
