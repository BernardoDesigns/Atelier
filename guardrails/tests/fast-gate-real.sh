#!/bin/bash
# Tests for the fast gate against a REAL TypeScript compiler (no stubs), so it
# can't be fooled the way a stub can. Prints PASS/FAIL lines for run.sh.
#
# One-time setup, needed before these can pass:
#
#   cd guardrails/tests && npm ci
#
# That installs the exact TypeScript in guardrails/tests/package.json (see the
# lockfile) into guardrails/tests/node_modules, which git ignores. If it is
# missing, every case below FAILS with a message saying so. They are never skipped.
#
# The headline case: a solution-style root tsconfig ("files": [] plus
# "references") where a plain `tsc --noEmit` checks nothing and exits 0, while
# the real check (`tsc -b`) reports the type error. The old gate ran the plain
# command and so reported clean.

T="$(cd "$(dirname "$0")" && pwd)"
G="$(cd "$T/.." && pwd)"
FX="$T/fixtures/fast-gate-real"
REALTSC="${ATELIER_TEST_TSC:-$T/node_modules/typescript/bin/tsc}"
pass=0; fail=0
ok() { echo "PASS fast-gate-real/$1"; pass=$((pass + 1)); }
no() { echo "FAIL fast-gate-real/$1: $2"; fail=$((fail + 1)); }
expect() { # <name> <condition-exit> [why]
    if [ "$2" -eq 0 ]; then ok "$1"; else no "$1" "${3:-condition false}"; fi
}

CASES="premise-plain-tsc-is-clean-on-solution-root
gate-blocks-on-solution-root
second-run-reports-the-same-errors
no-stale-clean-after-fix-and-rebreak
gate-writes-no-source-files
composite-outdir-build-info-removed
non-solution-project-keeps-plain-noemit
baseline-ignores-old-error-and-passes
baseline-importer-broken-by-change-blocks
baseline-extra-identical-error-blocks"

if [ ! -f "$REALTSC" ] || ! node "$REALTSC" -v >/dev/null 2>&1; then
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        no "$c" "the real TypeScript compiler is not installed. Run npm ci in guardrails/tests (one time), then re-run."
    done <<<"$CASES"
    echo "fast-gate-real: $pass passed, $fail failed"
    exit 1
fi
TSC_VERSION=$(node "$REALTSC" -v | sed "s/^Version //")

ROOT=$(mktemp -d)

# mkproj <fixture-dir>: a git repo (one commit) from the fixture, with the real
# tsc at node_modules/.bin/tsc. Sets R. node_modules is local to the repo, so the
# build info under node_modules/.tmp never leaves the temp dir.
mkproj() {
    R=$(mktemp -d "$ROOT/p.XXXXXX"); R=$(cd "$R" && pwd -P)
    cp -R "$1/." "$R/"
    mkdir -p "$R/node_modules/.bin" "$R/.atelier"
    ln -s "$REALTSC" "$R/node_modules/.bin/tsc"
    git -C "$R" init -q
    git -C "$R" config user.email t@example.com
    git -C "$R" config user.name t
    printf 'node_modules\n.atelier\n' >"$R/.git/info/exclude"
    git -C "$R" add -A . >/dev/null
    git -C "$R" commit -q -m start
}
# Marker as an older version wrote it: bound to the session, no baseline.
plain_marker() { printf '{"spec":"SPEC.md","branch":"feat/x","sessionId":"sess-build"}\n' >"$R/.atelier/session.json"; }
open_build() {
    printf 'sess-build\n%s\n' "$(date +%s)" >"$R/.atelier/session-claim"
    OPEN_OUT=$(cd "$R" && bash "$G/session-open.sh" SPEC.md feat/x 2>&1); OPEN_CODE=$?
}
gate() { # <file relative to the repo>
    jq -n --arg cwd "$R" --arg f "$R/$1" \
        '{cwd: $cwd, session_id: "sess-build", tool_name: "Edit", tool_input: {file_path: $f}}' \
        | (cd "$R" && bash "$G/fast-gate.sh") >"$R/../gate.out" 2>"$R/../gate.err"
    GATE_CODE=$?
}
err() { cat "$R/../gate.err"; }
has() { grep -qF -- "$1" "$R/../gate.err"; }
# Files in the work tree that git sees, ignoring the Atelier scratch dir.
tree_state() { git -C "$R" status --porcelain -uall | sort; }

# 1. the premise: on the solution fixture the old gate's command is clean
mkproj "$FX/solution"
(cd "$R" && node_modules/.bin/tsc --noEmit >"$R/../plain.out" 2>&1); plain=$?
(cd "$R" && node_modules/.bin/tsc -b --noEmit >"$R/../b.out" 2>&1); b=$?
expect "premise-plain-tsc-is-clean-on-solution-root" "$([ $plain -eq 0 ] && [ $b -ne 0 ] && grep -q 'TS2322' "$R/../b.out"; echo $?)" "TypeScript $TSC_VERSION: plain exit $plain, -b exit $b"
git -C "$R" status --porcelain >/dev/null

# 2. the gate blocks on it (an old gate would exit 0 here)
mkproj "$FX/solution"; plain_marker
gate src/a.ts
expect "gate-blocks-on-solution-root" "$([ $GATE_CODE -eq 2 ] && has 'error TS2322' && has 'src/a.ts' && has 'tsc -b --noEmit'; echo $?)" "TypeScript $TSC_VERSION: exit $GATE_CODE: $(err)"

# 3. a second run, nothing changed, reports the same thing
cp "$R/../gate.err" "$R/../gate.first"
gate src/a.ts
expect "second-run-reports-the-same-errors" "$([ $GATE_CODE -eq 2 ] && cmp -s "$R/../gate.first" "$R/../gate.err"; echo $?)" "exit $GATE_CODE: $(err)"

# 4. fix it: clean. Break it again: blocked again (stale state never turns clean)
printf 'export const a: number = 1;\n' >"$R/src/a.ts"
gate src/a.ts; fixed=$GATE_CODE
gate src/a.ts; fixed_again=$GATE_CODE
printf 'export const a: number = "broken again";\n' >"$R/src/a.ts"
gate src/a.ts; broken=$GATE_CODE
expect "no-stale-clean-after-fix-and-rebreak" "$([ $fixed -eq 0 ] && [ $fixed_again -eq 0 ] && [ $broken -eq 2 ] && has 'error TS2322'; echo $?)" "fixed $fixed, again $fixed_again, broken $broken"

# 5. the gate wrote no source files and left no new files behind
mkproj "$FX/solution"; plain_marker
before=$(tree_state)
gate src/a.ts; gate src/a.ts
after=$(tree_state)
expect "gate-writes-no-source-files" "$([ "$before" = "$after" ] && [ -z "$after" ]; echo $?)" "before: [$before] after: [$after]"

# 6. composite project with an outDir: tsc -b puts build info under outDir.
# The gate must not leave it (or the directory) in the source tree.
mkproj "$FX/solution"; plain_marker
printf '{ "compilerOptions": { "composite": true, "noEmit": true, "strict": true, "outDir": "out" }, "include": ["src"] }\n' >"$R/tsconfig.app.json"
git -C "$R" commit -q -am composite
gate src/a.ts; c1=$GATE_CODE
gate src/a.ts; c2=$GATE_CODE
leftover=$(cd "$R" && find . -name '*.tsbuildinfo' -not -path './node_modules/*' -not -path './.git/*'; [ -d out ] && echo out)
expect "composite-outdir-build-info-removed" "$([ $c1 -eq 2 ] && [ $c2 -eq 2 ] && [ -z "$leftover" ] && [ -z "$(tree_state)" ]; echo $?)" "exits $c1 $c2, left behind: [$leftover] [$(tree_state)]"

# 7. no references: the plain check is kept
mkproj "$FX/solution"; plain_marker
printf '{ "compilerOptions": { "noEmit": true, "strict": true }, "include": ["src"] }\n' >"$R/tsconfig.json"
rm -f "$R/tsconfig.app.json"
gate src/a.ts
expect "non-solution-project-keeps-plain-noemit" "$([ $GATE_CODE -eq 2 ] && has 'tsc --noEmit' && ! has 'tsc -b'; echo $?)" "exit $GATE_CODE: $(err)"

# Baseline end to end, real compiler. src/old.ts is already broken when the
# build opens; src/use.ts imports src/lib.ts.
baseline_project() {
    mkproj "$FX/solution"
    printf 'export const a: number = 1;\n' >"$R/src/a.ts"
    printf 'export function greet(name: string): string {\n  return `hi ${name}`;\n}\n' >"$R/src/lib.ts"
    printf 'import { greet } from "./lib";\n\nexport const hello = greet("there");\n' >"$R/src/use.ts"
    printf 'export const old: number = "already broken";\n' >"$R/src/old.ts"
    git -C "$R" add -A . >/dev/null; git -C "$R" commit -q -m files
    open_build
}

# 8. the old error is baseline: touching another file passes
baseline_project
printf '// tweak\nexport function greet(name: string): string {\n  return `hi ${name}`;\n}\n' >"$R/src/lib.ts"
gate src/lib.ts
expect "baseline-ignores-old-error-and-passes" "$([ $OPEN_CODE -eq 0 ] && grep -q 'baseline: 1 type error recorded (tsc -b --noEmit)' <<<"$OPEN_OUT" && [ $GATE_CODE -eq 0 ] && [ ! -s "$R/../gate.err" ]; echo $?)" "open: $OPEN_OUT; gate $GATE_CODE: $(err)"

# 9. changing an export breaks an importer you did not edit
printf 'export function greet(name: string, times: number): string {\n  return `hi ${name}`.repeat(times);\n}\n' >"$R/src/lib.ts"
gate src/lib.ts
expect "baseline-importer-broken-by-change-blocks" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you did not edit, caused by your change' && has 'src/use.ts' && ! has 'src/old.ts'; echo $?)" "exit $GATE_CODE: $(err)"

# 10. one more of the same message in the already-broken file is new
baseline_project
printf 'export const old: number = "already broken";\nexport const old2: number = "already broken";\n' >"$R/src/old.ts"
gate src/old.ts
expect "baseline-extra-identical-error-blocks" "$([ $GATE_CODE -eq 2 ] && has 'new errors in files you changed' && has 'src/old.ts(2,14)'; echo $?)" "exit $GATE_CODE: $(err)"

echo "fast-gate-real: $pass passed, $fail failed (TypeScript $TSC_VERSION)"
[ "$fail" -eq 0 ]
