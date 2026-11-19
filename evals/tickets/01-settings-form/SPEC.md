# Counter settings: field-level validation, an unsaved-changes guard and a save that can fail

## Goal

This is a change to the existing settings screen at `/settings`, not a new form. Its Counter tab today has a counter name and a default rental days field, a save and discard footer, and validation on those two fields. Take the Counter tab further: add the counter contact email, pickup hours and late-return grace period, give every field an error below it after it loses focus, guard unsaved changes when the person leaves, and make a failed save recoverable without retyping.

## User and core tension

The counter lead changes one setting between two customers and wants it saved in a single tap. A grace period typed wrong changes what counts as late, so the check has to be quick without blocking a save that is fine.

## Acceptance criteria

- The Counter tab gains three fields beside the two it has: counter contact email, pickup hours (an opening and a closing time) and late-return grace period in hours.
- Every field on the Counter tab, the two existing ones included, shows its error text below the field after the field loses focus, not on every keystroke and not only when save is pressed.
- The counter contact email shows an error naming the field when the value has no "@" or no domain part.
- Late-return grace period accepts whole hours from 0 to 72 and shows an error for anything else.
- Pickup hours take an opening and a closing time, each as 24-hour HH:MM, for example 09:00 and 18:00. The closing time must be later than the opening time. Any other value shows an error under the field.
- Pressing save with an invalid field does not call the mock data layer and moves focus to the first invalid field.
- With unsaved changes, switching to the Notifications tab or navigating elsewhere inside the app opens a confirmation with "Stay" and "Discard and leave" before anything changes. With no unsaved changes, nothing opens.
- With unsaved changes, reloading or closing the page shows the browser's own leave prompt.
- A save that fails keeps every entered value, keeps the form dirty, and shows an error above the form with a Retry button.
- Retry sends the same values again. When it succeeds, the error goes away and the form is clean.
- A successful save shows a saved confirmation that stays for at least three seconds.
- Helper text ends with a full stop. Labels take no full stop. The pickup hours helper is a short format hint, not a sentence, so it takes no full stop.

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

- The Notifications tab is out of scope, apart from the leave confirmation when its tab is picked with unsaved Counter changes.
- The existing counter name and default rental days rules, the footer layout and the URL-selectable loading and error states of the screen stay as they are. Only add what the criteria above ask for.
- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. The form reads and writes through the mock data layer in `lib/data/`, which may be extended to store the new fields and to fail a save on request. Nothing changes in the request layer.
- Deposit amounts, card details and refund rules are out of scope. They belong to `payments/`.
- Staff sign-in and staff roles are out of scope.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself. Add no Playwright or other dependency (it is already there) and start no server by hand. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the form works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, and the render shots for every state are in the PR (the preview for now; a hosted preview deployment comes later). The form ships behind a flag from the host flag module, `lib/flags.ts`. With the flag off nothing of the form renders, layout included: no empty column, header or gap.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
