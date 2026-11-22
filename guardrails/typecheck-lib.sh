# Sourced by fast-gate.sh and session-open.sh. Not run directly.
#
# One place for "how this repo type checks" and "which errors are new", so the
# baseline taken when a build opens and the check after each edit can't drift.
#
# Uses only the repo's own tsc (node_modules/.bin/tsc), jq, git, awk and sed.
#
#   atelier_run_limited <outfile> <cmd...>     run with a time limit ($TIMEOUT, seconds)
#   atelier_tsc_check <cwd> <outfile>          run the repo's real type check
#   atelier_tsc_keys                           stdin: tsc output; stdout: comparison keys
#   atelier_tsc_split <base|""> <changed> <C> <U>   split tsc output into new errors
#   atelier_changed_files <cwd> <start> <target>    stdout: files changed this session
#
# atelier_tsc_check picks the command from the repo's root tsconfig.json:
#   - root has a non-empty "references" array (solution style, the stock Vite
#     layout): `tsc -b --noEmit`. A root `tsc --noEmit` there checks no files and
#     exits 0 while the real check fails. If the installed tsc rejects --noEmit
#     with -b (error TS5094, TypeScript before 5.6), it falls back to
#     `tsc -p <each referenced config> --noEmit`, which never emits either.
#   - otherwise: `tsc --noEmit`.
# The config is read by tsc itself (`tsc --showConfig`), so comments and
# trailing commas in tsconfig files are fine.
#
# Sets: TC_CMD (text for messages), TC_CODE (exit code, 124 = timed out),
# TC_FILES (files the check covered, or "unknown"), TC_NOTE (extra line, may be empty).

TIMEOUT=${TIMEOUT:-${ATELIER_GATE_TIMEOUT:-60}}

# Run a command with a time limit (macOS has no timeout(1)). Output goes to $1.
# Stdin comes from $ATELIER_STDIN when set, else /dev/null.
atelier_run_limited() { # <outfile> <cmd...>
    local outfile=$1; shift
    "$@" >"$outfile" 2>&1 <"${ATELIER_STDIN:-/dev/null}" &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$TIMEOUT" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "[timed out after ${TIMEOUT}s]" >>"$outfile"
            return 124
        fi
        sleep 1; waited=$((waited + 1))
    done
    wait "$pid"
}

# Number of files a tsconfig covers, plus everything it references, via
# tsc --showConfig. Prints "unknown" when tsc can't say (stub, old tsc, broken
# config). References are followed to a depth of 5.
_atelier_cfg_files() { # <tsc> <config-path or dir> [depth]
    local json n total ref base depth=${3:-0}
    [ "$depth" -le 5 ] || { echo unknown; return; }
    json=$("$1" --showConfig -p "$2" 2>/dev/null) || { echo unknown; return; }
    total=$(jq -r '(.files // []) | length' <<<"$json" 2>/dev/null) || { echo unknown; return; }
    if [ -d "$2" ]; then base=$2; else base=$(dirname "$2"); fi
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        n=$(_atelier_cfg_files "$1" "$base/$ref" $((depth + 1)))
        [ "$n" != unknown ] || { echo unknown; return; }
        total=$((total + n))
    done < <(jq -r '(.references // [])[].path' <<<"$json" 2>/dev/null)
    echo "$total"
}

# Tree of *.tsbuildinfo files outside node_modules, .git and .atelier.
_atelier_buildinfo_list() { # <cwd>
    (cd "$1" && find . \( -name node_modules -o -name .git -o -name .atelier \) -prune -o -name '*.tsbuildinfo' -print 2>/dev/null | sort)
}

atelier_tsc_check() { # <cwd> <outfile>
    local cwd=$1 out=$2 tsc="$1/node_modules/.bin/tsc" json mode=plain refs ref scratch rc code=0 f
    TC_CMD="tsc --noEmit"; TC_CODE=0; TC_FILES=unknown; TC_NOTE=""
    scratch="$cwd/.atelier"
    mkdir -p "$scratch"
    : >"$out"

    if [ -f "$cwd/tsconfig.json" ]; then
        json=$(cd "$cwd" && "$tsc" --showConfig 2>/dev/null) || json=""
        if [ -n "$json" ] && jq -e '(.references | type) == "array" and (.references | length) > 0' >/dev/null 2>&1 <<<"$json"; then
            mode=build
            refs=$(jq -r '.references[].path' <<<"$json")
        fi
        # Files the check covers: the root's, and everything it references.
        if [ -n "$json" ] && jq -e . >/dev/null 2>&1 <<<"$json"; then
            TC_FILES=$(cd "$cwd" && _atelier_cfg_files "$tsc" "$cwd")
        fi
    fi

    # Build info the check creates inside the source tree is removed afterwards
    # (see the end of this function); snapshot what is there now.
    _atelier_buildinfo_list "$cwd" >"$scratch/.tsbuildinfo.before" 2>/dev/null

    if [ "$mode" = build ]; then
        TC_CMD="tsc -b --noEmit"
        (cd "$cwd" && atelier_run_limited "$out" "$tsc" -b --noEmit --pretty false)
        TC_CODE=$?
        if [ "$TC_CODE" -ne 0 ] && grep -q 'TS5094' "$out"; then
            # tsc before 5.6: --noEmit is not allowed with -b. Check each
            # referenced config on its own; nothing is emitted that way.
            TC_CMD="tsc -p <each referenced config> --noEmit"
            TC_NOTE="This TypeScript predates tsc -b --noEmit (5.6), so each referenced tsconfig was checked on its own."
            : >"$out"
            while IFS= read -r ref; do
                [ -n "$ref" ] || continue
                (cd "$cwd" && atelier_run_limited "$out.part" "$tsc" -p "$ref" --noEmit --pretty false)
                rc=$?
                cat "$out.part" >>"$out"
                if [ "$rc" -eq 124 ]; then code=124; elif [ "$code" -ne 124 ] && [ "$rc" -ne 0 ]; then code=$rc; fi
            done <<<"$refs"
            TC_CODE=$code
            rm -f "$out.part"
        fi
    else
        (cd "$cwd" && atelier_run_limited "$out" "$tsc" --noEmit --pretty false)
        TC_CODE=$?
    fi

    # Remove build info this run created in the source tree (composite projects
    # and incremental builds put it beside the tsconfig or in outDir), then the
    # directory if that left it empty. Build info that already existed, and
    # anything under node_modules (the Vite layout), stays and is tsc's to keep.
    _atelier_buildinfo_list "$cwd" >"$scratch/.tsbuildinfo.after" 2>/dev/null
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rm -f "$cwd/$f" && rmdir "$(dirname "$cwd/$f")" 2>/dev/null
    done < <(comm -13 "$scratch/.tsbuildinfo.before" "$scratch/.tsbuildinfo.after")
    rm -f "$scratch/.tsbuildinfo.before" "$scratch/.tsbuildinfo.after"
    return 0
}

# awk function shared by the key extractor and the splitter: one error line in,
# "file<TAB>code<TAB>message" out (empty when the line is not an error headline).
_ATELIER_AWK_PARSE='
    function parse(line,   rest, f, c, m) {
        if (match(line, /\([0-9]+,[0-9]+\): error TS[0-9]+: /)) {
            f = substr(line, 1, RSTART - 1); rest = substr(line, RSTART, RLENGTH)
            m = substr(line, RSTART + RLENGTH)
            match(rest, /TS[0-9]+/); c = substr(rest, RSTART, RLENGTH)
            sub(/^\.\//, "", f)
            return f "\t" c "\t" m
        }
        if (match(line, /^error TS[0-9]+: /)) {
            rest = substr(line, 1, RLENGTH); m = substr(line, RLENGTH + 1)
            match(rest, /TS[0-9]+/)
            return "\t" substr(rest, RSTART, RLENGTH) "\t" m
        }
        return ""
    }
'

# stdin: tsc output. stdout: one key per error, "file<TAB>code<TAB>message".
# No line numbers: they shift when the Builder edits. Continuation lines (the
# indented detail under an error) are not part of the key.
atelier_tsc_keys() {
    awk "$_ATELIER_AWK_PARSE"'
    { k = parse($0); if (k != "") print k }'
}

# Split tsc output (stdin) into errors that are new against the baseline.
#   $1  baseline keys file, or "" for no baseline (every error counts as new)
#   $2  file with one changed path per line
#   $3  output file for new errors in changed files (and errors tied to no file)
#   $4  output file for new errors in files that are not in the changed list
# A baseline key covers as many errors as it appears: one more of the same
# message in the same file is new. The whole error block is written, detail lines too.
atelier_tsc_split() { # <base|""> <changed> <outC> <outU>   (stdin: tsc output)
    : >"$3"; : >"$4"
    awk -v base="$1" -v changed="$2" -v outc="$3" -v outu="$4" "$_ATELIER_AWK_PARSE"'
    function flush() {
        if (block == "") return
        if (isnew) { if (sect == "C") print block >> outc; else print block >> outu }
        block = ""
    }
    BEGIN {
        if (base != "") { while ((getline line < base) > 0) cnt[line]++ }
        while ((getline line < changed) > 0) chg[line] = 1
    }
    {
        k = parse($0)
        if (k != "") {
            flush()
            split(k, parts, "\t")
            if (base != "" && cnt[k] > 0) { cnt[k]--; isnew = 0 } else isnew = 1
            sect = (parts[1] == "" || (parts[1] in chg)) ? "C" : "U"
            block = $0
        } else if (block != "" && $0 ~ /^[ \t]/) {
            block = block "\n" $0
        } else {
            flush()
        }
    }
    END { flush() }'
}

# eslint `-f json` output (core ESLint 9 has no unix formatter) to one line per
# error: "line:col<TAB>message<TAB>rule". Warnings (severity 1) are dropped.
# Prints nothing when the file isn't eslint JSON.
atelier_eslint_errors() { # <json-file>
    jq -r '.[]?.messages[]? | select(.severity == 2) | "\(.line):\(.column)\t\(.message | gsub("\n"; " "))\t\(.ruleId // "")"' "$1" 2>/dev/null
}

# Two error lists (output of atelier_eslint_errors), old then current. Prints
# the current lines the old list doesn't cover, matched by message and rule, not
# by line or column; duplicates are counted.
atelier_eslint_new() { # <old-lines> <cur-lines>
    awk -F'\t' '
    NR == FNR { cnt[$2 "\t" $3]++; next }
    { k = $2 "\t" $3; if (cnt[k] > 0) cnt[k]--; else print }' "$1" "$2"
}

# Files changed this session, one per line, relative to <cwd>: tracked files that
# differ from the starting commit (when there is one), untracked files, and the
# file just edited. Writes nothing; git failing (not a repo) just leaves the target.
atelier_changed_files() { # <cwd> <start-commit|""> <target>
    local cwd=$1 start=$2 target=$3 real rel
    real=$(cd "$cwd" && pwd -P)
    rel=${target#"$cwd"/}
    rel=${rel#"$real"/}
    rel=${rel#./}
    if [ -n "$start" ]; then git -C "$cwd" diff --name-only --relative "$start" 2>/dev/null; fi
    git -C "$cwd" ls-files -o --exclude-standard 2>/dev/null
    printf '%s\n' "$rel"
}

# The edited file's path relative to <cwd> (same rule as above).
atelier_rel() { # <cwd> <target>
    local real rel
    real=$(cd "$1" && pwd -P)
    rel=${2#"$1"/}; rel=${rel#"$real"/}; rel=${rel#./}
    printf '%s\n' "$rel"
}
