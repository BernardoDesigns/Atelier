#!/bin/bash
# PreToolUse hook for Write / Edit / NotebookEdit: per-repo protected paths.
#
# Reads <repo>/.claude/lane-rules.json:
#
#     { "protected": ["payments/", "src/billing/**", "lib/shared/"] }
#
# Patterns are relative to the repo root. A trailing "/" protects everything
# under that directory; "*" and "**" match across path segments. Matching ignores
# case (case-insensitive file systems would otherwise be a way around it). A
# match blocks the write (exit 2) and names the path and the rule.
#
# These rules are additive to the static deny rules lane-guard-init.sh puts in
# the repo's .claude/settings.json; they never replace them.
#
# The hook is scoped by the rules file: no <repo>/.claude/lane-rules.json means
# exit 0 with no output, so it does nothing in repos that haven't opted in.
#
# Fails closed: unreadable stdin or a malformed rules file (when a rules file
# exists) exits 2. install.sh wraps this script so a missing script exits 2 too.
#
# Reads only the hook JSON and the rules file. Writes nothing.

deny() { echo "Lane guard: $1" >&2; exit 2; }

input=$(cat)
valid=1
jq -e . >/dev/null 2>&1 <<<"$input" || valid=0

cwd=""
[ "$valid" -eq 1 ] && cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root=$cwd
root=$(cd "$root" 2>/dev/null && pwd -P) || exit 0
rules="$root/.claude/lane-rules.json"
[ -f "$rules" ] || exit 0

[ "$valid" -eq 1 ] || deny "couldn't read the hook input, blocking this write."
if ! jq -e '(.protected | type) == "array" and all(.protected[]; type == "string")' "$rules" >/dev/null 2>&1; then
    deny "$rules is malformed (expected {\"protected\": [\"path/\", ...]}), blocking this write."
fi

target=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
[ -n "$target" ] || deny "couldn't read the target path, blocking this write."
[[ "$target" = /* ]] || target="$cwd/$target"

# Lexically collapse . and .. so "src/../payments/x" can't slip past.
norm=""
IFS='/' read -r -a parts <<<"$target"
stack=()
for p in "${parts[@]}"; do
    case "$p" in
        ""|.) ;;
        ..) [ "${#stack[@]}" -gt 0 ] && unset 'stack[${#stack[@]}-1]' ;;
        *) stack+=("$p") ;;
    esac
done
for p in "${stack[@]}"; do norm="$norm/$p"; done
[ -n "$norm" ] || norm=/

# Resolve symlinks through the nearest existing ancestor.
dir=$(dirname "$norm"); rest=$(basename "$norm")
while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do
    rest="$(basename "$dir")/$rest"; dir=$(dirname "$dir")
done
resolved="$(cd "$dir" 2>/dev/null && pwd -P)/$rest"
[ -e "$norm" ] && resolved=$(realpath "$norm" 2>/dev/null || echo "$resolved")

case "$resolved" in
    "$root"/*) rel=${resolved#"$root"/} ;;
    *) exit 0 ;; # outside the repo: not this hook's business
esac

shopt -s nocasematch
while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    pat=${rule#./}; pat=${pat#/}
    [ -n "$pat" ] || continue
    if [[ "$pat" == */ ]]; then
        pat="${pat}*"
    elif [[ "$pat" != *[\*\?\[]* ]]; then
        # A plain path: the file itself, or anything under it as a directory.
        if [[ "$rel" == "$pat" ]]; then
            deny "$rel is protected by rule '$rule' in .claude/lane-rules.json. Ask the user before touching it."
        fi
        pat="$pat/*"
    fi
    # shellcheck disable=SC2053
    if [[ "$rel" == $pat ]]; then
        deny "$rel is protected by rule '$rule' in .claude/lane-rules.json. Ask the user before touching it."
    fi
done < <(jq -r '.protected[]' "$rules")
exit 0
