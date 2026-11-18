#!/bin/bash
# Installer tests. Every run has HOME pointed at a mktemp dir seeded with a
# sample settings.json, so the real ~/.claude is never written. The real
# settings.json is only hashed (read) before and after, as a safety check.
#   bash guardrails/tests/installer.sh

T="$(cd "$(dirname "$0")" && pwd)"
G="$(cd "$T/.." && pwd -P)"
FX="$T/fixtures/installer"
INSTALL="$G/install.sh"
ROOT=$(mktemp -d)
fails=0

REAL_SETTINGS="${HOME}/.claude/settings.json"
real_before=$(shasum "$REAL_SETTINGS" 2>/dev/null | cut -d' ' -f1)

ok()  { echo "PASS installer/$1"; }
bad() { echo "FAIL installer/$1${2:+: $2}"; fails=$((fails + 1)); }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi; }

# newhome: fresh temp HOME seeded with the sample settings; prints its path.
newhome() {
    local h; h=$(mktemp -d "$ROOT/home.XXXXXX")
    mkdir -p "$h/.claude"
    cp "$FX/seed-settings.json" "$h/.claude/settings.json"
    cp "$FX/seed-local.json" "$h/.claude/settings.local.json"
    echo "$h"
}
inst() { # <home> <install.sh> [flags]
    local h=$1 script=$2; shift 2
    HOME="$h" bash "$script" "$@"
}
norm() { # <file> <guardrails-dir>: absolute checkout path -> __G__
    sed "s|$2|__G__|g" "$1" | jq -S .
}
S() { echo "$1/.claude/settings.json"; }
hashf() { shasum "$1" | cut -d' ' -f1; }
jeq() { [ "$(jq -S . "$1")" = "$(jq -S . "$2")" ]; }
NEWPATHS='conventions-injector\.sh|lane-guard\.sh|fast-gate\.sh|dod-gate\.sh'

# 1. default run equals the baseline captured from the original installer
h=$(newhome)
inst "$h" "$INSTALL" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && [ "$(norm "$(S "$h")" "$G")" = "$(jq -S . "$FX/baseline-settings.json")" ] \
    && [ "$(norm "$h/.claude/settings.local.json" "$G")" = "$(jq -S . "$FX/baseline-local.json")" ]
check default-matches-baseline $? "exit $code"
default_state="$ROOT/default-state.json"; cp "$(S "$h")" "$default_state"

# 2. default installs none of the new hooks
! grep -qE "$NEWPATHS" "$(S "$h")"; check default-installs-no-new-hooks $?

# 3. enforce adds the four hooks with the right events and matchers
h=$(newhome)
inst "$h" "$INSTALL" --enforce >/dev/null 2>&1; code=$?
s=$(S "$h")
jq -e '
  def cmd($e; $m; $f): [.hooks[$e][] | select(.matcher == $m) | .hooks[].command | select(contains($f))] | length == 1;
  cmd("PreToolUse"; "Write|Edit"; "/guardrails/conventions-injector.sh")
  and cmd("PreToolUse"; "Write|Edit|NotebookEdit"; "/guardrails/lane-guard.sh")
  and cmd("PostToolUse"; "Write|Edit"; "/guardrails/fast-gate.sh")
  and ([.hooks.Stop[].hooks[].command | select(contains("/guardrails/dod-gate.sh"))] | length == 1)
  and ([.hooks.PreToolUse[].hooks[].command | select(contains("outside-repo-guard.sh"))] | length == 1)
  and ([.hooks.PreToolUse[].hooks[].command | select(contains("net-host-guard.py"))] | length == 1)
' "$s" >/dev/null 2>&1
check enforce-adds-four-hooks $? "exit $code"

# 4. every new command is fail-closed (exit 2 with a message when the script is missing)
n=$(jq -r '[.hooks[][] | .hooks[].command | select(test("conventions-injector|lane-guard|fast-gate|dod-gate"))
            | select(contains("exit 2") and contains("[ -x"))] | length' "$s")
[ "$n" -eq 4 ]; check enforce-commands-are-fail-closed $? "$n of 4 wrapped"

# 5. enforce twice: no duplicates, second run changes nothing
before=$(hashf "$s")
inst "$h" "$INSTALL" --enforce >/dev/null 2>&1
after=$(hashf "$s")
dups=$(jq -r '[.hooks[][] | .hooks[].command | select(test("conventions-injector|lane-guard|fast-gate|dod-gate"))] | length' "$s")
[ "$before" = "$after" ] && [ "$dups" -eq 4 ]; check enforce-is-idempotent $? "4 expected, got $dups"
enforced_hash=$(hashf "$s")

# 6. enforce then relax is jq-equal to the pre-enforce file; user keys and hooks survive
inst "$h" "$INSTALL" --relax >/dev/null 2>&1; code=$?
jeq "$s" "$default_state"
check relax-restores-pre-enforce-file $? "exit $code"
jq -e '.model == "opus" and .env.FOO == "bar"
       and (.hooks.PostToolUse | length) == 1 and .hooks.PostToolUse[0].hooks[0].command == "echo user-post"
       and (.hooks.Stop | length) == 1 and .hooks.Stop[0].hooks[0].command == "echo user-stop"
       and ([.hooks.PreToolUse[].hooks[].command | select(contains("user-pre") or contains("outside-repo-guard") or contains("net-host-guard"))] | length) == 3' "$s" >/dev/null 2>&1
check relax-keeps-user-hooks-and-existing-guards $?
jq -e '(.permissions.ask | index("Bash(git clean:*)")) and (.permissions.allow | index("Bash(ls:*)"))' "$s" >/dev/null 2>&1
check relax-keeps-permission-rules $?

# 7. relax twice, and relax on a file that never had enforce: no change
before=$(hashf "$s"); inst "$h" "$INSTALL" --relax >/dev/null 2>&1; after=$(hashf "$s")
[ "$before" = "$after" ]; check relax-is-idempotent $?

# 8. enforce after relax lands on the same file as the first enforce
inst "$h" "$INSTALL" --enforce >/dev/null 2>&1
[ "$(hashf "$s")" = "$enforced_hash" ]; check enforce-after-relax-matches-first-enforce $?

# 9. enforce on a settings file with no hooks at all, then relax: hooks key is gone again
h=$(newhome); printf '%s\n' '{"model":"opus"}' > "$(S "$h")"
inst "$h" "$INSTALL" --relax >/dev/null 2>&1
jq -e '. == {"model":"opus"}' "$(S "$h")" >/dev/null 2>&1; check relax-on-untouched-file-is-noop $?

# 10. both flags: non-zero, nothing touched
h=$(newhome); before=$(hashf "$(S "$h")")
inst "$h" "$INSTALL" --enforce --relax >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ "$(hashf "$(S "$h")")" = "$before" ] && [ "$(ls "$h/.claude" | grep -c bak)" -eq 0 ]
check both-flags-rejected $? "exit $code"

# 11. unknown flag: non-zero, nothing touched
inst "$h" "$INSTALL" --nope >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && [ "$(hashf "$(S "$h")")" = "$before" ]; check unknown-flag-rejected $? "exit $code"

# 12. default and --relax call no new script: run both from a copy with the four scripts moved away
mkdir -p "$ROOT/c1" "$ROOT/c2" && cp -R "$G" "$ROOT/c1/guardrails"
mkdir -p "$ROOT/gcopy-away"
for f in conventions-injector lane-guard fast-gate dod-gate; do mv "$ROOT/c1/guardrails/$f.sh" "$ROOT/gcopy-away/"; done
h=$(newhome)
inst "$h" "$ROOT/c1/guardrails/install.sh" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && [ "$(norm "$(S "$h")" "$ROOT/c1/guardrails")" = "$(jq -S . "$FX/baseline-settings.json")" ]
check default-works-without-new-scripts $? "exit $code"
inst "$h" "$G/install.sh" --enforce >/dev/null 2>&1
inst "$h" "$ROOT/c1/guardrails/install.sh" --relax >/dev/null 2>&1; code=$?

[ "$code" -eq 0 ] && ! grep -qE "$NEWPATHS" "$(S "$h")"; check relax-works-without-new-scripts $? "exit $code"

# 13. the wrapper blocks (exit 2, message) when a script is missing
h=$(newhome)
cp -R "$G" "$ROOT/c2/guardrails"
inst "$h" "$ROOT/c2/guardrails/install.sh" --enforce >/dev/null 2>&1
mv "$ROOT/c2/guardrails/dod-gate.sh" "$ROOT/gcopy-away/dod-gate.sh.2"
cmd=$(jq -r '.hooks.Stop[].hooks[].command | select(contains("dod-gate"))' "$(S "$h")")
msg=$(bash -c "$cmd" 2>&1 </dev/null); code=$?
[ "$code" -eq 2 ] && grep -qi 'missing' <<<"$msg"; check missing-script-fails-closed $? "exit $code: $msg"

# 14. nothing leaked into the installer's repo settings, and the real settings file is untouched
real_after=$(shasum "$REAL_SETTINGS" 2>/dev/null | cut -d' ' -f1)
[ "$real_before" = "$real_after" ]; check real-settings-unchanged $? "$real_before vs $real_after"
[ ! -e "$G/../.claude/settings.json" ]; check no-repo-settings-written $?

echo "installer: $fails failed"
[ "$fails" -eq 0 ]
