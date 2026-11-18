# Inventory table with loading, empty, error and paginated states

## Goal

Show the gear desk inventory as one data table. Each row carries item name, item ID, category, status, next due date and shelf location. The six statuses are available, reserved, checked out, overdue, in repair and retired, and staff must read any of them at a glance.

## User and core tension

A counter tech looking for a "50mm prime lens" while a customer waits needs the name, the status and the shelf location in one scan. Dense rows make that fast, but six status colours in a dense table turn into noise, so each status has to read from its text label first and its colour second.

## Acceptance criteria

- Each row shows item name, item ID, category, status, next due date and shelf location.
- Status is a badge with its text label, so the status reads with colour removed.
- The status badge uses one of six labels: available, reserved, checked out, overdue, in repair, retired.
- Sorting by the name column switches between ascending and descending, and the column header shows the current direction.
- While data loads, the table shows skeleton rows where data will go, and the column headers stay in place.
- When the inventory has no items, the table shows an empty state with one line of text and a button to add the first item.
- When the request fails, the table shows an error state with a retry button.
- Pagination shows 25 rows per page and the current page number, and moves forward and back by keyboard alone.
- A retired item shows its row muted, and its status badge still reads "retired".
- A status filter with no matching items shows the empty state, and the text names the filter.

## States to cover

- populated
- loading
- empty
- error
- paginated
- filtered empty

## Visual baseline

None, first build.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Rows come from the mock data layer in `lib/data/`.
- Editing an item, the check-out flow and the return flow are out of scope. The add item button only needs to be visible and focusable.
- Booking history and deposits are out of scope. They belong to `payments/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above, a Playwright e2e test covers the happy path and one error path, and `.atelier/tests.json` reports `"pass": true`.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the table and pagination work by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, a preview URL is in the PR, and the table ships behind a feature flag.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
