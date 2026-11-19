#!/bin/bash
# Run the host's tests and RECORD the result in .atelier/tests.json.
#
#   ~/.claude/atelier/guardrails/run-tests.sh <command> [args...]
#
# The command is the test command as separate arguments and runs as "$@" in the
# current directory. There is no eval of a string. A command that needs && or a
# pipe is passed as `bash -lc '...'` by the caller. Its output goes through
# untouched. Afterwards .atelier/tests.json is written (temp file, then mv) as
#
#   {"pass": <true when the exit code is 0>, "command": "<the command as given>",
#    "ranAt": "<UTC time from date, e.g. 2026-11-19T14:03:27Z>", "exitCode": <n>}
#
# and this script exits with the command's own exit code. dod-check.sh reads that
# file, and treats one with no exitCode as typed by hand, not recorded.
#
# Needs an existing .atelier/ directory in the current directory and refuses
# otherwise (exit 2, nothing run). It does not need the session marker, so /wrap
# can re-run the tests through it too. Run it from the repo root.

if [ $# -eq 0 ]; then
    echo "usage: run-tests.sh <command> [args...]" >&2
    exit 2
fi
if [ ! -d .atelier ]; then
    echo "run-tests.sh: no .atelier/ directory in $PWD, so there is nowhere to record the result. Run it from the repo root of an open build." >&2
    exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "run-tests.sh: needs jq to write .atelier/tests.json." >&2; exit 2; }

"$@"
code=$?

ran=$(date -u +%Y-%m-%dT%H:%M:%SZ)
pass=false
[ "$code" -eq 0 ] && pass=true
tmp=$(mktemp ".atelier/tests.json.XXXXXX") || { echo "run-tests.sh: couldn't write .atelier/tests.json." >&2; exit "$code"; }
if jq -n --argjson pass "$pass" --arg cmd "$*" --arg ran "$ran" --argjson code "$code" \
    '{pass: $pass, command: $cmd, ranAt: $ran, exitCode: $code}' >"$tmp" \
    && mv "$tmp" .atelier/tests.json; then
    :
else
    echo "run-tests.sh: couldn't write .atelier/tests.json." >&2
    rm -f "$tmp"
fi
exit "$code"
