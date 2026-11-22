#!/bin/bash
# Tests for the fast gate's "report only what the Builder caused" behavior:
# the baseline session-open.sh takes, and how fast-gate.sh compares against it,
# for type errors and for eslint. Prints PASS/FAIL lines for run.sh.
#
# tsc and eslint are stubs here. The real-compiler cases live in
# fast-gate-real.sh. Everything runs in mktemp dirs.
#
# A stub reads what to print from files beside the repo (../tsc.out,
# ../eslint.out, ../eslint.old.out, ../showconfig.json), so a case can change
# the "compiler's" answer between opening the build and the edit.

G="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=$(mktemp -d)
pass=0; fail=0
ok() { echo "PASS fast-gate-baseline/$1"; pass=$((pass + 1)); }
no() { echo "FAIL fast-gate-baseline/$1: $2"; fail=$((fail + 1)); }
expect() { # <name> <condition-exit> [why]
    if [ "$2" -eq 0 ]; then ok "$1"; else no "$1" "${3:-condition false}"; fi
}

TSC_STUB='#!/bin/sh
echo "tsc $*" >> "$PWD/../stub.log"
case "$*" in
    *--showConfig*) [ -f "$PWD/../showconfig.json" ] && { cat "$PWD/../showconfig.json"; exit 0; }; exit 1 ;;
esac
[ -z "$STUB_SLEEP" ] || sleep "$STUB_SLEEP"
f="$PWD/../tsc.out"
[ -f "$f" ] && cat "$f"
[ -f "$PWD/../tsc.exit" ] && exit "$(cat "$PWD/../tsc.exit")"
[ -f "$f" ] && grep -q "error TS" "$f" && exit 2
exit 0
'
ESLINT_STUB='#!/bin/sh
echo "eslint $*" >> "$PWD/../stub.log"
f="$PWD/../eslint.out"
case "$*" in *--stdin*) f="$PWD/../eslint.old.out" ;; esac
if [ -f "$f" ]; then cat "$f"; grep -q "\"severity\":2" "$f" && exit 1; else echo "[]"; fi
exit 0
'

# mk: a repo with one commit, stubs installed. Sets C (case dir) and R (repo).
mk() {
    C=$(mktemp -d "$ROOT/case.XXXXXX"); C=$(cd "$C" && pwd -P); R="$C/repo"
    mkdir -p "$R/src" "$R/node_modules/.bin" "$R/.atelier"
    git -C "$R" init -q
    git -C "$R" config user.email t@example.com
    git -C "$R" config user.name t
    printf 'node_modules\n.atelier\n' >"$R/.git/info/exclude"
    printf '%s' "$TSC_STUB" >"$R/node_modules/.bin/tsc"
    printf '%s' "$ESLINT_STUB" >"$R/node_modules/.bin/eslint"
    chmod +x "$R/node_modules/.bin/tsc" "$R/node_modules/.bin/eslint"
    printf 'export const a = 1;\n' >"$R/src/a.ts"
    printf 'export const o = 1;\n' >"$R/src/old.ts"
    printf '{}\n' >"$R/tsconfig.json"
    git -C "$R" add src tsconfig.json
    git -C "$R" commit -q -m start
}

OLD_ERR="src/old.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'."
A_ERR="src/a.ts(1,14): error TS2322: Type 'string' is not assignable to type 'number'."

# open_build: claim and open the build as sess-build. Sets OPEN_OUT, OPEN_CODE.
open_build() {
    printf 'sess-build\n%s\n' "$(date +%s)" >"$R/.atelier/session-claim"
    OPEN_OUT=$(cd "$R" && bash "$G/session-open.sh" SPEC.md feat/x 2>&1); OPEN_CODE=$?
}

# gate <file>: run the fast gate for an edit of <file> (relative to the repo).
gate() {
    jq -n --arg cwd "$R" --arg f "$R/$1" \
        '{cwd: $cwd, session_id: "sess-build", tool_name: "Edit", tool_input: {file_path: $f}}' \
        | (cd "$R" && bash "$G/fast-gate.sh") >"$C/gate.out" 2>"$C/gate.err"
    GATE_CODE=$?
}
has() { grep -qF -- "$1" "$C/gate.err"; }   # gate stderr contains <text>

# 1. opening records the starting commit, the baseline and says how many
mk
printf '%s\n%s\n' "$OLD_ERR" "src/old.ts(5,7): error TS2304: Cannot find name 'x'." >"$C/tsc.out"
open_build
expect "open: exits 0 and prints the baseline count" "$([ $OPEN_CODE -eq 0 ] && grep -q 'baseline: 2 type errors recorded' <<<"$OPEN_OUT"; echo $?)" "exit $OPEN_CODE: $OPEN_OUT"
expect "open: marker holds the starting commit" "$([ "$(jq -r .startCommit "$R/.atelier/session.json")" = "$(git -C "$R" rev-parse HEAD)" ]; echo $?)"
expect "open: baseline has no line numbers" "$(grep -q '^src/old.ts	TS2322	Type' "$R/.atelier/baseline.tsc.txt" && ! grep -q '(3,7)' "$R/.atelier/baseline.tsc.txt"; echo $?)"
cp "$R/.atelier/baseline.tsc.txt" "$C/baseline.first"
printf '%s\n' "$OLD_ERR" "$A_ERR" >"$C/tsc.out"
open_build   # refresh by the owner
expect "open: a refresh keeps the first baseline" "$([ $OPEN_CODE -eq 0 ] && cmp -s "$R/.atelier/baseline.tsc.txt" "$C/baseline.first"; echo $?)" "exit $OPEN_CODE"

# 2. a pre-existing error in an untouched file is not reported
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const a = 2;\n' >"$R/src/a.ts"
gate src/a.ts
expect "baseline error in an untouched file is not reported" "$([ $GATE_CODE -eq 0 ] && [ ! -s "$C/gate.err" ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 3. a pre-existing error in a file the Builder edits is not reported
mk
printf '%s\n' "$A_ERR" >"$C/tsc.out"
open_build
printf 'export const a = 2;\n' >"$R/src/a.ts"
gate src/a.ts
expect "baseline error in an edited file is not reported" "$([ $GATE_CODE -eq 0 ] && [ ! -s "$C/gate.err" ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 4. a new error in an edited file blocks, and the old one stays out of it
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const a = 2;\n' >"$R/src/a.ts"
printf '%s\n%s\n' "$OLD_ERR" "$A_ERR" >"$C/tsc.out"
gate src/a.ts
expect "new error in an edited file blocks" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you changed' && has 'src/a.ts(1,14)'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
expect "new error report leaves the baseline error out" "$(! has 'src/old.ts'; echo $?)"
expect "no baseline note when there is a baseline" "$(! has 'no baseline'; echo $?)"

# 5. a new error in a file the Builder did not edit blocks under its own label
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const a = 2;\n' >"$R/src/a.ts"
printf '%s\n%s\n' "$OLD_ERR" "src/use.ts(2,1): error TS2554: Expected 2 arguments, but got 1." >"$C/tsc.out"
gate src/a.ts
expect "new error in an untouched file blocks, own label" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you did not edit, caused by your change' && has 'src/use.ts(2,1)'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
expect "that report does not list the baseline error" "$(! has 'src/old.ts'; echo $?)"
expect "that report has no 'files you changed' section" "$(! has 'new errors in files you changed'; echo $?)"

# 6. the same message once more than the baseline counts as new
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const o = 2;\n' >"$R/src/old.ts"
printf '%s\n%s\n' "$OLD_ERR" "src/old.ts(8,7): error TS2322: Type 'string' is not assignable to type 'number'." >"$C/tsc.out"
gate src/old.ts
expect "one more of the same message is new" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you changed' && has 'src/old.ts'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
# and exactly the baseline count passes
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
gate src/old.ts
expect "the baseline count of the same message is not new" "$([ $GATE_CODE -eq 0 ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 7. line shifts do not make an old error look new
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf '\n\n\n\n\n\nexport const o = 2;\n' >"$R/src/old.ts"
printf '%s\n' "src/old.ts(9,7): error TS2322: Type 'string' is not assignable to type 'number'." >"$C/tsc.out"
gate src/old.ts
expect "a shifted old error is not new" "$([ $GATE_CODE -eq 0 ] && [ ! -s "$C/gate.err" ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 8. no baseline: a marker from an older version falls back and says so
mk
printf '{"spec":"SPEC.md","branch":"feat/x","sessionId":"sess-build"}\n' >"$R/.atelier/session.json"
printf 'export const a = 2;\n' >"$R/src/a.ts"
printf '%s\n%s\n' "$OLD_ERR" "$A_ERR" >"$C/tsc.out"
gate src/a.ts
expect "no baseline: errors in changed files are reported" "$([ $GATE_CODE -eq 2 ] && has 'src/a.ts(1,14)'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
expect "no baseline: errors in untouched files are not reported" "$(! has 'src/old.ts'; echo $?)"
expect "no baseline: one line says so" "$([ "$(grep -ci 'no baseline' "$C/gate.err")" -eq 1 ]; echo $?)" "$(cat "$C/gate.err")"

# 9. baseline step failing or timing out never stops the open
mk
printf 'boom\n' >"$C/tsc.out"; echo 1 >"$C/tsc.exit"
open_build
expect "open: a crashing type check still opens, no baseline" "$([ $OPEN_CODE -eq 0 ] && grep -q '^baseline: none' <<<"$OPEN_OUT" && [ -f "$R/.atelier/session.json" ] && [ ! -e "$R/.atelier/baseline.tsc.txt" ] && jq -e '.baseline == null' "$R/.atelier/session.json" >/dev/null; echo $?)" "exit $OPEN_CODE: $OPEN_OUT"
printf 'export const a = 2;\n' >"$R/src/a.ts"
printf '%s\n' "$A_ERR" >"$C/tsc.out"; rm -f "$C/tsc.exit"
gate src/a.ts
expect "after a failed baseline the gate falls back" "$([ $GATE_CODE -eq 2 ] && has 'no baseline'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
s=$(date +%s)
OPEN_OUT=$(cd "$R" && printf 'sess-build\n%s\n' "$(date +%s)" >.atelier/session-claim && STUB_SLEEP=20 ATELIER_GATE_TIMEOUT=1 bash "$G/session-open.sh" SPEC.md feat/x 2>&1); OPEN_CODE=$?
took=$(( $(date +%s) - s ))
expect "open: a slow type check times out at the gate's limit and still opens" "$([ $OPEN_CODE -eq 0 ] && [ "$took" -lt 10 ] && grep -q 'baseline: none (the type check timed out after 1s)' <<<"$OPEN_OUT" && [ -f "$R/.atelier/session.json" ]; echo $?)" "exit $OPEN_CODE after ${took}s: $OPEN_OUT"

# 10. zero-files guard: exit 0 on a check that covered nothing is an error
mk
printf '{"files":[]}\n' >"$C/showconfig.json"
open_build
expect "open: a check that covers no files records no baseline" "$([ $OPEN_CODE -eq 0 ] && grep -q 'baseline: none (the type check covers no files' <<<"$OPEN_OUT"; echo $?)" "$OPEN_OUT"
printf 'export const a = 2;\n' >"$R/src/a.ts"
gate src/a.ts
expect "zero files covered: exit 0 is not clean" "$([ $GATE_CODE -eq 2 ] && has 'covered no files' && has 'proves nothing'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
printf '{"files":["src/a.ts"]}\n' >"$C/showconfig.json"
gate src/a.ts
expect "files covered: exit 0 is clean" "$([ $GATE_CODE -eq 0 ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 11. a bare tsc call with no tsconfig is left as it was (no showConfig probing)
mk
rm -f "$R/tsconfig.json"
open_build
printf 'export const a = 2;\n' >"$R/src/a.ts"
gate src/a.ts
expect "no tsconfig: runs tsc --noEmit as before" "$([ $GATE_CODE -eq 0 ] && grep -q '^tsc --noEmit --pretty false' "$C/stub.log" && ! grep -q showConfig "$C/stub.log"; echo $?)" "exit $GATE_CODE: $(cat "$C/stub.log")"

# eslint -------------------------------------------------------------------
# ej <severity> <line> <rule> <message>: eslint -f json report with one message
ej() {
    jq -nc --argjson s "$1" --argjson l "$2" --arg r "$3" --arg m "$4" \
        '[{filePath: "/r/src/a.ts", messages: [{ruleId: $r, severity: $s, message: $m, line: $l, column: 1}]}]'
}
# ejoin <report>...: one report holding every message
ejoin() { printf '%s\n' "$@" | jq -sc '[{filePath: "/r/src/a.ts", messages: [.[][].messages[]]}]'; }
ESL_OLD=$(ej 2 1 no-unused-vars "'a' is defined but never used.")
ESL_MOVED=$(ej 2 3 no-unused-vars "'a' is defined but never used.")
ESL_NEW=$(ej 2 4 no-console "Unexpected console statement.")
ESL_WARN=$(ej 1 2 no-warning-comments "Unexpected todo.")

# 12. a pre-existing lint error in the edited file is not reported
mk
open_build
printf '%s\n' "$ESL_OLD" >"$C/eslint.old.out"
printf '\n\n%s\n' "x" >>"$R/src/a.ts"
printf '%s\n' "$ESL_MOVED" >"$C/eslint.out"
gate src/a.ts
expect "eslint: old error (moved lines) is not reported" "$([ $GATE_CODE -eq 0 ] && [ ! -s "$C/gate.err" ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
expect "eslint: old content is linted through stdin under the same filename" "$(grep -q -- "--stdin --stdin-filename $R/src/a.ts" "$C/stub.log"; echo $?)" "$(cat "$C/stub.log")"

# 13. a new lint error is reported, the old one is not
ejoin "$ESL_OLD" "$ESL_NEW" >"$C/eslint.out"
gate src/a.ts
expect "eslint: new error blocks" "$([ $GATE_CODE -eq 2 ] && has 'no-console' && has 'new errors'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"
expect "eslint: report leaves the old error out" "$(! has 'no-unused-vars'; echo $?)"

# 14. warnings never block
printf '%s\n' "$ESL_WARN" >"$C/eslint.out"
gate src/a.ts
expect "eslint: warnings do not block" "$([ $GATE_CODE -eq 0 ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 15. a file that is new has no baseline: all its lint errors count
mk
open_build
printf 'export const n = 1;\n' >"$R/src/new.ts"
printf '%s\n' "$ESL_OLD" >"$C/eslint.out"
gate src/new.ts
expect "eslint: a new file has no baseline" "$([ $GATE_CODE -eq 2 ] && has 'no-unused-vars'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 16. type errors in a new (untracked) file count as changed
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const n = 1;\n' >"$R/src/new.ts"
printf '%s\n%s\n' "$OLD_ERR" "src/new.ts(1,14): error TS2322: Type 'string' is not assignable to type 'number'." >"$C/tsc.out"
gate src/new.ts
expect "type error in a new file blocks as changed" "$([ $GATE_CODE -eq 2 ] && has 'src/new.ts(1,14)' && has 'new errors in files you changed'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 17. an error in a file changed earlier in the session (not the one just edited) is "changed"
mk
printf '%s\n' "$OLD_ERR" >"$C/tsc.out"
open_build
printf 'export const o = 2;\n' >"$R/src/old.ts"      # edited earlier this session
printf 'export const a = 2;\n' >"$R/src/a.ts"        # edited now
printf '%s\n%s\n' "$OLD_ERR" "src/old.ts(9,7): error TS2304: Cannot find name 'y'." >"$C/tsc.out"
gate src/a.ts
expect "a new error in an earlier-changed file is under 'you changed'" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you changed' && has 'src/old.ts(9,7)' && ! has 'did not edit'; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

# 18. N4: counts inside a message change with any edit and are not a new error
mk
open_build
ESL_L1=$(ej 2 1 max-lines "File has too many lines (312). Maximum allowed is 300.")
ESL_L2=$(ej 2 1 max-lines "File has too many lines (314). Maximum allowed is 300.")
printf '%s\n' "$ESL_L1" >"$C/eslint.old.out"
printf '%s\n' "$ESL_L2" >"$C/eslint.out"
printf 'export const a = 3;\n' >>"$R/src/a.ts"
gate src/a.ts
expect "eslint: a changed count in the same message is not new" "$([ $GATE_CODE -eq 0 ]; echo $?)" "exit $GATE_CODE: $(cat "$C/gate.err")"

echo "fast-gate-baseline: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
