# Sourced by conventions-injector.sh, fast-gate.sh, dod-gate.sh and pr-gate.sh.
# Not run directly. Reads only; writes nothing.
#
# ONE decision, in one place, so the four build-session hooks can't drift:
#
#   atelier_is_build_session <marker-file> <hook-input-json>
#
# Returns 0 only when ALL of these hold:
#   - the marker file (<cwd>/.atelier/session.json) exists,
#   - the marker's "sessionId" is a non-empty string,
#   - the hook input is JSON whose "session_id" is a non-empty string,
#   - the two are equal.
# Anything else returns 1 and the hook must do nothing (exit 0, no output). That
# covers: no marker; a marker bound to another session; an old-format or
# hand-made marker with no sessionId; unreadable hook input; hook input with no
# session_id. A session that isn't the build session never meets these gates,
# even in the same checkout while a build is open.
#
# Why failing open on unreadable input is safe: Claude Code documents session_id
# as a common input field of every hook event, so a real build session always
# supplies one. The marker is bound to a session id by guardrails/session-open.sh.

atelier_is_build_session() {
    local marker=$1 input=$2 hsid msid
    [ -f "$marker" ] || return 1
    hsid=$(jq -r 'if (.session_id | type) == "string" then .session_id else empty end' <<<"$input" 2>/dev/null) || return 1
    [ -n "$hsid" ] || return 1
    msid=$(jq -r 'if (.sessionId | type) == "string" then .sessionId else empty end' "$marker" 2>/dev/null) || return 1
    [ -n "$msid" ] && [ "$msid" = "$hsid" ]
}
