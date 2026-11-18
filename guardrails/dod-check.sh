# Sourced by dod-gate.sh (Stop, a nudge) and pr-gate.sh (PreToolUse on Bash, the
# hard gate). One copy of the definition-of-done check so the two can't drift.
# Not run directly. Reads only the .atelier/ directory it is given. Writes nothing.
#
#   dod_missing <atelier-dir>   sets $DOD_MISSING to one line per missing artefact
#                               (empty when everything is there)
#
#   screenshots  renders/<slug>/manifest.json with at least one .png beside it
#   assumptions  assumptions.md, non-empty
#   tests        tests.json reporting {"pass": true}
#   critique     critique.md, non-empty, with a line starting "Verdict:"

dod_missing() {
    local a=$1 m p shots=0
    DOD_MISSING=""

    for m in "$a"/renders/*/manifest.json; do
        [ -f "$m" ] || continue
        for p in "$(dirname "$m")"/*.png; do
            [ -f "$p" ] && { shots=1; break 2; }
        done
    done
    [ "$shots" -eq 1 ] || DOD_MISSING="$DOD_MISSING
- screenshots: no .atelier/renders/<slug>/manifest.json with at least one .png beside it. Run the render harness."

    [ -s "$a/assumptions.md" ] || DOD_MISSING="$DOD_MISSING
- assumptions: .atelier/assumptions.md is missing or empty. Log every unspecified choice and invented component."

    jq -e '.pass == true' "$a/tests.json" >/dev/null 2>&1 || DOD_MISSING="$DOD_MISSING
- tests: .atelier/tests.json is missing or doesn't report {\"pass\": true}. Run the tests and record the result."

    if [ ! -s "$a/critique.md" ] || ! grep -qE '^Verdict:' "$a/critique.md"; then
        DOD_MISSING="$DOD_MISSING
- critique: .atelier/critique.md is missing, empty, or has no line starting 'Verdict:'. Get the Critic's review and save it."
    fi
    DOD_MISSING=$(printf '%s\n' "$DOD_MISSING" | sed '/^$/d')
}
