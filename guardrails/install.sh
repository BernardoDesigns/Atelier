#!/bin/bash
# Merge the guardrails into ~/.claude/settings.json (user scope, every project
# and worktree). Idempotent, and every other key stays.
#
#   permissions-ask.json      unioned into permissions.ask (Proceed/Cancel)
#   permissions-allow.json    unioned into permissions.allow (local curl only)
#   permissions-retired.json  removed from allow and ask: rules that were too
#                             broad or that conflict with CLAUDE.md
#   outside-repo-guard.sh     PreToolUse hook on Write/Edit/NotebookEdit
#   net-host-guard.py         PreToolUse hook on Bash: curl/wget off-machine asks
#
# ~/.claude/settings.local.json only applies to sessions started from ~, so
# rules there look global but aren't. This removes the retired rules from it
# and any rule that now lives in user scope, so nothing is left behind there.
# Nothing is added to it.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$REPO_DIR/guardrails"
SETTINGS="$HOME/.claude/settings.json"
LOCAL="$HOME/.claude/settings.local.json"
WRITE_HOOK="$G/outside-repo-guard.sh"
NET_HOOK="$G/net-host-guard.py"

# Backup naming lives beside this script, so install.sh works on its own.
. "$G/backup-lib.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "Skipped guardrails (needs jq: brew install jq)"
    exit 0
fi

chmod +x "$WRITE_HOOK" "$NET_HOOK"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Fail closed: a missing or non-executable script blocks the tool call (exit 2)
# instead of letting it through. The net hook also blocks if it crashes, for
# example when python3 isn't there.
MSG="Atelier guardrail script missing; restore it or re-run guardrails/install.sh"
WRITE_CMD="[ -x '$WRITE_HOOK' ] && exec '$WRITE_HOOK' || { echo '$MSG' >&2; exit 2; }"
NET_CMD="[ -x '$NET_HOOK' ] || { echo '$MSG' >&2; exit 2; }; '$NET_HOOK' || { echo 'Atelier network guardrail failed, so this is blocked. Check python3, or re-run guardrails/install.sh' >&2; exit 2; }"

# Write in place (not mv) so a symlinked file stays a symlink, after a backup.
save() {
    local file=$1 merged=$2 label=$3
    if [ "$merged" = "$(jq . "$file")" ]; then
        echo "$label already up to date in $file, leaving it"
    else
        local backup
        backup=$(atelier_backup_path "$file" guardrails)
        cp "$file" "$backup"
        atelier_backup_log "$file" "$backup"
        printf '%s\n' "$merged" > "$file"
        echo "Updated $label in $file (backup: $backup)"
    fi
}

# Drop earlier entries for either script (bare or wrapped, from any checkout),
# then add the current ones, so re-running upgrades in place without
# duplicates. The hooks run from wherever this was last run, so run it from
# the main checkout, not a throwaway worktree: a missing script fails closed.
if MERGED=$(jq \
        --slurpfile ask "$G/permissions-ask.json" \
        --slurpfile allow "$G/permissions-allow.json" \
        --slurpfile retired "$G/permissions-retired.json" \
        --arg wh "/guardrails/outside-repo-guard.sh" --arg wc "$WRITE_CMD" \
        --arg nh "/guardrails/net-host-guard.py" --arg nc "$NET_CMD" '
        def strip($xs): map(select(. as $r | $xs | index($r) | not));
        .permissions.ask = (((.permissions.ask // []) | strip($retired[0])) + $ask[0] | unique)
        | .permissions.allow = (((.permissions.allow // []) | strip($retired[0])) + $allow[0] | unique)
        | .hooks.PreToolUse = (
            [(.hooks.PreToolUse // [])[]
             | select(any(.hooks[]?; (.command // "") | (contains($wh) or contains($nh))) | not)]
            + [{matcher: "Write|Edit|NotebookEdit", hooks: [{type: "command", command: $wc}]},
               {matcher: "Bash", hooks: [{type: "command", command: $nc}]}])
    ' "$SETTINGS"); then
    save "$SETTINGS" "$MERGED" "guardrails"
else
    echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
fi

if [ -s "$LOCAL" ]; then
    if CLEANED=$(jq \
            --slurpfile ask "$G/permissions-ask.json" \
            --slurpfile allow "$G/permissions-allow.json" \
            --slurpfile retired "$G/permissions-retired.json" '
            ($retired[0] + $ask[0] + $allow[0]) as $gone
            | def strip: map(select(. as $r | $gone | index($r) | not));
            if .permissions.allow then .permissions.allow |= strip else . end
            | if .permissions.ask then .permissions.ask |= strip else . end
            | if (.permissions.ask // null) == [] then del(.permissions.ask) else . end
        ' "$LOCAL"); then
        save "$LOCAL" "$CLEANED" "moved and retired rules"
    else
        echo "ERROR: $LOCAL is not valid JSON, left it alone."
    fi
fi
