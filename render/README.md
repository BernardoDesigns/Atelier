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
- `setup` (optional) runs in order after load, before axe and the screenshot. Each step has exactly one key: `{"click": "<css>"}`, `{"fill": ["<css>", "<value>"]}`, `{"hover": "<css>"}`, `{"wait": <ms 0..30000>}`. A step that fails marks the target's shots `error`. A `click` that opens something animated may need a `{"wait"}` after it (transitions and animations are switched off before the shot, but content a script mounts late is not awaited).
- Themes `light`, `dark`; breakpoints `sm` 375, `md` 768, `lg` 1280 (height 800). Each context is created with that viewport before navigation, so the page lays out at the right width from the first paint (nothing is resized afterwards). Every shot sets `colorScheme` emulation and `data-theme="<theme>"` on `<html>`.
- Theme on plain app URLs: also a `dark` class on `<html>` (light removes it), put there as soon as `<html>` exists, before page scripts run, and re-applied after setup.
- Theme on Storybook frames (path ends in `iframe.html`): the harness does not touch the `dark` class, because `withThemeByClassName` strips an externally set class on mount, story switch and theme change. It loads `iframe.html?id=<story>&viewMode=story&globals=theme:dark` (`theme:light` for light; other globals already in the URL are kept) and, after the story finishes rendering and again right before the shot, asserts `document.documentElement.classList.contains('dark')` matches. A mismatch (for example story-level `globals` overriding the URL global) marks the shot `error` with `Theme mismatch: requested dark but ...`; it is never shot silently.
- Screenshot mode is full page, at the viewport width. A page that fits in 800px gives an 800px-tall PNG, so a `position: fixed; height: 100vh` overlay or sheet is captured as exactly one viewport tall. On a longer page Chromium keeps fixed elements at viewport size at the top rather than stretching them; a fixed bar therefore shows once, at the top.
- The harness never clicks and never presses the mouse button before shooting, so `:focus-visible` from a Focus story's play function survives. Only an explicit `{"click"}` setup step clicks.
- Hover: a real pointer move (`:hover` applies; Storybook's `userEvent.hover` is synthetic and does not trigger it). Order of choice: a `{"hover": "<css>"}` setup step; else a Storybook story's `parameters.harness.hover` (a selector string, or `true` for the first interactive element), read from the live preview; else, when the state name contains `hover` or `hovered` as a `-`/`_` separated word, the first interactive element (`a[href]`, enabled `button`/`input`/`select`/`textarea`, `summary`, `[role=button|link|tab|menuitem]`, focusable `[tabindex]`), looked up inside `#storybook-root` first. If a hover is requested and nothing matches, the shot is `error`.
- Timing on Storybook frames: besides the story content check below, the harness waits for the preview's render phase to reach `completed` (after play functions) and fails the shot with `error` if the phase is `errored` (play function or render threw) or does not finish within the story timeout. Order: finished phase, theme check, setup, hover, animations off, theme check, shot, axe. Transitions and animations are switched off only after the finished phase. The page also waits for network idle (2s cap, never fails a shot).

## Commands
```
node render/cli.mjs [--plan .atelier/render-plan.json] [--out .atelier/renders] [--fixtures-dir <dir>]
node render/cli.mjs storybook --index <storybook-static/index.json | http://localhost:6006/index.json> \
     --base-url <url> --slug <slug> [--out .atelier/render-plan.json] [--include <glob>]... [--exclude <glob>]...
```
`storybook` reads the Storybook 10 index shape `{"v":5,"entries":{"<id>":{type,subtype,id,title,name,importPath,componentPath,tags,exportName}}}`. It keeps `type: "story"` entries, drops `type: "docs"` and `subtype: "test"` (component tests that re-render their parent story), filters on story id (`*` and `?` globs), and writes targets with `state` = slugged id and `url` = `/iframe.html?id=<id>&viewMode=story`. An http index must be on localhost and is fetched without following redirects.
Targets whose path ends in `iframe.html` (Storybook frames) also wait for story content (rule below); if the story never renders within 10s (`ATELIER_RENDER_STORY_TIMEOUT_MS` overrides) the shot is `error`, not `ok`.
A story counts as rendered when `#storybook-root` has a child element, or `<body>` has a direct child that is not `#storybook-root`/`#storybook-docs`, a script/style/link, or an `sb-` wrapper (portal-only dialogs and toasts); `sb-show-preparing-story` and `sb-show-preparing-docs` must also be gone.
Pages run with CSP bypassed (the harness injects a style that disables animations). The out dir and slug folder must not be symbolic links (exit 2).
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
