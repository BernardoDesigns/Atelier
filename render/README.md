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
- `setup` (optional) runs in order after load, before axe and the screenshot. Each step has exactly one key: `{"click": "<css>"}`, `{"fill": ["<css>", "<value>"]}`, `{"wait": <ms 0..30000>}`. A step that fails marks the target's shots `error`. A `click` that opens something animated may need a `{"wait"}` after it (transitions and animations are switched off before the shot, but content a script mounts late is not awaited).
- Themes `light`, `dark`; breakpoints `sm` 375, `md` 768, `lg` 1280 (height 800, full page). Dark sets `colorScheme: 'dark'`, a `dark` class and `data-theme="dark"` on `<html>`; light sets `data-theme="light"`. The markers go on `<html>` as soon as it exists, before page scripts run, and are re-applied after setup. Before the shot, transitions and animations are disabled and the page waits for network idle (2s cap, never fails a shot).

## Commands
```
node render/cli.mjs [--plan .atelier/render-plan.json] [--out .atelier/renders] [--fixtures-dir <dir>]
node render/cli.mjs storybook --index <storybook-static/index.json | http://localhost:6006/index.json> \
     --base-url <url> --slug <slug> [--out .atelier/render-plan.json] [--include <glob>]... [--exclude <glob>]...
```
`storybook` keeps `type: "story"` entries (docs dropped), filters on story id (`*` and `?` globs), and writes targets with `state` = slugged id and `url` = `/iframe.html?id=<id>&viewMode=story`. An http index must be on localhost and is fetched without following redirects.
Targets whose path ends in `iframe.html` (Storybook frames) also wait for `#storybook-root > *` and for `sb-show-preparing-story` to clear; if the story never renders within 10s (`ATELIER_RENDER_STORY_TIMEOUT_MS` overrides) the shot is `error`, not `ok`.
`--out` must be relative with no `..` in both commands unless `--allow-outside` is passed.

## Output
```
.atelier/renders/<slug>/<state>.<theme>.<bp>.png
.atelier/renders/<slug>/manifest.json
.atelier/renders/<slug>/axe.json
```
`manifest.json`: `{ "slug", "baseUrl", "generatedAt": "<ISO>", "shots": [ { "state", "theme", "bp", "path": "<state>.<theme>.<bp>.png" (relative to this folder), "status": "ok" | "missing" | "error", "error"?: "<reason>" } ], "axe": { "minor", "moderate", "serious", "critical" } }`. Every target gets 6 shot entries. `missing`: navigation failed or HTTP >= 400 (no PNG written). `error`: setup or axe threw (no PNG).

`axe.json`: `{ "slug", "shots": [ { "state", "theme", "bp", "violations": [ { "id", "impact": "minor|moderate|serious|critical", "help", "nodes": <count> } ] } ], "totals": { "minor", "moderate", "serious", "critical" } }`. Only shots that loaded are listed. `manifest.axe` equals `totals`. Both files are written even when the run fails.

## Exit codes
- `0` ok (some missing targets are reported in the manifest, not failed)
- `1` axe found serious or critical violations; stdout has one `FAIL <state>.<theme>.<bp>: <rule id> (<impact>)` line per violation
- `2` usage error, bad plan, nothing answering at the base URL (one stderr line starting `Nothing answering at <baseUrl>`), no shot rendered `ok` (manifest and axe.json are still written), or the run could not complete

## Reruns
At the start of a run, `*.png`, `manifest.json` and `axe.json` inside that one slug folder are deleted, so a renamed or dropped state never leaves a stale PNG beside the new manifest. Nothing else is touched.

## Fixtures and tests
`--fixtures-dir` answers every request to the base URL's origin from that folder through Playwright route interception (`/` maps to `index.html`, a missing file is a 404, other origins are blocked). No port is opened and the base URL probe is skipped, so the host can be a made-up one like `http://fixture.test`.
`cd render && npm test` runs all specs in `tests/`; fixtures live in `tests/fixtures/`.
