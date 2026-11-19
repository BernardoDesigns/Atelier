# Inventory table: sorting, filtering and a stacked layout at 375

## Goal

This is a change to the existing inventory table at `/inventory`, not a new table. Today it has item, SKU, category, status, day rate, deposit and overdue columns, a status badge with its text label for the six statuses, skeleton rows while loading, an error row with a Retry link, 10 rows per page with page numbers, URL-reachable loading, empty and error states, and a horizontally scrolling container. Make it findable and readable on a phone: sort by column and filter by status and category with all of it in the URL, and replace sideways scrolling at 375 with a stacked row.

## User and core tension

A counter tech looking for a "50mm prime lens" while a customer waits needs the name, the status and the shelf location in one scan. Dense rows make that fast, but six status colours in a dense table turn into noise, so each status has to read from its text label first and its colour second.

## Acceptance criteria

- The Item, Category, Status, Day rate and Overdue column headings are buttons that sort the table. A first press sorts ascending, a second descending, and the heading carries `aria-sort`.
- The sort is in the URL, for example `?sort=name&dir=desc`. Reloading or sharing the link restores it, and pagination links keep it.
- A status filter sits above the table with an "All statuses" choice and the six statuses. The choice is in the URL as `?status=`.
- A category filter sits beside it with "All categories" and the five categories, in the URL as `?category=`.
- Both filters use the host's own Select at its standard 32px height, and the table keeps its existing row height. The ticket asks for no custom control height.
- Changing a filter returns to page 1. The "Page 1 of N, M items" line counts the filtered items.
- A "Clear filters" button shows only while a filter is active, and clears both filters but keeps the sort.
- When the filters match nothing, the table area shows one line naming the active filters and a "Clear filters" button. It does not show the empty inventory message.
- The Retry link in the error row keeps the sort and the filters.
- At `sm` (375), each row stacks into two lines: the item name with its status badge, then SKU, category, day rate, deposit and overdue as label and value pairs. The page does not scroll sideways and the table is not a scroll region at `sm`.
- At `md` (768) and `lg` (1280), the table shows all seven columns, one row per item, without sideways scrolling.
- A retired item shows its row muted, and its status badge still reads "Retired".
- Sort headings and both filters work by keyboard alone, and each shows a visible focus ring.

## States to cover

- populated
- loading
- empty
- error
- paginated
- no matches

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Rows come from the mock data layer in `lib/data/`, which may be extended to sort and filter.
- The status badge, its six labels, the skeleton rows, the 10 rows per page and the URL-selectable loading, empty and error states stay as they are.
- Sorting by more than one column, row selection, bulk actions and a density choice are out of scope.
- Editing an item, adding an item, the check-out flow and the return flow are out of scope.
- Booking history and deposit rules are out of scope. They belong to `payments/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself, so start no server by hand. Add no test dependency; Playwright is already there. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the table and pagination work by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, and the render shots for every state are listed or linked in the PR description (the preview for now). The table ships behind a flag: read it with `isEnabled` from the host module `lib/flags.ts`. With the flag off the screen renders exactly as it does on `main`, and nothing of this change renders, layout included: no empty field slot, banner or gap.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
