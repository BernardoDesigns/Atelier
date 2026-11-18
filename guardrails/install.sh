#!/bin/bash
# Merge the guardrails into ~/.claude/settings.json (user scope, every project
# and worktree). Idempotent: unions permissions.ask with what's there and adds
# the hook entry only if it's missing. Every other key stays.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
RULES="$REPO_DIR/guardrails/permissions-ask.json"
HOOK="$REPO_DIR/guardrails/outside-repo-guard.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "Skipped guardrails (needs jq: brew install jq)"
    exit 0
fi

chmod +x "$HOOK"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Fail closed: if the script is missing or not executable (deleted, renamed,
# or a branch without it checked out), block the write with exit 2.
MSG="Atelier guardrail script missing; restore it or re-run guardrails/install.sh"
CMD="[ -x '$HOOK' ] && exec '$HOOK' || { echo '$MSG' >&2; exit 2; }"

# Drop any earlier entry that points at the script (bare or wrapped), then add
# the current one, so re-running upgrades in place without duplicates.
if MERGED=$(jq --slurpfile rules "$RULES" --arg hook "$HOOK" --arg cmd "$CMD" '
        .permissions.ask = (((.permissions.ask // []) + $rules[0]) | unique)
        | .hooks.PreToolUse = (
            [(.hooks.PreToolUse // [])[]
             | select(any(.hooks[]?; (.command // "") | contains($hook)) | not)]
            + [{matcher: "Write|Edit|NotebookEdit",
                hooks: [{type: "command", command: $cmd}]}])
    ' "$SETTINGS"); then
    if [ "$MERGED" = "$(jq . "$SETTINGS")" ]; then
        echo "Guardrails already in $SETTINGS, leaving it"
    else
        BACKUP="$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS" "$BACKUP"
        # Write in place (not mv) so a symlinked settings.json stays a symlink
        printf '%s\n' "$MERGED" > "$SETTINGS"
        echo "Added guardrails to $SETTINGS (backup: $BACKUP)"
    fi
else
    echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
fi
