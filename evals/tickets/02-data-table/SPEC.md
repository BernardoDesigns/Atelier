# Inventory table with loading, empty, error, paginated and populated states

## Goal

Show the gear desk inventory as one data table. Each row carries item name, item ID, category, status, next due date and shelf location. Staff can filter the table by status with one control. The six statuses are available, reserved, checked out, overdue, in repair and retired.

## User and core tension

A counter tech looking for a "50mm prime lens" while a customer waits needs the name, the status and the shelf location in one scan. Dense rows make that fast, but six status colours in a dense table turn into noise, so each status has to read from its text label first and its colour second.

## Acceptance criteria

- Each row shows item name, item ID, category, status, next due date and shelf location.
- Status is a badge with its text label, so the status reads with colour removed.
- The status badge uses one of six labels: available, reserved, checked out, overdue, in repair, retired.
- A status filter sits above the table. It is the only filter on the table.
- Table rows are 52px tall to fit a badge and two lines of text. The status filter control is 48px tall, the standard control height.
- While data loads, the table shows skeleton rows where data will go. The skeleton shimmer runs for 1.2 seconds and stops when reduced motion is on.
- When the inventory has no items, the empty state shows one line of text and an Add item button.
- When the status filter has no matching items, the empty state shows one line naming the filter and a Clear filters button. It does not show the Add item button.
- When the request fails, the table shows an error state with a retry button.
- Pagination shows 25 rows per page and the current page number, and moves forward and back by keyboard alone.
- At `sm` (375), each row stacks into two lines: the item name with its status badge, then item ID, category, due date and shelf location as label and value pairs. The table does not scroll horizontally at `sm`.
- At `md` (768) and `lg` (1280), the table shows all six columns, one row per item.
- A retired item shows its row muted, and its status badge still reads "retired".

## States to cover

- populated
- loading
- empty
- error
- paginated

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Rows come from the mock data layer in `lib/data/`.
- Sorting by any column is out of scope.
- Filtering by more than one field is out of scope. Only the status filter is built.
- Editing an item, the check-out flow and the return flow are out of scope. The Add item button only needs to be visible and focusable.
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
