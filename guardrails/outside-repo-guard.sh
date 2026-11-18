#!/bin/bash
# PreToolUse hook for Write / Edit / NotebookEdit.
#
# Inside the current git repo or worktree: stays silent, the normal permission
# flow applies (git can recover tracked files).
# Outside it, or when there's no repo at all: asks first and shows the full
# resolved path. Claude's own scratchpad (/private/tmp/claude-<uid>/) is exempt.
# Any path with a '..' segment asks, so it can't be used to step out of the repo.
#
# settings.json doesn't call this file directly. install.sh wraps it so that a
# missing or non-executable script blocks the write (exit 2) instead of failing
# open.
#
# Reads only the hook's JSON on stdin. No network, no keys, never auto-approves.
# If anything goes wrong it asks rather than letting the write through.

ask() {
    jq -n --arg reason "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
target=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)

[ -n "$target" ] || ask "Guardrail: couldn't read the target path, confirm this write."
[ -n "$cwd" ] || cwd=$PWD
[[ "$target" = /* ]] || target="$cwd/$target"

# Resolve symlinks via the nearest existing ancestor (the file may not exist
# yet). A link from ~/.claude into this repo counts as inside; a link from the
# repo pointing elsewhere counts as outside.
case "/$target/" in
    */../*) ask "Guardrail: path contains '..', confirm this write. Target: $target" ;;
esac
dir=$(dirname "$target")
rest=$(basename "$target")
while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do
    rest="$(basename "$dir")/$rest"
    dir=$(dirname "$dir")
done
if [ -e "$target" ]; then
    resolved=$(realpath "$target" 2>/dev/null) || resolved=$target
else
    resolved="$(cd "$dir" 2>/dev/null && pwd -P)/$rest"
fi

# Claude's own session scratchpad is exempt. Only that tree, nothing else in /tmp.
case "$resolved" in
    "/private/tmp/claude-$(id -u)"/*) exit 0 ;;
esac

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
    ask "Guardrail: not in a git repo, so this write isn't recoverable with git. Target: $resolved"
fi
root=$(cd "$root" && pwd -P)

case "$resolved" in
    "$root"/*) exit 0 ;;
esac

ask "Guardrail: write outside the repo ($root). Target: $resolved"
