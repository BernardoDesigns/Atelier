## Changelog

- Added `render/`, a self-contained render harness. It reads `.atelier/render-plan.json` and writes every target x 2 themes x 3 breakpoints as PNGs, plus `manifest.json` and `axe.json`, under `.atelier/renders/<slug>/`.
- Runs axe on every shot and exits 1 when any serious or critical violation exists, naming the shot.
- Added a `storybook` subcommand that turns a Storybook `index.json` into a render plan.
- Each run clears the previous PNGs, manifest and axe.json in its own slug folder, so stale renders never sit beside a new manifest.
- The harness never starts a server. With nothing at the base URL it exits 2 with one line.

## README

| Path | What |
|---|---|
| `render/` | Render harness. `node render/cli.mjs --plan .atelier/render-plan.json` screenshots every target in light and dark at 375, 768 and 1280, runs axe, and writes the manifest. Exit 0 ok, 1 axe failure, 2 usage, nothing at the base URL, or no shot rendered ok. Details in `render/README.md`. |

## Setup

`cd render && npm install && npx playwright install chromium`. Installs into `render/` only.
