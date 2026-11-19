#!/bin/bash
# Tests for the session binding: session-open.sh, session-close.sh and the claim
# step in pr-gate.sh (session-claim.sh). Prints PASS/FAIL lines for run.sh.
# Everything runs in mktemp dirs; no real marker is ever written.
#
# Flow under test, as in a real session: the PreToolUse hook (pr-gate.sh) sees
# the Bash command and the session_id, then the command runs. Here `call` does
# both steps: feed the hook the command as <sid>, then run the same command.

G="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=$(mktemp -d)
pass=0; fail=0
ok() { echo "PASS session-scripts/$1"; pass=$((pass + 1)); }
no() { echo "FAIL session-scripts/$1: $2"; fail=$((fail + 1)); }
expect() { # <name> <condition-exit> [why]
    if [ "$2" -eq 0 ]; then ok "$1"; else no "$1" "${3:-condition false}"; fi
}

newrepo() { # -> path
    local r
    r=$(mktemp -d "$ROOT/repo.XXXXXX"); r=$(cd "$r" && pwd -P)
    git -C "$r" init -q
    echo "$r"
}

hook() { # <repo> <sid> <command>  -> runs pr-gate.sh with that Bash call
    jq -n --arg cwd "$1" --arg sid "$2" --arg c "$3" \
        '{cwd: $cwd, session_id: $sid, tool_name: "Bash", tool_input: {command: $c}}' \
        | bash "$G/pr-gate.sh" >"$ROOT/hook.out" 2>"$ROOT/hook.err"
}

OPEN="$G/session-open.sh"
CLOSE="$G/session-close.sh"

# call <repo> <sid> <command...>: hook first, then the command, cwd = repo.
call() {
    local r=$1 sid=$2; shift 2
    hook "$r" "$sid" "$*"
    (cd "$r" && eval "$*") >"$ROOT/call.out" 2>"$ROOT/call.err"
}
sid_of() { jq -r '.sessionId // ""' "$1/.atelier/session.json" 2>/dev/null; }

# 1. claim of an unowned (absent) marker
r=$(newrepo)
call "$r" sess-A "$OPEN" SPEC.md feat/x; code=$?
expect "claim: absent marker is claimed" "$([ $code -eq 0 ] && [ "$(sid_of "$r")" = sess-A ]; echo $?)" "exit $code, sid=$(sid_of "$r")"
expect "claim: marker has spec, branch, sessionId" "$(jq -e '.spec=="SPEC.md" and .branch=="feat/x" and .sessionId=="sess-A"' "$r/.atelier/session.json" >/dev/null; echo $?)"
expect "claim: claim note is consumed" "$([ ! -e "$r/.atelier/session-claim" ]; echo $?)"

# 2. re-claim by the owner
call "$r" sess-A "$OPEN" SPEC.md feat/y; code=$?
expect "claim: owner re-claims (same spec)" "$([ $code -eq 0 ] && [ "$(sid_of "$r")" = sess-A ] && [ "$(jq -r .branch "$r/.atelier/session.json")" = feat/y ]; echo $?)" "exit $code"

# 3. refusal when owned by another session, marker untouched
before=$(cat "$r/.atelier/session.json")
call "$r" sess-B "$OPEN" SPEC.md feat/z; code=$?
expect "claim: other session is refused" "$([ $code -eq 1 ] && grep -q 'already open' "$ROOT/call.err"; echo $?)" "exit $code: $(cat "$ROOT/call.err")"
expect "claim: other session's marker is not overwritten" "$([ "$(cat "$r/.atelier/session.json")" = "$before" ]; echo $?)"
expect "claim: owner with a different spec is refused" \
    "$(call "$r" sess-A "$OPEN" OTHER.md feat/x; [ $? -eq 1 ] && [ "$(jq -r .spec "$r/.atelier/session.json")" = SPEC.md ]; echo $?)"

# 4. marker with no sessionId (old format): claimable for the same spec, not for another
r=$(newrepo); mkdir -p "$r/.atelier"; echo '{"spec":"SPEC.md","branch":"feat/x"}' >"$r/.atelier/session.json"
call "$r" sess-A "$OPEN" SPEC.md feat/x; code=$?
expect "claim: old-format marker is claimed by the first session" "$([ $code -eq 0 ] && [ "$(sid_of "$r")" = sess-A ]; echo $?)"
r=$(newrepo); mkdir -p "$r/.atelier"; echo '{"spec":"SPEC.md","branch":"feat/x"}' >"$r/.atelier/session.json"
call "$r" sess-A "$OPEN" OTHER.md feat/x; code=$?
expect "claim: old-format marker for another spec is refused" "$([ $code -eq 1 ] && [ -z "$(sid_of "$r")" ]; echo $?)"

# 5. commands that only MENTION the script do not claim
mention() { # <name> <command>
    local r
    r=$(newrepo)
    hook "$r" sess-X "$2"
    expect "no claim: $1" "$([ ! -e "$r/.atelier/session-claim" ] && [ ! -e "$r/.atelier/session.json" ]; echo $?)"
}
mention "echo mentions the script" "echo $OPEN SPEC.md feat/x"
mention "script inside a longer command (&&)" "ls && $OPEN SPEC.md feat/x"
mention "script after a semicolon" "true; $OPEN SPEC.md feat/x"
mention "script piped" "$OPEN SPEC.md feat/x | cat"
mention "script in a quoted string" "bash -c \"$OPEN SPEC.md feat/x\""
mention "script in a comment" "ls # $OPEN SPEC.md feat/x"
mention "script as an argument" "cat $OPEN"
mention "command substitution" "echo \$($OPEN SPEC.md feat/x)"
mention "heredoc line" "cat <<EOF
$OPEN SPEC.md feat/x
EOF"
mention "same name, different directory" "/tmp/elsewhere/session-open.sh SPEC.md feat/x"
mention "too many arguments" "$OPEN SPEC.md feat/x dir extra"
mention "newline-joined second command" "$OPEN SPEC.md feat/x
ls"
r=$(newrepo)
jq -n --arg cwd "$r" --arg c "$OPEN SPEC.md feat/x" '{cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}' | bash "$G/pr-gate.sh" >/dev/null 2>&1
expect "no claim: hook input without session_id" "$([ ! -e "$r/.atelier/session-claim" ]; echo $?)"

# 6. running the script with no hook claim writes nothing
r=$(newrepo)
(cd "$r" && "$OPEN" SPEC.md feat/x) >/dev/null 2>"$ROOT/err"; code=$?
expect "open without a claim: exit 1, no marker" "$([ $code -eq 1 ] && [ ! -e "$r/.atelier/session.json" ]; echo $?)"
mkdir -p "$r/.atelier"; printf 'sess-A\n%s\n' "$(( $(date +%s) - 600 ))" >"$r/.atelier/session-claim"
(cd "$r" && "$OPEN" SPEC.md feat/x) >/dev/null 2>&1; code=$?
expect "open with a stale claim: refused" "$([ $code -eq 1 ] && [ ! -e "$r/.atelier/session.json" ]; echo $?)"

# 7. explicit target dir (diverge: option worktree), tilde-free absolute path
r=$(newrepo); w=$(newrepo)
call "$r" sess-A "$OPEN" SPEC.md feat/x-opt-1 "$w"; code=$?
expect "target dir: marker lands in the option worktree only" "$([ $code -eq 0 ] && [ "$(sid_of "$w")" = sess-A ] && [ ! -e "$r/.atelier/session.json" ]; echo $?)" "exit $code: $(cat "$ROOT/call.err")"

# 8. close
r=$(newrepo)
call "$r" sess-A "$OPEN" SPEC.md feat/x >/dev/null
call "$r" sess-A "$CLOSE" --check; chk=$(cat "$ROOT/call.out")
expect "close --check: mine" "$([ "$chk" = mine ]; echo $?)" "got $chk"
call "$r" sess-B "$CLOSE" --check; chk=$(cat "$ROOT/call.out")
expect "close --check: other" "$([ "$chk" = other ]; echo $?)" "got $chk"
call "$r" sess-B "$CLOSE"; code=$?
expect "close: other session refused plainly, marker kept" "$([ $code -eq 1 ] && grep -q 'belongs to a different session' "$ROOT/call.err" && [ "$(sid_of "$r")" = sess-A ]; echo $?)"
call "$r" sess-A "$CLOSE"; code=$?
expect "close: owner closes, closed file keeps sessionId" "$([ $code -eq 0 ] && [ ! -e "$r/.atelier/session.json" ] && [ "$(jq -r .sessionId "$r/.atelier/session.closed.json")" = sess-A ]; echo $?)"
call "$r" sess-A "$CLOSE" --check; chk=$(cat "$ROOT/call.out")
expect "close --check: none after closing" "$([ "$chk" = none ]; echo $?)" "got $chk"
r=$(newrepo); mkdir -p "$r/.atelier"; echo '{"spec":"S","branch":"b"}' >"$r/.atelier/session.json"
call "$r" sess-A "$CLOSE" --check; chk=$(cat "$ROOT/call.out")
expect "close --check: unowned (old format)" "$([ "$chk" = unowned ]; echo $?)" "got $chk"
(cd "$r" && "$CLOSE" --check) >"$ROOT/call.out" 2>&1
expect "close --check: unknown without a claim" "$([ "$(cat "$ROOT/call.out")" = unknown ]; echo $?)"

# 9. claim step does not change the PR gate: a build-session PR create still blocks
r=$(newrepo)
call "$r" sess-A "$OPEN" SPEC.md feat/x >/dev/null
hook "$r" sess-A "gh pr create --fill"; code=$?
expect "pr gate still blocks the owner" "$([ $code -eq 2 ]; echo $?)" "exit $code"
hook "$r" sess-B "gh pr create --fill"; code=$?
expect "pr gate lets another session through, silently" "$([ $code -eq 0 ] && [ ! -s "$ROOT/hook.out" ] && [ ! -s "$ROOT/hook.err" ]; echo $?)"

echo "session-scripts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
