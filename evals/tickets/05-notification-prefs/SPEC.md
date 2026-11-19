# Notification preferences: a per-event channel matrix, quiet hours and a test notification

## Goal

This is a change to the existing Notifications tab on the settings screen at `/settings`, not a new page. Today the tab has switches for Overdue alerts, Return reminders and Repair updates, Email and Text message checkboxes under "Send alerts by", and a "Desk summary" select. The per-alert switches replace the "Send alerts by" checkboxes: every alert gets its own email and text message choice in a matrix. Add quiet hours and a way to send a test notification. The layout still reflows from a phone to a laptop without dropping any control.

`NotificationPrefs` becomes a per-alert map of `{ email, sms }` for the seven alerts. Overdue, return reminder, repair (item back from repair) and low stock carry over from today's values. The fixtures define each alert's default, which Reset to default restores.

## User and core tension

A lead on a phone between customers wants to mute one alert in a couple of taps, while a lead at a laptop wants every alert in view to compare them. Muting the overdue alert by mistake means a late return goes unflagged, so each switch has to say exactly what it turns off.

## Acceptance criteria

- Above the "Desk summary" select, alerts appear in two groups, "Customers" and "Inventory", each with a heading. The Customers group holds booking confirmed, pickup reminder, return reminder and overdue. The Inventory group holds item back from repair, item retired and low stock.
- Each alert has its own email switch and text message switch, so every alert can use a different channel mix. Each switch's label names the alert and the channel. The "Send alerts by" checkboxes are gone.
- At `md` and `lg`, the alerts sit in a matrix with the two channels as column headings and one alert per row. At `sm`, each row becomes a block with the two switches stacked under the alert name.
- Turning off both channels on the overdue row shows an inline note that says late returns will not be flagged to you.
- Each row has a "Reset to default" action that restores that alert's channels from the fixtures and is hidden while the row matches its default.
- A quiet hours block has an on switch, a start time and an end time, each as 24-hour HH:MM. A range that crosses midnight, such as 22:00 to 07:00, is valid. Equal start and end times show an error under the end time once the end time loses focus.
- With quiet hours on, a line under the block reads back the range and says that overdue alerts still come through.
- Each channel has a "Send test" button that sends a sample notification through the mock data layer. It shows a pending state, then a confirmation naming the channel.
- A "Send test" button is disabled, with its reason in text, when every alert has that channel off.
- When a test fails, an error appears next to that button with a Retry action, and nothing else on the tab changes.
- Saving and a failed save use the existing footer. The mock data layer gains a way to fail a save on request.
- Every switch and button is reachable by keyboard in visual order, each shows a visible focus ring, and the matrix switches are announced with both their row and column.

## States to cover

- loading
- loaded
- overdue alert off
- quiet hours on
- saving
- save failed
- test sent
- test failed

The Builder provides a story under `stories/` for each state (the host Storybook only picks up `components/` and `stories/`, not `app/`), or a mock-only URL switch in `settings-state.ts`, including the Notifications tab open.

## Visual baseline

None, first build.

Until a baseline exists, gate G6 is judged on every state having a render and on drift from this SPEC.

## Out of scope and protected paths

- The Counter tab is out of scope.
- The "Desk summary" select, the save and discard footer and the URL-selectable loading and error states stay as they are. The per-alert switches replace the "Send alerts by" checkboxes and the three single switches. Nothing else on the tab is removed.
- Protected paths `auth/`, `api/`, `payments/` and `lib/shared/` are out of scope. Preferences, quiet hours and test sends read and write through the mock data layer in `lib/data/`, which may be extended for them.
- Delivering real email or text messages is out of scope. A test notification only gets a mock result.
- Per-staff-member defaults and who may change another person's preferences are out of scope. Those belong to `auth/`.

## Definition of done

- G1 System fidelity: every component missing from the host design system manifest is listed in the assumptions log and approved at `/wrap`.
- G2 Types: `tsc --noEmit` exits 0 under strict, and no `any` appears in changed files.
- G3 Lint and format: the host eslint and prettier exit 0 on changed files.
- G4 Tests: a component test exists for each state above. A Playwright e2e test covers the happy path and one error path. It lives in the host `e2e/` folder and runs with the host `npm run test:e2e`, which builds and starts the app itself, so start no server by hand. Add no test dependency; Playwright is already there. `.atelier/tests.json` reports `"pass": true` and is recorded by running the tests through `~/.claude/atelier/guardrails/run-tests.sh`, never written by hand.
- G5 Accessibility: axe reports 0 serious or critical violations in every shot, every switch works by keyboard alone, and focus is visible on every control.
- G6 Visual: a render shot exists for each state in `light` and `dark` at `sm` 375, `md` 768 and `lg` 1280, and the stacked and row layouts both appear.
- G7 Lane: no changed file sits under a protected path.
- G8 Readability: no dead code, and every name reads without the SPEC.
- G9 PR hygiene: the diff is under about 400 changed lines, the PR template is complete, and the render shots for every state are listed or linked in the PR description (the preview for now). The page ships behind a flag: read it with `isEnabled` from the host module `lib/flags.ts`. With the flag off the screen renders exactly as it does on `main`, and nothing of this change renders, layout included: no empty field slot, banner or gap.
- G10 Taste: the Critic scores P1 to P5 from 1 to 5 and no score is below 3.
- Screenshots rendered for every state listed above.
- Assumptions log written at `.atelier/assumptions.md` and reviewed at `/wrap`.
- Passing test run recorded in `.atelier/tests.json`.
- Critique reviewed, with a `Verdict:` line in `.atelier/critique.md`.

## Open questions

None.
