# Failures

Known traps: things that go wrong in prototype work, how they show up, and what to do instead. Only the Critic and the Builder read this file. New entries arrive through accepted `/wrap` proposals.

Each item is a `### F<n>` heading, then `Name:`, `Trap:`, `Shows up as:`, `Instead:`, `Source:`, `Status:` and, optionally, `Verify:`.

Every item is a draft until `/taste-review` approves it.

### F1
Name: Lookalike components
Trap: An agent draws a near-copy of a design-system component instead of using the real one, so the prototype drifts from the system without anyone choosing that.
Shows up as: A new component whose name or markup closely resembles one in the manifest, or a raw element styled to match an existing component.
Instead: Search the component manifest before building anything. Use the system component, and log a genuinely new one in `.atelier/assumptions.md`.
Source: plan
Status: draft

### F2
Name: Empty FigJam from generate_diagram
Trap: The `generate_diagram` tool can report success while producing an empty FigJam file.
Shows up as: A FigJam link that opens to a blank board after a successful tool response.
Instead: Open the result and confirm it has content before reporting it done. If it is empty, rebuild the diagram by another route and say so.
Source: plan
Status: draft

### F3
Name: Key dismissal during a locked beat
Trap: A beat that freezes pointer input still lets a key such as Escape close the surface. The timer that was meant to end the beat then acts on a surface that no longer exists.
Shows up as: A console error or a stuck state a moment after dismissing a surface mid-beat with the keyboard.
Instead: Block key dismissal for the length of the beat, and make timer callbacks safe when the surface is already gone.
Source: log:A3
Status: draft

### F4
Name: Copy bound to too coarse a source
Trap: Generated copy that reads a coarser source than the fact belongs to goes wrong in plausible-looking ways.
Shows up as: The wrong item named, a miscount, or a claim that spans more than it should.
Instead: Bind every noun and number to the narrowest source that owns the fact.
Source: log:A5
Status: draft

### F5
Name: Cutting a line that carried a duty
Trap: Replacing a footer-style line with something else silently drops the job it was doing, such as disclosure or attribution.
Shows up as: A cleaned-up screen that no longer discloses or credits something it used to.
Instead: Before cutting a line that reads as filler, name the job it may be doing, then decide on purpose whether something else takes it over.
Source: log:A14
Status: draft

### F6
Name: Entrance state that can strand UI invisible
Trap: Hiding elements with a class flip means that a missed recalc leaves them invisible for good.
Shows up as: Elements that never appear on some loads or devices, with no error anywhere.
Instead: Rest elements visible in the stylesheet and run entrances as one-shot WAAPI animations with backwards fill, so a failed animation just appears instantly.
Source: log:E2
Status: draft

### F7
Name: Commit by flag
Trap: Marking an item as committed with a flag means every code path has to honor that flag, and one forgets.
Shows up as: A committed item that is still counted, hit-tested or dragged.
Instead: Commit an item by removing it from the interactive collection.
Source: log:E2
Status: draft

### F8
Name: Dismiss tap that reopens its surface
Trap: A global tap-to-open listener fires on the tap that was meant to dismiss the surface.
Shows up as: A sheet or panel that closes and reopens straight away on touch.
Instead: Dismiss controls stop propagation, and a global tap-to-open listener ignores events from inside the surface it opens.
Source: log:E2
Status: draft

### F9
Name: Offscreen only at scrollTop 0
Trap: "Translated offscreen" only holds at scrollTop 0. Scroll anchoring moves `overflow:hidden` pages on resize, so closed sheets drift into view.
Shows up as: A closed sheet or panel peeking into view after a resize or rotation.
Instead: Use `overflow: clip`, reset scrollTop on resize, and set `visibility: hidden` on closed sheets.
Source: log:E2
Status: draft
Verify: scroll anchoring on `overflow:hidden` pages still behaves as described in current browsers.

### F10
Name: Vertical drag canceled on touch
Trap: On touch, a vertical drag can fire `pointercancel` before `pointerup`, so a drag gesture ends without its release handler running.
Shows up as: A swipe-to-dismiss or drag that works with a mouse and stalls on a phone.
Instead: Give dedicated gesture surfaces `touch-action: none`, and keep scrollable content on its normal panning.
Source: log:E2
Status: draft
Verify: `pointercancel` on vertical touch drags still behaves as described in current browsers.

### F11
Name: Totals that count an item twice
Trap: A total built over fluid and committed state counts an item in both places, or drops it between the two.
Shows up as: A count or sum that is off by one around the moment of a commit, or that ticks late after a confirmation beat.
Instead: Sum a ledger incremented at commit plus a live scan of uncommitted items. Decrement a counter in the frame the item visibly leaves, not when the commit lands.
Source: log:E2
Status: draft

### F12
Name: Array length as an ID
Trap: Using `array.length` as the next ID collides after a delete.
Shows up as: Two items with the same ID, or an edit that hits the wrong row after something was removed.
Instead: Use `Math.max(...ids) + 1`.
Source: log:E15
Status: draft

### F13
Name: Background shorthand wipes the image
Trap: The CSS `background` shorthand resets `background-image`, so a hover rule written with it removes the image.
Shows up as: An image or gradient that vanishes on hover.
Instead: Use `background-color` in hover states.
Source: log:E15
Status: draft

### F14
Name: Bold on a font with weight gaps
Trap: Semantic `strong` silently falls back when the font family has weight gaps, so the bold is faked or missing.
Shows up as: Emphasis that looks smeared or does not change at all.
Instead: Set the font weight explicitly to one the family ships.
Source: log:E15
Status: draft

### F15
Name: Unscoped CSS order leaks
Trap: Unscoped rules depend on source order, so a later rule changes elements it was never meant to touch.
Shows up as: A style change in one component that moves something in another.
Instead: Scope the rules to a parent selector.
Source: log:E15
Status: draft

### F16
Name: Tailwind v4 buttons lose the pointer cursor
Trap: Tailwind v4 preflight gives buttons `cursor: default`.
Shows up as: Icon triggers and custom buttons with an arrow cursor on hover.
Instead: Add `cursor-pointer` to icon triggers.
Source: log:E15
Status: draft
Verify: the Tailwind v4 preflight cursor behavior on the current version.

### F17
Name: Orphaned CSS after deleting an element
Trap: Deleting a DOM element without its styles leaves dead rules behind that can match something later.
Shows up as: Unused base, hover or reduced-motion rules for a node that no longer exists.
Instead: Sweep the element's CSS in the same change: base, hover and reduced-motion rules.
Source: log:E15
Status: draft

### F18
Name: Word swap that doubles an article
Trap: Replacing a word with a phrase by plain find and replace loses case and breaks the grammar around it.
Shows up as: A doubled "the", a wrong "a" or "an", or a lowercase word at the start of a sentence.
Instead: Make it a case-preserving swap and read the surrounding articles afterwards.
Source: log:E15
Status: draft

### F19
Name: Tunneled Next.js dev app never hydrates
Trap: Next.js dev blocks cross-origin dev resources, so an app opened through a tunnel renders HTML but never hydrates.
Shows up as: A page that looks right and does nothing when clicked.
Instead: Set `allowedDevOrigins` to include `*.trycloudflare.com`.
Source: log:E16
Status: draft
Verify: the Next.js `allowedDevOrigins` requirement against the current version.

### F20
Name: Paint-timing bugs hidden by dev overhead
Trap: Dev-mode overhead masks paint-timing bugs, so a flash or wrong first frame never shows up in dev.
Shows up as: A clean dev session followed by a flicker in the production build.
Instead: Run visual QA on a production build, and make the bad state unpaintable rather than winning the race.
Source: log:E16
Status: draft

### F21
Name: Case mismatch that only breaks on Vercel
Trap: macOS is case-insensitive and Vercel is not, so a wrongly cased import or asset path works locally and fails when deployed.
Shows up as: A missing file or module on the deployed build that is fine on the laptop.
Instead: Reference the exact committed case, and verify it with `git ls-files`.
Source: log:E16
Status: draft

### F22
Name: Regression caused by the browser, not the code
Trap: A visual regression can come from a browser extension, so editing the code chases a cause that is not there.
Shows up as: A style that looks wrong in one browser profile and right in a clean one.
Instead: Pull the live computed style before editing anything.
Source: log:E16
Status: draft

### F23
Name: Stale assets through a quick tunnel
Trap: Cloudflare caches assets by URL when no cache headers are sent, so a quick tunnel keeps serving old files.
Shows up as: A change that does not appear through the tunnel while the local server shows it.
Instead: Bump `?v=N` on the asset URL, or send `no-store`.
Source: log:E16
Status: draft
Verify: the Cloudflare quick-tunnel caching behavior against the current service.

### F24
Name: Mid-animation frames without the OS setting
Trap: When the OS reduced-motion setting is off-limits, there is no easy way to see motion states, and guessing at them goes wrong.
Shows up as: Animation frames that were never looked at before the build was called done.
Instead: Boot the page in a same-origin `srcdoc` iframe with `matchMedia` stubbed, and step WAAPI `currentTime` to capture mid-animation frames.
Source: log:E16
Status: draft

### F25
Name: Flag gates the control, not the layout
Trap: A feature flag hides the button but the column, header or skeleton cell built for it still renders.
Shows up as: An empty column or gap in production while the feature ships dark.
Instead: Derive the layout from the flag (columns, headers, skeleton and message cells), and test the flag-off render.
Source: wrap:2026-11-19 finding 1
Status: draft

### F26
Name: Pending state with nothing focusable
Trap: Disabling every control in a dialog while a request is pending drops focus to body and breaks the trap.
Shows up as: Tab leaves the dialog, or focus lands on the page, during a confirming state.
Instead: Keep one control focusable (aria-disabled with an early-return handler) and move focus to it when pending starts.
Source: wrap:2026-11-19 finding 4
Status: draft

### F27
Name: Only the error branch is handled
Trap: A result type with more than success and error (loading, empty) gets handled as success-or-error, and the other branches fall through silently.
Shows up as: A pending state that clears with no feedback.
Instead: Treat every non-success result as the failed state, and test each branch.
Source: wrap:2026-11-19 finding 8
Status: draft

### F28
Name: Centered story hides how a wide component behaves when narrow
Trap: A width-dependent story rendered with Storybook's centered layout has no container to constrain it, so a wide table or grid sets the page width itself.
Shows up as: The narrow render overflows the viewport sideways (the render manifest reports overflowX above 0 for the sm shot), and the component's own scroll or wrap behavior is never exercised.
Instead: Use layout fullscreen (or padded) for width-dependent stories so the component gets the viewport's width, and read overflowX in the render manifest for every sm shot.
Source: wrap:2026-11-19 finding 7
Status: draft

### F29
Name: Live region on a display: contents box
Trap: A `role="status"` or `aria-live` region is styled `display: contents` to avoid adding a gap while empty.
Shows up as: Older WebKit drops the role, so the note may never announce on a phone, and current VoiceOver may too, while jsdom tests pass.
Instead: Keep the region a real, always-mounted box that collapses to zero height while empty, and fill it with text when the note appears.
Source: wrap:2026-11-21 finding 3
Status: draft
Verify: on an iPhone with VoiceOver, that a `display: contents` live region is silent on current iOS.

### F30
Name: axe passes, state still unreadable
Trap: Treating zero axe violations as proof that every state is readable.
Shows up as: An off Switch track far below 3:1 against the page passes axe, because axe does not test non-text contrast (WCAG 1.4.11), and it reads as disabled. A color that only appears in a state no shot renders, such as field error text, passes too.
Instead: Check by hand that a toggle's off track and thumb reach 3:1 against what touches them, in every theme the host ships, and render every state that brings in a new color.
Source: wrap:2026-11-21
Status: draft

### F31
Name: Dev server refuses the tunnel hostname
Trap: A dev server opened through the `devup` Cloudflare tunnel checks the Host header and rejects the tunnel's hostname. Vite and Storybook each have their own allow list.
Shows up as: Localhost works, and the tunnel link shows a blocked message. Vite answers "Blocked request" and says the host is not allowed. Storybook answers "Invalid host" (seen on Storybook 10.6.8). Next serves the page but never hydrates, which is F19.
Instead: Allow the tunnel domain in the host's dev config: `.trycloudflare.com` in Vite's `server.allowedHosts`, and in `core.allowedHosts` in `.storybook/main` (read only at startup, so restart Storybook). While a tunnel to Storybook is up, anyone with the link can reach its MCP endpoint.
Source: log:F8
Status: draft
Verify: the Vite and Storybook option names and messages against current versions.
