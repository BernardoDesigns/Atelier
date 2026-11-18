# Settings form with inline validation and save state

## Goal

Let the counter lead edit the gear desk shop settings: shop name, counter contact email, default rental length in days, pickup hours and the late-return grace period in hours. Each field validates after it loses focus, and the form tracks unsaved changes so nobody leaves with edits sitting in the form.

## User and core tension

The counter lead changes one setting between two customers and wants it saved in a single tap. A grace period typed wrong changes what counts as late, so the check has to be quick without blocking a save that is fine.

## Acceptance criteria

- Each field shows its error text below the field after the field loses focus, not on every keystroke.
- The counter contact email shows an error naming the field when the value has no "@" or no domain part.
- Default rental length accepts whole numbers from 1 to 30 and shows an error for anything else.
- Late-return grace period accepts whole hours from 0 to 72 and shows an error for anything else.
- The save button is disabled while every field matches its saved value.
- Changing any field enables the save button and shows "Unsaved changes" beside it.
- Navigating away inside the app with unsaved changes opens a confirmation before the page changes.
- Pickup hours take an opening and a closing time, each as 24-hour HH:MM, for example 09:00 and 18:00. The closing time must be later than the opening time. Any other value shows an error under the field.
- Helper text ends with a full stop. Labels take no full stop. The pickup hours helper is a short format hint, not a sentence, so it takes no full stop.
- Pressing save with an invalid field does not send the request and moves focus to the first invalid field.
- A successful save clears the unsaved note and shows a saved confirmation that stays for at least three seconds.
- A failed save keeps every entered value and shows an error above the form.

## States to cover

- clean
- dirty
- invalid
- saving
- saved
- save failed

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. The form reads and writes through the mock data layer in `lib/data/` and changes nothing in the request layer.
- Deposit amounts, card details and refund rules are out of scope. They belong to `payments/`.
- Staff sign-in and staff roles are out of scope.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above, a Playwright e2e test covers the happy path and one error path, and `.atelier/tests.json` reports `"pass": true`.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the form works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, a preview URL is in the PR, and the form ships behind a feature flag.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
