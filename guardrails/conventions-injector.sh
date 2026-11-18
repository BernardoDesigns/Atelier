#!/bin/bash
# PreToolUse hook for Write / Edit.
#
# When the target is a .tsx, .css, .svg or .html file, and the session is a build
# session (<cwd>/.atelier/session.json exists), adds the numbered items from
# conventions.md to the model's context, plus a reminder to check the component
# manifest first. It only adds context. It never asks, denies or approves.
#
# Silent (exit 0, no output) for every other extension and for any session that
# isn't a build session, so it can't leak into unrelated work.
#
# conventions.md is read from the Atelier repo root (one level above this
# script). ATELIER_CONVENTIONS overrides the path; tests use it.
#
# Fails closed: unreadable stdin, or a missing conventions.md when the hook
# would have fired, exits 2 with a message on stderr. install.sh wraps this
# script so a missing script exits 2 as well.
#
# Reads only the hook JSON on stdin, <cwd>/.atelier/session.json and
# conventions.md. Writes nothing.

LIMIT=6000
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

conv=${ATELIER_CONVENTIONS:-"$(dirname "$0")/../conventions.md"}
if [ ! -r "$conv" ]; then
    echo "Atelier conventions injector: conventions.md not found at $conv. Restore it, or turn enforcement off with guardrails/install.sh --relax." >&2
    exit 2
fi

# Numbered items (1. / 1) / C1. / **C1**). Fall back to the whole file if none match.
items=$(grep -E '^[[:space:]]*(\*\*)?[A-Za-z]{0,2}[0-9]+[.):]' "$conv")
[ -n "$items" ] || items=$(cat "$conv")

text="Atelier conventions (conventions.md):
$items"
if [ "${#text}" -gt "$LIMIT" ]; then
    text="${text:0:$LIMIT}
[truncated, see conventions.md for the rest]"
fi
text="$text

$REMINDER"

jq -n --arg ctx "$text" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'
exit 0
