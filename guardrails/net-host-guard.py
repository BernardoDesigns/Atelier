#!/usr/bin/env -S python3 -I
"""PreToolUse hook for Bash: ask before curl/wget reaches anything off-machine.

The allow rules in permissions-allow.json are globs, and a glob can't tell where
a URL's host is: `curl "https://evil.example/?next=http://localhost:1/"` matches
`curl *http://localhost:*/*`. This hook parses the command instead and asks
unless every URL's real host is one of:

    localhost, 127.0.0.1, [::1], *.trycloudflare.com  (cc's quick tunnels)

It stays silent for anything it can verify as local, so the normal permission
flow (the allow rules) decides. It never approves anything on its own.

It also asks when it can't verify: variables or command substitution in the
command, a curl/wget argument without a scheme, flags that reroute or read
URLs from elsewhere (--proxy, --resolve, --connect-to, -K, wget -e / -i), or a
command it can't parse. Asking costs one click; a wrong silence could leak data.

Reads only the hook JSON on stdin. No network, no files, no keys.
"""

import json
import os
import re
import shlex
import sys

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}
TUNNEL = re.compile(r"^[a-z0-9-]+\.trycloudflare\.com$")
URL = re.compile(r"([A-Za-z][A-Za-z0-9+.\-]*)://([^/?#\s\"']*)")
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;", "\n"}
WRAPPERS = {"sudo", "env", "command", "exec", "time", "nohup", "nice", "xargs", "builtin"}

# Flags that send traffic somewhere other than the URL, or read URLs/flags from
# elsewhere. Matched on the long name, or a short letter inside a cluster.
CURL_RISKY_LONG = ("--proxy", "--preproxy", "--socks4", "--socks4a", "--socks5", "--socks5-hostname",
                   "--resolve", "--connect-to", "--doh-url", "--config", "--variable", "--expand-",
                   "--proxy-header", "--haproxy", "--dns-servers")
CURL_RISKY_SHORT = set("xK")
WGET_RISKY_LONG = ("--execute", "--input-file", "--config", "--proxy", "--base", "--use-askpass")
WGET_RISKY_SHORT = set("eiB")

# Flags whose next token is a value, not a URL.
CURL_VALUE_SHORT = set("owHdXuAebcFTmrYyzCEQtUPD")
CURL_VALUE_LONG = {
    "--output", "--write-out", "--header", "--data", "--data-raw", "--data-binary", "--data-ascii",
    "--data-urlencode", "--json", "--request", "--user", "--user-agent", "--referer", "--cookie",
    "--cookie-jar", "--form", "--form-string", "--upload-file", "--max-time", "--connect-timeout",
    "--retry", "--retry-delay", "--retry-max-time", "--range", "--dump-header", "--cacert", "--capath",
    "--cert", "--cert-type", "--key", "--key-type", "--limit-rate", "--max-filesize", "--interface",
    "--local-port", "--output-dir", "--stderr", "--trace", "--trace-ascii", "--oauth2-bearer",
    "--url-query", "--unix-socket", "--abstract-unix-socket", "--speed-limit", "--speed-time",
    "--max-redirs", "--keepalive-time", "--continue-at", "--time-cond", "--create-file-mode",
}
WGET_VALUE_SHORT = set("OoaPtTUwlQA")
WGET_VALUE_LONG = {
    "--output-document", "--output-file", "--append-output", "--directory-prefix", "--tries",
    "--timeout", "--user-agent", "--header", "--post-data", "--post-file", "--body-data",
    "--body-file", "--method", "--user", "--password", "--http-user", "--http-password", "--referer",
    "--load-cookies", "--save-cookies", "--wait", "--limit-rate", "--level", "--quota", "--accept",
    "--reject", "--dns-timeout", "--connect-timeout", "--read-timeout",
}
# Flags that take a URL as their value: the value is checked like a positional URL.
URL_VALUE_LONG = {"--url"}


def ask(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": "Network guardrail: " + reason,
    }}))
    sys.exit(0)


def host_ok(host):
    h = host.lower()
    if h.startswith("[") and h.endswith("]"):
        return h[1:-1] in LOCAL_HOSTS
    return h in LOCAL_HOSTS or bool(TUNNEL.match(h))


def check_url(text):
    """Every scheme://authority inside text must be http(s) to an allowed host."""
    found = False
    for scheme, authority in URL.findall(text):
        found = True
        if scheme.lower() not in ("http", "https"):
            ask(f"{scheme}:// URL, confirm: {text}")
        if "\\" in authority or "%" in authority:
            ask(f"unusual characters in URL host, confirm: {text}")
        hostport = authority.rsplit("@", 1)[-1]  # userinfo tricks: http://localhost@evil
        if hostport.startswith("["):
            host = hostport.split("]", 1)[0] + "]"
        else:
            host = hostport.split(":", 1)[0]
        if not host_ok(host):
            ask(f"{host or '(empty host)'} isn't localhost or a cc tunnel")
    return found


def tokens(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(toks):
    seg = []
    for t in toks:
        if t in OPERATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def program(seg):
    """The command word of a segment, skipping VAR=x and wrappers like sudo/env."""
    i = 0
    while i < len(seg):
        word = seg[i].lstrip("`")
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", word):
            i += 1
            continue
        base = os.path.basename(word)
        if base in WRAPPERS:
            i += 1
            while i < len(seg) and seg[i].startswith("-"):  # wrapper's own flags
                i += 1
            continue
        return base, seg[i + 1:]
    return None, []


def check_fetch(tool, args):
    risky_long = CURL_RISKY_LONG if tool == "curl" else WGET_RISKY_LONG
    risky_short = CURL_RISKY_SHORT if tool == "curl" else WGET_RISKY_SHORT
    value_long = CURL_VALUE_LONG if tool == "curl" else WGET_VALUE_LONG
    value_short = CURL_VALUE_SHORT if tool == "curl" else WGET_VALUE_SHORT

    for a in args:
        check_url(a)  # any URL anywhere, flag values included

    i, positional = 0, []
    while i < len(args):
        a = args[i]
        if a == "--":
            positional += args[i + 1:]
            break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            if name.startswith(risky_long):
                ask(f"{tool} {name} can reroute the request, confirm")
            if name in URL_VALUE_LONG:
                if "=" in a:
                    positional.append(a.split("=", 1)[1])
                elif i + 1 < len(args):
                    positional.append(args[i + 1])
                    i += 1
            elif name in value_long and "=" not in a:
                i += 1  # skip the value
            i += 1
            continue
        if a.startswith("-") and len(a) > 1:
            letters = a[1:]
            for j, ch in enumerate(letters):
                if ch in risky_short:
                    ask(f"{tool} -{ch} can reroute the request, confirm")
                if ch in value_short:
                    if j == len(letters) - 1:
                        i += 1  # value is the next token
                    break  # rest of the cluster is the attached value
            i += 1
            continue
        positional.append(a)
        i += 1

    if not positional:
        ask(f"couldn't find the URL in this {tool} command, confirm")
    for p in positional:
        if not URL.search(p):
            ask(f"{tool} target without http:// or https:// ({p}), confirm")


def scan(command, depth=0):
    if depth > 3:
        ask("deeply nested shell, confirm")
    try:
        toks = tokens(command)
    except ValueError:
        if re.search(r"\b(curl|wget)\b", command):
            ask("couldn't parse a command that mentions curl/wget, confirm")
        return
    for seg in segments(toks):
        tool, args = program(seg)
        if tool in ("curl", "wget"):
            if any(re.search(r"[$`]", a) for a in args):
                ask(f"{tool} with variables or command substitution can't be checked, confirm")
            check_fetch(tool, args)
        # Script strings (bash -c "...", $(...), `...`) get the same check.
        for t in seg:
            if re.search(r"\b(curl|wget)\b", t) and (" " in t or "$(" in t or "`" in t):
                inner = re.sub(r"^\$\(|\)$|^`|`$", "", t.strip())
                scan(inner, depth + 1)


def main():
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
    except Exception:
        ask("couldn't read the command, confirm")
    if not isinstance(command, str):
        ask("couldn't read the command, confirm")
    if not re.search(r"\b(curl|wget)\b", command):
        sys.exit(0)
    # $(...) and backticks would hide the real command from the tokenizer.
    if re.search(r"\$\(|`", command) and re.search(r"\b(curl|wget)\b", command):
        for inner in re.findall(r"\$\(([^()]*)\)|`([^`]*)`", command):
            scan(inner[0] or inner[1], 1)
    scan(command)
    sys.exit(0)


if __name__ == "__main__":
    main()
