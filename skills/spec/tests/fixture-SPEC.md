# SPEC: Notification preferences

## Goal

Account owners choose which emails they receive, from the settings page.

## User and core tension

An account owner wants fewer emails but is afraid of missing a billing notice. Billing notices win if the two conflict.

## Acceptance criteria

- [ ] Toggling a category saves without a page reload.
- [ ] The billing category is on and cannot be switched off.
- [ ] A failed save shows an error message and keeps the previous value.

## States to cover

- default
- hover
- focus
- disabled
- loading
- saving
- error

## Visual baseline

none, first build

## Out of scope and protected paths

Out of scope:

- Email delivery settings

Protected paths:

- `auth/`
- `api/`
- `payments/`
- `lib/shared/`

## Definition of done

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

- Should digest emails default to on? Owner: product.
