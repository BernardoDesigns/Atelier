# Scoring a Critic run

This sheet scores one Critic run against the seeded defects in `defects.json`, and against the decoys in the same file. Scores are taken from the Critic's last `/build` pass, saved as `.atelier/critique.md`. Copy that file somewhere else before you score it, so the original stays as it was.

## Detection types

Every defect has a `detected_by` value:

- `critic-screenshot`: visible in a render. The Critic cites a render path under `.atelier/renders/`.
- `critic-diff`: visible by reading the diff. The Critic cites `file:line` in the diff.
- `script`: only a tool reliably catches it, such as `tsc`, prettier, the diff check for protected paths or the PR line count. The Critic cannot run commands, so these are not scored against it. They are scored in the gate table.

Critic-detectable defects are the entries with `"kind": "defect"` and a `detected_by` of `critic-screenshot` or `critic-diff`.

## Five buckets

Every finding in a Critic run goes into exactly one bucket.

- **caught.** The finding matches a critic-detectable seeded defect under the matching rule below.
- **bonus.** The finding matches a seeded defect tagged `script`. The Critic saw it in the diff anyway. Bonus findings are excluded from both precision and recall.
- **unseeded-valid.** A real issue that was not seeded. The repo owner adjudicates each one. Unseeded-valid findings are excluded from both precision and recall, and each one is listed in the notes.
- **decoy-flagged.** The finding matches a decoy under the matching rule. It counts as noise.
- **noise.** Everything else: a finding the owner would not care about, or one that matches nothing.

A finding that repeats a defect already matched goes in no bucket. Count it under verbosity.

A critic-detectable defect the Critic did not report is **missed**. Missed is reported beside the buckets, but it is not a bucket.

Only caught and missed count toward recall. Only caught, noise and decoy-flagged count toward precision.

## Matching rule

A finding matches a defect when its evidence matches and it describes the same problem. Two scorers following this rule get the same numbers.

- **Screenshot defects.** Evidence matches when the finding cites a render of the same state, in any theme or breakpoint where the defect is visible. The render must show the problem. A render where the defect is not visible does not match.
- **Diff defects.** Evidence matches when the finding cites the same file within 5 lines of the defect's `file:line`, either way.
- The gate or principle ID the Critic attached is ignored for matching. Only the evidence and the problem decide the match.
- If two findings match the same defect, the first is caught and the second is a repeat. Repeats are counted as verbosity, beside the buckets. They are not noise and stay out of precision.
- Only the numbered findings count. A defect named only in a score note or under Spec drift is not caught.
- The Critic writes one finding per root cause and keeps one evidence line, which may be the other kind from the one in the defect's `detected_by`. That still matches when the finding's reason describes the same problem and the evidence line points at the defect: for a screenshot defect, a `Diff:` line in the planted file within 10 lines of the planted line; for a diff defect, a `Screenshot:` line citing a render where the defect is visible.

Worked examples:

- **Screenshot, match.** D06 is visible at md. A finding cites `.atelier/renders/<slug>/populated.light.md.png` and says the shelf location column is missing. The render is the same state, the breakpoint is one where the defect shows, and the problem is the same. Caught.
- **Screenshot, no match.** The same finding cites `populated.light.lg.png`. At lg the column is present, so the defect is not visible in that render. Not a match. The finding is noise, and the note says why.
- **Diff, match.** D05 is at `app/inventory/retire/page.tsx:N`. A finding cites `app/inventory/retire/page.tsx:N+3` and says the dialog is rendered with `modal={false}`, so focus is not trapped. Same file, within 5 lines, same problem. Caught.
- **Diff, no match.** A finding cites `app/inventory/retire/page.tsx:N+40` for the same problem. Outside the 5 line window, so it does not match. It is noise unless it matches another defect.

Each defect's planted `file:line` is written into its `evidence` when the set is planted. Until then, the `N` in `evidence` stands for that line.

## Formulas

- Critic-detectable defects: `D` (11 at the time of writing). Count the entries whose `detected_by` is `critic-screenshot` or `critic-diff`.
- Recall = caught / D
- Precision = caught / (caught + noise + decoy-flagged)

Decoy-flagged counts in the precision denominator, as noise. Report the decoy-flagged count and the decoy flags out of 3 alongside precision. Report bonus and unseeded-valid counts beside caught, noise and recall.

## How the set is planted

Defects are planted per ticket. For each ticket, the planter takes that ticket's finished benchmark branch in the app repo, adds the seeded defects for that ticket on a separate throwaway branch, and never merges that branch. The Critic runs once per ticket, given that ticket's SPEC, its renders and its diff. Scores are summed across the five tickets before the formulas are applied.

Planting and running belong to the build's integration step. They are not done in this folder. This folder holds only the known answers and the rules for scoring them.

## Critic table

One row per scored run, summed across the five tickets. Do not overwrite earlier rows.

| Run date | Critic model | Builder model | Caught | Missed | Bonus | Unseeded-valid | Noise | Decoy-flagged | Recall | Precision | Verbosity (repeats of all findings) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | | |

## Gate table

One row per run for the script-detected defects. Mark yes only when the gate named in the column reported the defect. These rows are not counted against the Critic.

| Run date | Builder model | D02 tsc (G2) | D03 prettier (G3) | D07 diff check (G7) | D09 PR line count (G9) | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## When to re-score

Score again whenever the Critic prompt, the Critic model or these scoring rules change. A new row goes in each table every time. Compare the new row with the last row before you tune the Critic, so each change has a number behind it.
