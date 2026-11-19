# Sourced by lane-guard.sh and dod-check.sh. Not run directly. Reads and writes nothing.
#
# One copy of the protected-path matching, so the lane guard (a write through
# Write/Edit) and the definition-of-done "lane" check (what git says changed)
# can't disagree about what is protected.
#
#   LANE_DEFAULT_RULES               the four defaults, same paths as
#                                    lane-guard-deny.json (project-root anchored)
#   lane_rule_matches <rel> <rule>   0 when the repo-relative path <rel> is
#                                    covered by <rule>. Rule syntax is the one
#                                    documented in lane-guard.sh: a trailing "/"
#                                    protects a directory, "*" and "**" match
#                                    across segments, a plain path is the file or
#                                    anything under it, case-insensitive.

LANE_DEFAULT_RULES="auth/
api/
payments/
lib/shared/"

lane_rule_matches() {
    local rel=$1 rule=$2 pat rc=1 had=0
    shopt -q nocasematch && had=1
    shopt -s nocasematch
    pat=${rule#./}; pat=${pat#/}
    if [ -n "$pat" ]; then
        if [[ "$pat" == */ ]]; then
            pat="${pat}*"
        elif [[ "$pat" != *[\*\?\[]* ]]; then
            # A plain path: the file itself, or anything under it as a directory.
            [[ "$rel" == "$pat" ]] && rc=0
            pat="$pat/*"
        fi
        # shellcheck disable=SC2053
        [[ "$rel" == $pat ]] && rc=0
    fi
    [ "$had" -eq 1 ] || shopt -u nocasematch
    return $rc
}
