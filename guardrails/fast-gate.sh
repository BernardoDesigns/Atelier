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
#     stock Vite layout): `tsc -b --force --noEmit`. A plain `tsc --noEmit` there
#     checks no files and exits 0 while the real check fails. --force because tsc -b
#     trusts build info timestamps, which can be stale (build info shared between
#     worktrees, a broken file imported from outside "include"). A tsc that
#     predates `-b --noEmit` (before 5.6) gets `tsc -p <each referenced config>
#     --noEmit`.
#   - otherwise: `tsc --noEmit`.
# Two guards against a false clean. Some tsc errors mean the check did not check
# (TS6310 and TS6306 on composite chains, TS6305, TS18002 and TS18003 for configs
# with no inputs, TS5083 for an unreadable config; see ATELIER_TSC_NORUN in
# typecheck-lib.sh). They are never baselined and always block, with an
# explanation. And a plain `tsc --noEmit` that exits 0 while the root config
# lists no files is an error too.
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
# Never runs --fix, never touches source files. Its writes: per-run scratch files
# named .atelier/.fast-gate.<pid>.* (removed when it exits), a copy of the last tsc
# output at .atelier/fast-gate.tsc.out, and the removal of build info it created
# inside the source tree. tsc keeps its own build info where the tsconfig says,
# usually node_modules/.tmp; in a diverge worktree whose node_modules is linked to
# the main checkout, that is the linked checkout's directory. It does not write
# .atelier/tests.json; the Builder does that after a test run.
#
# Known limits: the pre-5.6 fallback checks only the referenced configs, and a file
# outside every tsconfig is not type checked at all.
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
# Scratch files get a per-run name, so two overlapping runs in one tree can't read
# each other's half-written output. All of them are removed on the way out.
run="$tmp/.fast-gate.$$"
trap 'rm -f "$run".*' EXIT
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
    atelier_tsc_check "$cwd" "$run.tsc.out"
    atelier_tsc_norun <"$run.tsc.out" >"$run.norun"
    if [ -s "$run.norun" ]; then
        errors="$errors
the type check did not run for this layout, so nothing was verified ($TC_CMD):
$(capped "$run.norun")
These errors are never baselined. Until they are fixed, a clean result from this check means nothing. Make the tsconfig layout checkable with --noEmit (for example, referenced projects that are composite and build with --noEmit, and configs that match some files)."
    fi
    if [ "$TC_CODE" -eq 0 ]; then
        if [ "$TC_ZERO" -eq 1 ]; then
            errors="$errors
type check covered no files ($TC_CMD):
Exit 0 here proves nothing, because there was nothing to check. The root tsconfig lists no files. Point \"include\" or \"files\" at the sources, or list the configs that do in \"references\"."
        fi
    else
        nkeys=$(atelier_tsc_keys <"$run.tsc.out" | wc -l | tr -d ' ')
        if [ "$TC_CODE" -eq 124 ] || { [ "$nkeys" -eq 0 ] && [ ! -s "$run.norun" ]; }; then
            # Timed out, crashed, or output we can't read: show it as is.
            errors="$errors
$TC_CMD:
$(capped "$run.tsc.out")"
        elif [ "$nkeys" -gt 0 ]; then
            atelier_changed_files "$cwd" "$start" "$target" | sort -u >"$run.changed"
            atelier_tsc_split "$base" "$run.changed" "$run.new-changed" "$run.new-other" <"$run.tsc.out"
            if [ -s "$run.new-changed" ]; then
                errors="$errors
$TC_CMD, new errors in files you changed:
$(capped "$run.new-changed")"
            fi
            if [ -n "$base" ] && [ -s "$run.new-other" ]; then
                errors="$errors
$TC_CMD, new errors in files you did not edit, caused by your change:
$(capped "$run.new-other")"
            fi
            if [ -z "$base" ] && [ -s "$run.new-changed" ]; then
                notes="$notes
There was no baseline of type errors for this build, so every error in the files you changed is listed, including ones that may have been there before."
            fi
        fi
    fi
    # Keep the last tsc output where a human can read it (written by a final mv).
    cp "$run.tsc.out" "$run.last" 2>/dev/null && mv -f "$run.last" "$tmp/fast-gate.tsc.out"
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
    if [ -n "$start" ] && git show "$start:./$rel" >"$run.eslint.old.src" 2>/dev/null; then have_old=1; fi
    if [ "$have_old" -eq 1 ]; then
        # Compare against the file as it was when the build opened.
        atelier_run_limited "$run.eslint.out" "$bin/eslint" -f json "$target"
        ecode=$?
        if [ "$ecode" -ne 0 ]; then
            if [ "$ecode" -eq 124 ] || ! jq -e . "$run.eslint.out" >/dev/null 2>&1; then
                # Timed out, or eslint failed without a report (bad config): show it as is.
                errors="$errors
eslint $rel:
$(capped "$run.eslint.out")"
            else
                atelier_eslint_errors "$run.eslint.out" >"$run.eslint.cur"
                ATELIER_STDIN="$run.eslint.old.src" atelier_run_limited "$run.eslint.old.out" \
                    "$bin/eslint" -f json --stdin --stdin-filename "$target"
                ocode=$?
                ATELIER_STDIN=""
                if [ "$ocode" -eq 124 ] || ! jq -e . "$run.eslint.old.out" >/dev/null 2>&1; then
                    # The old version couldn't be linted, so there is no baseline for this file.
                    : >"$run.eslint.oldlines"
                    notes="$notes
The old version of $rel couldn't be linted for a baseline, so every eslint error in it is listed."
                else
                    atelier_eslint_errors "$run.eslint.old.out" >"$run.eslint.oldlines"
                fi
                atelier_eslint_new "$run.eslint.oldlines" "$run.eslint.cur" >"$run.eslint.new"
                if [ -s "$run.eslint.new" ]; then
                    errors="$errors
eslint $rel, new errors (line:col, message, rule):
$(capped "$run.eslint.new")"
                fi
            fi
        fi
    else
        atelier_run_limited "$run.eslint.out" "$bin/eslint" "$target"
        [ $? -eq 0 ] || {
            errors="$errors
eslint $target:
$(capped "$run.eslint.out")"
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
