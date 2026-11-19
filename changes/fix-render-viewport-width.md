## Changelog

### Fixed

- The render harness now shoots at exactly the requested width. When a page overflowed horizontally, `fullPage: true` made the PNG as wide as the document's scroll width: a 731px table in a 375px viewport produced a 731px image labelled `sm`, and nothing in the manifest said so. Shots are now clipped to the viewport width (375, 768 or 1280) at full document height; a page shorter than 800px still gives an 800px image.

### Added

- Overflow is reported as a fact. Each shot that was taken carries `"overflowX": <px beyond the viewport, 0 when none>` in `manifest.json` (1px or less counts as 0), plus `"overflowBy": "<tag#id.class[data-slot]>"` naming the element that reaches furthest past the viewport when there is one. The manifest has a top-level `"overflow"` count next to `axe`. Each overflowing shot prints `OVERFLOW <state>.<theme>.<bp>: page is <n>px wider than <width>` on stdout. Exit codes are unchanged: overflow is information for the Critic, not a failure.

## README

`render/README.md` documents the clipped screenshot mode and the new manifest fields (`overflowX`, `overflowBy`, `overflow`).

For Storybook stories: a story of a wide component should not use `layout: "centered"` if you want to see how it behaves in a narrow container, because a centred story root shrinks to its content.

## Setup

None. Existing manifests keep working; consumers that read `manifest.json` can ignore the new fields.
