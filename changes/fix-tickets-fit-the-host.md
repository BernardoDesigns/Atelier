## Changelog

### Changed

- The five benchmark tickets now fit what the proving ground host can give. G9 no longer asks for a hosted preview URL: for v2.0 the render shots under `.atelier/renders/<slug>/` (every state, light and dark, at 375, 768 and 1280) listed or linked in the PR description are the preview. Each ticket's G4 line says how the Playwright e2e test is met on the host (the host's `e2e/` folder, run with its own e2e script, no new test dependency, no server started by hand), and each G9 line says the feature ships behind a flag read with `isEnabled` from the host's `lib/flags.ts`, with nothing rendered when the flag is off, layout included.
- `quality.md` G4 now says `.atelier/tests.json` is recorded by `run-tests.sh`, never written by hand. G9 swaps "a preview URL is in the PR" for the render shots wording and adds the flag-off rule. IDs, order and format are unchanged.
- Tickets 01 (settings form), 02 (inventory table) and 05 (notification preferences) are rewritten as changes to the existing `/settings` and `/inventory` screens, so every acceptance criterion is something the screen does not already do. Ticket 01 goes further on validation, the browser leave prompt and save recovery. Ticket 02 adds sorting, status and category filters in the URL, and a stacked row at 375. Ticket 05 adds a per-alert channel matrix and quiet hours.

- The 400-line cap now counts source only: tests, stories and fixtures do not count. `quality.md` G9 says so, and `agents/builder.md` gives a pasteable `git diff --shortstat` with exclusions for test files, stories and fixtures, for the committed part and the uncommitted part. The Builder reports source lines and total lines in its hand-back, and the split rule applies to the source number. `commands/build.md` reports both numbers.
- Final wording. G4: "Every state named in the SPEC "States to cover" has a component test. Playwright e2e, run through the host's e2e script, covers the happy path and at least one error path. `.atelier/tests.json` reports "pass": true and is recorded by run-tests.sh, never written by hand." G9: "The diff is under about 400 changed lines of source (tests, stories and fixtures don't count), or a split is proposed in the PR. The PR template is complete. Until preview deployments arrive in v2.1, the PR lists or links the render shots for every state as its preview. New features ship behind a feature flag; with the flag off, the screen is exactly as it was before, layout included."

## README

None.

## Setup

None.
