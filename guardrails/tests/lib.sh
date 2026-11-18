#!/bin/bash
# Fixture runner helpers. Sourced by run.sh.
#
# Case layout: fixtures/<hook>/<case>/
#   input.json        hook stdin; the literal {{CWD}} becomes the temp repo path
#   expect            one line: block | ask | deny | pass | context
#   repo/             optional tree copied into a fresh mktemp dir (git init if no .git)
#   env               optional KEY=VALUE lines exported for the hook ({{CWD}} expands)
#   stderr.contains   optional, one fixed string per line that stderr must contain
#   stdout.contains   optional, same for stdout
#   setup.sh          optional, run inside the temp repo before the hook
#   stdout.absent     optional, fixed strings that stdout must NOT contain
#   silent            optional marker: stdout and stderr must both be empty
#   after.sh          optional, run inside the temp repo after the hook; non-zero = FAIL
#
# Decision: exit 2 = block; exit 0 with permissionDecision ask/deny = that;
# exit 0 with additionalContext = context; exit 0 and no output = pass.
# Anything else is reported as "error:<detail>" and fails the case.

# Every temp dir lives under one mktemp root; nothing is written elsewhere.
LIB_TMP_ROOT=${LIB_TMP_ROOT:-$(mktemp -d)}

derive_decision() { # <exit> <stdout-file>
    local code=$1 out=$2 d
    if [ "$code" -eq 2 ]; then echo block; return; fi
    if [ "$code" -ne 0 ]; then echo "error:exit-$code"; return; fi
    if [ ! -s "$out" ]; then echo pass; return; fi
    d=$(jq -r '.hookSpecificOutput.permissionDecision // empty' "$out" 2>/dev/null)
    if [ "$d" = ask ] || [ "$d" = deny ]; then echo "$d"; return; fi
    if jq -e '.hookSpecificOutput.additionalContext // empty' "$out" >/dev/null 2>&1; then
        echo context; return
    fi
    echo "error:unrecognised-output"
}

run_case() { # <hook-cmd> <case-dir>
    local cmd=$1 dir=$2 name tmp repo out err code got want input line kind f why
    name="$(basename "$(dirname "$dir")")/$(basename "$dir")"
    tmp=$(mktemp -d "$LIB_TMP_ROOT/case.XXXXXX")
    repo="$tmp/repo"
    mkdir -p "$repo"
    [ -d "$dir/repo" ] && cp -R "$dir/repo/." "$repo/"
    [ -e "$repo/.git" ] || git -C "$repo" init -q
    repo=$(cd "$repo" && pwd -P)

    [ -f "$dir/setup.sh" ] && (cd "$repo" && bash "$dir/setup.sh") >/dev/null 2>&1
    input=$(<"$dir/input.json")
    input=${input//\{\{CWD\}\}/$repo}
    out="$tmp/stdout"; err="$tmp/stderr"
    (
        cd "$repo" || exit 99
        if [ -f "$dir/env" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                [ -n "$line" ] || continue
                line=${line//\{\{CWD\}\}/$repo}
                export "$line"
            done <"$dir/env"
        fi
        printf '%s' "$input" | bash -c "$cmd" >"$out" 2>"$err"
    )
    code=$?
    got=$(derive_decision "$code" "$out")
    want=$(tr -d '[:space:]' <"$dir/expect")

    why=""
    [ "$got" = "$want" ] || why="expected $want, got $got"
    if [ -z "$why" ] && [ -f "$dir/silent" ] && { [ -s "$out" ] || [ -s "$err" ]; }; then
        why="expected no output at all"
    fi
    if [ -z "$why" ] && [ -f "$dir/stdout.absent" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "$line" ] || continue
            grep -qiF -- "$line" "$out" && { why="stdout should not contain: $line"; break; }
        done <"$dir/stdout.absent"
    fi
    for kind in stdout stderr; do
        if [ -z "$why" ] && [ -f "$dir/$kind.contains" ]; then
            f="$out"; [ "$kind" = stderr ] && f="$err"
            while IFS= read -r line || [ -n "$line" ]; do
                [ -n "$line" ] || continue
                grep -qiF -- "$line" "$f" || { why="$kind missing: $line"; break; }
            done <"$dir/$kind.contains"
        fi
    done
    if [ -z "$why" ] && [ -f "$dir/after.sh" ]; then
        (cd "$repo" && bash "$dir/after.sh") >"$tmp/after.out" 2>&1 \
            || why="after.sh failed: $(head -c 200 "$tmp/after.out")"
    fi

    if [ -z "$why" ]; then
        echo "PASS $name ($want)"; return 0
    fi
    echo "FAIL $name: $why"; return 1
}
