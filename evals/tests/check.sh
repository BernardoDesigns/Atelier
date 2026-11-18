#!/usr/bin/env bash
# check.sh - Lane 7 checks for the evals folder.
#
# Checks the five benchmark tickets, the metrics schema and sample row,
# any rows in the metrics log, and the Critic calibration set.
#
# Usage:  bash evals/tests/check.sh [repo-root]
# Needs:  bash and python3 (standard library only, no installs).
# Exit:   0 when every check passes, 1 when any check fails, 2 on usage error.

set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"

if [ ! -f "$ROOT/quality.md" ]; then
  echo "check.sh: no quality.md under $ROOT" >&2
  exit 2
fi

python3 -I - "$ROOT" <<'PY'
import glob
import json
import os
import re
import sys

root = sys.argv[1]
failures = 0


def report(ok, name, detail=""):
    global failures
    if ok:
        print("PASS  " + name)
    else:
        failures += 1
        print("FAIL  " + name + (": " + detail if detail else ""))


def read_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def rel(path):
    return os.path.relpath(path, root)


# ---------------------------------------------------------------- tickets

TICKET_HEADINGS = [
    "Goal",
    "User and core tension",
    "Acceptance criteria",
    "States to cover",
    "Visual baseline",
    "Out of scope and protected paths",
    "Definition of done",
    "Open questions",
]

ticket_files = sorted(glob.glob(os.path.join(root, "evals", "tickets", "*", "SPEC.md")))
report(len(ticket_files) == 5, "five ticket SPEC files exist",
       "found %d" % len(ticket_files))

for path in ticket_files:
    name = rel(path)
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")

    report(bool(lines) and lines[0].startswith("# ") and not lines[0].startswith("## "),
           name + ": starts with a # title line")

    headings = [l[3:].strip() for l in lines if l.startswith("## ")]
    report(headings == TICKET_HEADINGS,
           name + ": eight ## headings in contract order",
           "got %s" % headings)

    states = []
    inside = False
    for line in lines:
        if line.startswith("## "):
            inside = line[3:].strip() == "States to cover"
            continue
        if inside and line.startswith("- "):
            states.append(line[2:].strip())

    report(len(states) >= 3, name + ": at least three states",
           "found %d" % len(states))

    bare = [s for s in states if not re.fullmatch(r"[a-z][a-z ]*[a-z]", s)]
    report(not bare, name + ": each state is a bare name on its own line",
           "odd lines: %s" % bare)

    if os.path.basename(os.path.dirname(path)).startswith("02-"):
        for needed in ("loading", "empty", "error", "paginated"):
            report(needed in states, name + ": states include " + needed)

# ---------------------------------------------------------------- metrics

TYPE_OK = {
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "object": lambda v: isinstance(v, dict),
    "null": lambda v: v is None,
}


def validate(value, spec, where):
    """Validate against the JSON Schema subset this folder uses."""
    errors = []
    types = spec.get("type")
    if isinstance(types, str):
        types = [types]
    if types and not any(TYPE_OK[t](value) for t in types):
        return ["%s: expected %s" % (where, "/".join(types))]
    if value is None:
        return errors
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in spec and value < spec["minimum"]:
            errors.append("%s: below %s" % (where, spec["minimum"]))
        if "maximum" in spec and value > spec["maximum"]:
            errors.append("%s: above %s" % (where, spec["maximum"]))
    if isinstance(value, str):
        if "minLength" in spec and len(value) < spec["minLength"]:
            errors.append("%s: shorter than %s" % (where, spec["minLength"]))
        if "pattern" in spec and not re.search(spec["pattern"], value):
            errors.append("%s: does not match pattern" % where)
    if isinstance(value, dict) and "properties" in spec:
        for key in spec.get("required", []):
            if key not in value:
                errors.append("%s.%s: missing" % (where, key))
        for key, sub in spec["properties"].items():
            if key in value:
                errors.extend(validate(value[key], sub, where + "." + key))
        if spec.get("additionalProperties") is False:
            for key in value:
                if key not in spec["properties"]:
                    errors.append("%s.%s: not allowed" % (where, key))
    return errors


schema_path = os.path.join(root, "evals", "metrics", "schema.json")
schema = read_json(schema_path)

IDENTITY = ["run_id", "date", "ticket", "routing", "branch"]
METRICS = [
    "first_try_ci_pass", "invented_component_count", "axe_violations",
    "critic_score", "review_minutes", "critic_issues_agreed",
    "cost_per_accepted_pr",
]
report(sorted(schema.get("required", [])) == sorted(IDENTITY + METRICS),
       "schema requires the five identity fields and seven metric fields")

sample_path = os.path.join(root, "evals", "metrics", "sample-row.json")
sample = read_json(sample_path)
for key in schema.get("required", []):
    report(key in sample, "sample row has required field " + key)

errs = validate(sample, schema, "sample")
report(not errs, "sample row matches schema.json types and ranges",
       "; ".join(errs))

agreed = sample.get("critic_issues_agreed", {})
report(agreed.get("agreed", 0) <= agreed.get("total", 0),
       "sample row: critic_issues_agreed.agreed does not exceed total")

log_path = os.path.join(root, "evals", "metrics", "log.jsonl")
if os.path.exists(log_path):
    bad = []
    with open(log_path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except ValueError as exc:
                bad.append("line %d: %s" % (n, exc))
                continue
            bad.extend(validate(row, schema, "log line %d" % n))
    report(not bad, "metrics log rows match schema.json", "; ".join(bad))

# ---------------------------------------------------------------- calibration

with open(os.path.join(root, "quality.md"), encoding="utf-8") as fh:
    quality = fh.read()
QUALITY_IDS = set(re.findall(r"^\|\s*([GP][0-9]+)\s*\|", quality, re.M))
GATES = {i for i in QUALITY_IDS if i.startswith("G")}
PRINCIPLES = {i for i in QUALITY_IDS if i.startswith("P")}
report(len(GATES) == 10 and len(PRINCIPLES) == 5,
       "quality.md lists gates G1 to G10 and principles P1 to P5",
       "gates %d, principles %d" % (len(GATES), len(PRINCIPLES)))

defects_path = os.path.join(root, "evals", "calibration", "defects.json")
entries = read_json(defects_path)
report(isinstance(entries, list), "defects.json is an array")
if not isinstance(entries, list):
    entries = []

kinds_ok = all(isinstance(e, dict) and e.get("kind") in ("defect", "decoy") for e in entries)
report(kinds_ok, "every entry in defects.json has kind defect or decoy")

defects = [e for e in entries if isinstance(e, dict) and e.get("kind") == "defect"]
decoys = [e for e in entries if isinstance(e, dict) and e.get("kind") == "decoy"]

ids = [e.get("id") for e in entries if isinstance(e, dict)]
report(len(ids) == len(set(ids)) and all(ids), "entry ids are present and unique")

report(12 <= len(defects) <= 15, "12 to 15 seeded defects",
       "found %d" % len(defects))

DEFECT_FIELDS = ["id", "what", "where", "breaks", "severity"]
for d in defects:
    label = str(d.get("id", "?"))
    missing = [f for f in DEFECT_FIELDS if f not in d]
    report(not missing, label + ": has id, what, where, breaks and severity",
           "missing %s" % missing)
    report(d.get("severity") in ("low", "medium", "high"),
           label + ": severity is low, medium or high")
    breaks = d.get("breaks")
    report(isinstance(breaks, str) and breaks in QUALITY_IDS,
           label + ": breaks names one ID that exists in quality.md",
           "got %r" % (breaks,))
    report(bool(str(d.get("where", "")).strip()), label + ": where is set")

covered = {d.get("breaks") for d in defects}
missing_gates = sorted(GATES - covered, key=lambda g: int(g[1:]))
report(not missing_gates, "defects cover every gate G1 to G10",
       "not covered: %s" % missing_gates)
covered_principles = {p for p in covered if isinstance(p, str) and p.startswith("P")}
report(len(covered_principles) >= 2, "defects cover at least two principles",
       "covered: %s" % sorted(covered_principles))

report(len(decoys) == 3, "exactly 3 decoys", "found %d" % len(decoys))
for d in decoys:
    label = str(d.get("id", "?"))
    report(bool(str(d.get("reason", "")).strip()), label + ": decoy has a reason")

# ---------------------------------------------------------------- summary

if failures:
    print("RESULT  FAIL  (%d check%s failed)" % (failures, "" if failures == 1 else "s"))
    sys.exit(1)
print("RESULT  PASS")
sys.exit(0)
PY
exit $?
