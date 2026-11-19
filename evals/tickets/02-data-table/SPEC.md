# Inventory table: sorting, a status filter and a stacked layout at 375

## Goal

This is a change to the existing inventory table at `/inventory`, not a new table. Today it has item, SKU, category, status, day rate, deposit and overdue columns, a status badge with its text label for the six statuses, skeleton rows while loading, an error row with a Retry link, 10 rows per page with page numbers, URL-reachable loading, empty and error states, and a horizontally scrolling container. Make it findable and readable on a phone: sort by column and filter by status with all of it in the URL, and replace sideways scrolling at 375 with a stacked row.

## User and core tension

A counter tech looking for a "50mm prime lens" while a customer waits needs the name, the status and the day rate in one scan. Dense rows make that fast, but six status colours in a dense table turn into noise, so each status has to read from its text label first and its colour second.

## Acceptance criteria

- The Item, Category, Status, Day rate and Overdue column headings each hold a link to the table sorted by that column, and the heading carries `aria-sort`. A first press sorts ascending, a second descending, and a third ascending again. Overdue is sortable only while `overdueColumn` is on.
- With no `?sort`, rows keep today's order. Status sorts in `GEAR_STATUSES` order, ties by SKU. Unknown `sort`, `dir` and `status` values are ignored.
- The sort is in the URL, for example `?sort=name&dir=desc`. Reloading or sharing the link restores it, and pagination links keep it.
- A status filter sits above the table with an "All statuses" choice and the six statuses. The choice is in the URL as `?status=`.
- Extend `listGear` with `sort` and `dir`, and return a result the screen can tell apart from an empty inventory when the filter matches nothing. `?state=empty` keeps today's empty message.
- The filter is the host `Select` with a visible label. At `md` and `lg` rows keep their current height.
- Changing the filter removes `?page=` from the URL. The "Page 1 of N, M items" line counts the filtered items.
- A "Clear filter" button shows only while the filter is active, and clears it but keeps the sort.
- When the filter matches nothing, the table area shows one line naming the active filter and a "Clear filter" button. It does not show the empty inventory message.
- Read sort and filter only in `InventoryData`, inside the existing Suspense, and pass them down as props. Use no `useSearchParams`.
- The Retry link in the error row keeps the sort and the filter.
- At `sm` (375), each row stacks into two lines: the item name with its status badge, then SKU, category, day rate, deposit and overdue as label and value pairs. The page does not scroll sideways and the table is not a scroll region at `sm`. Skeleton and error rows stack at `sm` too. Build the stacked layout in `inventory-table.tsx`. Do not edit `components/ui/table.tsx`.
- At `md` (768) and `lg` (1280), every column shows, one row per item, with no sideways scroll. At `md` the item name truncates inside a width-capped inner element and keeps its full name in `title`. It does not stack at `md`.
- A retired item shows its row muted with `text-muted-foreground`, not opacity, and its status badge still reads "Retired".
- Each sort heading's link shows the host focus ring. The sort headings and the filter work by keyboard alone.
- Add one flag to `lib/flags.ts`. With it off, `?sort`, `?dir` and `?status` are ignored: same data, same pagination links, Retry still goes to `inventoryHref(page)`, and today's scroll region at 375 stays.
- Every state is a URL on the build: populated `/inventory`, loading `?state=loading`, empty `?state=empty`, error `?state=error&sort=name`, paginated `?page=2`, filtered `?status=retired&sort=name&dir=desc`. No story; the screen lives in `app/`.
- No matches has no URL today. Every status has at least four fixture items, so no status filter on its own matches nothing. A component test covers the state with a filtered result of zero items, it has no render shot, and the assumptions log says so.
- The Builder updates the inventory line in the host `AGENTS.md`, which says nothing but canned outcomes is reachable from the query string. Docs do not count toward the source line cap.

## States to cover

- populated
- loading
- empty
- error
- paginated
- filtered
- no matches

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state that has a URL having a render and on drift from this SPEC.

## Out of scope and protected paths

- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Rows come from the mock data layer in `lib/data/`, which may be extended to sort and filter.
- The status badge, its six labels, the skeleton rows, the 10 rows per page and the URL-selectable loading, empty and error states stay as they are.
- Filtering by category, sorting by more than one column, row selection, bulk actions and a density choice are out of scope.
- Editing an item, adding an item, the check-out flow and the return flow are out of scope.
- Booking history and deposit rules are out of scope. They belong to `payments/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself, so start no server by hand. Add no test dependency; Playwright is already there. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, the table and pagination work by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state that has a URL in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines of source (tests, stories and fixtures don't count) or a split is proposed in the PR, the PR template is complete, and the PR lists or links the render shots for every state as its preview (hosted preview deployments arrive in v2.1). The table ships behind a flag: read it with `isEnabled` from the host module `lib/flags.ts`. With the flag off the screen is exactly as it was before, layout included: no empty control, column or gap. The flag's default is on, as a kill switch, and a test that turns it off with the host's `overrideFlags` proves the flag-off behaviour.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above that has a URL.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
