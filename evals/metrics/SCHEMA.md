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
| `critic_score` | number | 1 to 5. Mean of the five principle scores P1 to P5 | The last `/build` pass of the Critic, principle scores (G10) |
| `review_minutes` | number | Minutes, 0 or more, rounded to the nearest 0.5 | Owner self-report. Time from the Critic's findings being posted in the session to the owner's one-line verdict at `/wrap` step 3. No tool records it |
| `critic_issues_agreed` | object | `agreed` and `total` counts. `agreed` must not exceed `total` | The last `/build` pass of the Critic. `agreed` counts findings the owner marked `fix` or `later`. `disagree` is not agreed. Findings with no token are excluded from `total`. The schema cannot check `agreed <= total`, so check it by hand when the row is entered |
| `cost_usd` | number | USD, 0 or more. An estimate | Spend for this run, whether or not the PR was accepted. Taken from the usage shown for the session. It is an estimate, because the session usage display is approximate |
| `accepted` | boolean | `true` when the run's PR was merged | The PR state in Atelier after the review, recorded by the foreman |

Every row has `cost_usd` and `accepted`, so the log keeps the spend of runs that were not accepted too.

## Cost per accepted PR

Cost per accepted PR is a derived figure. It is not stored in any row. To compute it for a set of rows being compared:

    cost per accepted PR = sum of cost_usd over the rows / count of rows where accepted is true

If no row in the set has `accepted` true, the figure is undefined. Report that, not zero.

Cost is measured per accepted PR, not per token. A run whose PR nobody accepts still has a row with its `cost_usd`, and its cost counts toward the total for the set.

## Shadow runs

Before a model swap, run the same ticket under two routing setups. Each run gets its own row, with the same `ticket` and `date` range and a different `routing`. Compare the two sets on the derived cost per accepted PR, and read the other metrics alongside it. Give each row its own `run_id`.
