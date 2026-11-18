# Assumptions

One entry per choice the SPEC did not specify, and one per component invented instead of taken from the system. The Builder appends entries to `.atelier/assumptions.md` as it works. Ids run `A1`, `A2`, `A3` in order, so a verdict like `A2 wrong` points at one entry.

## A1
- Choice: <what was decided>
- Why: <one line>
- Kind: <unspecified | invented-component>
- Where: <file path>
- Verdict:

## A2
- Choice: <what was decided>
- Why: <one line>
- Kind: <unspecified | invented-component>
- Where: <file path>
- Verdict:

In diverge mode each option has its own `.atelier/assumptions.md` in its own worktree.

The Verdict line stays blank until `/wrap`, where it becomes `right` or `wrong`. An entry not mentioned in the verdict line counts as right.
