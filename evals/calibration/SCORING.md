# Scoring a Critic run

This sheet scores one Critic run against the seeded defects in `defects.json`. The defects are planted in the proving ground, so each run is scored on the same known answers.

Scoring uses the Critic's output saved as `.atelier/critique.md` in the proving ground. Copy that file somewhere else before you score it, so the original stays as it was.

## Counting

Each entry in `defects.json` with `"kind": "defect"` counts once. Each entry with `"kind": "decoy"` is a harmless difference.

- **Caught.** The Critic names the defect. The finding must name the defect's `where` path or its `breaks` ID, and cite a screenshot path under `.atelier/renders/`. A gate ID alone, with no path and no screenshot, does not count.
- **Missed.** No finding matches the defect.
- **Noise.** A finding that matches no defect and no decoy. A finding that matches a decoy is also noise. Count it under decoy flags as well.

If two findings name the same defect, the first is caught and the second is noise. A finding that names a defect but cites the wrong screenshot is noise, and the note says why.

## Formulas

- Total defects: `D` (15 at the time of writing). Count the `"kind": "defect"` entries and use that number.
- Recall = caught / D
- Precision = caught / (caught + noise)
- Decoy flags = number of decoys flagged, out of 3

Precision includes decoy flags in noise. Recall counts only defects.

## Table

Fill one row per scored run. Do not overwrite earlier rows.

| Run date | Critic model | Builder model | Caught | Missed | Noise | Decoy flags | Recall | Precision | Notes |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

## When to re-score

Score again whenever the Critic prompt, the Critic model or these scoring rules change. A new row goes in the table each time. Compare the new row with the last row before you tune the Critic, so each change has a number behind it.
