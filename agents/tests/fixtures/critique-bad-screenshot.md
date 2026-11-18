## Core tension

The user wants a dense table they can scan fast without it feeling like a spreadsheet. The build is dense and calm in the default state, and loses that in the loading state.

## Findings

1. Severity: major. The loading state shows a spinner instead of row skeletons, so the layout jumps.
   Screenshot: .atelier/renders/table/loading.light.lg.png
2. Severity: minor. Row hover contrast is faint in dark.

## Rubric scores

| Gate | Score | Note |
|---|---|---|
| G1 System fidelity | 4 | One logged invention. |
| G2 Types | 5 | Clean. |
| G3 Lint/format | 5 | Clean. |
| G4 Tests | 4 | Empty state untested. |
| G5 Accessibility | 4 | axe clean. |
| G6 Visual | 3 | Loading drifts from baseline. |
| G7 Lane | 5 | Nothing protected touched. |
| G8 Readability | 4 | Clear. |
| G9 PR hygiene | 4 | Under 400 lines. |
| G10 Taste | 4 | See principles. |

## Principle scores

| Principle | Score | Note |
|---|---|---|
| P1 Feelings are the metric | 3 | Layout jump feels jittery. |
| P2 Consistency is care | 4 | Matches the scale. |
| P3 Restraint is confidence | 4 | Quiet. |
| P4 Systems over one-offs | 4 | Uses system parts. |
| P5 Warmth through detail | 3 | Empty copy is flat. |

## Spec drift

None found.

Verdict: pass
