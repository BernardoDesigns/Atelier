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

# 10. archive of a finished build's artefacts on open
FIX="$G/tests/fixtures/dod-gate/complete-session/repo/.atelier"
closedrepo() { # [branch] -> repo holding a wrapped build's artefacts
    local r
    r=$(newrepo); mkdir -p "$r/.atelier"; cp -R "$FIX/." "$r/.atelier/"
    rm -f "$r/.atelier/session.json"
    echo "fast gate output" >"$r/.atelier/fast-gate.tsc.out"; echo stamp >"$r/.atelier/conventions-injected"
    [ -n "${1:-}" ] && jq -n --arg b "$1" '{spec:"OLD.md",branch:$b,sessionId:"sess-old"}' >"$r/.atelier/session.closed.json"
    echo "$r"
}
missing_of() { # <repo> -> dod_missing output, one line per missing requirement
    ( . "$G/dod-check.sh"; dod_missing "$1/.atelier"; printf '%s\n' "$DOD_MISSING" )
}
r=$(closedrepo feat/old-thing)
expect "archive: fixture build is complete before the open" "$([ -z "$(missing_of "$r")" ]; echo $?)" "$(missing_of "$r")"
call "$r" sess-A "$OPEN" SPEC.md feat/new; code=$?
out=$(cat "$ROOT/call.out")
arch=$(ls "$r/.atelier/archive" 2>/dev/null)
expect "archive: open succeeds and says what it archived, before opened:" \
    "$([ $code -eq 0 ] && [ "$(sed -n 1p "$ROOT/call.out")" = "archived the previous build's artefacts to .atelier/archive/$arch/" ] && sed -n 2p "$ROOT/call.out" | grep -q '^opened: '; echo $?)" "exit $code: $out"
expect "archive: only archive/ and the new session.json are left" \
    "$([ "$(ls -A "$r/.atelier" | sort | tr '\n' ' ')" = "archive session.json " ]; echo $?)" "$(ls -A "$r/.atelier")"
expect "archive: one folder, named <UTC timestamp>-<closed branch slug>" \
    "$([ "$(printf '%s\n' "$arch" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$arch" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-feat-old-thing$'; echo $?)" "$arch"
expect "archive: everything came across (renders, notes, tests, closed marker, stamps)" \
    "$(d="$r/.atelier/archive/$arch"; [ -d "$d/renders" ] && [ -f "$d/critique.md" ] && [ -f "$d/tests.json" ] && [ -f "$d/assumptions.md" ] && [ -f "$d/session.closed.json" ] && [ -f "$d/fast-gate.tsc.out" ] && [ -f "$d/conventions-injected" ]; echo $?)" "$(ls -A "$r/.atelier/archive/$arch")"
expect "archive: new marker is bound to the opener" "$([ "$(sid_of "$r")" = sess-A ] && [ "$(jq -r .branch "$r/.atelier/session.json")" = feat/new ]; echo $?)"
m=$(missing_of "$r")
expect "archive: dod-check reports screenshots, assumptions, tests and critique missing again" \
    "$(grep -q '^- screenshots:' <<<"$m" && grep -q '^- assumptions:' <<<"$m" && grep -q '^- tests:' <<<"$m" && grep -q '^- critique:' <<<"$m"; echo $?)" "$m"

# the owner refreshing the same spec archives nothing, even with artefacts present
echo "mine" >"$r/.atelier/assumptions.md"
call "$r" sess-A "$OPEN" SPEC.md feat/new2; code=$?
expect "archive: refresh by the owner (same spec) archives nothing" \
    "$([ $code -eq 0 ] && [ "$(ls "$r/.atelier/archive" | wc -l | tr -d ' ')" = 1 ] && [ "$(cat "$r/.atelier/assumptions.md")" = mine ] && ! grep -q archived "$ROOT/call.out"; echo $?)" "exit $code: $(cat "$ROOT/call.out")"

# refused opens archive nothing
snap() { ls -A "$1/.atelier"; ls -A "$1/.atelier/archive" 2>/dev/null; }
before=$(snap "$r")
call "$r" sess-B "$OPEN" SPEC.md feat/z; code=$?
expect "archive: refused (owned by another session) archives nothing" "$([ $code -eq 1 ] && [ "$(snap "$r")" = "$before" ]; echo $?)"
call "$r" sess-A "$OPEN" OTHER.md feat/z; code=$?
expect "archive: refused (different spec) archives nothing" "$([ $code -eq 1 ] && [ "$(snap "$r")" = "$before" ]; echo $?)"
r2=$(closedrepo feat/old-thing); echo '{"spec":"S","branch":"b"}' >"$r2/.atelier/session.json"
call "$r2" sess-A "$OPEN" OTHER.md feat/z; code=$?
expect "archive: refused (old-format marker, different spec) archives nothing" "$([ $code -eq 1 ] && [ ! -d "$r2/.atelier/archive" ] && [ -f "$r2/.atelier/critique.md" ]; echo $?)"
r2=$(closedrepo feat/old-thing)
(cd "$r2" && "$OPEN" SPEC.md feat/z) >/dev/null 2>&1; code=$?
expect "archive: refused (no claim) archives nothing" "$([ $code -eq 1 ] && [ ! -d "$r2/.atelier/archive" ] && [ -f "$r2/.atelier/critique.md" ]; echo $?)"

# no closed marker: branch is "unknown"; an old archive is never swept into the new one
r2=$(closedrepo)
mkdir -p "$r2/.atelier/archive/20200101T000000Z-older"; echo keep >"$r2/.atelier/archive/20200101T000000Z-older/x"
call "$r2" sess-A "$OPEN" SPEC.md feat/new; code=$?
expect "archive: no closed marker names the folder -unknown" "$([ $code -eq 0 ] && ls "$r2/.atelier/archive" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-unknown$'; echo $?)"
expect "archive: earlier archive folders stay where they are" "$([ -f "$r2/.atelier/archive/20200101T000000Z-older/x" ] && [ "$(ls "$r2/.atelier/archive" | wc -l | tr -d ' ')" = 2 ]; echo $?)"

# an existing folder with the same name gets a numeric suffix
r2=$(closedrepo feat/old-thing)
stub="$ROOT/date-stub"; mkdir -p "$stub"
printf '#!/bin/sh\nif [ "$1" = "-u" ]; then echo 20261119T181500Z; else exec /bin/date "$@"; fi\n' >"$stub/date"; chmod +x "$stub/date"
mkdir -p "$r2/.atelier/archive/20261119T181500Z-feat-old-thing"
hook "$r2" sess-A "$OPEN SPEC.md feat/new"
(cd "$r2" && PATH="$stub:$PATH" "$OPEN" SPEC.md feat/new) >"$ROOT/call.out" 2>"$ROOT/call.err"; code=$?
expect "archive: same-name folder gets a numeric suffix" \
    "$([ $code -eq 0 ] && [ -f "$r2/.atelier/archive/20261119T181500Z-feat-old-thing-2/critique.md" ] && [ -z "$(ls -A "$r2/.atelier/archive/20261119T181500Z-feat-old-thing")" ]; echo $?)" "exit $code: $(cat "$ROOT/call.err")"

# a failing move stops the open and writes no marker
r2=$(closedrepo feat/old-thing)
chmod 555 "$r2/.atelier"
call "$r2" sess-A "$OPEN" SPEC.md feat/new; code=$?
chmod 755 "$r2/.atelier"
expect "archive: unwritable archive parent exits non-zero, no marker, nothing moved" \
    "$([ $code -ne 0 ] && [ ! -e "$r2/.atelier/session.json" ] && [ -f "$r2/.atelier/critique.md" ] && [ ! -d "$r2/.atelier/archive" ]; echo $?)" "exit $code: $(cat "$ROOT/call.err")"
r2=$(closedrepo feat/old-thing); mkdir -p "$r2/.atelier/archive"
chmod 555 "$r2/.atelier/archive"
call "$r2" sess-A "$OPEN" SPEC.md feat/new; code=$?
chmod 755 "$r2/.atelier/archive"
expect "archive: unwritable archive folder exits non-zero, no marker" \
    "$([ $code -ne 0 ] && [ ! -e "$r2/.atelier/session.json" ] && [ -f "$r2/.atelier/critique.md" ]; echo $?)" "exit $code: $(cat "$ROOT/call.err")"

# diverge: the same rule applies to the option worktree directory
r=$(newrepo); w=$(closedrepo feat/opt-old)
call "$r" sess-A "$OPEN" SPEC.md feat/opt-1 "$w"; code=$?
expect "archive: option worktree is archived like any other dir" \
    "$([ $code -eq 0 ] && [ "$(ls -A "$w/.atelier" | sort | tr '\n' ' ')" = "archive session.json " ] && ls "$w/.atelier/archive" | grep -Eq -- '-feat-opt-old$' && [ ! -e "$r/.atelier/archive" ]; echo $?)" "exit $code: $(cat "$ROOT/call.err")"

# gates look at the live files only: a complete build sitting in archive/ satisfies nothing
r2=$(newrepo); mkdir -p "$r2/.atelier/archive/old"; cp -R "$FIX/." "$r2/.atelier/archive/old/"
m=$(missing_of "$r2")
expect "archive: dod-check ignores what is under archive/" "$(grep -q '^- screenshots:' <<<"$m" && grep -q '^- critique:' <<<"$m" && grep -q '^- tests:' <<<"$m" && grep -q '^- assumptions:' <<<"$m"; echo $?)" "$m"

echo "session-scripts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
