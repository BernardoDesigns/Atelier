# render

Screenshots every target of a render plan at 2 themes x 3 breakpoints, runs axe on each shot, writes a manifest. It never starts a server: it takes a base URL that something else is already serving.

Install (self-contained, touches nothing outside `render/`):
`cd render && npm install && npx playwright install chromium`

## Render plan
`.atelier/render-plan.json`
```json
{ "baseUrl": "http://localhost:6006", "slug": "button",
  "targets": [ { "state": "default", "url": "/iframe.html?id=button--primary&viewMode=story",
                 "setup": [ { "click": "#open" }, { "fill": ["#name", "Ada"] }, { "wait": 200 } ] } ] }
```
- `slug`: letters, digits, `-`, `_`. `state`: file-name-safe after slugging (anything else becomes `-`, dots included); unique per plan.
- `setup` (optional) runs in order after load, before axe and the screenshot. Each step has exactly one key: `{"click": "<css>"}`, `{"fill": ["<css>", "<value>"]}`, `{"wait": <ms 0..30000>}`. A step that fails marks the target's shots `error`.
- Themes `light`, `dark`; breakpoints `sm` 375, `md` 768, `lg` 1280 (height 800, full page). Dark sets `colorScheme: 'dark'`, a `dark` class and `data-theme="dark"` on `<html>`; light sets `data-theme="light"`.

## Commands
```
node render/cli.mjs [--plan .atelier/render-plan.json] [--out .atelier/renders] [--fixtures-dir <dir>]
node render/cli.mjs storybook --index <storybook-static/index.json | http://localhost:6006/index.json> \
     --base-url <url> --slug <slug> [--out .atelier/render-plan.json] [--include <glob>]... [--exclude <glob>]...
```
`storybook` keeps `type: "story"` entries (docs dropped), filters on story id (`*` and `?` globs), and writes targets with `state` = slugged id and `url` = `/iframe.html?id=<id>&viewMode=story`. An http index must be on localhost.

## Output
```
.atelier/renders/<slug>/<state>.<theme>.<bp>.png
.atelier/renders/<slug>/manifest.json
.atelier/renders/<slug>/axe.json
```
`manifest.json`: `{ "slug", "baseUrl", "generatedAt": "<ISO>", "shots": [ { "state", "theme", "bp", "path": "<state>.<theme>.<bp>.png" (relative to this folder), "status": "ok" | "missing" | "error", "error"?: "<reason>" } ], "axe": { "minor", "moderate", "serious", "critical" } }`. Every target gets 6 shot entries. `missing`: navigation failed or HTTP >= 400 (no PNG written). `error`: setup or axe threw (no PNG).

`axe.json`: `{ "slug", "shots": [ { "state", "theme", "bp", "violations": [ { "id", "impact": "minor|moderate|serious|critical", "help", "nodes": <count> } ] } ], "totals": { "minor", "moderate", "serious", "critical" } }`. Only shots that loaded are listed. `manifest.axe` equals `totals`. Both files are written even when the run fails.

## Exit codes
- `0` ok (missing targets are reported in the manifest, not failed)
- `1` axe found serious or critical violations; stdout has one `FAIL <state>.<theme>.<bp>: <rule id> (<impact>)` line per violation
- `2` usage error, bad plan, nothing answering at the base URL (one stderr line starting `Nothing answering at <baseUrl>`), or the run could not complete

## Fixtures and tests
`--fixtures-dir` answers every request to the base URL's origin from that folder through Playwright route interception (`/` maps to `index.html`, a missing file is a 404, other origins are blocked). No port is opened and the base URL probe is skipped, so the host can be a made-up one like `http://fixture.test`.
`cd render && npm test` runs all specs in `tests/`; fixtures live in `tests/fixtures/`.
