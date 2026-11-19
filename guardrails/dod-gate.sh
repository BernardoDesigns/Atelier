#!/bin/bash
# Stop hook: definition-of-done NUDGE for build sessions.
#
# In THE build session (<cwd>/.atelier/session.json exists and its sessionId equals
# the hook input's session_id; see session-lib.sh) it refuses to let the
# session stop while any of five requirements is unmet (screenshots, assumptions,
# a passing test run, a reviewed critique, and lane: no protected path changed;
# see dod-check.sh). Every missing item is listed in one message on stderr and
# the hook exits 2.
#
# Silent while the session is waiting for its own background work. The turn of
# the parent session ends while the Builder or Critic subagent runs in the
# background, and nudging then is noise: the artefacts are being made. The Stop
# input carries `background_tasks`, an array of objects, one per in-flight task
# ({"id","type","status","description",...}; the docs example has
# "status": "running"; https://code.claude.com/docs/en/hooks#stop-input).
# If at least one entry is an object whose status is not a finished state
# (completed, failed, killed, cancelled, stopped, ...) this exits 0. An absent
# field, a non-array, or entries that aren't objects count as no task, so the
# nudge behaves as before. session_crons is not looked at. pr-gate.sh never
# does this: the PR gate doesn't yield to background work.
#
# THIS IS A NUDGE, NOT THE HARD GATE. It refuses once per stop attempt and then
# yields: when stop_hook_active is true it exits 0. That is deliberate. The
# Builder has to be able to stop to ask the user a question, and a Stop hook that
# never yields would loop forever. The hard gate is pr-gate.sh, which blocks
# `gh pr create` until the same artefacts exist and never yields.
#
# Anywhere else it does nothing (exit 0, no output): no marker, a marker bound to
# another session, a marker with no sessionId, unreadable hook input, or input with
# no session_id. So it can't trap an unrelated session, even one in the same
# checkout while a build is open.
#
# No override file, no environment variable, no flag. The ways out are: meet the
# gate, remove .atelier/session.json by hand, or run guardrails/install.sh --relax.
#
# Fails open: if this script or session-lib.sh is missing, install.sh's wrapper
# (or the check below) warns and exits 1 (non-blocking), so a missing file can
# never trap a session. Reads only .atelier/. Writes nothing.

input=$(cat)

# shellcheck source=session-lib.sh
if ! . "$(dirname "$0")/session-lib.sh"; then
    echo "Atelier definition-of-done gate: session-lib.sh is missing; restore it or re-run guardrails/install.sh. Not blocking." >&2
    exit 1
fi

# Unreadable input: nothing can be bound to it, so this isn't the build session.
jq -e . >/dev/null 2>&1 <<<"$input" || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

a="$cwd/.atelier"
atelier_is_build_session "$a/session.json" "$input" || exit 0

# Waiting on its own background task (see the header): stay silent.
running=$(jq -r '
    [ (.background_tasks // empty) | if type == "array" then .[] else empty end
      | select(type == "object")
      | select(((.status // "running") | tostring | ascii_downcase)
               | IN("completed","complete","done","finished","failed","error","errored","killed","cancelled","canceled","stopped","exited","timed_out") | not)
    ] | length' <<<"$input" 2>/dev/null)
[ "${running:-0}" -gt 0 ] 2>/dev/null && exit 0

# shellcheck source=dod-check.sh
if ! . "$(dirname "$0")/dod-check.sh"; then
    echo "Atelier definition-of-done gate: dod-check.sh is missing; restore it or re-run guardrails/install.sh. Not blocking." >&2
    exit 1
fi
dod_missing "$a"
[ -n "$DOD_MISSING" ] || exit 0

{
    echo "Atelier definition of done: this build session can't end yet. Missing:"
    printf '%s\n' "$DOD_MISSING"
    echo "Finish these. If you cannot, tell the user; only the user can end a build session without them."
} >&2
exit 2
