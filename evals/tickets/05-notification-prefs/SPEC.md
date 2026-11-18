# Notification preferences with grouped toggles and a responsive layout

## Goal

Let each counter lead choose which gear desk alerts reach them. Alerts sit in two groups, Customers and Inventory, and each alert has an in-app switch and an email switch. The layout reflows from a phone to a laptop without dropping any control.

## User and core tension

A lead on a phone between customers wants to mute one alert in a couple of taps, while a lead at a laptop wants every alert in view to compare them. Muting the overdue alert by mistake means a late return goes unflagged, so each switch has to say exactly what it turns off.

## Acceptance criteria

- Alerts appear in two groups, "Customers" and "Inventory", and each group has a heading.
- The Customers group holds booking confirmed, pickup reminder, return reminder and overdue. The Inventory group holds item back from repair, item retired and low stock.
- Each alert has an in-app switch and an email switch, and each switch's label names the alert and the channel.
- At the `sm` breakpoint, the two switches for an alert stack under its name. At `md` and `lg`, the two switches sit on one row beside the name.
- Turning off the in-app switch on the overdue row in the Customers group shows an inline note that says late returns will not be flagged to you in the app.
- Each switch saves when it changes, and its group heading shows a saving indicator until the request finishes.
- When a save fails, the switch returns to its previous state and an error appears next to the group heading.
- Every switch is reachable by keyboard in visual order, and each shows a visible focus ring.

## States to cover

- loading
- loaded
- overdue alert off
- saving
- save failed

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Preferences read and write through the mock data layer in `lib/data/`.
- Delivering real email or push messages is out of scope.
- Per-staff-member defaults and who may change another person's preferences are out of scope. Those belong to `auth/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above, a Playwright e2e test covers the happy path and one error path, and `.atelier/tests.json` reports `"pass": true`.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, every switch works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280, and the stacked and row layouts both appear.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, a preview URL is in the PR, and the page ships behind a feature flag.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
