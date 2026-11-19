#!/bin/bash
# PostToolUse hook for Write / Edit.
#
# After an edit to a .ts, .tsx, .js or .jsx file in THE build session, runs
# `tsc --noEmit` and `eslint <file>` from the repo root using the host's local
# binaries (node_modules/.bin), and hands any errors back to the model: exit 2
# with the first ~40 lines on stderr.
#
# Does nothing (exit 0, no output, no tool invoked) unless
# <cwd>/.atelier/session.json exists AND its sessionId equals the hook input's
# session_id (session-lib.sh). A marker bound to another session, a marker with no
# sessionId, unreadable input and input with no session_id all do nothing. That
# check comes first, so this can't interfere with an unrelated session, even one in
# the same checkout while a build is open.
#
# A tool that isn't installed is skipped and named in the feedback; it doesn't
# fail the gate. Each tool gets 60 seconds (ATELIER_GATE_TIMEOUT overrides, for
# tests); a timeout is reported as an error.
#
# Never runs --fix, never touches source files. Its only writes are two scratch
# files inside .atelier/ (fast-gate.tsc.out, fast-gate.eslint.out), overwritten each run.
# It does not write .atelier/tests.json; the Builder does that after a test run.
#
# Fails open (PostToolUse): if this script or session-lib.sh is missing, install.sh's
# wrapper (or the check below) warns and exits 1, which doesn't block.

TIMEOUT=${ATELIER_GATE_TIMEOUT:-60}
MAXLINES=40

input=$(cat)

# shellcheck source=session-lib.sh
if ! . "$(dirname "$0")/session-lib.sh"; then
    echo "Atelier fast gate: session-lib.sh is missing, so this check was skipped; restore it or re-run guardrails/install.sh" >&2
    exit 1
fi

jq -e . >/dev/null 2>&1 <<<"$input" || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

atelier_is_build_session "$cwd/.atelier/session.json" "$input" || exit 0

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
