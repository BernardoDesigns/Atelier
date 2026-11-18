# Critique

The Critic returns this shape as its reply. The parent session saves it to `.atelier/critique.md`. Sections appear in this order. Scores are whole numbers from 1 to 5.

## Core tension

<The tension from the SPEC heading "User and core tension", in a sentence or two, then how well the build holds it.>

## Findings

Ranked, most important first. Every finding has a severity (`blocker`, `major` or `minor`), a one-line reason, and one evidence line, exactly one of:

- `Screenshot: .atelier/renders/<slug>/<state>.<theme>.<bp>.png` for anything visual or about taste.
- `Diff: <file>:<line>` for anything about the code.

A finding with neither evidence line is invalid and is left out.

1. Severity: <blocker | major | minor>. <One-line reason.>
   Screenshot: .atelier/renders/<slug>/<state>.<theme>.<bp>.png
2. Severity: <blocker | major | minor>. <One-line reason.>
   Diff: <file>:<line>

## Rubric scores

One row per gate, G1 to G10, in the order of `~/.claude/atelier/quality.md`.

| Gate | Score | Note |
|---|---|---|
| G1 System fidelity | <1-5> | <note> |
| G2 Types | <1-5> | <note> |
| G3 Lint/format | <1-5> | <note> |
| G4 Tests | <1-5> | <note> |
| G5 Accessibility | <1-5> | <note> |
| G6 Visual | <1-5> | <note> |
| G7 Lane | <1-5> | <note> |
| G8 Readability | <1-5> | <note> |
| G9 PR hygiene | <1-5> | <note> |
| G10 Taste | <1-5> | <note> |

## Principle scores

| Principle | Score | Note |
|---|---|---|
| P1 Feelings are the metric | <1-5> | <note> |
| P2 Consistency is care | <1-5> | <note> |
| P3 Restraint is confidence | <1-5> | <note> |
| P4 Systems over one-offs | <1-5> | <note> |
| P5 Warmth through detail | <1-5> | <note> |

## Spec drift

<Where the build departs from the SPEC, each with a screenshot path or a `<file>:<line>` location. "None found" if there is none.>

Verdict: <pass | revise>

The verdict is `revise` whenever any principle scores below 3. It is a single line that starts with `Verdict:` and holds one word.

## Ranking

Optional. Diverge mode only, placed after the per-option critiques. Order best first. Each row: option id, total of the gate and principle scores, a one-line reason. Mark the top 2 or 3.

1. opt-<n> | total <sum> | <one-line reason> | top pick
2. opt-<n> | total <sum> | <one-line reason> | top pick
3. opt-<n> | total <sum> | <one-line reason>

# Example

Everything below this line is a worked example, not part of the template. The numbers and paths are made up.

## Core tension

The user needs to change many settings quickly but must never lose an edit by accident. The build holds this in the default state and breaks it in the error state, where a failed save clears the form.

## Findings

1. Severity: blocker. A failed save resets every field, so the user loses their edits.
   Screenshot: .atelier/renders/settings/error.light.md.png
2. Severity: major. The dirty-state bar is a new component, not the system's Alert.
   Screenshot: .atelier/renders/settings/dirty.dark.md.png
3. Severity: major. The save handler reads from `lib/shared/` state directly, a protected path.
   Diff: app/settings/save.ts:42
4. Severity: minor. The helper text is crowded against the input at the narrowest width.
   Screenshot: .atelier/renders/settings/default.light.sm.png

## Rubric scores

| Gate | Score | Note |
|---|---|---|
| G1 System fidelity | 3 | One invented component, logged as A2. |
| G2 Types | 5 | tests.json shows pass, and the diff has no `any`. |
| G3 Lint/format | 5 | Clean. |
| G4 Tests | 4 | Error path covered, loading state is not. |
| G5 Accessibility | 4 | axe clean, focus ring faint in dark. |
| G6 Visual | 3 | Matches baseline at lg, drifts at sm. |
| G7 Lane | 5 | No protected paths touched. |
| G8 Readability | 4 | Clear names. |
| G9 PR hygiene | 4 | Under 400 lines. |
| G10 Taste | 3 | See principle scores. |

## Principle scores

| Principle | Score | Note |
|---|---|---|
| P1 Feelings are the metric | 2 | Losing edits on error feels hostile. |
| P2 Consistency is care | 4 | Spacing follows the scale. |
| P3 Restraint is confidence | 4 | Calm layout. |
| P4 Systems over one-offs | 3 | The dirty bar is a one-off. |
| P5 Warmth through detail | 3 | Success message is generic. |

## Spec drift

The SPEC lists an empty state for "no connected accounts". It is not rendered. See .atelier/renders/settings/default.light.lg.png for the closest shot.

Verdict: revise
