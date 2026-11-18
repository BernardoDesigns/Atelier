# Quality

What "production grade" means for a prototype built with Atelier. The Builder works to it, the Critic scores against it, and `/wrap` reports on it. Each gate has a pass bar that a script or a reviewer can check. Every threshold here is a draft until `/taste-review` finalizes it.

Fixed values used below: themes `light` and `dark`; breakpoints `sm` 375, `md` 768, `lg` 1280; protected paths `auth/`, `api/`, `payments/`, `lib/shared/`.

## Gates

| ID | Gate | Pass bar | Checked by | Status |
|---|---|---|---|---|
| G1 | System fidelity | Zero invented components. Each component not found in the host design system manifest is listed in `.atelier/assumptions.md` and approved at `/wrap`. | Reviewer (Critic reads the assumptions log against the manifest) | draft |
| G2 | Types | `tsc --noEmit` exits 0 under `strict`, and no `any` appears in changed files. | Script | draft |
| G3 | Lint/format | The host's eslint and prettier both exit 0 on changed files, using the host's own config. | Script | draft |
| G4 | Tests | Every state named in the SPEC "States to cover" has a component test. Playwright e2e covers the happy path and at least one error path. `.atelier/tests.json` reports `"pass": true`. | Script | draft |
| G5 | Accessibility | axe reports 0 serious or critical violations in every shot. The full flow is reachable by keyboard alone. Focus is visible on every interactive element. Text and UI contrast meet WCAG AA in both `light` and `dark`. | Script for axe, reviewer for keyboard, focus and contrast | draft |
| G6 | Visual | Render shots exist for every SPEC state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280, and each matches the SPEC "Visual baseline". | Reviewer (Critic cites each shot path) | draft |
| G7 | Lane | No changed file sits under `auth/`, `api/`, `payments/` or `lib/shared/`, unless the SPEC lists that path as in scope. | Script (lane guard, or a diff check) | draft |
| G8 | Readability | Code follows the host conventions. No dead code, commented-out code or unused exports. Every name can be understood without reading the SPEC. | Reviewer | draft |
| G9 | PR hygiene | The diff is under about 400 changed lines, or a split is proposed in the PR. The PR template is complete. A preview URL is in the PR. New features ship behind a feature flag. | Reviewer, with a script for the line count | draft |
| G10 | Taste | The Critic scores each of P1 to P5 from 1 to 5, and no score is below 3. | Reviewer (Critic) | draft |

## Principles

The five design principles, in short form. The Critic scores each one 1 to 5 under G10. Judgment items in `taste.md` hang off these.

| ID | Principle | In short | Status |
|---|---|---|---|
| P1 | Feelings are the metric | The measure of a screen is what a person feels using it. A design that passes every check and feels wrong has failed. | draft |
| P2 | Consistency is care | The same thing looks and behaves the same way everywhere. Drift reads as carelessness. | draft |
| P3 | Restraint is confidence | Every element earns its place. Cutting is the default, and adding needs a reason. | draft |
| P4 | Systems over one-offs | Reach for the existing token, component or pattern first. A new one must be reusable and recorded. | draft |
| P5 | Warmth through detail | Small, considered touches in copy, motion and spacing make a product feel human. | draft |

## Changing this file

Nothing writes to this file except an accepted `/wrap` proposal. The other contract files are `taste.md`, `conventions.md` and `failures.md`; this one holds the bars they are checked against.
