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
#
# Flags (at most one):
#   (none)     everything above, exactly as before. The build-session hooks
#              below are NOT installed.
#   --enforce  everything above, then add the build-session hooks (off by
#              default, they only act in the one session that opened the build:
#              .atelier/session.json with a sessionId equal to the hook's session_id,
#              apart from the lane guard, which acts in repos with a
#              .claude/lane-rules.json):
#                conventions-injector.sh  PreToolUse  Write|Edit
#                lane-guard.sh            PreToolUse  Write|Edit|NotebookEdit
#                fast-gate.sh             PostToolUse Write|Edit
#                pr-gate.sh               PreToolUse  Bash
#                dod-gate.sh              Stop
#   --relax    remove exactly those five hooks, and nothing else. The two
#              hooks above and every permission rule stay.
#
# Two wrappers. PreToolUse hooks (conventions injector, lane guard, PR gate) fail
# CLOSED: a missing or non-executable script exits 2 and blocks the tool call.
# The Stop hook and the PostToolUse fast gate fail OPEN: a missing script prints
# a one-line warning and exits 1 (a non-blocking error), never 2, so a missing
# file can't trap every session in every repo.
#
# Matchers containing "|" are unanchored regular expressions, so "Write|Edit"
# also matches NotebookEdit ("Edit" is a substring). That is harmless for the
# conventions injector and the fast gate: both exit early on the file extension
# and read only tool_input.file_path.
# The lane guard's deny rules are per repo: run lane-guard-init.sh on a repo.
# This installer never touches any repo's .claude/settings.json.

ENFORCE=0
RELAX=0
for arg in "$@"; do
    case "$arg" in
        --enforce) ENFORCE=1 ;;
        --relax) RELAX=1 ;;
        *) echo "Unknown option: $arg (use --enforce or --relax)" >&2; exit 2 ;;
    esac
done
if [ "$ENFORCE" -eq 1 ] && [ "$RELAX" -eq 1 ]; then
    echo "Use --enforce or --relax, not both." >&2
    exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$REPO_DIR/guardrails"
SETTINGS="$HOME/.claude/settings.json"
LOCAL="$HOME/.claude/settings.local.json"
WRITE_HOOK="$G/outside-repo-guard.sh"
NET_HOOK="$G/net-host-guard.py"

# Backup naming lives beside this script, so install.sh works on its own.
if [ -r "$G/backup-lib.sh" ]; then . "$G/backup-lib.sh"; fi
if ! type atelier_backup_copy >/dev/null 2>&1; then
    echo "ERROR: $G/backup-lib.sh is missing or broken, so no backup can be made. Nothing was changed. Restore the file (git checkout guardrails/backup-lib.sh) and re-run." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Skipped guardrails (needs jq: brew install jq)"
    exit 0
fi

# Write in place (not mv) so a symlinked file stays a symlink, after a backup.
# <file> <new content> <what changed, for the message> <backup label>
# The backup label ends up in the file name: guardrails (plain install),
# guardrails-enforce, guardrails-relax.
save() {
    local file=$1 merged=$2 label=$3 blabel=${4:-guardrails}
    if [ "$merged" = "$(jq . "$file")" ]; then
        echo "$label already up to date in $file, leaving it"
    else
        local backup
        if ! backup=$(atelier_backup_copy "$file" "$blabel"); then
            echo "ERROR: no backup of $file could be made, so it was left untouched." >&2
            exit 1
        fi
        printf '%s\n' "$merged" > "$file"
        echo "Updated $label in $file (backup: $backup)"
    fi
}

# The build-session hooks that --enforce adds and --relax removes.
CONV_HOOK="$G/conventions-injector.sh"
LANE_HOOK="$G/lane-guard.sh"
FAST_HOOK="$G/fast-gate.sh"
DOD_HOOK="$G/dod-gate.sh"
PR_HOOK="$G/pr-gate.sh"
# Matched as substrings of a hook command, from any checkout.
ENFORCE_PATHS='["/guardrails/conventions-injector.sh","/guardrails/lane-guard.sh","/guardrails/fast-gate.sh","/guardrails/dod-gate.sh","/guardrails/pr-gate.sh"]'

if [ "$RELAX" -eq 1 ]; then
    # Removes only the five entries --enforce added. Calls no hook script and
    # merges no permission rules.
    if [ ! -s "$SETTINGS" ]; then
        echo "Nothing to relax: $SETTINGS is missing or empty"
        exit 0
    fi
    if RELAXED=$(jq --argjson paths "$ENFORCE_PATHS" '
            def ours: any(.hooks[]?; (.command // "") as $c | any($paths[]; . as $p | $c | contains($p)));
            reduce ("PreToolUse", "PostToolUse", "Stop") as $e (.;
                if .hooks[$e] then
                    .hooks[$e] |= map(select(ours | not))
                    | if .hooks[$e] == [] then del(.hooks[$e]) else . end
                else . end)
            | if (.hooks // null) == {} then del(.hooks) else . end
        ' "$SETTINGS"); then
        save "$SETTINGS" "$RELAXED" "relaxed guardrails (build-session hooks removed)" guardrails-relax
    else
        echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
    fi
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
    LABEL="guardrails"
    BLABEL="guardrails"
    if [ "$ENFORCE" -eq 1 ]; then
        # PreToolUse hooks get the same fail-closed wrapper as the two hooks above.
        # The Stop hook and the fast gate get a fail-open one (warn, exit 1).
        # Entries for these five scripts (from any checkout) are dropped first,
        # then the current ones are added, so re-running upgrades in place
        # without duplicates.
        chmod +x "$CONV_HOOK" "$LANE_HOOK" "$FAST_HOOK" "$DOD_HOOK" "$PR_HOOK" 2>/dev/null
        MSG_OPEN="Atelier guardrail script missing, so this check was skipped; restore it or re-run guardrails/install.sh"
        wrap() { echo "[ -x '$1' ] && exec '$1' || { echo '$MSG' >&2; exit 2; }"; }
        wrap_open() { echo "[ -x '$1' ] && exec '$1' || { echo '$MSG_OPEN' >&2; exit 1; }"; }
        if MERGED=$(jq --argjson paths "$ENFORCE_PATHS" \
                --arg cc "$(wrap "$CONV_HOOK")" --arg lc "$(wrap "$LANE_HOOK")" --arg pc "$(wrap "$PR_HOOK")" \
                --arg fc "$(wrap_open "$FAST_HOOK")" --arg dc "$(wrap_open "$DOD_HOOK")" '
                def ours: any(.hooks[]?; (.command // "") as $c | any($paths[]; . as $p | $c | contains($p)));
                def keep($e): [(.hooks[$e] // [])[] | select(ours | not)];
                .hooks.PreToolUse = (keep("PreToolUse")
                    + [{matcher: "Write|Edit", hooks: [{type: "command", command: $cc}]},
                       {matcher: "Write|Edit|NotebookEdit", hooks: [{type: "command", command: $lc}]},
                       {matcher: "Bash", hooks: [{type: "command", command: $pc}]}])
                | .hooks.PostToolUse = (keep("PostToolUse")
                    + [{matcher: "Write|Edit", hooks: [{type: "command", command: $fc}]}])
                | .hooks.Stop = (keep("Stop") + [{hooks: [{type: "command", command: $dc}]}])
            ' <<<"$MERGED"); then
            LABEL="guardrails and build-session hooks (--enforce)"
            BLABEL="guardrails-enforce"
        else
            echo "ERROR: couldn't add the build-session hooks, left $SETTINGS alone."
            exit 1
        fi
    fi
    save "$SETTINGS" "$MERGED" "$LABEL" "$BLABEL"
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
