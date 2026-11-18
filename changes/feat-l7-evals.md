## Changelog

- Added `evals/tickets/`: five standing benchmark tickets (settings form, data table, onboarding, destructive confirm, notification preferences), each a SPEC in the gear desk domain.
- Added `evals/metrics/`: schema for one row per benchmark run covering the seven Phase 7 metrics, a sample row, and an empty append-only log.
- Added `evals/calibration/`: fifteen seeded defects across gates G1 to G10 and principles P1 to P5, three decoys, and a scoring sheet for Critic runs.
- Added `evals/tests/check.sh`: stdlib-only checks for the tickets, metrics schema and calibration set.

## README

| File | What it is |
|---|---|
| `evals/tickets/` | Five benchmark SPECs for the regression suite |
| `evals/metrics/` | Per-run metrics schema, sample row and append-only log |
| `evals/calibration/` | Seeded defects, decoys and the Critic scoring sheet |
| `evals/tests/check.sh` | Checks for the evals folder, run with `bash evals/tests/check.sh` |

## Setup

none
