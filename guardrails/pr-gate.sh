#!/bin/bash
# PreToolUse hook for Bash: the HARD definition-of-done gate.
#
# In a build session (<cwd>/.atelier/session.json exists), a Bash command that
# creates a pull request (`gh pr create`) is blocked (exit 2) until the same four
# artefacts dod-gate.sh checks exist: screenshots, assumptions, a passing test
# run, a reviewed critique. Both scripts source dod-check.sh so they can't drift.
# The missing items are listed on stderr.
#
# dod-gate.sh (Stop) is only a nudge, because a Stop hook has to yield. This one
# never yields. NO BYPASS: no override file, no environment variable, no flag.
# The ways out are: meet the gate, remove .atelier/session.json by hand, or run
# guardrails/install.sh --relax.
#
# Silent (exit 0, no output) when there is no .atelier/session.json, or when the
# command doesn't create a PR.
#
# Detecting "creates a PR": the command is split into shell words (python3
# shlex), then into segments at ; && || | & ( ) and unquoted newlines. In each
# segment leading env assignments (A=b), `cd`-chains (they are separate segments),
# and wrappers (env, sudo, time, command, exec, nohup, !, {) are skipped, then
# `gh [-R repo] pr create` must be the command. `bash -c "..."`, `sh -c` and
# `eval` strings are scanned the same way. A mention inside an echo, a quoted
# string or a commit message is not a command, so it passes.
# Known false positives: a heredoc body whose line starts with `gh pr create`.
# Known false negatives: backtick substitution, `xargs gh pr create`, aliases and
# shell functions, a script that calls gh internally, `gh api` or another client
# creating a PR, and a PR opened in the web UI. If the command can't be parsed
# but contains the words gh pr create, it is treated as a PR create.
#
# Fails closed in a build session: unreadable stdin, a missing python3 or a
# missing dod-check.sh exits 2. install.sh wraps this script so a missing script
# exits 2 too. Writes nothing.

input=$(cat)
valid=1
jq -e . >/dev/null 2>&1 <<<"$input" || valid=0

cwd=""
[ "$valid" -eq 1 ] && cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

a="$cwd/.atelier"
[ -f "$a/session.json" ] || exit 0

if [ "$valid" -ne 1 ]; then
    echo "Atelier PR gate: couldn't read the hook input in a build session, so this is blocked. Tell the user; only they can leave the build session or relax enforcement." >&2
    exit 2
fi

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$command" ] || exit 0
# Cheap prefilter: all three words must appear somewhere.
grep -qE 'gh' <<<"$command" && grep -qE 'pr' <<<"$command" && grep -qE 'create' <<<"$command" || exit 0

DETECT='
import re, shlex, sys

cmd = sys.stdin.read()
SKIP = {"env", "sudo", "time", "command", "exec", "nohup", "!", "{", "then", "do", "else", "builtin"}
OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
SHELLS = {"bash", "sh", "zsh"}


def newlines_to_semicolons(text):
    out, q, esc = [], None, False
    for ch in text:
        if esc:
            out.append(ch); esc = False; continue
        if ch == "\\" and q != "\x27":
            out.append(ch); esc = True; continue
        if q:
            if ch == q:
                q = None
            out.append(ch); continue
        if ch in "\"\x27":
            q = ch; out.append(ch); continue
        out.append(";" if ch == "\n" else ch)
    return "".join(out)


def tokens(text):
    lex = shlex.shlex(newlines_to_semicolons(text), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(toks):
    seg = []
    for t in toks:
        if t in OPS or set(t) <= set(";&|()"):
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def is_pr_create(seg, depth):
    i = 0
    while i < len(seg):
        t = seg[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t) or t in SKIP or (t.startswith("-") and i > 0 and seg[i - 1] in SKIP):
            i += 1
            continue
        break
    if i >= len(seg):
        return False
    prog = seg[i].rsplit("/", 1)[-1]
    rest = seg[i + 1:]
    if prog == "gh":
        j = 0
        while j < len(rest) and (rest[j] in ("-R", "--repo", "--hostname") or rest[j].startswith(("--repo=", "--hostname="))):
            j += 1 if "=" in rest[j] else 2
        return rest[j:j + 2] == ["pr", "create"]
    if depth < 3 and prog in SHELLS:
        for k, r in enumerate(rest):
            if r.startswith("-") and not r.startswith("--") and "c" in r[1:] and k + 1 < len(rest):
                return scan(rest[k + 1], depth + 1)
    if depth < 3 and prog == "eval":
        return scan(" ".join(rest), depth + 1)
    return False


def scan(text, depth=0):
    try:
        toks = tokens(text)
    except ValueError:
        return bool(re.search(r"\bgh\s+pr\s+create\b", text))
    return any(is_pr_create(s, depth) for s in segments(toks))


print("yes" if scan(cmd) else "no")
'
is_pr=$(python3 -I -c "$DETECT" <<<"$command" 2>/dev/null) || {
    echo "Atelier PR gate: couldn't check this command (is python3 installed?), so it is blocked in a build session." >&2
    exit 2
}
[ "$is_pr" = yes ] || exit 0

# shellcheck source=dod-check.sh
if ! . "$(dirname "$0")/dod-check.sh"; then
    echo "Atelier PR gate: dod-check.sh is missing, so PR creation is blocked. Restore it or re-run guardrails/install.sh." >&2
    exit 2
fi
dod_missing "$a"
[ -n "$DOD_MISSING" ] || exit 0

{
    echo "Atelier PR gate: this PR can't be created yet. Missing:"
    printf '%s\n' "$DOD_MISSING"
    echo "Finish these, then create the PR. If you cannot, tell the user; only the user can open a PR without them."
} >&2
exit 2
