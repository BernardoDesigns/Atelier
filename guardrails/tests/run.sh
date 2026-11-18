#!/bin/bash
# Guardrail test runner.
#   bash guardrails/tests/run.sh              every hook, then the extra suites
#   bash guardrails/tests/run.sh <hook-name>  one fixtures dir (or: installer, lane-init)
#
# Adding a hook: add fixtures/<name>/<case>/ dirs and one line to HOOKS_MAP.
# Everything runs against mktemp dirs. Nothing here touches the real ~/.claude.

T="$(cd "$(dirname "$0")" && pwd)"
G="$(cd "$T/.." && pwd)"
# shellcheck source=lib.sh
. "$T/lib.sh"

# <fixtures-dir>=<command run with the hook JSON on stdin>
HOOKS_MAP="
outside-repo-guard=bash '$G/outside-repo-guard.sh'
net-host-guard=python3 -I '$G/net-host-guard.py'
conventions-injector=bash '$G/conventions-injector.sh'
fast-gate=bash '$G/fast-gate.sh'
lane-guard=bash '$G/lane-guard.sh'
dod-gate=bash '$G/dod-gate.sh'
pr-gate=bash '$G/pr-gate.sh'
"

pass=0; fail=0
tally() { if [ "$1" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi; }

run_hook_dir() { # <name> <cmd>
    local d
    for d in "$T/fixtures/$1"/*/; do
        [ -f "$d/input.json" ] || continue
        run_case "$2" "${d%/}"; tally $?
    done
}

# Run a standalone suite script that prints PASS/FAIL lines.
run_suite() { # <script> <required: 1|0>
    local out code p f
    if [ ! -f "$T/$1" ]; then
        [ "$2" = 1 ] && echo "SKIP $1 (not written yet)"
        return
    fi
    out=$(bash "$T/$1" 2>&1); code=$?
    printf '%s\n' "$out"
    p=$(grep -c '^PASS' <<<"$out"); f=$(grep -c '^FAIL' <<<"$out")
    pass=$((pass + p)); fail=$((fail + f))
    if [ "$code" -ne 0 ] && [ "$f" -eq 0 ]; then
        echo "FAIL $1 exited $code"; fail=$((fail + 1))
    fi
}

# Installer tests (L3-06 writes installer.sh) and lane-guard init tests (L3-04).
run_installer_tests() { run_suite installer.sh 1; }
run_lane_init_tests() { run_suite lane-init.sh 0; }

only=${1:-}
known=0
while IFS='=' read -r name cmd; do
    [ -n "$name" ] || continue
    if [ -z "$only" ] || [ "$only" = "$name" ]; then
        known=1; run_hook_dir "$name" "$cmd"
    fi
done <<<"$HOOKS_MAP"
if [ -z "$only" ] || [ "$only" = lane-init ]; then known=1; run_lane_init_tests; fi
if [ -z "$only" ] || [ "$only" = installer ]; then known=1; run_installer_tests; fi
[ "$known" -eq 1 ] || { echo "unknown hook: $only"; exit 2; }

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
