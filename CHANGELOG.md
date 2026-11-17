# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-11-17

### Added

- MIT license.

### Changed

- Renamed the repo from `bernardo-claude-config` to `atelier`. The old GitHub URL redirects, and the local checkout folder keeps its name so existing symlinks still resolve.

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

[1.0.1]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.1
[1.0.0]: https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.0
