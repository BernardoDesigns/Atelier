#!/bin/bash
# PostToolUse hook for Write / Edit.
#
# After an edit to a .ts, .tsx, .js or .jsx file in THE build session, runs the
# repo's type check and `eslint <file>` from the repo root using the host's local
# binaries (node_modules/.bin), and hands any errors the Builder caused back to
# the model: exit 2 with the first ~40 lines of each section on stderr.
#
# Does nothing (exit 0, no output, no tool invoked) unless
# <cwd>/.atelier/session.json exists AND its sessionId equals the hook input's
# session_id (session-lib.sh). A marker bound to another session, a marker with no
# sessionId, unreadable input and input with no session_id all do nothing. That
# check comes first, so this can't interfere with an unrelated session, even one in
# the same checkout while a build is open.
#
# The type check (typecheck-lib.sh) is the repo's real one:
#   - root tsconfig.json has a non-empty "references" array (solution style, the
#     stock Vite layout): `tsc -b --noEmit`. A plain `tsc --noEmit` there checks no
#     files and exits 0 while the real check fails. A tsc that predates
#     `-b --noEmit` (before 5.6) gets `tsc -p <each referenced config> --noEmit`.
#   - otherwise: `tsc --noEmit`.
# If the check covered zero files, exit 0 is not treated as clean: that is
# reported as an error. Build info the check leaves inside the source tree is
# removed again; the gate never writes source files.
#
# Only what the Builder caused is reported. session-open.sh took a baseline of the
# repo's type errors when the build opened (.atelier/baseline.tsc.txt, matched by
# file, error code and message, never by line number, duplicates counted). After
# each edit an error is new when the baseline doesn't cover it. New errors are
# reported in two sections: files changed in this session (against the commit the
# build started from, plus untracked files and the file just edited), and files
# you did not edit that broke because of your change. Both block. Without a
# baseline (marker from an older version, or the baseline step failed or timed out)
# every error in changed files is reported, with a one-line note.
#
# eslint runs on the edited file only, as before. Only errors count (warnings never
# block), and only those that are new against that file's content at the starting
# commit (the old content is linted through stdin under the same filename). A file
# that is new, or a marker with no starting commit, has no baseline: all its errors count.
#
# A tool that isn't installed is skipped and named in the feedback; it doesn't
# fail the gate. Each tool gets 60 seconds (ATELIER_GATE_TIMEOUT overrides, for
# tests); a timeout is reported as an error.
#
# Never runs --fix, never touches source files. Its only writes are scratch
# files inside .atelier/ (fast-gate.*), overwritten each run, and the removal of
# build info it created. It does not write .atelier/tests.json; the Builder does
# that after a test run.
#
# Fails open (PostToolUse): if this script, session-lib.sh or typecheck-lib.sh is
# missing, install.sh's wrapper (or the check below) warns and exits 1, which
# doesn't block.

TIMEOUT=${ATELIER_GATE_TIMEOUT:-60}
MAXLINES=40

input=$(cat)

# shellcheck source=session-lib.sh
if ! . "$(dirname "$0")/session-lib.sh"; then
    echo "Atelier fast gate: session-lib.sh is missing, so this check was skipped; restore it or re-run guardrails/install.sh" >&2
    exit 1
fi
# shellcheck source=typecheck-lib.sh
if ! . "$(dirname "$0")/typecheck-lib.sh"; then
    echo "Atelier fast gate: typecheck-lib.sh is missing, so this check was skipped; restore it or re-run guardrails/install.sh" >&2
    exit 1
fi

jq -e . >/dev/null 2>&1 <<<"$input" || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

atelier_is_build_session "$cwd/.atelier/session.json" "$input" || exit 0

target=$(jq -r '.tool_input.file_path // empty' <<<"$input")
case "${target##*.}" in
    ts|tsx|js|jsx) ;;
    *) exit 0 ;;
esac
case "$target" in
    *.*) ;;
    *) exit 0 ;;
esac

cd "$cwd" || exit 0
tmp="$cwd/.atelier"
marker="$tmp/session.json"
errors=""
notes=""

capped() { # <file>: the file's lines, at most MAXLINES, with a count of the rest
    local n
    n=$(wc -l <"$1" | tr -d ' ')
    head -n "$MAXLINES" "$1"
    [ "$n" -le "$MAXLINES" ] || echo "[$((n - MAXLINES)) more lines not shown]"
}

start=$(jq -r 'if (.startCommit | type) == "string" then .startCommit else empty end' "$marker" 2>/dev/null)
base=""
if jq -e '.baseline.file | type == "string"' "$marker" >/dev/null 2>&1 && [ -f "$tmp/baseline.tsc.txt" ]; then
    base="$tmp/baseline.tsc.txt"
fi

bin="$cwd/node_modules/.bin"
if [ -x "$bin/tsc" ]; then
    atelier_tsc_check "$cwd" "$tmp/fast-gate.tsc.out"
    if [ "$TC_CODE" -eq 0 ]; then
        if [ "$TC_FILES" = 0 ]; then
            errors="$errors
type check covered no files ($TC_CMD):
Exit 0 here proves nothing, because there was nothing to check. The tsconfig matches no source files. A solution-style root (\"files\": [] plus \"references\") checks nothing on its own, and an \"include\" that matches nothing does the same. Point \"include\" or \"files\" at the sources, or list the configs that do in \"references\"."
        fi
    else
        nkeys=$(atelier_tsc_keys <"$tmp/fast-gate.tsc.out" | wc -l | tr -d ' ')
        if [ "$TC_CODE" -eq 124 ] || [ "$nkeys" -eq 0 ]; then
            # Timed out, crashed, or output we can't read: show it as is.
            errors="$errors
$TC_CMD:
$(capped "$tmp/fast-gate.tsc.out")"
        else
            atelier_changed_files "$cwd" "$start" "$target" | sort -u >"$tmp/fast-gate.changed"
            atelier_tsc_split "$base" "$tmp/fast-gate.changed" "$tmp/fast-gate.new-changed" "$tmp/fast-gate.new-other" <"$tmp/fast-gate.tsc.out"
            if [ -s "$tmp/fast-gate.new-changed" ]; then
                errors="$errors
$TC_CMD, new errors in files you changed:
$(capped "$tmp/fast-gate.new-changed")"
            fi
            if [ -n "$base" ] && [ -s "$tmp/fast-gate.new-other" ]; then
                errors="$errors
$TC_CMD, new errors in files you did not edit, caused by your change:
$(capped "$tmp/fast-gate.new-other")"
            fi
            if [ -z "$base" ] && [ -s "$tmp/fast-gate.new-changed" ]; then
                notes="$notes
There was no baseline of type errors for this build, so every error in the files you changed is listed, including ones that may have been there before."
            fi
        fi
    fi
    [ -z "$TC_NOTE" ] || notes="$notes
$TC_NOTE"
else
    notes="$notes
tsc is not installed in node_modules/.bin, so it was skipped."
fi

if [ ! -x "$bin/eslint" ]; then
    notes="$notes
eslint is not installed in node_modules/.bin, so it was skipped."
elif [ -f "$target" ] || [ -f "$cwd/$target" ]; then
    rel=$(atelier_rel "$cwd" "$target")
    have_old=0
    if [ -n "$start" ] && git show "$start:./$rel" >"$tmp/fast-gate.eslint.old.src" 2>/dev/null; then have_old=1; fi
    if [ "$have_old" -eq 1 ]; then
        # Compare against the file as it was when the build opened.
        atelier_run_limited "$tmp/fast-gate.eslint.out" "$bin/eslint" -f json "$target"
        ecode=$?
        if [ "$ecode" -ne 0 ]; then
            if [ "$ecode" -eq 124 ] || ! jq -e . "$tmp/fast-gate.eslint.out" >/dev/null 2>&1; then
                # Timed out, or eslint failed without a report (bad config): show it as is.
                errors="$errors
eslint $rel:
$(capped "$tmp/fast-gate.eslint.out")"
            else
                atelier_eslint_errors "$tmp/fast-gate.eslint.out" >"$tmp/fast-gate.eslint.cur"
                ATELIER_STDIN="$tmp/fast-gate.eslint.old.src" atelier_run_limited "$tmp/fast-gate.eslint.old.out" \
                    "$bin/eslint" -f json --stdin --stdin-filename "$target"
                ocode=$?
                ATELIER_STDIN=""
                if [ "$ocode" -eq 124 ] || ! jq -e . "$tmp/fast-gate.eslint.old.out" >/dev/null 2>&1; then
                    # The old version couldn't be linted, so there is no baseline for this file.
                    : >"$tmp/fast-gate.eslint.oldlines"
                    notes="$notes
The old version of $rel couldn't be linted for a baseline, so every eslint error in it is listed."
                else
                    atelier_eslint_errors "$tmp/fast-gate.eslint.old.out" >"$tmp/fast-gate.eslint.oldlines"
                fi
                atelier_eslint_new "$tmp/fast-gate.eslint.oldlines" "$tmp/fast-gate.eslint.cur" >"$tmp/fast-gate.eslint.new"
                if [ -s "$tmp/fast-gate.eslint.new" ]; then
                    errors="$errors
eslint $rel, new errors (line:col, message, rule):
$(capped "$tmp/fast-gate.eslint.new")"
                fi
            fi
        fi
    else
        atelier_run_limited "$tmp/fast-gate.eslint.out" "$bin/eslint" "$target"
        [ $? -eq 0 ] || {
            errors="$errors
eslint $target:
$(capped "$tmp/fast-gate.eslint.out")"
            [ -n "$start" ] || notes="$notes
This build has no starting commit recorded, so every eslint error in the file is listed."
        }
    fi
fi

[ -n "$errors" ] || exit 0

{
    echo "Atelier fast gate: fix these before moving on."
    printf '%s\n' "$errors"
    [ -z "$notes" ] || printf '%s\n' "$notes"
} >&2
exit 2
