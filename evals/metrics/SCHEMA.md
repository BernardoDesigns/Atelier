# Benchmark run metrics

One row per benchmark run, stored as one JSON object per line in `log.jsonl`. The log is append only. Never edit or delete a row. If a row was wrong, leave it and say so in the PR that adds the next rows.

Rows are written by the build's foreman. A run happens in the proving ground, and the foreman records its row in Atelier through a pull request. Nothing commits metrics rows from the proving ground repo.

The row format is defined by `schema.json` (JSON Schema draft-07). `sample-row.json` is a valid example with invented numbers. It is for reference only and must never be appended to `log.jsonl`.

## Fields

Units are given where they apply. "Source" says who fills the field in and where the value comes from.

### Identity

| Field | Type | Unit or format | Source |
|---|---|---|---|
| `run_id` | string | Unique. Timestamp plus ticket, for example `20261118T1430-t02` | Foreman, when the run is recorded |
| `date` | string | ISO calendar date, `YYYY-MM-DD` | Foreman, the date the run finished |
| `ticket` | integer | 1 to 5, matching `evals/tickets/NN-slug/` | Foreman, from the run dispatch |
| `routing` | object | `builder` and `critic` hold the model names used for each agent | Foreman, from the run dispatch |
| `branch` | string | Git branch the run built on | The `branch` value in `.atelier/session.json` |

### Metrics

| Field | Type | Unit or range | Source |
|---|---|---|---|
| `first_try_ci_pass` | boolean | `true` when the first CI run on the first push passed with no fix commits | CI result for the first push of the PR |
| `invented_component_count` | integer | Count, 0 or more | Assumptions log: components not in the design system manifest (G1) |
| `axe_violations` | object | `serious` and `critical` counts, 0 or more each | Sum of axe counts across all shots in the render harness output (G5) |
| `critic_score` | number | 1 to 5. Mean of the five principle scores P1 to P5 | `.atelier/critique.md`, principle scores (G10) |
| `review_minutes` | number | Minutes, 0 or more | Reviewer self-report at `/wrap`: minutes from opening the PR to the decision, rounded to the nearest 0.5. Not tracked by a tool |
| `critic_issues_agreed` | object | `agreed` and `total` counts. `agreed` must not exceed `total` | Reviewer at `/wrap`. `total` is the number of Critic findings. `agreed` is the number the reviewer accepted. The schema cannot check `agreed <= total`, so check it by hand when the row is entered |
| `cost_per_accepted_pr` | number or null | USD. Null when the PR is not accepted | Model spend for the run from the provider usage record. Recorded only when the PR is accepted |

Cost is measured per accepted PR, not per token. A run that produces a PR nobody accepts still has a row, with `cost_per_accepted_pr` set to `null`.

## Shadow runs

Before a model swap, run the same ticket under two routing setups. Each run gets its own row, with the same `ticket` and `date` range and a different `routing`. Compare the two rows on `cost_per_accepted_pr`, and read the other metrics alongside it. Give each row its own `run_id`.
