# Counter settings: field-level validation, a leave prompt and a save that can fail

## Goal

This is a change to the existing settings screen at `/settings`, not a new form. Its Counter tab today has counter name, default rental length, deposit policy and require-ID fields, a save and discard footer, and blur validation on the first two. Take the Counter tab further: add the counter contact email, pickup hours and late-return grace period, show the browser's leave prompt when the person leaves with unsaved changes, and make a failed save recoverable from an error above the form.

## User and core tension

The counter lead changes one setting between two customers and wants it saved in a single tap. A grace period typed wrong changes what counts as late, so the check has to be quick without blocking a save that is fine.

## Acceptance criteria

- The Counter tab gains three fields: counter contact email, pickup hours (an opening and a closing time) and late-return grace period in hours.
- The three new fields follow the rule the existing two already use: the error appears below the field once it loses focus, and while shown it updates as the person types.
- The counter contact email shows an error naming the field when the value has no "@" or no domain part.
- Late-return grace period accepts whole hours from 0 to 72 and shows an error for anything else.
- Pickup hours take an opening and a closing time, each as 24-hour HH:MM, for example 09:00 and 18:00. Any other value shows an error under the field. A closing time not later than the opening time shows its error under the closing time.
- Pressing save with invalid fields keeps today's behaviour and extends it to the new fields in visual order. The status line beside save says how many fields need fixing, for example "2 fields need fixing".
- With unsaved changes, reloading or closing the page shows the browser's own leave prompt.
- A failed save keeps every value and the form dirty, as today, and replaces the footer's "Could not save. Try again." with an error above the form that has a Retry button. The mock data layer gains a way to fail a save on request, so the e2e error path and the save failed render can reach it.
- Retry sends the same values again. When it succeeds, the error goes away and the form is clean.
- A successful save shows a confirmation naming the time of the save, for example "Saved at 14:32", which clears on the next edit.
- The new fields' helper text ends with a full stop, except the pickup hours hint ("HH:MM, 24-hour"), which takes none. Their labels take no full stop.

## States to cover

- clean
- dirty
- invalid
- saving
- saved
- save failed

The Builder provides a story under `stories/` for each state (the host Storybook only picks up `components/` and `stories/`, not `app/`), or a mock-only URL switch in `settings-state.ts`, including the Notifications tab open.

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- The Notifications tab is out of scope.
- An in-app confirmation when leaving through the desk navigation with unsaved changes is out of scope.
- The existing counter name and default rental length rules, deposit policy, require-ID, the footer layout and the URL-selectable loading and error states of the screen stay as they are. Only add what the criteria above ask for.
- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. The form reads and writes through the mock data layer in `lib/data/`, which may be extended to store the new fields and to fail a save on request. Nothing changes in the request layer.
- Deposit amounts, card details and refund rules are out of scope. They belong to `payments/`.
- Staff sign-in and staff roles are out of scope.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself, so start no server by hand. Add no test dependency; Playwright is already there. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the form works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines of source (tests, stories and fixtures don't count), the PR template is complete, and the PR lists or links the render shots for every state as its preview (hosted preview deployments arrive in v2.1). The form ships behind a flag: read it with `isEnabled` from the host module `lib/flags.ts`. With the flag off the screen is exactly as it was before, layout included: no empty field slot, banner or gap.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
