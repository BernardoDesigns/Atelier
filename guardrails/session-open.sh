#!/bin/bash
# Opens a build session: writes .atelier/session.json bound to the calling
# session. Run by /build (and by the Builder, once per option worktree in
# diverge mode) through Bash, as the ONLY command on the line:
#
#   ~/.claude/atelier/guardrails/session-open.sh <spec> <branch> [<dir>]
#
# <dir> defaults to the current directory (the repo or option worktree that gets
# the marker). The marker is { "spec": ..., "branch": ..., "sessionId": ... }.
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
# Exit 0 prints one line "opened: ..."; every refusal prints why on stderr.
# Needs jq. Writes only <dir>/.atelier/session.json (via a temp file) and
# deletes the claim.

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

mkdir -p "$a" || exit 2
tmp="$marker.tmp.$$"
jq -n --arg spec "$spec" --arg branch "$branch" --arg sid "$sid" \
    '{spec: $spec, branch: $branch, sessionId: $sid}' >"$tmp" && mv -f "$tmp" "$marker" \
    || { echo "session-open: couldn't write $marker" >&2; exit 2; }
echo "opened: $marker (spec $spec, branch $branch, bound to this session)"
