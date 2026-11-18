#!/bin/bash
# Tests for guardrails/lane-guard-init.sh. Every repo is a mktemp dir and HOME
# points at a mktemp dir too, so nothing real is touched.
#   bash guardrails/tests/lane-init.sh

G="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$G/lane-guard-init.sh"
ROOT=$(mktemp -d)
export HOME="$ROOT/home"
mkdir -p "$HOME"
fails=0

ok()   { echo "PASS lane-init/$1"; }
bad()  { echo "FAIL lane-init/$1${2:+: $2}"; fails=$((fails + 1)); }
check() { # <name> <condition-exit-code> [detail]
    if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi
}
newrepo() { local d; d=$(mktemp -d "$ROOT/repo.XXXXXX"); git -C "$d" init -q; (cd "$d" && pwd -P); }
hash() { shasum "$1" | cut -d' ' -f1; }

PATHS="auth api payments lib/shared"

# 1. fresh repo gets all four paths, Edit and Write
r=$(newrepo)
bash "$INIT" "$r" >/dev/null 2>&1; code=$?
missing=""
for p in $PATHS; do
    for t in Edit Write; do
        jq -e --arg r "$t($p/**)" '.permissions.deny | index($r)' "$r/.claude/settings.json" >/dev/null 2>&1 || missing="$missing $t($p/**)"
    done
done
check fresh-repo-has-all-four-paths $((code + ${#missing})) "exit $code, missing:$missing"

# 2. twice is byte-identical and makes no backup
h1=$(hash "$r/.claude/settings.json")
bash "$INIT" "$r" >/dev/null 2>&1
h2=$(hash "$r/.claude/settings.json")
baks=$(ls "$r/.claude" | grep -c '\.bak\.')
[ "$h1" = "$h2" ] && [ "$baks" -eq 0 ]; check second-run-byte-identical-no-backup $? "hash $h1 vs $h2, backups $baks"

# 3. unrelated keys and existing deny order survive; backup written
r=$(newrepo); mkdir -p "$r/.claude"
printf '%s\n' '{"model":"sonnet","permissions":{"allow":["Bash(ls)"],"deny":["Read(.env)","Edit(auth/**)"]},"hooks":{"Stop":[]}}' > "$r/.claude/settings.json"
bash "$INIT" "$r" >/dev/null 2>&1
s="$r/.claude/settings.json"
jq -e '.model == "sonnet" and .permissions.allow == ["Bash(ls)"] and .hooks == {"Stop":[]}
       and .permissions.deny[0] == "Read(.env)" and .permissions.deny[1] == "Edit(auth/**)"
       and ([.permissions.deny[] | select(. == "Edit(auth/**)")] | length) == 1
       and (.permissions.deny | index("Write(lib/shared/**)"))' "$s" >/dev/null 2>&1
check keeps-unrelated-keys-and-dedupes $?
baks=$(ls "$r/.claude" | grep -c '^settings.json.bak\.')
[ "$baks" -eq 1 ]; check existing-file-is-backed-up $? "backups: $baks"

# 4. non-git dir: non-zero, nothing written
d=$(mktemp -d "$ROOT/plain.XXXXXX")
bash "$INIT" "$d" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ ! -e "$d/.claude" ]; check non-git-dir-refused $? "exit $code"

# 5. $HOME refused even when it is a git repo
git -C "$HOME" init -q
bash "$INIT" "$HOME" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ ! -e "$HOME/.claude" ]; check home-refused $? "exit $code"

# 6. a subdirectory of a repo is refused (run it on the root)
r=$(newrepo); mkdir -p "$r/sub"
bash "$INIT" "$r/sub" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ ! -e "$r/sub/.claude" ] && [ ! -e "$r/.claude" ]; check subdir-refused $? "exit $code"

# 7. invalid JSON is left alone
r=$(newrepo); mkdir -p "$r/.claude"; printf 'not json {' > "$r/.claude/settings.json"
bash "$INIT" "$r" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ "$(cat "$r/.claude/settings.json")" = "not json {" ]; check invalid-json-untouched $? "exit $code"

# 8. no argument: non-zero
bash "$INIT" >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ]; check no-argument-refused $? "exit $code"

# 9. nothing was written under the (temp) home's .claude
[ ! -e "$HOME/.claude" ]; check nothing-written-under-home-claude $?

echo "lane-init: $fails failed"
[ "$fails" -eq 0 ]
