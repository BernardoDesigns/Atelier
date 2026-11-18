# SPEC: <feature name>

## Goal

<!-- One or two sentences: what this build makes possible, and for whom. Example: "People can change their notification preferences without leaving the settings page." -->

## User and core tension

<!-- Who uses this, and the one tension the design has to resolve. The Critic leads with this. Example: "A busy account owner wants fewer emails but is afraid of missing a billing notice." -->

## Acceptance criteria

<!-- A checklist. Each line is one observation that a reviewer can answer yes or no. Example: "- [ ] Turning a toggle off shows a saved confirmation within one second." -->

- [ ] 

## States to cover

<!-- A plain bullet list. One state name per line and nothing else on the line. The render plan and the Critic both read this list. Keep the standard names below, delete the ones that do not apply and add your own. Example: "- partially saved" -->

- default
- hover
- focus
- disabled
- loading
- empty
- error

## Visual baseline

<!-- A screenshot path, a Figma frame link, or the words "none, first build". Example: "https://www.figma.com/design/<file>?node-id=1-2" -->

## Out of scope and protected paths

<!-- What this build will not touch, then the protected paths. Remove a protected path only if this build must change it, and say why. Example: "Out of scope: email delivery settings." -->

Out of scope:

- 

Protected paths:

- `auth/`
- `api/`
- `payments/`
- `lib/shared/`

## Definition of done

<!-- Done means the quality gates in quality.md pass and the build-session artefacts exist. Trim a gate only with a reason written here. Example: "G9: split proposed, the diff is over 400 lines." -->

Quality gates, by ID and name (see `quality.md`):

- G1 System fidelity
- G2 Types
- G3 Lint/format
- G4 Tests
- G5 Accessibility
- G6 Visual
- G7 Lane
- G8 Readability
- G9 PR hygiene
- G10 Taste

Build-session artefacts the PR gate checks:

- Screenshots rendered for every state under States to cover
- The assumptions log, `.atelier/assumptions.md`, reviewed at /wrap
- A passing test run, recorded in `.atelier/tests.json`
- A reviewed critique, `.atelier/critique.md`, ending in a `Verdict:` line

## Open questions

<!-- Anything unsettled, each with who can answer it. An empty list is fine. Example: "- Should digest emails be on by default? Owner: product." -->

- 
