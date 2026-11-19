#!/bin/bash
# Closes a build session: renames .atelier/session.json to
# .atelier/session.closed.json (contents kept, so sessionId stays on record).
# Run by /wrap through Bash as the ONLY command on the line:
#
#   ~/.claude/atelier/guardrails/session-close.sh [--check] [<dir>]
#
# <dir> defaults to the current directory. Same identity trick as
# session-open.sh: pr-gate.sh records the calling session in
# <dir>/.atelier/session-claim just before this runs.
#
# --check changes nothing and prints one word, exit 0:
#   none     no marker here
#   mine     marker bound to the calling session
#   other    marker bound to a different session
#   unowned  marker with no sessionId (old format or hand-made)
#   unknown  couldn't tell which session is calling
# Without --check: none (nothing to do), mine and unowned are closed;
# other is refused (exit 1) with a plain message and the marker is left alone;
# unknown is refused (exit 1). A previous session.closed.json is replaced.
# Needs jq. Deletes nothing but the claim.

check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
dir=${1:-.}
[ $# -le 1 ] || { echo "usage: session-close.sh [--check] [<dir>]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "session-close: needs jq" >&2; exit 2; }
dir=$(cd "$dir" 2>/dev/null && pwd -P) || { echo "session-close: no such directory" >&2; exit 2; }
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

state=none
if [ -f "$marker" ]; then
    owner=$(jq -r 'if (.sessionId | type) == "string" then .sessionId else "" end' "$marker" 2>/dev/null)
    if [ -z "$sid" ]; then state=unknown
    elif [ -z "$owner" ]; then state=unowned
    elif [ "$owner" = "$sid" ]; then state=mine
    else state=other
    fi
fi

if [ "$check" -eq 1 ]; then echo "$state"; exit 0; fi

case "$state" in
    none) echo "session-close: no build marker here, nothing to close."; exit 0 ;;
    other)
        echo "session-close: this build belongs to a different session, so it was NOT closed. Run /wrap in the session that opened it (or remove $marker by hand if that session is gone)." >&2
        exit 1 ;;
    unknown)
        echo "session-close: couldn't tell which session is calling, so nothing was closed. Re-run guardrails/install.sh --enforce, or rename $marker by hand." >&2
        exit 1 ;;
esac
mv -f "$marker" "$a/session.closed.json" || exit 2
echo "closed: $a/session.closed.json"
