# Conventions

Literal standards. Each item is one rule with an exact value or pattern, and a Check line a reviewer can answer yes or no. `taste.md` holds the judgment calls.

Every item is a draft until `/taste-review` approves it.

### C1
Prose that carries a live count has separate phrasings for many, one and zero. At zero, the whole clause is rewritten, including its lead-in, instead of swapping the digit.
Source: log:A4
Check: Does every sentence with a live count have distinct many, one and zero phrasings, with zero rewriting the lead-in?
Status: draft

### C2
When a section only matters if it is included, one switch controls both inclusion and disclosure.
Source: log:A8
Check: Is there a single control for include-and-open, with no reachable open-but-excluded state?
Status: draft

### C3
When a scroll target cannot be reached, add exactly the missing scroll length for that action and remove it when the action is undone. No permanent spacer.
Source: log:A12
Check: Is the extra scroll room added per action and removed on undo, rather than a permanent spacer?
Status: draft

### C4
In a segmented control, the default option is the first segment.
Source: log:A13
Check: Is the default the first segment in every segmented control?
Status: draft

### C5
An ambient gauge stays hidden until it crosses its own per-signal threshold, set by how fast that signal moves. A limit with a 5-hour window shows at 75%. A limit with a 7-day window shows at 90%.
Source: log:A16
Check: Is the gauge hidden below its own per-signal threshold, with no shared line across signals of different speed?
Status: draft

### C6
A treatment that spans a region edge to edge is its own fixed or absolute layer sized to the viewport, not a `::before` trapped by the container's padding.
Source: log:E3
Check: Is each edge-to-edge treatment a separate fixed or absolute layer sized to the viewport?
Status: draft

### C7
Over a backdrop whose color is not fixed, content fades with `mask-image`, not a gradient painted in the background color.
Source: log:E3
Check: Do fades over a variable backdrop use `mask-image` rather than a background-colored gradient?
Status: draft

### C8
A tooltip branches on `pointerType`. A mouse hovers (`pointerenter` and `pointerleave`). Touch and pen tap-toggle on `pointerdown`.
Source: log:E4
Check: Does the tooltip branch on `pointerType`, with mouse on hover and touch and pen on `pointerdown` toggle?
Status: draft
Verify: that Radix Tooltip is still hover and focus only, which is why a hover-and-tap tooltip is custom, and whether the call against Floating UI still holds.

### C9
The tooltip bubble is `pointer-events: none`, switching to `auto` only under `pointer:coarse`, so it never blocks desktop hover.
Source: log:E4
Check: Is the bubble `pointer-events: none` except under `pointer:coarse`?
Status: draft

### C10
The tooltip caret is anchored to the trigger, and the bubble is positioned independently of it.
Source: log:E4
Check: Is the caret positioned from the trigger while the bubble has its own position?
Status: draft

### C11
When the border is the only selection signal, the selected state uses a 2px saturated border. A color change on a 1px translucent border reads as ambient.
Source: log:E7
Check: Is a border-only selected state 2px and saturated?
Status: draft

### C12
A persistent selected state layers `ring-1` over the 1px border instead of switching to `border-2`, which shifts content each cycle.
Source: log:E7
Check: Does the selected state use `ring-1` over a 1px border, with no switch to `border-2`?
Status: draft

### C13
Tap targets smaller than 44px grow to 44px using `p-2` and `-m-2`, so layout does not move.
Source: log:E7
Check: Is every tap target at least 44px, grown with `p-2` and `-m-2`?
Status: draft

### C14
Touch swipes record the start point, judge the whole gesture once at `pointerup`, and set `touch-action: pan-y`.
Source: log:E7
Check: Is each swipe judged once at `pointerup`, with `touch-action: pan-y` set?
Status: draft

### C15
Trackpad swipes use a module-level lock that engages before the DOM swap and releases when wheel events go silent, not on a fixed cooldown, because momentum runs 300 to 600ms.
Source: log:E7
Check: Does the trackpad lock engage before the DOM swap and release on wheel silence rather than a timer?
Status: draft
Verify: trackpad momentum timing and `pointercancel` behavior on current browsers.

### C16
Fitted layouts are sized with `svh`, never `dvh` or `vh`, plus `env(safe-area-inset-bottom)`.
Source: log:E8, log:A10
Check: Are fitted layouts sized in `svh` with `env(safe-area-inset-bottom)`, and no `dvh` or `vh`?
Status: draft
Verify: `svh`, `dvh` and browser-bar behavior on current mobile browsers.

### C17
Height-driven layouts are tested at the visible viewport height, not the screen height. Browser bars can take about 20% of a phone, so a layout that works at 844 can fail at 664.
Source: log:E8, log:A10
Check: Was each height-driven layout tested at the visible viewport height, for example 664 on an 844 phone?
Status: draft

### C18
When content is bounded to the viewport height, the visual is the flex-shrink target and the controls are `shrink-0`.
Source: log:E8
Check: Is the visual the shrinking item and every control `shrink-0`?
Status: draft

### C19
Width responds through container queries and height responds through `min-height` media queries. The two axes are kept separate.
Source: log:E8
Check: Do width changes use container queries and height changes use `min-height` media queries?
Status: draft

### C20
Body text on content-led pages spans the main container. A second `ch` max-width double-constrains it.
Source: log:E8
Check: Is body text free of a `ch` max-width inside the main container?
Status: draft

### C21
Wide-but-short viewports are a first-class breakpoint: `(min-width: 1024px) and (max-height: ~900px)`.
Source: log:E9
Check: Is there a rule for `(min-width: 1024px) and (max-height: ~900px)`?
Status: draft

### C22
Responsive behavior is keyed on a measured layout size, with a `ResizeObserver` crossing a threshold, not on device class and not on live text-versus-graphic collision.
Source: log:E9
Check: Is each responsive switch triggered by a `ResizeObserver` crossing a threshold?
Status: draft

### C23
Responsive thresholds are named constants at the top of the file.
Source: log:E9
Check: Is every threshold a named top-of-file constant?
Status: draft

### C24
For SSR, a responsive flag is initialized to match the server render and resolved in an isomorphic layout effect before paint.
Source: log:E9
Check: Is the flag initialized to the server value and resolved in an isomorphic layout effect?
Status: draft

### C25
Styles are scoped with descendant selectors when the state is already encoded in the DOM.
Source: log:E13
Check: Are state styles written as descendant selectors off the state class?
Status: draft

### C26
User-visible accents take the brand token, not a mechanical or internal one.
Source: log:E13
Check: Does every visible accent reference the brand token?
Status: draft

### C27
A color rebrand takes two passes. Flip the token, then sweep the whole hue family (hardcoded hex, `rgba`, hover variants, glows, gradient stops, tints).
Source: log:E13
Check: After the rebrand, was the whole hue family swept, with every CTA pressed?
Status: draft

### C28
Multi-brand demos use custom properties on brand body classes and data attributes for assets.
Source: log:E13
Check: Are brand values set as custom properties on brand body classes, with assets chosen by data attribute?
Status: draft

### C29
A monochrome SVG is recolored with a CSS mask and a solid fill, with the URL in an inline custom property, rather than by editing the asset.
Source: log:E13
Check: Is each recolored monochrome SVG done with a CSS mask and solid fill?
Status: draft

### C30
In the stacked mobile layout, fixed heights that existed to align neighbors on wide screens are released to `auto`.
Source: log:C2
Check: Are fixed heights released to `auto` in the stacked mobile layout?
Status: draft

### C31
Every hover state that implies interactivity has a click handler.
Source: log:C7
Check: Does every element with a hover affordance do something on click?
Status: draft

### C32
Every long-press or swipe action is also available as a tap, and tappable controls sit alongside the swipe.
Source: log:C8
Check: Is every long-press or swipe action also reachable by a tap?
Status: draft

### C33
Full-screen motifs still read when scaled down to 16px.
Source: log:C8
Check: Does the motif read at 16px?
Status: draft

### C34
Local state updates immediately, and persistence happens in the background.
Source: log:C9
Check: Does the UI update before persistence returns?
Status: draft

### C35
Every state-changing action has an undo.
Source: log:C9
Check: Is undo available after each state-changing action?
Status: draft

### C36
Batches use a single submit-all instead of individual action buttons.
Source: log:C11
Check: Is there one submit for the batch?
Status: draft

### C37
Both the suggested value and the final value are recorded.
Source: log:C11
Check: Are suggested and final values both stored?
Status: draft

### C38
In rule builders, downstream options are filtered by the upstream selections.
Source: log:C12
Check: Do downstream options depend on the upstream selection?
Status: draft

### C39
When a trigger change invalidates downstream fields, they clear silently, because orphaned selections are worse than empty fields.
Source: log:C12
Check: Do invalidated downstream fields clear without a blocking message?
Status: draft

### C40
System-initiated changes flash warm amber `#fef3c7` for 1.5s.
Source: log:C12
Check: Do system-initiated changes flash `#fef3c7` for 1.5s?
Status: draft

### C41
A diagram that needs a legend is split into more than one diagram.
Source: log:C19
Check: Is every diagram free of a legend?
Status: draft

### C42
Diagram cards use 3px accent lines instead of filled headers.
Source: log:C19
Check: Are card headers marked with 3px accent lines rather than fills?
Status: draft

### C43
Section labels in diagrams use display type of 20 to 22px or larger.
Source: log:C19
Check: Are section labels at least 20px?
Status: draft

### C44
UI transitions run 300 to 500ms.
Source: log:C22
Check: Does every UI transition last between 300 and 500ms?
Status: draft

### C45
Emphasis is delayed about 1 to 1.3s after the text settles.
Source: log:C22
Check: Does emphasis start 1 to 1.3s after the text settles?
Status: draft

### C46
Before layout math on motion assets, the bounding box of non-transparent pixels is measured by script.
Source: log:C22
Check: Was the bounding box measured by script before layout?
Status: draft

### C47
Draw-on animations animate `clip-path: inset()` instead of `stroke-dashoffset`.
Source: log:C23
Check: Do draw-ons use `clip-path: inset()` and not `stroke-dashoffset`?
Status: draft

### C48
Draw, hold and fade are sequenced in one `@keyframes` block.
Source: log:C23
Check: Are draw, hold and fade in one keyframes block?
Status: draft

### C49
A child's animation is delayed until its parent's fade-in completes, or it plays behind opacity 0.
Source: log:C23
Check: Does each child animation start after its parent's fade-in ends?
Status: draft

### C50
At emoji or icon scale, assets are SVG (produced with cairosvg) with a transparent background.
Source: log:C25
Check: Is each small-format asset an SVG with a transparent background?
Status: draft

### C51
Each small-format asset has one hero element, and stroke weight is matched across the set.
Source: log:C25
Check: Does each asset have one hero element and the same stroke weight as its siblings?
Status: draft

### C52
Before recreating anything from a reference, every element is inventoried and each is verified in the rebuild. Omissions and simplifications are flagged explicitly, never made quietly.
Source: log:C32
Check: Was every reference element inventoried, with each omission or simplification flagged?
Status: draft

### C53
When Figma is the source of truth, specific properties are patched in place. A node the user has touched is never removed and recreated.
Source: log:C35
Check: Were changes patched in place, with no touched node deleted and rebuilt?
Status: draft

### C54
After each push to Figma, the source node's deep tree JSON is saved as a diff baseline.
Source: log:C35
Check: Was a deep-tree JSON baseline saved after each push?
Status: draft

### C55
Design annotations are stripped before usability testing.
Source: log:C36
Check: Are annotations removed from the build used for testing?
Status: draft

### C56
In a monorepo, each experiment is its own deployed project with a scoped `rootDirectory`.
Source: log:C36
Check: Does each experiment deploy as its own project with a scoped `rootDirectory`?
Status: draft
Verify: the project-per-experiment and `rootDirectory` setup, and that a static site gains serverless functions by adding an `api/` folder, against current Vercel docs.

### C57
Design deliverables use no italics.
Source: spec-convention, log:S1
Check: Is there any italic (copy, `em`, `font-style`, italic font variant) in the deliverable?
Status: draft

### C58
Emphasis is bold, `font-weight` 600 or 700. For a single-weight serif with no bold axis, emphasis uses a brand accent color instead, after checking the loaded font's weight axis.
Source: spec-convention, log:S1
Check: Is every emphasis weight 600 or 700, or an accent color where the font has no bold axis?
Status: draft

### C59
Spec-sheet connectors are `#CEC4AC`, and the dot anchors at the annotation text, not the screen (line-dot, not dot-line).
Source: spec-convention, log:S3
Check: Are connectors `#CEC4AC` with the dot at the annotation text end?
Status: draft

### C60
Annotation text is a bold header in `#1F2937` plus body in `#6B7280`.
Source: spec-convention, log:S3
Check: Are headers bold `#1F2937` and body `#6B7280`?
Status: draft

### C61
Spec-sheet annotations have no numbered circles and no color coding.
Source: spec-convention, log:S3
Check: Are numbered circles and color coding absent from the annotations?
Status: draft

### C62
Device frames have a realistic bezel, a camera cutout and the correct aspect ratio.
Source: spec-convention, log:S3
Check: Does each device frame have a bezel, a camera cutout and the correct aspect ratio?
Status: draft

### C63
On dark canvases, muted text is `#959590` or lighter (about 6.7:1).
Source: spec-convention, log:S5, log:C17
Check: Is muted text on dark at least `#959590`?
Status: draft

### C64
On dark canvases, decorative borders are at least `rgba(255,255,255,0.15)`.
Source: spec-convention, log:S5, log:C17
Check: Are decorative borders on dark at least `rgba(255,255,255,0.15)`?
Status: draft

### C65
On dark canvases, structural borders are at least `rgba(255,255,255,0.28)` (WCAG 3:1 for non-text UI).
Source: spec-convention, log:S5, log:C17
Check: Are structural borders on dark at least `rgba(255,255,255,0.28)`?
Status: draft

### C66
Metrics are distributed across their container: first left-aligned, middle centered, last right-aligned.
Source: spec-convention, log:S9
Check: Is the first metric left-aligned, the middle centered and the last right-aligned?
Status: draft

### C67
Description text fills the width of its container, since short lines in a wide container read as a layout error.
Source: spec-convention, log:S9
Check: Does description text span the full container width?
Status: draft

### C68
In permission rows, the higher-level role appears as inline muted metadata instead of a competing column.
Source: spec-convention, log:S10
Check: Is the higher-level role inline muted text, with no column of its own?
Status: draft

### C69
In permission rows, the role dropdown is the only primary element.
Source: spec-convention, log:S10
Check: Is the role dropdown the only primary element in each permission row?
Status: draft

### C70
In scatter plots, z-index is inverse to item number so the highest priority renders on top, and the hover z-index clears the highest base value.
Source: spec-convention, log:S11
Check: Is z-index inverse to item number, with hover above the highest base value?
Status: draft

### C71
A build may add a prop to an existing shared UI component (a `components/ui` file, or the host's equivalent) when all four of these hold. The prop is opt-in, and a test proves the default render is unchanged. The prop has its own story and its own test. The change is written in the assumptions log as a system change. The prop changes how the component presents, not what it does. Anything else is a wrapper or a question to the user: a changed default, new behavior, or a prop only one screen could want. Where the host's own rules forbid editing shared components, the host's rules win.
Source: wrap:2026-11-20
Check: Does every prop added to a shared UI component meet all four conditions (opt-in with the default proven unchanged, own story and test, logged as a system change, presentation only)?
Status: approved
