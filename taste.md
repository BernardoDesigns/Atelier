# Taste

Judgment, to be interpreted rather than followed word for word. Each item says what to aim for and how an agent applies it. `conventions.md` holds the literal rules.

Each item is a `### T<n>` heading, the one-line judgment, then `Source:`, `Status:` and `Applied as:`. Items under `## From builds` came from build reviews.

Every item is a draft until `/taste-review` approves it.

### T1
Feelings are the metric. The measure of a screen is what a person feels using it, so judge the result by feel before judging it by checklist.
Source: principle
Status: approved
Applied as: Before calling a screen done, say in one sentence what it should make someone feel, then check each element against that sentence.

### T2
Consistency is care. The same thing looks and behaves the same way everywhere.
Source: principle
Status: approved
Applied as: When touching one instance of a pattern, find its siblings and fix them in the same pass.

### T3
Restraint is confidence. Every element earns its place, and cutting is the default.
Source: principle
Status: approved
Applied as: For each element ask what is lost if it goes. If the answer is nothing, remove it.

### T4
Systems over one-offs. Reach for the existing token, component or pattern first.
Source: principle
Status: approved
Applied as: Search the manifest before drawing anything. A new component is a last resort and gets logged as an assumption.

### T5
Warmth through detail. Small, considered touches in copy, motion and spacing make a product feel human.
Source: principle
Status: approved
Applied as: Spend the extra effort on the moments a person lingers on (empty states, confirmations, first run) and keep the rest quiet.

### T6
When a surface has finished its job, land it on a quiet done state and let the person close it. Hold any downstream cascade, such as an advance or a payoff, until they do. Never close it with a timer, which takes the moment of completion from the person who earned it.
Source: log:A2
Status: approved
Applied as: Replace auto-dismiss with a visible close control, and fire the next step from that control.

### T7
Show completion copy only where there was something to complete. On a surface that never needed the person, the gauge and summary already say it, and the line is restatement.
Source: log:A7
Status: approved
Applied as: If a "done" message would only repeat what a gauge or summary already shows, leave it out.

### T8
Open a demo built on a system rule at the bottom of that system, with the default off, so the first few interactions reveal the rule. This trades first-screen impact for understanding, so decide which one the audience needs.
Source: log:A9
Status: approved
Applied as: Start the demo in its off state, and say in the assumptions log which trade was chosen and why.

### T9
Keep a side tool for thinking separate from the build, and send nothing into the working session until the person sends it. Make costly or destructive paths opt-in, and append to an existing draft instead of replacing it.
Source: log:A17
Status: approved
Applied as: Give the side tool its own folder when it is not part of the main tool's purpose, keep forking a whole session opt-in on long runs, and have "send to prompt" append under any draft already there.
Verify: UNVERIFIED as of 2026-11-20, approved with this check still open. Check that the main tool's own chat surface still cannot host a side conversation, which is why the side tool stays separate.

### T10
A summary section earns trust by telling one story in one voice: one visualization, in the order verdict, why, evidence. The verdict visualization owns semantic color, and everything nearby (numbers, chips, pills) goes neutral rather than asserting a different reading.
Source: log:E1, log:A6
Status: approved
Applied as: When zone colors already name a scale, drop the zone words and title the gauge with what it measures. A per-bucket sparkline gives direction, not a count.

### T11
Equal box gaps around large numerals still read unequal.
Source: log:E1
Status: approved
Applied as: Measure from the glyphs and correct in em.

### T12
Grain and irregular linework come out sterile when redrawn as clean geometry, so bake a seamless tile from the real asset instead.
Source: log:E5
Status: approved
Applied as: A finite cover image leaves a void on tall pages, so use a repeating tile. Flatten low-frequency vignettes first so the repeat does not blotch, offset-heal the seams, and scale the tile to the apparent on-screen size of the cover-scaled original, not its native pixels.

### T13
Make visuals part of the product's logic, so every appearance maps to behavior. It costs discipline and pays in coherence.
Source: log:E12
Status: approved
Applied as: Use brand color only when that brand's voice is active.

### T14
A treatment doesn't carry across element types.
Source: log:E12
Status: approved
Applied as: Re-derive it for each from the same character family rather than copying and adjusting down.

### T15
Center-out reveals read "we're starting"; left-to-right reads narrative. Reuse the same signature gesture at start and end so opening and closing rhyme.
Source: log:E12
Status: approved
Applied as: When a carousel backs a cyclical concept, clone the first and last slides as phantoms and snap silently so the wraparound is invisible; a visible rewind contradicts the thesis.

### T16
Stacking reassigns meaning. Side-by-side reads as peers; stacked on mobile, vertical order becomes hierarchy and a horizontal "journey" becomes a vertical "plan."
Source: log:C1
Status: approved
Applied as: Design mobile order and orientation for mobile reading context, not as rotated desktop. Content order carries more weight in single-column layouts.

### T17
On mobile, restructure instead of shrinking, and make every section earn its scroll. If it is not worth the scroll, merge it, collapse it or make it on-demand.
Source: log:C3, log:A11
Status: approved
Applied as: Below a narrow width, restructure tables into stacked name and detail pairs rather than squeezing columns. On small screens the object being edited outranks the scene around it, so if the context can only show as a sliver, remove it and let the container hug the content.

### T18
Responsive design is a trust contract. Preserve content parity, layout stability, and control proximity across breakpoints.
Source: log:C4
Status: approved
Applied as: Controls always visible next to what they affect.

### T19
Multi-tier systems: show outcomes, hide plumbing. Surface the result the user cares about, not system state.
Source: log:C6
Status: approved
Applied as: Secondary tiers as muted metadata. When dense, cut more aggressively than instinct suggests.

### T20
Side panel architecture: visualization as primary nav, detail in adjacent panel; one panel with dynamic content over multiple regions.
Source: log:C13
Status: approved
Applied as: On external item selection, smooth-scroll reset.

### T21
Every element earns its space through function. If removing it does not hurt, it goes. When two elements carry the same information at different fidelity, cut the weaker. When a feature goes, audit the constraints written to protect it and keep only those with their own reason.
Source: log:C15, log:A15
Status: approved
Applied as: Containers leave with their content, and a removed element's space does not need a substitute.

### T22
Every color must carry a function and meet contrast against its immediate parent, not the page background. Validate at first use, not in review.
Source: log:C16
Status: approved
Applied as: When adding a color, name its job and check contrast against the surface directly behind it before moving on.

### T23
Naming is a design tool. Give territories personality names and options identity labels, and match call-to-action tone to the surface register. If the design has to shout what it means, the hierarchy is not working.
Source: log:C18
Status: approved
Applied as: Rename generic labels such as "Option A" into something with identity, and fix a loud button by fixing the hierarchy around it.

### T24
Escape the default SaaS register with an editorial one. Mix a serif with Inter, use pills over small-caps for category labels, and do typography in design files rather than a whiteboard tool.
Source: log:C20
Status: approved
Applied as: Pair Inter with a serif such as Georgia or Source Serif Pro for display moments, and set category labels as pills.

### T25
Give external data a light grammar pass, and replace jargon labels with the action they represent.
Source: log:C21
Status: approved
Applied as: Rewrite labels such as a verb-less status code into the thing the person can do. Cap LLM-generated card text at two sentences.

### T26
Hand-drawn UI: confidence over imperfection. Waver and jitter read nervous, not human. Confidence comes from intentional asymmetry (pressure, tilt, committed gestures). One bold arc beats many small wobbles.
Source: log:C24
Status: approved
Applied as: Ask if a simpler gesture gets 80% of the win with none of the failure modes. Confident easing needs duration (1.7s+) to read zen, not nervous.

### T27
Heavy-weight primary CTAs read confident, light ones tentative.
Source: log:C27
Status: approved
Applied as: Weight 800 for primary CTAs.

### T28
Onboarding copy only reveals itself when rendered at actual size.
Source: log:C27
Status: approved
Applied as: Expect 3 to 4 copy passes in the real layout. Placeholder copy can frame unfinished space as collaborative.

### T29
Closing screens plant a seed rather than summarize. Atmosphere plus a few words beats a paragraph.
Source: log:C28
Status: approved
Applied as: Promote the domain term that downstream artifacts anchor to into the closing headline.

### T30
Keep brand marks in product chrome white or low-opacity, and reserve saturated brand color for hero and identity moments. Use one identity element per location, match optical weight rather than pixel dimensions, and preserve a color's semantic role across rebrands, not just its palette value.
Source: log:C29
Status: approved
Applied as: A wordmark needs no text label beside it. When two marks share a row, size them until they look equal in weight.

### T31
When the same feedback arrives twice, go broader, not deeper. Stop iterating on instinct and research.
Source: log:C33
Status: approved
Applied as: On the second round of the same note, look at references and alternatives before touching the design again.

## Moved from conventions

### T32
Commit or skip on full-bleed backdrops. Either go edge to edge so the effect lives in the gaps, or make the foreground translucent. Never use a subtle glow behind opaque cards.
Source: log:E3
Status: approved
Applied as: Before adding a backdrop layer, look for a hidden or dead one to repurpose.

### T33
Completion states get their own distinct surface, and timing carries the feeling. 1.8s feels earned, and 400ms feels transactional.
Source: log:C8
Status: approved
Applied as: Give a finished state its own surface rather than reusing the working one, and pick the duration for the feeling wanted.

### T34
Surface exceptions as gentle nudges, not blockers.
Source: log:C9
Status: approved
Applied as: Update local state immediately, persist in the background, always provide undo.

### T35
In spec sheets, proximity is the primary connector.
Source: log:S3
Status: approved
Applied as: Lines are confirmation.

### T36
In diagrams, setup precedes the punchline, and reading order is validated against the viewer's knowledge state. Use vectors, not Venn diagrams, when patterns do not exist on both sides.
Source: log:C19
Status: approved
Applied as: Read the diagram as someone who has not seen the brief, and reorder until each step depends only on what came before it.

## From builds

### T37
A row action that the row's state blocks keeps its trigger visible. The dialog explains the block and when it lifts, rather than the action disappearing per row.
Source: wrap:2026-11-19 finding 10
Status: approved
Applied as: Don't flag a visible-but-blocked trigger as an extra round trip when the SPEC asks for a blocked state.

### T38
A contrast or state fix for a shared primitive goes in the theme as the default for every instance, not as a one-off inside the feature's component.
Source: wrap:2026-11-21
Status: draft
Applied as: Flag a per-component override of a primitive's base state as a one-off when the problem would show on every instance.
