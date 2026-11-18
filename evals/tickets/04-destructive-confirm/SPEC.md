# Destructive-action confirmation to retire an item, with focus trapping

## Goal

Retire an item from the gear desk inventory through a confirmation dialog. A retired item leaves the active inventory and keeps its history on record. The dialog names the item, says what happens, and blocks retirement while the item is reserved or checked out.

## User and core tension

Retiring a cinema camera body is hard to undo, and a tired lead could confirm it on the wrong row in a busy hour. A confirmation heavy enough to catch that misclick slows down a desk that needs to move fast.

## Acceptance criteria

- The dialog title names the item, for example "Retire cinema camera body?"
- The dialog body says the item leaves the active inventory and its history stays on record.
- When the dialog opens, focus moves to the Cancel button.
- While the dialog is open, Tab and Shift+Tab cycle only through the dialog's controls, so focus is trapped inside the dialog.
- Escape closes the dialog without retiring the item.
- When the dialog closes, focus returns to the Retire button that opened it.
- The confirm button reads the action and the item name, not "OK" or "Yes".
- For an item that is reserved or checked out, the confirm button is disabled and the body gives the reason.
- While the request is pending, both buttons are disabled and the confirm button shows a pending state.
- Clicking outside the dialog does not close it while the request is pending.
- When the request fails, the dialog stays open, keeps the item name, and shows an error message.

## States to cover

- open
- blocked
- confirming
- failed
- retired

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. The retire action calls the mock data layer in `lib/data/`.
- Cancelling bookings is out of scope. Booking changes that touch deposits belong to `payments/`.
- Permanent deletion and restoring a retired item are out of scope.
- Checking whether a staff member may retire items is out of scope. It belongs to `auth/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above, a Playwright e2e test covers the happy path and one error path, and `.atelier/tests.json` reports `"pass": true`.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, focus is trapped in the dialog and returns to the trigger on close, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, a preview URL is in the PR, and the action ships behind a feature flag.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
