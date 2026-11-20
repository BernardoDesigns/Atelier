# MCP servers

The MCP servers Claude Code installs locally, versioned here so every machine gets the same set at the same versions. `setup.sh` runs the installer; you can also run it on its own.

```bash
bash mcp/install.sh            # install and register everything in servers.json
bash mcp/install.sh --dry-run  # preview, change nothing
bash mcp/tests/check.sh        # tests, against stubs and a temp HOME
```

## Three kinds of MCP, and which ones live here

| Kind | Where it's installed | Synced how |
|---|---|---|
| Claude Code local servers (Awwwards) | npm global + `claude mcp add -s user` | **This folder.** `servers.json` + `install.sh` |
| claude.ai connectors (Mobbin, Muzli, Figma and the rest) | Your claude.ai account | Already follow you to every machine once you sign in. Nothing to version |
| Claude Desktop extensions (Filesystem, Control Chrome, Apple Notes) | Claude Desktop, Settings, Extensions | Installed through the app, one click per machine. Listed here so a new machine doesn't miss one |

## What `install.sh` does, per server

1. Checks the Node version against `minNode`.
2. `npm install -g` the pinned packages, allowing install scripts only for the packages named in `allowScripts` (ffmpeg-static needs its script to download ffmpeg).
3. Runs any `postInstall` commands (the Chromium download for live captures).
4. Registers the server with Claude Code at **user scope**, so it works in every project, not just the folder you happened to be in. A registration that already matches is left alone, one that differs is replaced.
5. Installs companion skills from a pinned tag into `~/.claude/skills/`.
6. Copies the versioned preferences, only if the machine has none. It never overwrites preferences you changed locally.

A server that fails is reported and the rest still install. `setup.sh` never fails because of this step.

## Adding a server

1. Vet it first. Follow `guardrails/VETTING.md`: read every script, list its tools, check what it writes and where.
2. Add an entry to `servers.json`. Pin every package to `x.y.z` and the skills to a tag (`/tree/<tag>`). The tests fail on anything unpinned.
3. `bash mcp/tests/check.sh`, then `bash mcp/install.sh --dry-run`, then `bash mcp/install.sh`.

**No secrets in this folder.** The repo is public. A server that needs an API key reads it from your shell environment or the keychain, never from `servers.json`.

## Updating a server

Bump the versions in `servers.json` only after re-vetting (a clean v1 says nothing about v2), then re-run `bash mcp/install.sh` on each machine. The Awwwards server can also self-update with `AWWWARDS_AUTO_UPDATE=1`; leave that off here so the pinned version stays the one that was vetted.

## Awwwards notes

- Preferences live in `awwwards/preferences.json`: full results, desktop viewport, captures on, local index on.
- The local index (`~/.awwwards-mcp/cache.db`) is per machine and not versioned. The server builds it in the background on first use and refreshes it weekly. To build it right away: `awwwards-index`.
- If the index says "another index run is in progress" and nothing is running, a killed run left its lock behind. Use the `awwwards-doctor` skill rather than deleting the cache.
