# Sourced by pr-gate.sh (the PreToolUse hook on Bash). Not run directly.
#
#   session_claim_record <hook-input-json> <guardrails-dir>
#
# Learns WHICH session is calling guardrails/session-open.sh or
# guardrails/session-close.sh, because a script can't see its caller's session
# id and a hook can. When the Bash command is exactly one of those two scripts,
# it writes <target>/.atelier/session-claim holding the hook input's session_id
# and the current epoch seconds. The script reads that file, uses it as "who am
# I", and deletes it. The claim is only an identity note; the ownership rules
# (claim an unowned marker or your own, never overwrite another session's) are
# enforced by the scripts, not here.
#
# "Exactly" means: after trimming, the command is one simple command whose first
# word is the real path of the script next to this file (~ allowed), with only
# the arguments that script takes. Any of  ; & | < > ` $ ( ) \ # or a newline
# anywhere in the command, a different program, a longer command line, or a
# string, comment or echo that merely mentions the script name: no claim.
#
# Always returns 0 and never blocks. Any failure just means no claim is written.

session_claim_record() {
    local input=$1 gdir=$2 command sid cwd target tmp
    command=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || return 0
    sid=$(jq -r 'if (.session_id | type) == "string" then .session_id else empty end' <<<"$input" 2>/dev/null) || return 0
    cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || return 0
    [ -n "$command" ] && [ -n "$sid" ] || return 0
    case "$command" in *session-open.sh*|*session-close.sh*) ;; *) return 0 ;; esac
    [ -n "$cwd" ] || cwd=$PWD

    # Prints the target directory (resolved) when the command is exactly a call.
    target=$(python3 -I -c '
import os, re, shlex, sys
cmd, gdir, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
if re.search(r"[;&|<>`$()\\#\n\r]", cmd):
    sys.exit(1)
try:
    toks = shlex.split(cmd)
except ValueError:
    sys.exit(1)
if not toks:
    sys.exit(1)
prog = os.path.realpath(os.path.expanduser(toks[0]))
args = toks[1:]
if prog == os.path.realpath(os.path.join(gdir, "session-open.sh")):
    if len(args) not in (2, 3) or any(a.startswith("-") for a in args):
        sys.exit(1)
    d = args[2] if len(args) == 3 else "."
elif prog == os.path.realpath(os.path.join(gdir, "session-close.sh")):
    if args[:1] == ["--check"]:
        args = args[1:]
    if len(args) > 1 or any(a.startswith("-") for a in args):
        sys.exit(1)
    d = args[0] if args else "."
else:
    sys.exit(1)
print(os.path.realpath(os.path.join(cwd, os.path.expanduser(d))))
' "$command" "$gdir" "$cwd" 2>/dev/null) || return 0
    [ -d "$target" ] || return 0

    mkdir -p "$target/.atelier" 2>/dev/null || return 0
    tmp="$target/.atelier/session-claim.$$"
    printf '%s\n%s\n' "$sid" "$(date +%s)" >"$tmp" 2>/dev/null \
        && mv -f "$tmp" "$target/.atelier/session-claim" 2>/dev/null
    return 0
}
