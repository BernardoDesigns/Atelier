#!/bin/bash
# Opens a build session: writes .atelier/session.json bound to the calling
# session. Run by /build (and by the Builder, once per option worktree in
# diverge mode) through Bash, as the ONLY command on the line:
#
#   ~/.claude/atelier/guardrails/session-open.sh <spec> <branch> [<dir>]
#
# <dir> defaults to the current directory (the repo or option worktree that gets
# the marker). The marker is { "spec": ..., "branch": ..., "sessionId": ... }, plus
# "startCommit" (HEAD when the build opened, if the repo has one) and "baseline"
# (see below).
#
# Baseline: on a fresh open (not a refresh) it also runs the repo's type check
# (see typecheck-lib.sh) and stores the errors it finds in .atelier/baseline.tsc.txt,
# as file, error code and message, no line numbers. fast-gate.sh then reports only
# errors the Builder adds. The check gets the same time limit as the gate
# (ATELIER_GATE_TIMEOUT, default 60s). If it can't run (no tsc, timeout, crash) the
# open still succeeds, no baseline is stored and one line says so. It prints
# "baseline: N type errors recorded". A refresh keeps the first open's baseline.
#
# The script can't see its caller's session id. pr-gate.sh (PreToolUse on Bash)
# can: just before this command runs it recognises exactly this command and
# writes <dir>/.atelier/session-claim (session_id, epoch). This script reads that
# claim, uses it, and deletes it. A claim older than 2 minutes is ignored.
#
# Rules:
#   - no marker, or one with no sessionId and the same spec: claimed for this session
#   - a marker with no sessionId for a different spec: exit 1 (ask the user)
#   - marker owned by this session, same spec: refreshed (re-claim), exit 0
#   - marker owned by this session, different spec: exit 1 (ask the user)
#   - marker owned by another session: never touched, exit 1, says so
#   - no claim at all: exit 1 (the enforce hooks aren't installed, or the command
#     wasn't the bare script call); nothing is written
#
# Archive: opening a build when no session.json is present first moves whatever
# an earlier build left in <dir>/.atelier/ (everything except archive/ itself)
# into .atelier/archive/<UTC timestamp>-<branch of the closed build, or unknown>/,
# so the gates can't be satisfied by the previous build's screenshots, tests or
# critique. Moved with mv, never deleted; a name that exists gets a -2, -3 suffix.
# Refreshing your own marker, and every refusal, archive nothing. If any move
# fails the script stops (exit 2) and writes no marker.
#
# Exit 0 prints "opened: ..." (after an "archived ..." line when it archived);
# every refusal prints why on stderr.
# Needs jq. Writes <dir>/.atelier/session.json (via a temp file), moves old
# artefacts into .atelier/archive/, and deletes the claim.

spec=${1:-}; branch=${2:-}; dir=${3:-.}
if [ -z "$spec" ] || [ -z "$branch" ] || [ $# -gt 3 ]; then
    echo "usage: session-open.sh <spec> <branch> [<dir>]" >&2; exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "session-open: needs jq" >&2; exit 2; }
dir=$(cd "$dir" 2>/dev/null && pwd -P) || { echo "session-open: no such directory: ${3:-.}" >&2; exit 2; }
a="$dir/.atelier"
claim="$a/session-claim"
marker="$a/session.json"

sid=""
if [ -f "$claim" ]; then
    csid=$(sed -n 1p "$claim"); cts=$(sed -n 2p "$claim")
    rm -f "$claim"
    now=$(date +%s)
    if [ -n "$csid" ] && [ "${cts:-0}" -ge $((now - 120)) ] 2>/dev/null; then sid=$csid; fi
fi
if [ -z "$sid" ]; then
    {
        echo "session-open: couldn't tell which session is calling, so no build was opened and nothing was written."
        echo "Either the session-binding hook isn't running (re-run guardrails/install.sh --enforce) or this wasn't the bare command on its own line."
        if [ -f "$marker" ]; then
            echo "A build marker already exists here: spec $(jq -r '.spec // "?"' "$marker" 2>/dev/null), branch $(jq -r '.branch // "?"' "$marker" 2>/dev/null)."
        fi
    } >&2
    exit 1
fi

if [ -f "$marker" ]; then
    owner=$(jq -r 'if (.sessionId | type) == "string" then .sessionId else "" end' "$marker" 2>/dev/null)
    mspec=$(jq -r '.spec // ""' "$marker" 2>/dev/null)
    if [ -n "$owner" ] && [ "$owner" != "$sid" ]; then
        echo "session-open: a build is already open here (spec $mspec) and it belongs to another session. Not touching it. Tell the user; they can close it from that session with /wrap, or remove $marker by hand." >&2
        exit 1
    fi
    if [ "$mspec" != "$spec" ]; then
        echo "session-open: a build marker for a different spec ($mspec) already exists here. Stop and ask the user; do not overwrite it." >&2
        exit 1
    fi
fi

if [ ! -f "$marker" ] && [ -d "$a" ]; then
    # The claim is already consumed above, so anything left is an earlier build's.
    left=$(find "$a" -mindepth 1 -maxdepth 1 ! -name archive 2>/dev/null | head -n 1)
    if [ -n "$left" ]; then
        cb=""
        [ -f "$a/session.closed.json" ] && cb=$(jq -r 'if (.branch | type) == "string" then .branch else "" end' "$a/session.closed.json" 2>/dev/null)
        cb=$(printf '%s' "$cb" | tr -c 'A-Za-z0-9._-' '-')
        [ -n "$cb" ] || cb=unknown
        base="$(date -u +%Y%m%dT%H%M%SZ)-$cb"
        mkdir -p "$a/archive" || { echo "session-open: couldn't create $a/archive, so nothing was archived and no build was opened." >&2; exit 2; }
        name=$base; n=1
        until mkdir "$a/archive/$name" 2>/dev/null; do
            [ -e "$a/archive/$name" ] || { echo "session-open: couldn't create $a/archive/$name, so nothing was archived and no build was opened." >&2; exit 2; }
            n=$((n + 1)); name="$base-$n"
        done
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            mv "$entry" "$a/archive/$name/" || {
                echo "session-open: couldn't move $entry into $a/archive/$name/. No build was opened. Part of the old artefacts may already be in that folder; sort it out by hand, then open again." >&2
                exit 2
            }
        done < <(find "$a" -mindepth 1 -maxdepth 1 ! -name archive)
        echo "archived the previous build's artefacts to .atelier/archive/$name/"
    fi
fi

mkdir -p "$a" || exit 2
tmp="$marker.tmp.$$"
if [ -f "$marker" ]; then
    # Refresh: keep what the first open recorded (starting commit, baseline), so
    # the Builder's own errors never become part of the baseline.
    fresh=0
    jq --arg spec "$spec" --arg branch "$branch" --arg sid "$sid" \
        '. + {spec: $spec, branch: $branch, sessionId: $sid}' "$marker" >"$tmp" && mv -f "$tmp" "$marker" \
        || { rm -f "$tmp"; echo "session-open: couldn't write $marker" >&2; exit 2; }
else
    fresh=1
    start=$(cd "$dir" && git rev-parse --verify -q HEAD 2>/dev/null) || start=""
    jq -n --arg spec "$spec" --arg branch "$branch" --arg sid "$sid" --arg start "$start" \
        '{spec: $spec, branch: $branch, sessionId: $sid} + (if $start != "" then {startCommit: $start} else {} end)' >"$tmp" && mv -f "$tmp" "$marker" \
        || { rm -f "$tmp"; echo "session-open: couldn't write $marker" >&2; exit 2; }
fi
echo "opened: $marker (spec $spec, branch $branch, bound to this session)"

# Baseline: the type errors the repo already has, so the fast gate only reports
# what the Builder causes. Taken once, on a fresh open. Never stops the open:
# any failure prints one line and the gate falls back to reporting every error
# in the files the Builder changed.
if [ "$fresh" -eq 1 ]; then
    TIMEOUT=${ATELIER_GATE_TIMEOUT:-60}
    if ! . "$(dirname "$0")/typecheck-lib.sh" 2>/dev/null; then
        echo "baseline: none (typecheck-lib.sh is missing); the fast gate will report every error in changed files"
    elif [ ! -x "$dir/node_modules/.bin/tsc" ]; then
        echo "baseline: none (tsc is not installed in node_modules/.bin)"
    else
        out="$a/baseline.tsc.out"
        atelier_tsc_check "$dir" "$out"
        keys="$a/baseline.tsc.txt.tmp.$$"
        atelier_tsc_keys <"$out" >"$keys"
        n=$(wc -l <"$keys" | tr -d ' ')
        if [ "$TC_CODE" -eq 124 ]; then
            echo "baseline: none (the type check timed out after ${TIMEOUT}s); the fast gate will report every error in changed files"
        elif [ "$TC_CODE" -ne 0 ] && [ "$n" -eq 0 ]; then
            echo "baseline: none (the type check failed to run: $(head -n 1 "$out")); the fast gate will report every error in changed files"
        elif [ "$TC_CODE" -eq 0 ] && [ "$TC_FILES" = 0 ]; then
            echo "baseline: none (the type check covers no files; the fast gate will say so)"
        elif mv -f "$keys" "$a/baseline.tsc.txt" \
            && jq --argjson n "$n" --arg cmd "$TC_CMD" '. + {baseline: {file: "baseline.tsc.txt", errors: $n, command: $cmd}}' "$marker" >"$tmp" \
            && mv -f "$tmp" "$marker"; then
            echo "baseline: $n type error$([ "$n" -eq 1 ] || echo s) recorded ($TC_CMD); the fast gate will report only new ones"
        else
            rm -f "$a/baseline.tsc.txt" "$tmp"
            echo "baseline: none (couldn't write it); the fast gate will report every error in changed files"
        fi
        rm -f "$keys" "$out" "$tmp"
    fi
fi
exit 0
