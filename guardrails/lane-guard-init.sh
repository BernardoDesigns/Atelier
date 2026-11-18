#!/bin/bash
# Apply the lane guard deny rules to ONE host repo (project scope).
#
#   guardrails/lane-guard-init.sh <host-repo>
#
# Unions the rules in lane-guard-deny.json (four project-root-anchored Edit
# rules: /auth/**, /api/**, /payments/**, /lib/shared/**) into
# <host-repo>/.claude/settings.json under permissions.deny. Creates the file if it's missing, keeps every other key
# and every existing deny rule (in its original order), and backs up an existing
# file as settings.json.bak.<timestamp> before changing it. Running it twice
# changes nothing.
#
# These are project-scope rules on purpose: a user-scope deny on api/ or auth/
# would block those paths in every repo on the machine. This script never writes
# to ~/.claude, and it refuses to run on $HOME or on anything that isn't the root
# of a git repo.
#
# Per-repo extras go in <host-repo>/.claude/lane-rules.json and are enforced by
# lane-guard.sh. They add to these rules, they never replace them.

SRC="$(cd "$(dirname "$0")" && pwd)/lane-guard-deny.json"

die() { echo "lane-guard-init: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "needs jq (brew install jq)"
[ -n "$1" ] || die "usage: lane-guard-init.sh <host-repo>"
[ -d "$1" ] || die "$1 is not a directory"
[ -f "$SRC" ] || die "missing $SRC"

repo=$(cd "$1" && pwd -P)
root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || die "$repo is not a git repo, nothing written"
root=$(cd "$root" && pwd -P)
[ "$root" = "$repo" ] || die "$repo is inside the repo at $root; run it on the repo root, nothing written"
home=$(cd "$HOME" 2>/dev/null && pwd -P)
[ "$repo" != "$home" ] || die "refusing to run on \$HOME ($home), nothing written"

settings="$repo/.claude/settings.json"
if [ -s "$settings" ]; then
    current=$(jq . "$settings" 2>/dev/null) || die "$settings is not valid JSON, left it alone"
else
    current='{}'
fi

# The first draft wrote unanchored Edit/Write rules ("Edit(auth/**)" matches an
# auth directory at any depth, and Edit rules already cover every file-editing
# tool). Those eight are removed if found, so older repos upgrade cleanly.
OLD='["Edit(auth/**)","Write(auth/**)","Edit(api/**)","Write(api/**)","Edit(payments/**)","Write(payments/**)","Edit(lib/shared/**)","Write(lib/shared/**)"]'
merged=$(jq --slurpfile add "$SRC" --argjson old "$OLD" '
    ($add[0].permissions.deny) as $new
    | .permissions.deny = (((.permissions.deny // []) - $old) as $have | $have + ($new - $have))
' <<<"$current") || die "couldn't merge into $settings, left it alone"

if [ -f "$settings" ] && [ "$merged" = "$current" ]; then
    echo "Lane guard rules already in $settings, leaving it"
    exit 0
fi

mkdir -p "$repo/.claude" || die "couldn't create $repo/.claude"
if [ -s "$settings" ]; then
    backup="$settings.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$settings" "$backup" || die "couldn't back up $settings"
    echo "Backed up to $backup"
fi
printf '%s\n' "$merged" >"$settings"
echo "Updated $settings. permissions.deny now has:"
jq -r '.permissions.deny[] | "  " + .' "$settings"
