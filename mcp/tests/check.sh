#!/bin/bash
# Checks for mcp/: the manifest is pinned, and install.sh does the right thing
# on a fresh machine, a machine that already matches, and one registered
# differently. claude, npm and npx are stubs that log their arguments, and HOME
# is a temp folder, so nothing real is installed or changed.
#   bash mcp/tests/check.sh
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$REPO/mcp/servers.json"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- Manifest ---
check "manifest is valid JSON with a servers list" "jq -e '.servers | type == \"array\" and length > 0' '$MANIFEST' >/dev/null"
check "every npm package is pinned to x.y.z" "[ -z \"\$(jq -r '.servers[].npm // [] | .[] | select(test(\"@[0-9]+\\\\.[0-9]+\\\\.[0-9]+\$\") | not)' '$MANIFEST')\" ]"
check "every skills source is a pinned tree URL" "[ -z \"\$(jq -r '.servers[].skills // empty | select(test(\"/tree/\") | not)' '$MANIFEST')\" ]"
check "every preferences file exists" "jq -r '.servers[].preferences.from // empty' '$MANIFEST' | while read -r f; do [ -f \"$REPO/mcp/\$f\" ] || exit 1; done"
check "install.sh parses" "bash -n '$REPO/mcp/install.sh'"

# --- install.sh against stubs ---
T="$(mktemp -d "${TMPDIR:-/tmp}/atelier-mcp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
LOG="$T/calls.log"
for STUB in claude npm npx; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$STUB" "$LOG" > "$T/bin/$STUB"
    chmod +x "$T/bin/$STUB"
done

runit() {  # runit <claude.json contents>
    : > "$LOG"
    printf '%s' "$1" > "$T/home/.claude.json"
    HOME="$T/home" PATH="$T/bin:$PATH" ATELIER_CLAUDE_JSON="$T/home/.claude.json" \
        bash "$REPO/mcp/install.sh" > "$T/out.log" 2>&1
}

# Fresh machine
rm -rf "$T/home/.awwwards-mcp"
runit '{}'; RC=$?
check "fresh: exits 0" "[ $RC = 0 ]"
check "fresh: npm installs the pinned packages with ffmpeg-static scripts allowed" "grep -q 'npm install -g --allow-scripts=ffmpeg-static awwwards-mcp@1.21.1' '$LOG'"
check "fresh: registers awwwards at user scope" "grep -qx 'claude mcp add -s user awwwards -- awwwards-mcp' '$LOG'"
check "fresh: removes nothing" "! grep -q 'claude mcp remove' '$LOG'"
check "fresh: installs skills from the pinned tag" "grep -q 'npx -y skills add https://github.com/INSANE0777/awwwards-skills/tree/skills-v' '$LOG'"
check "fresh: copies preferences" "cmp -s '$REPO/mcp/awwwards/preferences.json' '$T/home/.awwwards-mcp/preferences.json'"

# Already registered the same way, preferences already there and edited
echo '{"responseMode":"compact"}' > "$T/home/.awwwards-mcp/preferences.json"
runit '{"mcpServers":{"awwwards":{"type":"stdio","command":"awwwards-mcp","args":[],"env":{}}}}'; RC=$?
check "matching: exits 0" "[ $RC = 0 ]"
check "matching: leaves the registration alone" "! grep -q 'claude mcp' '$LOG'"
check "matching: never overwrites existing preferences" "grep -q compact '$T/home/.awwwards-mcp/preferences.json'"

# Registered differently (the old npx form)
runit '{"mcpServers":{"awwwards":{"type":"stdio","command":"npx","args":["-y","awwwards-mcp"]}}}'; RC=$?
check "different: removes the old registration first" "[ \"\$(grep 'claude mcp' '$LOG' | head -1)\" = 'claude mcp remove awwwards -s user' ]"
check "different: then adds the manifest one" "grep -qx 'claude mcp add -s user awwwards -- awwwards-mcp' '$LOG'"

# Dry run changes nothing
rm -rf "$T/home/.awwwards-mcp"
: > "$LOG"
HOME="$T/home" PATH="$T/bin:$PATH" ATELIER_CLAUDE_JSON="$T/home/.claude.json" bash "$REPO/mcp/install.sh" --dry-run > "$T/out.log" 2>&1
check "dry run: calls no stub" "[ ! -s '$LOG' ]"
check "dry run: copies no preferences" "[ ! -e '$T/home/.awwwards-mcp' ]"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
