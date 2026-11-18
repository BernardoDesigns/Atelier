#!/bin/bash
# Stop hook: definition-of-done gate for build sessions.
#
# In a build session (<cwd>/.atelier/session.json exists) the session can't end
# until all four artefacts exist:
#
#   screenshots  .atelier/renders/<slug>/manifest.json with at least one .png beside it
#   assumptions  .atelier/assumptions.md, non-empty
#   tests        .atelier/tests.json reporting {"pass": true}
#   critique     .atelier/critique.md, non-empty, with a line starting "Verdict:"
#
# Every missing item is listed in one message on stderr and the hook exits 2.
# Everything present: exit 0, no output.
#
# Outside a build session it does nothing (exit 0, no output), so it can't trap
# an unrelated session. It also exits 0 when stop_hook_active is true, so one
# refusal can never become a loop.
#
# THERE IS NO OVERRIDE. No override file, no environment variable, no flag. The
# ways out are: meet the gate, remove .atelier/session.json by hand, or run
# guardrails/install.sh --relax.
#
# Fails closed inside a build session: unreadable stdin exits 2. install.sh wraps
# this script so a missing script exits 2 too. Reads only .atelier/. Writes
# nothing.

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

missing=""

shots=0
for m in "$a"/renders/*/manifest.json; do
    [ -f "$m" ] || continue
    for p in "$(dirname "$m")"/*.png; do
        [ -f "$p" ] && { shots=1; break 2; }
    done
done
[ "$shots" -eq 1 ] || missing="$missing
- screenshots: no .atelier/renders/<slug>/manifest.json with at least one .png beside it. Run the render harness."

[ -s "$a/assumptions.md" ] || missing="$missing
- assumptions: .atelier/assumptions.md is missing or empty. Log every unspecified choice and invented component."

jq -e '.pass == true' "$a/tests.json" >/dev/null 2>&1 || missing="$missing
- tests: .atelier/tests.json is missing or doesn't report {\"pass\": true}. Run the tests and record the result."

if [ ! -s "$a/critique.md" ] || ! grep -qE '^Verdict:' "$a/critique.md"; then
    missing="$missing
- critique: .atelier/critique.md is missing, empty, or has no line starting 'Verdict:'. Get the Critic's review and save it."
fi

[ -n "$missing" ] || exit 0

{
    echo "Atelier definition of done: this build session can't end yet. Missing:"
    printf '%s\n' "$missing" | sed '/^$/d'
    echo "Finish these. If you cannot, tell the user; only the user can end a build session without them."
} >&2
exit 2
