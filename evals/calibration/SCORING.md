# Scoring a Critic run

This sheet scores one Critic run against the seeded defects in `defects.json`. The defects are planted in the proving ground, so each run is scored on the same known answers.

Scoring uses the Critic's output saved as `.atelier/critique.md` in the proving ground. Copy that file somewhere else before you score it, so the original stays as it was.

Every defect has a `detected_by` value:

- `critic-screenshot`: visible in a render. The Critic must cite a screenshot.
- `critic-diff`: visible by reading the diff. The Critic must cite a diff location, written `file:line`.
- `script`: only a tool reliably catches it, such as `tsc`, prettier, the lane guard or the PR line count. The Critic cannot run commands, so it is not scored on these.

## Counting Critic findings

Each entry in `defects.json` with `"kind": "defect"` and a `detected_by` of `critic-screenshot` or `critic-diff` is critic-detectable. Each entry with `"kind": "decoy"` is a harmless difference.

- **Caught.** The Critic names the defect, and its evidence is valid for the defect's `detected_by`. A `critic-screenshot` defect needs a screenshot path under `.atelier/renders/`. A `critic-diff` defect needs a `file:line` in the diff. The finding must also name the defect's `where` path or its `breaks` ID. A gate ID alone does not count. Evidence of the wrong kind does not count either. A screenshot cited for a code finding, or a `file:line` cited for a visual finding, is noise, and the note says why.
- **Missed.** No finding matches the critic-detectable defect.
- **Noise.** A finding that matches no defect and no decoy, or that cites invalid evidence. A finding that matches a decoy is also noise, and it counts under decoy flags as well.

If two findings name the same defect, the first is caught and the second is noise.

## Gate-detected defects

Script-detected defects are not counted against the Critic. Score them in the gate table below, as caught by the gates yes or no. The gate that should catch each one is listed in `evidence`.

## Formulas

- Critic-detectable defects: `D` (11 at the time of writing). Count the `"kind": "defect"` entries whose `detected_by` is `critic-screenshot` or `critic-diff`, and use that number.
- Recall = caught / D
- Precision = caught / (caught + noise)
- Decoy flags = number of decoys flagged, out of 3

Precision includes decoy flags in noise. Recall counts only critic-detectable defects.

## Critic table

Fill one row per scored run. Do not overwrite earlier rows.

| Run date | Critic model | Builder model | Caught | Missed | Noise | Decoy flags | Recall | Precision | Notes |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

## Gate table

Fill one row per run for the script-detected defects. Mark yes only when the gate named in the column reported the defect.

| Run date | Builder model | D02 tsc (G2) | D03 prettier (G3) | D07 lane guard (G7) | D09 PR line count (G9) | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## When to re-score

Score again whenever the Critic prompt, the Critic model or these scoring rules change. A new row goes in each table every time. Compare the new row with the last row before you tune the Critic, so each change has a number behind it.
