# Sourced by dod-gate.sh (Stop, a nudge) and pr-gate.sh (PreToolUse on Bash, the
# hard gate). One copy of the definition-of-done check so the two can't drift.
# Not run directly. Reads only the .atelier/ directory it is given. Writes nothing.
#
#   dod_missing <atelier-dir>   sets $DOD_MISSING to one line per missing artefact
#                               (empty when everything is there)
#
#   screenshots  renders/<slug>/manifest.json with at least one .png beside it
#   assumptions  assumptions.md, non-empty
#   tests        tests.json reporting {"pass": true}, written by run-tests.sh (it
#                carries a numeric exitCode; a hand-written file without one is
#                treated as not recorded)
#   critique     critique.md, non-empty, with a line starting "Verdict:"
#   lane         no file under a protected path is changed on the branch or in the
#                working tree. Computed from git in the host repo (the parent of
#                the .atelier dir), not from tool calls, so it holds however the
#                file was written (Write, Edit, a shell redirect, a script).
#                Changed files = `git diff --name-only <base>...HEAD` plus
#                unstaged, staged and untracked files. <base> is main if it
#                exists, else master, else the branch origin/HEAD points to; with
#                no base, or no commits yet, only the working tree is checked.
#                Not a git repo: skipped. Protected paths = the four defaults in
#                lane-lib.sh (auth/, api/, payments/, lib/shared/) plus the
#                "protected" patterns of <repo>/.claude/lane-rules.json, matched
#                by the same function lane-guard.sh uses. A rules file that can't
#                be read adds nothing (the defaults still apply).

# shellcheck source=lane-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lane-lib.sh" 2>/dev/null || LANE_LIB_MISSING=1

# Prints the repo-relative paths changed on the branch or in the working tree.
lane_changed_files() { # <toplevel>
    local top=$1 base="" b
    for b in main master; do
        git -C "$top" rev-parse --verify -q "refs/heads/$b^{commit}" >/dev/null 2>&1 && { base=$b; break; }
    done
    if [ -z "$base" ]; then
        b=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
        [ -n "$b" ] && git -C "$top" rev-parse --verify -q "$b^{commit}" >/dev/null 2>&1 && base=$b
    fi
    {
        if [ -n "$base" ] && git -C "$top" rev-parse --verify -q HEAD >/dev/null 2>&1; then
            git -C "$top" -c core.quotepath=off diff --name-only "$base...HEAD" 2>/dev/null
        fi
        git -C "$top" -c core.quotepath=off diff --name-only 2>/dev/null
        git -C "$top" -c core.quotepath=off diff --name-only --cached 2>/dev/null
        git -C "$top" -c core.quotepath=off ls-files --others --exclude-standard 2>/dev/null
    } | sort -u
}

# Sets $LANE_OFFENDERS to "<file>|<rule>" lines (empty when clean).
lane_offenders() { # <repo-dir>
    local top rules f rule extra="" hit
    LANE_OFFENDERS=""
    [ -z "${LANE_LIB_MISSING:-}" ] || return 0   # dod_missing reports this itself
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
    rules="$top/.claude/lane-rules.json"
    if [ -f "$rules" ] && jq -e '(.protected | type) == "array" and all(.protected[]; type == "string")' "$rules" >/dev/null 2>&1; then
        extra=$(jq -r '.protected[]' "$rules")
    fi
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        hit=""
        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            lane_rule_matches "$f" "$rule" && { hit=$rule; break; }
        done <<<"$LANE_DEFAULT_RULES
$extra"
        [ -n "$hit" ] && LANE_OFFENDERS="$LANE_OFFENDERS
$f|$hit"
    done < <(lane_changed_files "$top")
    LANE_OFFENDERS=$(printf '%s\n' "$LANE_OFFENDERS" | sed '/^$/d')
}

dod_missing() {
    local a=$1 m p shots=0 f rule n=0
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

    if [ ! -f "$a/tests.json" ] || ! jq -e 'type == "object"' "$a/tests.json" >/dev/null 2>&1; then
        DOD_MISSING="$DOD_MISSING
- tests: .atelier/tests.json is missing or unreadable. Run the tests through ~/.claude/atelier/guardrails/run-tests.sh <command>."
    elif ! jq -e 'has("exitCode") and (.exitCode | type) == "number"' "$a/tests.json" >/dev/null 2>&1; then
        DOD_MISSING="$DOD_MISSING
- tests: .atelier/tests.json was not written by run-tests.sh; run the tests through ~/.claude/atelier/guardrails/run-tests.sh"
    elif ! jq -e '.pass == true' "$a/tests.json" >/dev/null 2>&1; then
        DOD_MISSING="$DOD_MISSING
- tests: .atelier/tests.json doesn't report {\"pass\": true}. Fix the failures and run the tests again through ~/.claude/atelier/guardrails/run-tests.sh <command>."
    fi

    if [ ! -s "$a/critique.md" ] || ! grep -qE '^Verdict:' "$a/critique.md"; then
        DOD_MISSING="$DOD_MISSING
- critique: .atelier/critique.md is missing, empty, or has no line starting 'Verdict:'. Get the Critic's review and save it."
    fi

    [ -z "${LANE_LIB_MISSING:-}" ] || DOD_MISSING="$DOD_MISSING
- lane: lane-lib.sh is missing, so the protected-path check can't run. Restore it or re-run guardrails/install.sh."
    lane_offenders "$(dirname "$a")"
    while IFS='|' read -r f rule; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        [ "$n" -le 20 ] || continue
        DOD_MISSING="$DOD_MISSING
- lane: $f is changed and sits under a protected path (rule '$rule'). Revert it (git restore --staged --worktree, or delete it if it is new) and tell the user."
    done <<<"$LANE_OFFENDERS"
    [ "$n" -le 20 ] || DOD_MISSING="$DOD_MISSING
- lane: and $((n - 20)) more files under protected paths. Revert them all and tell the user."
    DOD_MISSING=$(printf '%s\n' "$DOD_MISSING" | sed '/^$/d')
}
