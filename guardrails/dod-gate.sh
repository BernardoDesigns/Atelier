#!/bin/bash
# Stop hook: definition-of-done NUDGE for build sessions.
#
# In a build session (<cwd>/.atelier/session.json exists) it refuses to let the
# session stop while any of four artefacts is missing (screenshots, assumptions,
# a passing test run, a reviewed critique; see dod-check.sh). Every missing item
# is listed in one message on stderr and the hook exits 2.
#
# THIS IS A NUDGE, NOT THE HARD GATE. It refuses once per stop attempt and then
# yields: when stop_hook_active is true it exits 0. That is deliberate. The
# Builder has to be able to stop to ask the user a question, and a Stop hook that
# never yields would loop forever. The hard gate is pr-gate.sh, which blocks
# `gh pr create` until the same artefacts exist and never yields.
#
# Outside a build session it does nothing (exit 0, no output), so it can't trap
# an unrelated session.
#
# No override file, no environment variable, no flag. The ways out are: meet the
# gate, remove .atelier/session.json by hand, or run guardrails/install.sh --relax.
#
# Inside a build session unreadable stdin exits 2. If this script is missing,
# install.sh's wrapper warns and exits 1 (non-blocking), so a missing file can
# never trap a session. Reads only .atelier/. Writes nothing.

input=$(cat)
valid=1
jq -e . >/dev/null 2>&1 <<<"$input" || valid=0

cwd=""
if [ "$valid" -eq 1 ]; then
    [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0
    cwd=$(jq -r '.cwd // empty' <<<"$input")
fi
[ -n "$cwd" ] || cwd=$PWD

a="$cwd/.atelier"
[ -f "$a/session.json" ] || exit 0

if [ "$valid" -ne 1 ]; then
    echo "Atelier definition-of-done gate: couldn't read the hook input in a build session, so this is blocked. Tell the user; only they can leave the build session or relax enforcement." >&2
    exit 2
fi

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
