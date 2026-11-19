#!/bin/bash
# PreToolUse hook for Bash: the HARD definition-of-done gate.
#
# In THE build session (<cwd>/.atelier/session.json exists and its sessionId equals
# the hook input's session_id; see session-lib.sh), a Bash command that
# creates a pull request (`gh pr create`) is blocked (exit 2) until the same four
# requirements dod-gate.sh checks are met: screenshots, assumptions, a passing test
# run, a reviewed critique, and lane (no protected path changed, by any means; read
# from git). Both scripts source dod-check.sh so they can't drift.
# The missing items are listed on stderr.
#
# dod-gate.sh (Stop) is only a nudge, because a Stop hook has to yield. This one
# never yields. NO BYPASS: no override file, no environment variable, no flag.
# The ways out are: meet the gate, remove .atelier/session.json by hand, or run
# guardrails/install.sh --relax.
#
# Silent (exit 0, no output) when there is no .atelier/session.json, when the
# marker is bound to another session or has no sessionId, when the hook input is
# unreadable or has no session_id, or when the command doesn't create a PR. A
# session that isn't the build session never meets this gate, even in the same
# checkout while a build is open.
#
# Separate job, same hook (it is already the PreToolUse hook on Bash): before any of
# that, session-claim.sh notes which session is running guardrails/session-open.sh
# or session-close.sh so those scripts can bind or close the marker. It never blocks
# and doesn't touch the gate logic below.
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
# Third job, same hook, build session only: the Bash WRITE NUDGE
# (atelier_bash_write_nudge below). The Builder must create and change files with
# the Write and Edit tools, because the conventions injector, the fast gate and the
# lane guard only see those. A Bash command that obviously writes a file into the
# repo is blocked (exit 2) with a message saying so. It is a nudge, not a wall: the
# real backstop for protected paths is the "lane" requirement in dod-check.sh, so
# a missed write is acceptable and a wrongly blocked command is not. Anything the
# detector can't be sure about passes. The command is tokenised like the PR check
# (heredoc bodies and # comments dropped first, quoted text is never an operator),
# split into segments at ; && || | & ( ), and each segment is judged on its own.
#
# BLOCKED, when the target is a literal path inside the repo:
#   - an output redirect: `> f`, `>> f`, `&> f`, `>| f`, with or without an fd
#     (`1> f`). That covers `cat > f <<EOF`, `cat >> f`, `echo x > f`, `jq . > f`.
#   - `tee [-a] f ...` (each file argument)
#   - `sed -i ...` / `sed --in-place ...` / `sed -ni ...` (flag cluster with i),
#     judged by the last non-option word
#   - `perl -i ...` / `perl -pi ...` / `perl -i.bak ...`, same rule
#   - an interpreter on an INLINE script that calls a file write. Inline means
#     python/python3 with `-c` or `-` or a heredoc on stdin, node with `-e`,
#     `--eval`, `-p` or a heredoc, ruby or perl with `-e` or a heredoc, and no
#     script file argument. The heredoc body or the -c/-e string is the one text
#     that is read (everywhere else heredoc bodies are ignored). Write calls:
#       python  open( / io.open( / codecs.open( whose mode (2nd argument or
#               mode=) is a string literal with w, a or x; .write_text( ;
#               .write_bytes(
#       node    writeFileSync( writeFile( appendFileSync( appendFile(
#               createWriteStream(
#       ruby    File.write( File.binwrite( IO.write( ; File.open( with a literal
#               mode containing w or a
#       perl    open( with > in a literal mode (2 or 3 argument form)
#     An inline write is let through only when the call's first argument is a
#     single plain string literal that is under .atelier/, /tmp, $TMPDIR or
#     outside the repo (`open(".atelier/x.json","w")`). Variables, concatenation,
#     f-strings, template literals, Path(...).write_text and every perl write are
#     blocked, because the target can't be read statically.
# NEVER BLOCKED:
#   - segments whose program is git, gh, npm, npx, pnpm, yarn, bun or node (so
#     scripts, the render harness `node .../render/cli.mjs`, and `git diff > x`
#     are left alone), or a path under /atelier/render/. node, python, ruby and
#     perl running a script FILE are never blocked; neither are inline scripts
#     with no write call (reads: open(p), open(p,'r'); prints: python3 -I -c)
#   - guardrails/run-tests.sh and whatever command it is given (plain command)
#   - `2>&1`, `>&2`, `>&-` (fd duplication) and anything into /dev/ (/dev/null)
#   - targets under .atelier/ (relative, or absolute with /.atelier/ in it)
#   - targets under /tmp, /private/tmp, /var/folders, $TMPDIR's value, or any
#     target with a $ variable or `...` / $(...) in it (`$(mktemp)`, `$TMPDIR/x`,
#     `"$out"`: unknowable, so allowed), or with a glob, or starting with ~
#   - targets outside the repo (absolute and not under the cwd, or `../x`)
#   - relative targets after a `cd` / `pushd` earlier in the command
#   - input redirects and heredocs themselves (`<`, `<<`, `<<<`); pipes into
#     tail, head, grep and the like (no file is named)
#   - a quoted ">" or "tee" (quotes make it an argument, not an operator)
#   - a command that can't be parsed (unbalanced quotes) or a missing python3
# `bash -c "..."`, `sh -c` and `eval` strings are judged the same way, 2 levels deep.
# Known false negatives: scripts run from a FILE that write files, inline scripts
# that write by other means (shutil, os.system, fs.promises.cp), piped scripts
# (`cat x | python3 -`), `cp`, `mv`, `dd of=`, `install`, `git apply`, `patch`,
# backticks, aliases.
#
# Fails closed in the build session: a missing python3 or a missing dod-check.sh
# exits 2. A missing session-lib.sh or session-claim.sh exits 2 too (PreToolUse).
# install.sh wraps this script so a missing script exits 2 as well. Writes nothing
# except the session claim note (see above).

input=$(cat)

# shellcheck source=session-lib.sh
# shellcheck source=session-claim.sh
if ! . "$(dirname "$0")/session-lib.sh" || ! . "$(dirname "$0")/session-claim.sh"; then
    echo "Atelier PR gate: session-lib.sh or session-claim.sh is missing, so Bash is blocked. Restore them or re-run guardrails/install.sh." >&2
    exit 2
fi

# Unreadable input: nothing can be bound to it, so this isn't the build session.
jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd=$PWD

# Separate job: record who is calling session-open.sh / session-close.sh.
session_claim_record "$input" "$(cd "$(dirname "$0")" && pwd -P)"

a="$cwd/.atelier"
atelier_is_build_session "$a/session.json" "$input" || exit 0

WRITE_DETECT='
import os, posixpath, re, shlex, sys

cmd = sys.stdin.read()
cwd = os.path.normpath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
EXEMPT = {"git", "gh", "npm", "npx", "pnpm", "yarn", "bun", "node"}
SKIP = {"env", "sudo", "time", "command", "exec", "nohup", "!", "{", "then", "do", "else", "builtin"}
SHELLS = {"bash", "sh", "zsh"}
TEMPS = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")
TMPDIR = os.environ.get("TMPDIR", "").rstrip("/")
state = {"cd": False}


BODIES = {}


def strip_heredocs(text):
    # Heredoc bodies are removed from the command. Each operator becomes
    # "<< __HDn__" and the body is kept in BODIES, read only for inline scripts.
    out, pending = [], []
    for line in text.split("\n"):
        if pending:
            if line.strip() == pending[0][0]:
                pending.pop(0)
            else:
                BODIES[pending[0][1]] = BODIES.get(pending[0][1], "") + line + "\n"
            continue

        def sub(m):
            key = "__HD%d__" % len(BODIES)
            BODIES[key] = ""
            pending.append((m.group(2), key))
            return "<< " + key

        out.append(re.sub(r"<<(?!<)-?\s*([\x27\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", sub, line))
    return "\n".join(out)


def dequote(t):
    try:
        return " ".join(shlex.split(t, posix=True))
    except ValueError:
        return unq(t)


def split_args(text, start):
    # Top-level arguments of the call whose "(" is just before text[start].
    args, cur, depth, q = [], "", 0, None
    i = start
    while i < len(text):
        ch = text[i]
        if q:
            cur += ch
            if ch == "\\" and i + 1 < len(text):
                cur += text[i + 1]; i += 1
            elif ch == q:
                q = None
        elif ch in "\"\x27`":
            q = ch; cur += ch
        elif ch in "([{":
            depth += 1; cur += ch
        elif ch in ")]}":
            if depth == 0:
                args.append(cur.strip()); return args
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            args.append(cur.strip()); cur = ""
        else:
            cur += ch
        i += 1
    args.append(cur.strip())
    return args


def literal(a):
    m = re.fullmatch(r"([\x27\"])([^\x27\"\\]*)\1", a.strip())
    return m.group(2) if m else None


def write_calls(kind, text):
    # [(first-argument text or None)] for each file-write call; None = no way to tell.
    calls = []
    if kind == "python":
        for m in re.finditer(r"(?<![\w.])(?:io\.|codecs\.)?open\s*\(", text):
            args = split_args(text, m.end())
            mode = None
            for a in args:
                km = re.fullmatch(r"mode\s*=\s*(.*)", a, re.S)
                if km:
                    mode = literal(km.group(1))
            if mode is None and len(args) > 1 and not re.match(r"\w+\s*=", args[1]):
                mode = literal(args[1])
            if mode is not None and re.fullmatch(r"[rwxabt+U]+", mode) and set(mode) & set("wax"):
                first = re.sub(r"^file\s*=\s*", "", args[0]) if args else ""
                calls.append(first)
        if re.search(r"\.\s*write_(text|bytes)\s*\(", text):
            calls.append(None)
    elif kind == "node":
        for m in re.finditer(r"\b(?:writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream)\s*\(", text):
            args = split_args(text, m.end())
            calls.append(args[0] if args else "")
    elif kind == "ruby":
        for m in re.finditer(r"\b(?:File\.write|File\.binwrite|IO\.write|IO\.binwrite)\s*\(", text):
            args = split_args(text, m.end())
            calls.append(args[0] if args else "")
        for m in re.finditer(r"\bFile\.open\s*\(", text):
            args = split_args(text, m.end())
            mode = literal(args[1]) if len(args) > 1 else None
            if mode is not None and re.fullmatch(r"[rwab+tx]+", mode) and set(mode) & set("wax"):
                calls.append(args[0])
    elif kind == "perl":
        if re.search(r"\bopen\s*\(?\s*(?:my\s+)?[$\w]+\s*,\s*[\x27\"]\s*\+?>", text):
            calls.append(None)
    return calls


def inline_write(kind, args, redirs):
    # An interpreter run on an INLINE script (-c/-e string, or a heredoc on stdin).
    flag = {"python": r"-[A-Za-z]*c", "node": r"-[A-Za-z]*e|-p|--eval|--print", "ruby": r"-[A-Za-z]*e", "perl": r"-[A-Za-z]*[eE]"}[kind]
    texts = []
    for k, a in enumerate(args):
        if re.fullmatch(flag, a) and k + 1 < len(args):
            texts.append(dequote(args[k + 1]))
        elif kind == "node" and a.startswith("--eval="):
            texts.append(dequote(a[len("--eval="):]))
    if not texts and [a for a in args if not a.startswith("-")]:
        return None  # runs a script file: not inline
    if not texts:
        for op, tgt in redirs:
            if op == "<<" and tgt in BODIES:
                texts.append(BODIES[tgt])
    for text in texts:
        for first in write_calls(kind, text):
            lit = literal(first) if first is not None else None
            if lit is not None and not into_repo(lit):
                continue
            return kind + " inline script writes a file"
    return None


def prep(text):
    # Newlines become ";" and # comments are dropped, both only outside quotes.
    out, q, esc, prev = [], None, False, "\n"
    skipping = False
    for ch in text:
        if skipping:
            if ch == "\n":
                skipping = False
                out.append(";")
                prev = ch
            continue
        if esc:
            out.append(ch); esc = False; prev = ch; continue
        if ch == "\\" and q != "\x27":
            out.append(ch); esc = True; prev = ch; continue
        if q:
            if ch == q:
                q = None
            out.append(ch); prev = ch; continue
        if ch in "\"\x27":
            q = ch; out.append(ch); prev = ch; continue
        if ch == "#" and (prev.isspace() or prev == ";"):
            skipping = True; continue
        out.append(";" if ch == "\n" else ch)
        prev = ch
    return "".join(out)


def tokens(text):
    lex = shlex.shlex(prep(strip_heredocs(text)), posix=False, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def unq(t):
    return t.replace("\"", "").replace("\x27", "")


def is_break(t):
    return re.fullmatch(r"[;&|()]+", t) is not None


def is_redirect(t):
    return re.fullmatch(r"[<>&|]+", t) is not None and ("<" in t or ">" in t)


def into_repo(raw):
    t = unq(raw)
    if not t or "$" in t or "`" in t or re.search(r"[*?\[]", t) or t.startswith("~") or t.startswith("/dev/"):
        return False
    if t.startswith("/"):
        p = posixpath.normpath(t)
        if "/.atelier/" in p + "/" or p.startswith(TEMPS) or (TMPDIR and (p + "/").startswith(TMPDIR + "/")):
            return False
        return p == cwd or p.startswith(cwd.rstrip("/") + "/")
    if state["cd"]:
        return False
    p = posixpath.normpath(t)
    if p == ".." or p.startswith("../") or p == ".atelier" or p.startswith(".atelier/"):
        return False
    return True


def judge(seg, depth):
    words, redirs, i = [], [], 0
    while i < len(seg):
        t = seg[i]
        if is_redirect(t):
            tgt = seg[i + 1] if i + 1 < len(seg) and not is_redirect(seg[i + 1]) else None
            redirs.append((t, tgt))
            i += 2 if tgt is not None else 1
            continue
        words.append(t)
        i += 1
    j = 0
    while j < len(words):
        w = words[j]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w) or w in SKIP or (w.startswith("-") and j > 0 and words[j - 1] in SKIP):
            j += 1
            continue
        break
    if j >= len(words):
        prog, args = "", []
    else:
        prog, args = unq(words[j]).rsplit("/", 1)[-1], words[j + 1:]
        if "/atelier/render/" in unq(words[j]):
            return None
    if prog in ("cd", "pushd"):
        state["cd"] = True
        return None
    kind = "python" if re.fullmatch(r"python[0-9.]*", prog) else prog if prog in ("node", "ruby", "perl") else None
    if kind:
        r = inline_write(kind, args, redirs)
        if r:
            return r
    if prog in EXEMPT:
        return None
    if depth < 2 and prog in SHELLS:
        for k, a in enumerate(args):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:] and k + 1 < len(args):
                return scan(unq(args[k + 1]), depth + 1)
    if depth < 2 and prog == "eval":
        return scan(" ".join(unq(a) for a in args), depth + 1)
    for op, tgt in redirs:
        if ">" not in op or tgt is None:
            continue
        if op == ">&" and re.fullmatch(r"\d+|-", unq(tgt)):
            continue
        if into_repo(tgt):
            return "a redirect (" + op + ") into " + unq(tgt)
    opts = [a for a in args if a.startswith("-")]
    files = [a for a in args if not a.startswith("-")]
    if prog == "tee":
        for f in files:
            if into_repo(f):
                return "tee into " + unq(f)
    if prog in ("sed", "perl") and files:
        inplace = any(a.startswith("--in-place") or re.fullmatch(r"-[A-Za-z]*i\S*", a) for a in opts)
        if inplace and into_repo(files[-1]):
            return prog + " -i on " + unq(files[-1])
    return None


def scan(text, depth=0):
    try:
        toks = tokens(text)
    except ValueError:
        return None
    seg = []
    for t in toks + [";"]:
        if is_break(t):
            if seg:
                r = judge(seg, depth)
                if r:
                    return r
            seg = []
        else:
            seg.append(t)
    return None


r = scan(cmd)
print(r if r else "")
'

# Build-session nudge (see the header): sets WRITE_HIT to a short description of the
# file write, or leaves it empty. Any trouble running the detector counts as no hit.
atelier_bash_write_nudge() { # <command> <cwd>
    WRITE_HIT=$(python3 -I -c "$WRITE_DETECT" "$2" <<<"$1" 2>/dev/null) || WRITE_HIT=""
}

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$command" ] || exit 0

atelier_bash_write_nudge "$command" "$cwd"
if [ -n "$WRITE_HIT" ]; then
    echo "Atelier write guard: this command writes a file into the repo ($WRITE_HIT). Write files with the Write or Edit tool so the conventions and the fast gate apply; redirects under .atelier/ and temp dirs are allowed. If this is a tool's own output (a formatter, an npm script, the render harness), run that tool rather than redirecting into the file." >&2
    exit 2
fi
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
