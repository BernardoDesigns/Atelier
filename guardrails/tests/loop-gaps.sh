#!/bin/bash
# Tests for the three dry-run loop gaps. Prints PASS/FAIL lines for run.sh.
#   lane        the "lane" requirement in dod-check.sh, through dod-gate.sh (Stop)
#               and pr-gate.sh (gh pr create). Small temp git repos.
#   bash-write  the Bash write nudge in pr-gate.sh (build session only)
#   stop-bg     dod-gate.sh stays silent while background_tasks are running
# Everything runs in mktemp dirs. No real marker is written, nothing leaves them.

G="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$G/tests/fixtures/dod-gate/complete-session/repo/.atelier"
ROOT=$(mktemp -d)
GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
pass=0; fail=0
ok() { echo "PASS loop-gaps/$1"; pass=$((pass + 1)); }
no() { echo "FAIL loop-gaps/$1: $2"; fail=$((fail + 1)); }

# Run a hook. Sets RC and ERR. <hook> is dod or pr; <extra> is a jq object merged into the input.
gate() { # <hook> <repo> <sid> <extra-json> [command]
    local hook=$1 repo=$2 sid=$3 extra=$4 cmd=${5:-}
    if [ "$hook" = dod ]; then
        jq -n --arg cwd "$repo" --arg sid "$sid" --argjson x "$extra" \
            '{cwd: $cwd, session_id: $sid, hook_event_name: "Stop", stop_hook_active: false} + $x' \
            | bash "$G/dod-gate.sh" >"$ROOT/out" 2>"$ROOT/err"
    else
        jq -n --arg cwd "$repo" --arg sid "$sid" --arg c "$cmd" --argjson x "$extra" \
            '{cwd: $cwd, session_id: $sid, tool_name: "Bash", tool_input: {command: $c}} + $x' \
            | bash "$G/pr-gate.sh" >"$ROOT/out" 2>"$ROOT/err"
    fi
    RC=$?; ERR=$(cat "$ROOT/err")
}

# A repo whose build session is bound to sess-build. <complete> = 1 copies the
# four artefacts so only the lane requirement can fail. Branch <branch> (default main).
newrepo() { # <complete> [branch]
    local r
    r=$(mktemp -d "$ROOT/repo.XXXXXX"); r=$(cd "$r" && pwd -P)
    git -C "$r" init -q -b "${2:-main}"
    if [ "$1" = 1 ]; then
        mkdir -p "$r/.atelier"; cp -R "$SRC/." "$r/.atelier/"
    else
        mkdir -p "$r/.atelier"; cp "$SRC/session.json" "$r/.atelier/session.json"
    fi
    echo base >"$r/README.md"; mkdir -p "$r/src" "$r/auth" "$r/payments" "$r/api" "$r/lib/shared"
    echo a >"$r/src/a.ts"; echo a >"$r/auth/login.ts"; echo a >"$r/lib/shared/util.ts"
    git -C "$r" add README.md src auth lib
    "${GIT[@]}" -C "$r" commit -q -m base
    echo "$r"
}
commit_file() { # <repo> <path>
    mkdir -p "$(dirname "$1/$2")"; echo "$RANDOM" >"$1/$2"
    git -C "$1" add "$2"; "${GIT[@]}" -C "$1" commit -q -m "touch $2"
}

# expect <name> <hook> <repo> <want: pass|block> [stderr needle] [sid] [extra] [command]
expect() {
    local name=$1 hook=$2 repo=$3 want=$4 needle=${5:-} sid=${6:-sess-build} extra=${7:-"{}"} cmd=${8:-"gh pr create --fill"} got=pass
    gate "$hook" "$repo" "$sid" "$extra" "$cmd"
    [ "$RC" -eq 2 ] && got=block
    if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ]; then no "$name" "exit $RC"; return; fi
    if [ "$got" != "$want" ]; then no "$name" "expected $want, got $got: $ERR"; return; fi
    if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$ERR"; then no "$name" "stderr missing '$needle': $ERR"; return; fi
    if [ "$want" = pass ] && [ -s "$ROOT/err" ]; then no "$name" "expected silence, got: $ERR"; return; fi
    ok "$name"
}

# ---- lane, through both gates -------------------------------------------------
for hook in dod pr; do
    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x; commit_file "$r" src/b.ts
    expect "lane/$hook: clean branch passes" "$hook" "$r" pass

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x; commit_file "$r" auth/session.ts
    expect "lane/$hook: committed change under auth/ fails and names the file" "$hook" "$r" block "auth/session.ts"
    expect "lane/$hook: message says revert and tell the user" "$hook" "$r" block "tell the user"

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x; commit_file "$r" src/b.ts
    echo x >"$r/payments/charge.ts"
    expect "lane/$hook: untracked file under payments/ fails" "$hook" "$r" block "payments/charge.ts"

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x
    echo changed >"$r/lib/shared/util.ts"
    expect "lane/$hook: unstaged edit under lib/shared/ fails" "$hook" "$r" block "lib/shared/util.ts"

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x
    echo x >"$r/api/route.ts"; git -C "$r" add api/route.ts
    expect "lane/$hook: staged file under api/ fails" "$hook" "$r" block "api/route.ts"

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x
    mkdir -p "$r/src/billing" "$r/.claude"; echo x >"$r/src/billing/a.ts"
    expect "lane/$hook: src/billing/ is not protected without a rule" "$hook" "$r" pass
    echo '{"protected":["src/billing/**"]}' >"$r/.claude/lane-rules.json"
    expect "lane/$hook: lane-rules.json extra path is honoured" "$hook" "$r" block "src/billing/a.ts"
    echo '{"protected":' >"$r/.claude/lane-rules.json"
    rm "$r/src/billing/a.ts"; echo x >"$r/auth/new.ts"
    expect "lane/$hook: unreadable rules file still applies the defaults" "$hook" "$r" block "auth/new.ts"

    r=$(newrepo 1 trunk); commit_file "$r" auth/session.ts
    expect "lane/$hook: no base branch, committed change is not seen (working tree only)" "$hook" "$r" pass
    echo changed >"$r/auth/login.ts"
    expect "lane/$hook: no base branch, working-tree change still fails" "$hook" "$r" block "auth/login.ts"

    r=$(newrepo 1 master); git -C "$r" checkout -q -b feat/y; commit_file "$r" payments/x.ts
    expect "lane/$hook: master is used as the base when main is absent" "$hook" "$r" block "payments/x.ts"

    r=$(newrepo 1); git -C "$r" checkout -q -b feat/x; commit_file "$r" auth/session.ts
    expect "lane/$hook: another session is not gated" "$hook" "$r" pass "" other-sess
done

# ---- Stop gate with background tasks -------------------------------------------
r=$(newrepo 0)
bg='{"background_tasks":[{"id":"t1","type":"subagent","status":"running","agent_type":"builder"}]}'
expect "stop-bg: a running subagent keeps the Stop gate silent" dod "$r" pass "" sess-build "$bg"
expect "stop-bg: a running task among finished ones keeps it silent" dod "$r" pass "" sess-build \
    '{"background_tasks":[{"id":"a","status":"completed"},{"id":"b","type":"shell","status":"running"}]}'
expect "stop-bg: no tasks, nudges as before" dod "$r" block "Missing" sess-build '{"background_tasks":[],"session_crons":[]}'
expect "stop-bg: field absent, nudges as before" dod "$r" block "Missing"
expect "stop-bg: only finished tasks, nudges" dod "$r" block "Missing" sess-build '{"background_tasks":[{"id":"a","status":"completed"},{"id":"b","status":"failed"}]}'
expect "stop-bg: a string instead of an array, nudges" dod "$r" block "Missing" sess-build '{"background_tasks":"running"}'
expect "stop-bg: an object instead of an array, nudges" dod "$r" block "Missing" sess-build '{"background_tasks":{"status":"running"}}'
expect "stop-bg: entries that are not objects, nudges" dod "$r" block "Missing" sess-build '{"background_tasks":["running",1,null]}'
expect "stop-bg: only session_crons set, nudges" dod "$r" block "Missing" sess-build '{"background_tasks":[],"session_crons":[{"id":"c","schedule":"0 9 * * *","recurring":true}]}'
expect "stop-bg: the PR gate ignores background tasks" pr "$r" block "Missing" sess-build "$bg"

# ---- Bash write nudge ------------------------------------------------------------
r=$(newrepo 1)
# nudge <name> <block|pass> <command> [sid]
nudge() {
    local want=$2 sid=${4:-sess-build} got=pass
    gate pr "$r" "$sid" "{}" "$3"
    [ "$RC" -eq 2 ] && got=block
    if [ "$got" != "$want" ]; then no "bash-write/$1" "expected $want, got $got (exit $RC): $ERR"; return; fi
    if [ "$want" = block ] && ! grep -qF "Write or Edit tool" <<<"$ERR"; then no "bash-write/$1" "message missing: $ERR"; return; fi
    if [ "$want" = pass ] && [ -s "$ROOT/err" ]; then no "bash-write/$1" "expected silence: $ERR"; return; fi
    ok "bash-write/$1"
}
nudge "blocks cat > file with a heredoc" block 'cat > src/Card.tsx <<EOF
export const Card = () => <div onClick={() => go()} />;
EOF'
nudge "blocks cat >> file with a quoted heredoc" block "cat >> src/Card.tsx <<'EOF'
more
EOF"
nudge "blocks echo > file" block 'echo "export {}" > src/index.ts'
nudge "blocks >> into a repo file" block 'echo x >> README.md'
nudge "blocks tee into a repo file" block 'printf x | tee src/x.ts'
nudge "blocks tee -a into a repo file" block 'echo x | tee -a src/x.ts'
nudge "blocks sed -i" block "sed -i '' 's/a/b/' src/a.ts"
nudge "blocks sed -i.bak" block "sed -i.bak 's/a/b/' src/a.ts"
nudge "blocks perl -pi" block "perl -pi -e 's/a/b/' src/a.ts"
nudge "blocks jq into the repo" block 'jq . package.json > src/data.json'
nudge "blocks a redirect inside bash -c" block 'bash -c "echo hi > src/x.ts"'
nudge "blocks after other commands on the line" block 'ls && echo hi > src/x.ts'
nudge "blocks the dry-run cat >> with a heredoc" block "cat >> lib/data/index.ts <<'EOF'
export const rows = [];
EOF"
# Inline scripts that write files (the second thing the Builder reached for in the dry run).
nudge "blocks the dry-run python3 - heredoc read then write" block "python3 - <<'EOF'
p='src/a.ts'
s=open(p).read()
s=s.replace('a','b')
open(p,'w').write(s)
EOF"
nudge "blocks python3 heredoc without the dash" block "python3 <<EOF
with open(path, \"a\") as f:
    f.write('x')
EOF"
nudge "blocks python3 -c with open(p,'w')" block "python3 -c \"open(p,'w').write('x')\""
nudge "blocks python -c with open(p, \"a\")" block "python -c 'open(p, \"a\").write(1)'"
nudge "blocks open with mode=" block "python3 -c \"open(p, mode='w').write('x')\""
nudge "blocks open with mode x and a literal repo path" block "python3 -c \"open('src/x.ts','x').write('x')\""
nudge "blocks Path.write_text" block "python3 -c \"import pathlib; pathlib.Path(p).write_text('x')\""
nudge "blocks write_bytes in a heredoc" block "python3 - <<'EOF'
Path('src/a.bin').write_bytes(b'x')
EOF"
nudge "blocks node -e writeFileSync" block "node -e \"require('fs').writeFileSync(p, 'x')\""
nudge "blocks node --eval appendFileSync" block "node --eval \"fs.appendFileSync('src/a.ts', 'x')\""
nudge "blocks node heredoc writeFile" block "node - <<'EOF'
const fs = require('fs');
fs.writeFile(p, s, () => {});
EOF"
nudge "blocks node createWriteStream and fs.promises.writeFile" block "node -e \"fs.createWriteStream(out)\""
nudge "blocks ruby -e File.write" block "ruby -e \"File.write(p, 'x')\""
nudge "blocks ruby heredoc File.open with w" block "ruby <<'EOF'
File.open(p, 'w') { |f| f.write('x') }
EOF"
nudge "blocks perl -e open with >" block "perl -e 'open(F, \">\", \$p); print F 1'"
nudge "blocks an inline write whose target is built from a variable under a temp-looking name" block "python3 -c \"open('/tmp/' + name + '/../../x','w')\""
nudge "allows an inline write to a literal .atelier path" pass "python3 -c \"open('.atelier/x.json','w').write('{}')\""
nudge "allows an inline write to a literal /tmp path" pass "node -e \"require('fs').writeFileSync('/tmp/x.json', '{}')\""
nudge "allows node running a script file" pass 'node scripts/x.mjs --out build'
nudge "allows python running a script file" pass 'python3 tools/y.py --fix'
nudge "allows python -m pytest" pass 'python3 -m pytest -q'
nudge "allows node -e with no write call" pass "node -e \"console.log(require('./package.json').version)\""
nudge "allows python3 -c with no write call" pass "python3 -c 'print(1)'"
nudge "allows python3 -I -c that prints" pass "python3 -I -c 'import sys; print(sys.version)'"
nudge "allows an inline script that only reads" pass "python3 - <<'EOF'
p='src/a.ts'
s=open(p).read()
t=open(p,'r').read()
print(len(s), len(t))
EOF"
nudge "allows a node heredoc that only reads" pass "node - <<'EOF'
console.log(require('fs').readFileSync('package.json','utf8').length)
EOF"
nudge "allows run-tests.sh with a plain command" pass '~/.claude/atelier/guardrails/run-tests.sh npm test'
nudge "allows run-tests.sh with bash -lc" pass "~/.claude/atelier/guardrails/run-tests.sh bash -lc 'npm run lint && npm test 2>&1 | tail -20'"
nudge "allows git commands" pass 'git add -A && git commit -m "a -> b" && git diff --shortstat main...HEAD'
nudge "allows git diff redirected" pass 'git diff main...HEAD > changes.patch'
nudge "allows npm run with 2>&1 and a pipe to tail" pass 'npm run build 2>&1 | tail -20'
nudge "allows npx and node scripts" pass 'npx tsc --noEmit 2>&1 | head -40; node scripts/check.mjs'
nudge "allows 2>&1" pass 'npm test 2>&1'
nudge "allows >/dev/null" pass 'ls >/dev/null'
nudge "allows 2>/dev/null" pass 'ls src 2>/dev/null'
nudge "allows >/dev/null 2>&1" pass 'git fetch >/dev/null 2>&1'
nudge "allows a redirect into .atelier/" pass 'echo "A1" >> .atelier/assumptions.md'
nudge "allows jq into .atelier/" pass 'jq -n "{pass:true}" > .atelier/tests.json'
nudge "allows a redirect into ./.atelier/ and an absolute .atelier path" pass 'echo x > ./.atelier/a.txt; echo y > /somewhere/repo/.atelier/b.txt'
nudge "allows a redirect into /tmp" pass 'echo x > /tmp/scratch.txt'
nudge "allows a redirect into \$TMPDIR" pass 'echo x > $TMPDIR/scratch.txt'
nudge "allows a mktemp path" pass 'f=$(mktemp); echo x > "$f"; echo y > $(mktemp)/z'
nudge "allows pipes to tail, head, grep" pass 'git log --oneline | grep fix | head -5 | tail -2'
nudge "allows the render harness" pass 'node ~/.claude/atelier/render/cli.mjs --plan .atelier/render-plan.json > .atelier/render.log 2>&1'
nudge "allows gh commands" pass 'gh pr view 3 --json title > pr.json'
nudge "allows a quoted > argument" pass 'grep -c ">" src/a.ts'
nudge "allows > inside a quoted commit message" pass 'git commit -m "move a > b"'
nudge "allows a > in a comment" pass 'ls src # > nowhere'
nudge "allows tee into a temp path" pass 'echo x | tee /tmp/x.log'
nudge "allows a write after cd into a temp dir" pass 'cd /tmp && echo x > a.txt'
nudge "allows a write outside the repo" pass 'echo x > /Users/someone/elsewhere/file.txt'
nudge "does nothing for another session" pass 'echo hi > src/x.ts' other-sess
mv "$r/.atelier/session.json" "$r/.atelier/session.json.away"
nudge "does nothing without a marker" pass 'echo hi > src/x.ts'
mv "$r/.atelier/session.json.away" "$r/.atelier/session.json"
echo '{"spec":"S","branch":"b"}' >"$r/.atelier/session.json"
nudge "does nothing for a marker with no sessionId" pass 'echo hi > src/x.ts'

# ---- run-tests.sh records .atelier/tests.json ---------------------------------------
RT="$G/run-tests.sh"
chk() { # <name> <condition-exit> [why]
    if [ "$2" -eq 0 ]; then ok "$1"; else no "$1" "${3:-condition false}"; fi
}
r=$(newrepo 1); rm -f "$r/.atelier/tests.json"
(cd "$r" && bash "$RT" true) >"$ROOT/o" 2>&1; code=$?
chk "run-tests: a passing command exits 0" "$([ $code -eq 0 ]; echo $?)" "exit $code"
chk "run-tests: records pass true, exitCode 0, the command" "$(jq -e '.pass == true and .exitCode == 0 and .command == "true"' "$r/.atelier/tests.json" >/dev/null; echo $?)"
chk "run-tests: ranAt is a UTC ISO time" "$(jq -e '.ranAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$r/.atelier/tests.json" >/dev/null; echo $?)"
chk "run-tests: no temp file left behind" "$([ "$(ls "$r/.atelier" | grep -c '^tests.json.')" -eq 0 ]; echo $?)"
(cd "$r" && bash "$RT" bash -c 'echo out-line; echo err-line >&2; exit 3') >"$ROOT/o" 2>&1; code=$?
chk "run-tests: exits with the command's code" "$([ $code -eq 3 ]; echo $?)" "exit $code"
chk "run-tests: output passes through" "$(grep -q out-line "$ROOT/o" && grep -q err-line "$ROOT/o"; echo $?)"
chk "run-tests: records pass false, exitCode 3, the command as given" "$(jq -e '.pass == false and .exitCode == 3 and (.command | startswith("bash -c"))' "$r/.atelier/tests.json" >/dev/null; echo $?)"
(cd "$r" && bash "$RT" no-such-command-xyz) >/dev/null 2>&1; code=$?
chk "run-tests: a missing command is a recorded failure" "$([ $code -eq 127 ] && jq -e '.pass == false and .exitCode == 127' "$r/.atelier/tests.json" >/dev/null; echo $?)" "exit $code"
d=$(mktemp -d "$ROOT/bare.XXXXXX")
(cd "$d" && bash "$RT" true) >"$ROOT/o" 2>&1; code=$?
chk "run-tests: refuses without .atelier/, runs nothing, writes nothing" "$([ $code -eq 2 ] && [ ! -e "$d/.atelier" ] && grep -q '.atelier' "$ROOT/o"; echo $?)" "exit $code"
(cd "$r" && bash "$RT") >/dev/null 2>&1; code=$?
chk "run-tests: no command is a usage error" "$([ $code -eq 2 ]; echo $?)" "exit $code"
mv "$r/.atelier/session.json" "$r/.atelier/session.json.away"
(cd "$r" && bash "$RT" true) >/dev/null 2>&1; code=$?
chk "run-tests: needs no session marker" "$([ $code -eq 0 ]; echo $?)" "exit $code"
mv "$r/.atelier/session.json.away" "$r/.atelier/session.json"

# The definition of done reads it. Gate on a repo whose only variable is tests.json.
for hook in dod pr; do
    r=$(newrepo 1)
    (cd "$r" && bash "$RT" true) >/dev/null 2>&1
    expect "run-tests/$hook: a recorded pass is accepted" "$hook" "$r" pass
    (cd "$r" && bash "$RT" false) >/dev/null 2>&1
    expect "run-tests/$hook: a recorded fail is rejected" "$hook" "$r" block "tests:"
    echo '{"pass":true,"command":"npm test","ranAt":"2026-11-18T18:00:00Z"}' >"$r/.atelier/tests.json"
    expect "run-tests/$hook: a hand-written file without exitCode is rejected" "$hook" "$r" block "was not written by run-tests.sh"
    echo '{"pass":true,"exitCode":"0"}' >"$r/.atelier/tests.json"
    expect "run-tests/$hook: a non-numeric exitCode is rejected" "$hook" "$r" block "was not written by run-tests.sh"
    rm "$r/.atelier/tests.json"
    expect "run-tests/$hook: a missing file is rejected" "$hook" "$r" block "run-tests.sh"
done

echo "loop-gaps: $pass passed, $fail failed" >&2
[ "$fail" -eq 0 ]
