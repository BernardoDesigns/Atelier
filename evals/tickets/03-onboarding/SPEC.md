# Multi-step onboarding with progress and back-navigation

## Goal

Add a new counter staff member to the gear desk in four steps: their details, their role at the counter, a training checklist, and a review before saving. A stepper shows where the person is, and each step keeps its values when the person goes back.

## User and core tension

The counter lead adds someone between customers, so every step has to be quick to finish and easy to leave. The review step has to catch a wrong role before it saves, and that pulls against making the last step feel like a formality.

## Acceptance criteria

- A stepper shows four steps, marks the current step, and marks finished steps as done.
- The Next button stays disabled until the required fields on the current step are valid. On the checklist step, that means the three required training items are checked.
- The Back button returns to the previous step with every value still filled in.
- The stepper is reachable by keyboard, and only finished steps can be jumped to.
- The review step lists every value entered, and each section has an Edit link that returns to its step.
- While the record saves, the Finish button shows a pending state and cannot be pressed twice. The pending spinner turns once every 0.9 seconds, and the step marker animates over 0.2 seconds. Both motions stop when reduced motion is on.
- When saving fails, the person stays on the review step and sees the error above the Finish button.
- Values typed on a step survive a round trip to the review step and back.
- After Finish succeeds, the page shows a success message that names the new staff member.

## States to cover

- first step
- middle step
- review
- submitting
- submit failed
- success

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. The record saves to the mock data layer in `lib/data/`.
- Account creation, passwords and sign-in are out of scope. They belong to `auth/`.
- Enforcing what each role may do is out of scope. The role field only records the choice.
- Pay rates and payroll are out of scope.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself, so start no server by hand. Add no test dependency; Playwright is already there. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the full flow works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, and the render shots for every state are listed or linked in the PR description (the preview for now). The flow ships behind a flag: read it with `isEnabled` from the host module `lib/flags.ts`. With the flag off nothing of the flow renders, layout included: no empty column, header or gap.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
