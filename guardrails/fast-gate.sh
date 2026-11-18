#!/bin/bash
# PostToolUse hook for Write / Edit.
#
# After an edit to a .ts, .tsx, .js or .jsx file in a build session, runs
# `tsc --noEmit` and `eslint <file>` from the repo root using the host's local
# binaries (node_modules/.bin), and hands any errors back to the model: exit 2
# with the first ~40 lines on stderr.
#
# Does nothing (exit 0, no output, no tool invoked) unless
# <cwd>/.atelier/session.json exists. That check comes first, so this can't
# interfere with an unrelated session if it is enforced user-wide.
#
# A tool that isn't installed is skipped and named in the feedback; it doesn't
# fail the gate. Each tool gets 60 seconds (ATELIER_GATE_TIMEOUT overrides, for
# tests); a timeout is reported as an error.
#
# Never runs --fix, never touches source files. Its only writes are two scratch
# files inside .atelier/ (fast-gate.tsc.out, fast-gate.eslint.out), overwritten each run.
# It does not write .atelier/tests.json; the Builder does that after a test run.
#
# Fails closed inside a build session: unreadable stdin exits 2. install.sh
# wraps this script so a missing script exits 2 too.

TIMEOUT=${ATELIER_GATE_TIMEOUT:-60}
MAXLINES=40

input=$(cat)
valid=1
jq -e . >/dev/null 2>&1 <<<"$input" || valid=0

cwd=""
[ "$valid" -eq 1 ] && cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

[ -f "$cwd/.atelier/session.json" ] || exit 0

if [ "$valid" -ne 1 ]; then
    echo "Atelier fast gate: couldn't read the hook input in a build session, blocking. Use guardrails/install.sh --relax to turn it off." >&2
    exit 2
fi

target=$(jq -r '.tool_input.file_path // empty' <<<"$input")
case "${target##*.}" in
    ts|tsx|js|jsx) ;;
    *) exit 0 ;;
esac
case "$target" in
    *.*) ;;
    *) exit 0 ;;
esac

# Run a command with a time limit (macOS has no timeout(1)). Output goes to $2.
run_limited() { # <outfile> <cmd...>
    local outfile=$1; shift
    "$@" >"$outfile" 2>&1 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$TIMEOUT" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "[timed out after ${TIMEOUT}s]" >>"$outfile"
            return 124
        fi
        sleep 1; waited=$((waited + 1))
    done
    wait "$pid"
}

cd "$cwd" || exit 0
tmp="$cwd/.atelier"
errors=""
notes=""

bin="$cwd/node_modules/.bin"
if [ -x "$bin/tsc" ]; then
    run_limited "$tmp/fast-gate.tsc.out" "$bin/tsc" --noEmit
    [ $? -eq 0 ] || errors="$errors
tsc --noEmit:
$(cat "$tmp/fast-gate.tsc.out")"
else
    notes="$notes
tsc is not installed in node_modules/.bin, so it was skipped."
fi

if [ ! -x "$bin/eslint" ]; then
    notes="$notes
eslint is not installed in node_modules/.bin, so it was skipped."
elif [ -f "$target" ] || [ -f "$cwd/$target" ]; then
    run_limited "$tmp/fast-gate.eslint.out" "$bin/eslint" "$target"
    [ $? -eq 0 ] || errors="$errors
eslint $target:
$(cat "$tmp/fast-gate.eslint.out")"
fi

[ -n "$errors" ] || exit 0

{
    echo "Atelier fast gate: fix these before moving on."
    printf '%s\n' "$errors" | head -n "$MAXLINES"
    [ -z "$notes" ] || printf '%s\n' "$notes"
} >&2
exit 2
