#!/bin/bash
# PreToolUse hook for Write / Edit.
#
# When the target is a .tsx, .css, .svg or .html file, and the session is a build
# session (<cwd>/.atelier/session.json exists), adds the rule from each item of
# conventions.md to the model's context, plus a reminder to check the component
# manifest first. It only adds context. It never asks, denies or approves.
#
# Silent (exit 0, no output) for every other extension and for any session that
# isn't a build session, so it can't leak into unrelated work.
#
# It injects one compact "C<n>: <rule>" line per item. conventions.md is read from the Atelier repo root (one level above this
# script). ATELIER_CONVENTIONS overrides the path; tests use it.
#
# Fails closed: unreadable stdin, or a missing conventions.md when the hook
# would have fired, exits 2 with a message on stderr. install.sh wraps this
# script so a missing script exits 2 as well.
#
# Injects the full text once per session, then a one-line reminder, so a long
# build session doesn't fill with repeats. The stamp is .atelier/conventions-injected
# holding the hook input's session_id. Without a session_id the full text goes in
# at most once every 30 minutes, judged by the stamp's modification time.
#
# Reads only the hook JSON on stdin, <cwd>/.atelier/session.json, the stamp and
# conventions.md. Its one write is the stamp, inside .atelier/.

LIMIT=12000
REMINDER="Check the component manifest before creating any component. Check the manifest first: if a component exists, use it."

input=$(cat)
if ! jq -e . >/dev/null 2>&1 <<<"$input"; then
    echo "Atelier conventions injector: couldn't read the hook input, blocking. Re-run guardrails/install.sh --relax to turn it off." >&2
    exit 2
fi

target=$(jq -r '.tool_input.file_path // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

ext=$(printf '%s' "${target##*.}" | tr '[:upper:]' '[:lower:]')
case "$target" in
    *.*) ;;
    *) exit 0 ;;
esac
case "$ext" in
    tsx|css|svg|html) ;;
    *) exit 0 ;;
esac

[ -f "$cwd/.atelier/session.json" ] || exit 0

# Once per session: after the full text has gone in, later edits get a one-line
# reminder. The stamp holds the session id; with no session_id in the input the
# full text goes in at most once every 30 minutes (the stamp's modification time).
stamp="$cwd/.atelier/conventions-injected"
sid=$(jq -r '.session_id // empty' <<<"$input")
seen=0
if [ -f "$stamp" ]; then
    if [ -n "$sid" ]; then
        [ "$(cat "$stamp" 2>/dev/null)" = "$sid" ] && seen=1
    elif [ -n "$(find "$stamp" -mmin -30 2>/dev/null)" ]; then
        seen=1
    fi
fi
if [ "$seen" -eq 1 ]; then
    jq -n --arg ctx "Atelier conventions (conventions.md) are already in context for this session. Check the manifest before creating any component." '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

conv=${ATELIER_CONVENTIONS:-"$(dirname "$0")/../conventions.md"}
if [ ! -r "$conv" ]; then
    echo "Atelier conventions injector: conventions.md not found at $conv. Restore it, or turn enforcement off with guardrails/install.sh --relax." >&2
    exit 2
fi

# conventions.md items are blocks: a "### C<n>" heading, then the rule on the next
# non-blank line, then Source / Check / Status / Verify lines. Emit one compact
# "C<n>: <rule>" line per item and nothing else (not the intro, not the metadata).
# If the list is over the cap, cut at a whole-item boundary and point at the file.
# With no "### C<n>" headings at all, fall back to the first $LIMIT characters.
items=$(awk '/^### C[0-9]+[[:space:]]*$/ { id = $2; want = 1; next }
             want && NF { sub(/^[[:space:]]+/, ""); print id ": " $0; want = 0 }' "$conv")
head="Atelier conventions (conventions.md):"
if [ -n "$items" ]; then
    text="$head"
    truncated=0
    while IFS= read -r line; do
        if [ $(( ${#text} + ${#line} + 1 )) -gt "$LIMIT" ]; then truncated=1; break; fi
        text="$text
$line"
    done <<<"$items"
    [ "$truncated" -eq 0 ] || text="$text
[truncated at a whole item, see conventions.md for the rest]"
else
    text="$head
$(cat "$conv")"
    if [ "${#text}" -gt "$LIMIT" ]; then
        text="${text:0:$LIMIT}
[truncated, see conventions.md for the rest]"
    fi
fi
text="$text

$REMINDER"

printf '%s\n' "${sid:-no-session-id}" >"$stamp" 2>/dev/null

jq -n --arg ctx "$text" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'
exit 0
