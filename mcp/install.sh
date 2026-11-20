#!/bin/bash
# Installs the MCP servers listed in mcp/servers.json for Claude Code, at user
# scope, so they work in every project on this machine.
#
#   bash mcp/install.sh            install everything in the manifest
#   bash mcp/install.sh --dry-run  print what it would do, change nothing
#
# Safe to re-run. Packages are pinned, a registration that already matches is
# left alone, one that differs is replaced, and preferences are only copied
# when the machine has none yet. A server that fails is reported and the rest
# still install. Exit 1 if any server failed.
#
# Tests point it at fixtures with ATELIER_MCP_MANIFEST and ATELIER_CLAUDE_JSON.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${ATELIER_MCP_MANIFEST:-$DIR/servers.json}"
MANIFEST_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
CLAUDE_JSON="${ATELIER_CLAUDE_JSON:-$HOME/.claude.json}"
DRY=0
for ARG in "$@"; do [ "$ARG" = "--dry-run" ] && DRY=1; done

# Run a command, or print it in a dry run.
run() {
    if [ "$DRY" = 1 ]; then echo "    would run: $*" >&2; return 0; fi
    "$@"
}

# 0 when the running node is at least $1 (x.y.z).
node_at_least() {
    node -e '
        const [have, want] = process.argv.slice(1).map(v => v.replace(/^v/, "").split(".").map(Number));
        for (let i = 0; i < 3; i++) {
            if ((have[i] || 0) > (want[i] || 0)) process.exit(0);
            if ((have[i] || 0) < (want[i] || 0)) process.exit(1);
        }
    ' "$(node -v)" "$1"
}

for TOOL in jq node npm; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        echo "ERROR: $TOOL not found, so no MCP servers were installed. Install it and re-run: bash mcp/install.sh"
        exit 1
    fi
done
HAVE_CLAUDE=1
command -v claude >/dev/null 2>&1 || HAVE_CLAUDE=0
if ! jq -e '.servers | type == "array"' "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: $MANIFEST is missing or has no servers list."
    exit 1
fi

[ "$DRY" = 1 ] && echo "Dry run: nothing is installed or changed."
FAILED=""
COUNT=$(jq '.servers | length' "$MANIFEST")

for ((i = 0; i < COUNT; i++)); do
    S=".servers[$i]"
    NAME=$(jq -r "$S.name" "$MANIFEST")
    echo ""
    echo "MCP server: $NAME"

    MIN_NODE=$(jq -r "$S.minNode // empty" "$MANIFEST")
    if [ -n "$MIN_NODE" ] && ! node_at_least "$MIN_NODE"; then
        echo "  WARNING: needs Node $MIN_NODE or later, this machine has $(node -v). Skipped."
        FAILED="$FAILED $NAME"
        continue
    fi

    # 1. Packages, installed globally at the pinned versions
    PKGS=()
    while IFS= read -r P; do [ -n "$P" ] && PKGS+=("$P"); done < <(jq -r "$S.npm // [] | .[]" "$MANIFEST")
    ALLOW=$(jq -r "$S.allowScripts // [] | join(\",\")" "$MANIFEST")
    if [ "${#PKGS[@]}" -gt 0 ]; then
        echo "  Installing ${PKGS[*]}"
        if [ -n "$ALLOW" ]; then
            run npm install -g --allow-scripts="$ALLOW" "${PKGS[@]}" || { echo "  WARNING: npm install failed. Skipped the rest of $NAME."; FAILED="$FAILED $NAME"; continue; }
        else
            run npm install -g "${PKGS[@]}" || { echo "  WARNING: npm install failed. Skipped the rest of $NAME."; FAILED="$FAILED $NAME"; continue; }
        fi
    fi

    # 2. One-time extras (browser downloads and the like)
    while IFS= read -r CMD; do
        [ -n "$CMD" ] || continue
        echo "  Running: $CMD"
        run bash -c "$CMD" || { echo "  WARNING: '$CMD' failed. The server still registers, but tools that need it will error."; FAILED="$FAILED $NAME"; }
    done < <(jq -r "$S.postInstall // [] | .[]" "$MANIFEST")

    # 3. Register with Claude Code at user scope
    COMMAND=$(jq -r "$S.command" "$MANIFEST")
    ARGS=()
    while IFS= read -r A; do ARGS+=("$A"); done < <(jq -r "$S.args // [] | .[]" "$MANIFEST")
    WANT=$(jq -c "{command: $S.command, args: ($S.args // [])}" "$MANIFEST")
    HAVE=""
    [ -f "$CLAUDE_JSON" ] && HAVE=$(jq -c --arg n "$NAME" '.mcpServers[$n] // empty | {command, args: (.args // [])}' "$CLAUDE_JSON" 2>/dev/null)
    if [ "$HAVE_CLAUDE" = 0 ]; then
        echo "  WARNING: claude CLI not found, so $NAME was not registered. After installing Claude Code, re-run: bash mcp/install.sh"
        FAILED="$FAILED $NAME"
    elif [ "$HAVE" = "$WANT" ]; then
        echo "  Already registered at user scope, leaving it"
    else
        if [ -n "$HAVE" ]; then
            echo "  Registered differently ($HAVE), replacing it"
            run claude mcp remove "$NAME" -s user >/dev/null
        fi
        if run claude mcp add -s user "$NAME" -- "$COMMAND" ${ARGS[@]+"${ARGS[@]}"} >/dev/null; then
            echo "  Registered $NAME at user scope: $COMMAND ${ARGS[*]-}"
        else
            echo "  WARNING: claude mcp add failed for $NAME."
            FAILED="$FAILED $NAME"
        fi
    fi

    # 4. Companion skills, from a pinned tag
    SKILLS=$(jq -r "$S.skills // empty" "$MANIFEST")
    if [ -n "$SKILLS" ]; then
        echo "  Installing skills from $SKILLS"
        run npx -y skills add "$SKILLS" -g -a claude-code -y >/dev/null || { echo "  WARNING: skills install failed for $NAME."; FAILED="$FAILED $NAME"; }
    fi

    # 5. Preferences: copied only when this machine has none, never overwritten
    FROM=$(jq -r "$S.preferences.from // empty" "$MANIFEST")
    TO=$(jq -r "$S.preferences.to // empty" "$MANIFEST")
    if [ -n "$FROM" ] && [ -n "$TO" ]; then
        TO="${TO/#\~/$HOME}"
        if [ -e "$TO" ]; then
            echo "  Preferences already at $TO, leaving them"
        elif run mkdir -p "$(dirname "$TO")" && run cp "$MANIFEST_DIR/$FROM" "$TO"; then
            echo "  Copied preferences to $TO"
        else
            echo "  WARNING: couldn't copy preferences to $TO"
            FAILED="$FAILED $NAME"
        fi
    fi
done

echo ""
if [ -n "$FAILED" ]; then
    echo "MCP servers with problems, see the warnings above:$(printf '%s\n' $FAILED | sort -u | tr '\n' ' ')"
    exit 1
fi
echo "MCP servers done. Restart running Claude Code sessions to pick them up."
