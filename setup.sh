#!/bin/bash
# Setup script for Claude Code agent commands
# Run this after cloning the repo on a new machine

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backup naming shared with guardrails/install.sh: every backup gets a step
# label and a name that never collides. The log lets the end of the run say
# which backup is the pre-run original (install.sh appends to it too).
# Without the helper nothing that needs a backup is touched: those steps are
# skipped and named in the summary at the end.
SKIPPED=""
if [ -r "$REPO_DIR/guardrails/backup-lib.sh" ]; then . "$REPO_DIR/guardrails/backup-lib.sh"; fi
if type atelier_backup_copy >/dev/null 2>&1 && type atelier_backup_move >/dev/null 2>&1; then
    HAVE_BACKUP_LIB=1
else
    HAVE_BACKUP_LIB=0
    echo "WARNING: guardrails/backup-lib.sh is missing or broken. Steps that need a backup (commands folder, dev-aliases.sh, settings.json) will be skipped, and so will the guardrails."
fi
# Temp log of the backups made this run. Removed on any exit; if mktemp fails
# the run carries on without it and the end-of-run report is skipped.
ATELIER_BACKUP_LOG="$(mktemp "${TMPDIR:-/tmp}/atelier-backups.XXXXXX" 2>/dev/null)" || ATELIER_BACKUP_LOG=""
export ATELIER_BACKUP_LOG
trap '[ -n "$ATELIER_BACKUP_LOG" ] && rm -f "$ATELIER_BACKUP_LOG"' EXIT

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# If commands directory already exists as a real dir, back it up (timestamped)
SKIP_COMMANDS=0
SKIP_ALIASES=0
if [ -d "$COMMANDS_DIR" ] && [ ! -L "$COMMANDS_DIR" ]; then
    if [ "$HAVE_BACKUP_LIB" = 1 ] && BACKUP=$(atelier_backup_move "$COMMANDS_DIR" commands); then
        echo "Backed up existing commands directory to $BACKUP"
    else
        SKIP_COMMANDS=1
        SKIPPED="$SKIPPED
  - ~/.claude/commands link (the existing folder could not be backed up, so it was left in place)"
        echo "WARNING: skipped the ~/.claude/commands link, the existing folder was left in place."
    fi
fi

if [ "$SKIP_COMMANDS" = 1 ]; then
    :
else
# Remove existing symlink (live or broken) if present
if [ -L "$COMMANDS_DIR" ]; then
    if [ ! -e "$COMMANDS_DIR" ]; then
        echo "Found broken symlink at $COMMANDS_DIR (target missing) — removing"
    fi
    rm "$COMMANDS_DIR"
fi

# Create symlink
ln -s "$REPO_DIR/commands" "$COMMANDS_DIR"

# Verify
if [ ! -e "$COMMANDS_DIR" ]; then
    echo "ERROR: symlink created but target $REPO_DIR/commands does not exist"
    exit 1
fi

echo "Done! ~/.claude/commands -> $REPO_DIR/commands"
fi

# --- Atelier home: ~/.claude/atelier -> the main checkout ---
# Agents and commands run inside other repos, so they reach Atelier's files
# (contract files, templates) through this one fixed path. A linked git
# worktree gets deleted eventually, so the link is never made from one. Only a
# symlink is ever replaced; anything else sitting there is left alone.
ATELIER_LINK="$CLAUDE_DIR/atelier"
GIT_DIR_ABS="$(cd "$REPO_DIR" 2>/dev/null && cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
GIT_COMMON_ABS="$(cd "$REPO_DIR" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
IN_LINKED_WORKTREE=0
if [ -n "$GIT_DIR_ABS" ] && [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
    IN_LINKED_WORKTREE=1
fi
if [ "$IN_LINKED_WORKTREE" = 1 ]; then
    echo "WARNING: $REPO_DIR is a linked git worktree, so ~/.claude/atelier was not created or changed. Run setup.sh from the main checkout for this step."
elif [ -e "$ATELIER_LINK" ] && [ ! -L "$ATELIER_LINK" ]; then
    echo "WARNING: $ATELIER_LINK exists and isn't a symlink, left it alone. Move it aside and re-run setup.sh."
else
    if [ -L "$ATELIER_LINK" ] && [ "$(readlink "$ATELIER_LINK")" != "$REPO_DIR" ]; then
        echo "WARNING: $ATELIER_LINK pointed at $(readlink "$ATELIER_LINK"), repointing it to $REPO_DIR"
    fi
    if ln -sfn "$REPO_DIR" "$ATELIER_LINK"; then
        echo "Done! ~/.claude/atelier -> $REPO_DIR"
    else
        echo "WARNING: couldn't create the link $ATELIER_LINK"
    fi
fi

# --- Helper: link ONE file or folder into a directory we don't own ---
# ~/.claude/agents and ~/.claude/skills hold other tools' files, so Atelier adds
# its links beside them. Never moves, replaces or deletes the directory itself.
#   link_into <absolute path of a file or folder in this repo> <target dir>
# The source must be an absolute path. Returns non-zero when it skips (missing
# source, couldn't create the dir, something not ours in the way), so a caller
# running under set -e must handle that.
# Links when the destination is absent or already a link into this repo.
# A real file or folder, or a link pointing elsewhere, is left with a warning.
# Skills and the Builder and Critic agents are linked below.
link_into() {
    local src=$1 dir=$2 dest
    dest="$dir/$(basename "$src")"
    if [ ! -e "$src" ]; then
        echo "WARNING: $src doesn't exist, nothing linked into $dir"
        return 1
    fi
    mkdir -p "$dir" || { echo "WARNING: couldn't create $dir, skipped $dest"; return 1; }
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        ln -sfn "$src" "$dest"
    elif [ -L "$dest" ] && [[ "$(readlink "$dest")" == "$REPO_DIR/"* ]]; then
        ln -sfn "$src" "$dest"
    else
        echo "WARNING: $dest exists and isn't ours, left it alone"
        return 1
    fi
}

# --- Skills: link spec and taste-review into ~/.claude/skills/, beside what's there ---
# Same hazard as the atelier link: from a linked git worktree the links would
# point at a folder that gets deleted, so they are not made there. A skipped
# link warns and the script carries on.
if [ "$IN_LINKED_WORKTREE" = 1 ]; then
    echo "WARNING: $REPO_DIR is a linked git worktree, so the spec and taste-review skills were not linked into ~/.claude/skills. Run setup.sh from the main checkout for this step."
else
    for SKILL in spec taste-review; do
        if link_into "$REPO_DIR/skills/$SKILL" "$CLAUDE_DIR/skills"; then
            echo "Done! ~/.claude/skills/$SKILL -> $REPO_DIR/skills/$SKILL"
        fi
    done
fi

# --- Agents: link the Builder and the Critic into ~/.claude/agents/, file by file ---
# Same rules as the skills: beside whatever is there, never replacing the
# directory, not from a linked git worktree. A link that already points at the
# right file is fine and is left alone; a real file or a link elsewhere is
# skipped with a warning by link_into.
if [ "$IN_LINKED_WORKTREE" = 1 ]; then
    echo "WARNING: $REPO_DIR is a linked git worktree, so the builder and critic agents were not linked into ~/.claude/agents. Run setup.sh from the main checkout for this step."
else
    for AGENT in builder critic; do
        AGENT_LINK="$CLAUDE_DIR/agents/$AGENT.md"
        if [ -L "$AGENT_LINK" ] && [ "$(readlink "$AGENT_LINK")" = "$REPO_DIR/agents/$AGENT.md" ]; then
            echo "Already linked: ~/.claude/agents/$AGENT.md -> $REPO_DIR/agents/$AGENT.md"
        elif link_into "$REPO_DIR/agents/$AGENT.md" "$CLAUDE_DIR/agents"; then
            echo "Done! ~/.claude/agents/$AGENT.md -> $REPO_DIR/agents/$AGENT.md"
        fi
    done
fi

# --- dev-aliases.sh: symlink into home + wire .zshrc ---
ALIASES_LINK="$HOME/.dev-aliases.sh"

# Back up a real file in the way (timestamped), then clear any stale symlink
if [ -f "$ALIASES_LINK" ] && [ ! -L "$ALIASES_LINK" ]; then
    if [ "$HAVE_BACKUP_LIB" = 1 ] && BACKUP=$(atelier_backup_move "$ALIASES_LINK" aliases); then
        echo "Backed up existing dev-aliases.sh to $BACKUP"
    else
        SKIP_ALIASES=1
        SKIPPED="$SKIPPED
  - ~/.dev-aliases.sh link (the existing file could not be backed up, so it was left in place)"
        echo "WARNING: skipped the ~/.dev-aliases.sh link, the existing file was left in place."
    fi
fi
if [ "${SKIP_ALIASES:-0}" = 1 ]; then
    :
else
[ -L "$ALIASES_LINK" ] && rm "$ALIASES_LINK"

# Symlink home -> repo copy
ln -s "$REPO_DIR/dev-aliases.sh" "$ALIASES_LINK"

# Verify the link resolves
if [ ! -e "$ALIASES_LINK" ]; then
    echo "ERROR: dev-aliases symlink created but target $REPO_DIR/dev-aliases.sh does not exist"
    exit 1
fi
echo "Done! ~/.dev-aliases.sh -> $REPO_DIR/dev-aliases.sh"
fi

# Wire the source line into .zshrc (only if missing)
ZSHRC="$HOME/.zshrc"
if grep -qF '.dev-aliases.sh' "$ZSHRC" 2>/dev/null; then
    echo "Source line already in $ZSHRC, leaving it"
else
    echo '[ -f ~/.dev-aliases.sh ] && source ~/.dev-aliases.sh' >> "$ZSHRC"
    echo "Added source line to $ZSHRC"
fi

# --- Retire the old status line (replaced by Aurora Usage) ---
# Earlier versions linked ~/.claude/statusline.sh to this repo. Remove that
# link, but leave alone any status line script that isn't ours.
STATUSLINE_LINK="$CLAUDE_DIR/statusline.sh"
if [ -L "$STATUSLINE_LINK" ] && [[ "$(readlink "$STATUSLINE_LINK")" == "$REPO_DIR/"* ]]; then
    rm "$STATUSLINE_LINK"
    echo "Removed old status line link $STATUSLINE_LINK"
fi

# Dependencies: warn loudly instead of failing silently
if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found. The settings merge below needs it:"
    echo "    brew install jq"
fi

# --- Mods: load the Aurora billboard and Co-driver from this repo in every session ---
# Adds each mod folder to env.CLAUDE_CODE_PLUGIN_DIRS (appended, ':' separated,
# if other folders are already listed), removes the retired sketchpad folder
# (renamed to codriver) and drops the old statusLine entry only if it still
# points at our retired script. Every other key stays.
SETTINGS="$CLAUDE_DIR/settings.json"
BILLBOARD_DIR="$REPO_DIR/aurora-usage/aurora-billboard"
CODRIVER_DIR="$REPO_DIR/codriver"
RETIRED_SKETCHPAD_DIR="$REPO_DIR/sketchpad"
OLD_STATUSLINE='{"type":"command","command":"~/.claude/statusline.sh"}'
if command -v jq >/dev/null 2>&1; then
    [ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    if MERGED=$(jq --arg billboard "$BILLBOARD_DIR" --arg codriver "$CODRIVER_DIR" --arg retired "$RETIRED_SKETCHPAD_DIR" --argjson old "$OLD_STATUSLINE" '
            ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(. != $retired and . != "")) | join(":")) as $kept
            | (reduce ($billboard, $codriver) as $dir ($kept;
                if . == "" then $dir
                elif (split(":") | index($dir)) then .
                else . + ":" + $dir end)) as $dirs
            | .env = ((.env // {}) + {CLAUDE_CODE_PLUGIN_DIRS: $dirs})
            | if .statusLine == $old then del(.statusLine) else . end
        ' "$SETTINGS"); then
        if [ "$MERGED" = "$(jq . "$SETTINGS")" ]; then
            echo "Mods already wired in $SETTINGS, leaving it"
        else
            if [ "$HAVE_BACKUP_LIB" = 1 ] && BACKUP=$(atelier_backup_copy "$SETTINGS" aurora-mods); then
                # Write in place (not mv) so a symlinked settings.json stays a symlink
                printf '%s\n' "$MERGED" > "$SETTINGS"
                echo "Wired the Aurora billboard and Co-driver into $SETTINGS (backup: $BACKUP)"
            else
                SKIPPED="$SKIPPED
  - Aurora billboard and Co-driver wiring in $SETTINGS (no backup could be made, so the file was left untouched)"
                echo "WARNING: skipped the Aurora billboard and Co-driver wiring, $SETTINGS was left untouched."
            fi
        fi
    else
        echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
    fi
else
    echo "Skipped the Aurora billboard and Co-driver in $SETTINGS (needs jq)"
fi

# --- aurora command: switch Aurora threshold profiles (aurora profile fable-run) ---
# Linked into ~/.local/bin, where the claude CLI lives, so it's already on PATH.
# Only replaces an existing aurora link that points into this repo.
AURORA_LINK="$HOME/.local/bin/aurora"
mkdir -p "$HOME/.local/bin"
chmod +x "$REPO_DIR/aurora-usage/aurora"
if [ -e "$AURORA_LINK" ] && ! [[ "$(readlink "$AURORA_LINK")" == "$REPO_DIR/"* ]]; then
    echo "WARNING: $AURORA_LINK exists and isn't ours, left it alone"
else
    ln -sfn "$REPO_DIR/aurora-usage/aurora" "$AURORA_LINK"
    echo "Done! $AURORA_LINK -> $REPO_DIR/aurora-usage/aurora"
fi

# --- Guardrails: ask before destructive commands and writes outside the repo ---
if ! command -v python3 >/dev/null 2>&1; then
    echo "WARNING: python3 not found. The network guardrail is a python3 script, so it will block every Bash tool call in Claude Code until python3 is installed. Continuing with the install anyway."
fi
# --enforce also installs the five build-session hooks (conventions injector,
# fast gate, lane guard, Stop gate, PR gate). The build-session hooks only act
# in a session that opened a build with /build (the marker .atelier/session.json,
# bound to that session), and the lane guard only acts in a repo that has run
# guardrails/lane-guard-init.sh. To undo just those five hooks:
#     bash guardrails/install.sh --relax
if ! bash "$REPO_DIR/guardrails/install.sh" --enforce; then
    SKIPPED="$SKIPPED
  - guardrails (guardrails did not finish; any file it updated is listed above with its backup)"
    echo "WARNING: the guardrails step did not complete."
fi

# --- MCP servers: install and register everything in mcp/servers.json ---
# User scope, so every project on this machine gets them. Pinned versions,
# safe to re-run, never overwrites preferences. A failure never fails setup.
# Skip it with: bash setup.sh --no-mcp (or ATELIER_SKIP_MCP=1). Run it on its
# own with: bash mcp/install.sh (add --dry-run to preview).
SKIP_MCP="${ATELIER_SKIP_MCP:-0}"
for ARG in "$@"; do [ "$ARG" = "--no-mcp" ] && SKIP_MCP=1; done
if [ "$SKIP_MCP" = 1 ]; then
    echo "Skipped the MCP servers. To install them later, run: bash $REPO_DIR/mcp/install.sh"
elif bash "$REPO_DIR/mcp/install.sh"; then
    echo "Done! MCP servers from mcp/servers.json are installed"
else
    SKIPPED="$SKIPPED
  - MCP servers (see the warnings above, then re-run: bash mcp/install.sh)"
    echo "WARNING: some MCP servers did not install. Everything else carries on."
fi

# --- Render harness: the dependencies /build needs to take screenshots ---
# Installs into render/ only (node_modules and a Chromium download, about 150MB).
# Runs when npm exists. A failure never fails setup: it prints the commands to
# run by hand. Idempotent: npm install and playwright install both do nothing
# when everything is already there. Skip it with: bash setup.sh --no-render
# (or ATELIER_SKIP_RENDER=1). Put --no-hud first if you pass both.
RENDER_CMD="cd $REPO_DIR/render && npm install && npx playwright install chromium"
SKIP_RENDER="${ATELIER_SKIP_RENDER:-0}"
for ARG in "$@"; do [ "$ARG" = "--no-render" ] && SKIP_RENDER=1; done
if [ "$SKIP_RENDER" = 1 ]; then
    echo "Skipped the render harness install. Before /build can render, run:"
    echo "    $RENDER_CMD"
elif ! command -v npm >/dev/null 2>&1; then
    echo "WARNING: npm not found, so the render harness dependencies were not installed. Before /build can render, install Node and run:"
    echo "    $RENDER_CMD"
else
    echo "Installing the render harness dependencies into $REPO_DIR/render: npm packages and a Chromium download of about 150MB."
    echo "To skip this, stop now (Ctrl-C) and re-run with: bash setup.sh --no-render"
    if (cd "$REPO_DIR/render" && npm install && npx playwright install chromium); then
        echo "Done! Render harness dependencies are installed in $REPO_DIR/render"
    else
        echo "WARNING: the render harness install failed. Everything else is set up. Before /build can render, run:"
        echo "    $RENDER_CMD"
    fi
fi

# --- Aurora HUD: build the floating usage panel and start it at login ---
# On by default. Skip with: bash setup.sh --no-hud   Undo with: aurora-usage/aurora-hud/remove.sh
# Set to 0 to take it out of setup entirely.
HUD_ENABLED=1
HUD_DIR="$REPO_DIR/aurora-usage/aurora-hud"
if [ "$HUD_ENABLED" != 1 ]; then
    echo "Skipped Aurora HUD (in progress, see aurora-usage/README.md)"
elif [ "${1:-}" = "--no-hud" ]; then
    echo "Skipped Aurora HUD (--no-hud)"
elif [ "$(uname)" != "Darwin" ]; then
    echo "Skipped Aurora HUD (macOS only)"
elif ! command -v swiftc >/dev/null 2>&1; then
    echo "WARNING: swiftc not found, so the Aurora HUD wasn't built. Run this once, then re-run setup.sh:"
    echo "    xcode-select --install"
elif "$HUD_DIR/build.sh" && "$HUD_DIR/start-at-login.sh"; then
    echo "Done! Aurora HUD is running and starts at login"
else
    echo "WARNING: Aurora HUD build or launch failed. Everything else is set up."
fi

# --- Which backup is the pre-run original? ---
# The log is in the order backups were made, so the first line per file is the
# file as it was before this run touched it.
if [ -s "$ATELIER_BACKUP_LOG" ]; then
    echo ""
    echo "Your files as they were before this run:"
    SEEN=""
    LINK_NOTE=0
    while IFS="$(printf '\t')" read -r SRC BAK; do
        case "$SEEN" in *"|$SRC|"*) continue ;; esac
        SEEN="$SEEN|$SRC|"
        echo "  $SRC -> $BAK"
        case "$SRC" in "$COMMANDS_DIR"|"$ALIASES_LINK") LINK_NOTE=1 ;; esac
    done < "$ATELIER_BACKUP_LOG"
    if [ "${LINK_NOTE:-0}" = 1 ]; then
        echo "For commands and .dev-aliases.sh, remove the link first, then move the backup back."
    fi
elif [ -z "$ATELIER_BACKUP_LOG" ]; then
    echo ""
    echo "Note: no temp file for the backup log, so the pre-run originals are not listed. Each backup path was printed above."
fi
if [ -n "$SKIPPED" ]; then
    echo ""
    echo "Skipped, see the warnings above:$SKIPPED"
fi

echo ""
echo "Available commands:"
ls "$COMMANDS_DIR"/*.md 2>/dev/null | while read f; do
    echo "  /$(basename "$f" .md)"
done
echo ""
echo "Restart any running Claude Code sessions (and the desktop app) to pick up the commands, the billboard and Co-driver."
