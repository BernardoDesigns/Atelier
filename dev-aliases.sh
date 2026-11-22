#!/usr/bin/env bash
# dev-aliases.sh — local dev server + cloudflare tunnel, on your clock.
#
#   devup     server + tunnel, port auto-detected (or pass one:  devup 8000)
#   devdown   kill the server + tunnel for that port
#   cc        launch Claude Code with the stack up before and torn down after
#             (also on Ctrl+C, a closed terminal window and SIGTERM; see cc below)
#   tunnel    print the current tunnel URL (optionally per port: tunnel 8000)
#
# Tunnels always use --protocol http2. QUIC (the cloudflared default) fails on
# some wired networks: the tunnel registers fine but the hostname never becomes
# publicly resolvable. http2 rides TCP and works everywhere.
#
# The server and the tunnel are both launched detached (nohup + disown), so
# neither dies when the shell that ran devup exits or its window is closed, and
# the Claude Code session can't signal them. What protects the server is
# disown: the shell no longer lists it as a job, so it sends it no SIGHUP on exit
# (tested with a server that resets SIGHUP to default, as Node does, and with
# nohup removed). nohup's ignored SIGHUP does not carry into such a server; it
# only backs up servers that keep it. After a plain devup, devdown is the
# off switch (cc runs it for you). Teardown is PID-tracked so we never
# blanket-kill a tunnel belonging to another project.
#
# PID lists are kept one per line and walked with `while read`, never with an
# unquoted `for p in $list`: zsh does not split those, bash does.
#
# Static mode never serves dotfiles (.git, .env, .DS_Store...): any path with a
# segment starting with "." gets a 404. It refuses to run in $HOME, and warns
# (without blocking) when the folder holds a .env / .env.* file.
#
# Loopback has two lines: 127.0.0.1 (IPv4) and ::1 (IPv6), and macOS often
# resolves "localhost" to ::1 first. The static server answers on both, and the
# tunnel dials whichever address the server actually answers on, so npm/Vite
# servers that only listen on one of them work too.
#
# devup keeps a little state per port (/tmp/devstack-<port>.pids and .state: the
# PIDs it started, the PIDs actually listening, and the folder it ran from). On
# the next run it uses that to spot leftovers of its own: dead PIDs are pruned,
# a server it started from this folder is reused, a server it started from some
# other folder is torn down and replaced, and anything it did not start is never
# touched. A dead tunnel's URL is dropped so nobody gets handed a dead link.
#
# cc takes its port from DEV_PORT when that is set (DEV_PORT=4000 cc), otherwise
# from the same auto-detection devup uses.
#
# The browser opens the public tunnel URL (and it's copied to the clipboard),
# so what you see is exactly what you share. Chrome may show a Local Network
# Access prompt if the page calls localhost; every tunnel is a new hostname,
# so it can ask each launch. Set DEV_OPEN=local to open http://localhost:<port>
# instead (no prompt), or DEV_OPEN=none to open nothing.
#
# The tunnel sends the dev server "Host: localhost:<port>" (cloudflared's
# --http-host-header), so Vite and Storybook host checks do not block the public
# hostname. This skips the dev server's host check for tunnel traffic only; local
# browser traffic is unaffected. Set DEV_TUNNEL_HOST=public to forward the tunnel
# hostname instead (the old behavior). Any other value or none means localhost.

# Loopback only (both lines); the tunnel is the only way in from outside.
_DEV_STATIC_PY='
import http.server, socket, sys, threading, urllib.parse
class H(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if any(s.startswith(".") for s in path.replace("\\", "/").split("/")):
            self.send_error(404)
            return None
        return super().send_head()
class V6(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
port = int(sys.argv[1])
servers = [http.server.ThreadingHTTPServer(("127.0.0.1", port), H)]
try:
    servers.append(V6(("::1", port), H))
except OSError:
    pass  # no IPv6 on this machine; IPv4 loopback is enough
for s in servers[1:]:
    threading.Thread(target=s.serve_forever, daemon=True).start()
servers[0].serve_forever()
'

# Matches any cloudflared quick tunnel pointed at this port, whichever loopback
# spelling it used (older sessions used localhost).
_dev_cf_pattern() {
  printf 'cloudflared tunnel.*(localhost|127\\.0\\.0\\.1|\\[::1\\]):%s( |$)' "$1"
}

_dev_detect() {
  local port kind script
  if [ -f package.json ] && grep -q '"dev"[[:space:]]*:' package.json; then
    kind=npm
    script=$(grep -o '"dev"[^,]*' package.json | head -1)
    port=$(echo "$script" | grep -oE -- '(-p|--port)[ =]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -z "$port" ] && { echo "$script" | grep -q vite && port=5173 || port=3000; }
  else
    kind=static; port=8000
  fi
  echo "$port $kind"
}

# PIDs listening on a port (not clients connected to it).
_dev_listeners() {
  lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null
}

# Send signal $1 to every PID in $2 (one per line; see _dev_reconcile for why).
_dev_kill_list() {
  local sig=$1 p
  while read -r p; do
    [ -n "$p" ] && kill -s "$sig" "$p" 2>/dev/null
  done <<EOF
$2
EOF
  return 0
}

# True when pid $1 is pid $2 or one of its ancestors.
_dev_is_ancestor() {
  local anc=$1 cur=$2 n=0
  while [ -n "$cur" ] && [ "$cur" -gt 1 ] 2>/dev/null && [ "$n" -lt 12 ]; do
    [ "$cur" = "$anc" ] && return 0
    cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    n=$((n+1))
  done
  return 1
}

# Compare what devup recorded for this port with what is alive right now.
# Prunes pidfile entries that are gone or no longer plausibly ours (a PID counts
# only if it holds the port, is a parent of what does, or is a cloudflared for
# this port, so a reused PID is never trusted). Sets:
#   _DEV_OWN_SERVER  1 when a listener on the port is a server devup started
#   _DEV_OWN_DIR     the folder that server was started from (may be empty)
#   _DEV_OWN_TUNNEL  PID of a live tunnel devup started for this port
# and drops a recorded tunnel URL when no live tunnel stands behind it.
_dev_reconcile() {
  local port=$1
  local pidfile="/tmp/devstack-$port.pids"
  local statefile="/tmp/devstack-$port.state"
  local listeners recorded tracked p l keep=""
  _DEV_OWN_SERVER=""; _DEV_OWN_DIR=""; _DEV_OWN_TUNNEL=""

  # Every list here is one PID per line and is walked with `while read`.
  # Looping over an unquoted "a b c" works in bash but zsh keeps it as one
  # word, so never write `for p in $list`.
  listeners=$(_dev_listeners "$port")
  recorded=$(sed -n 's/^listeners=//p' "$statefile" 2>/dev/null | head -1 | tr -s ' ' '\n')
  _DEV_OWN_DIR=$(sed -n 's/^dir=//p' "$statefile" 2>/dev/null | head -1)
  tracked=""
  [ -f "$pidfile" ] && tracked=$(grep -E '^[0-9]+$' "$pidfile")

  while read -r l; do
    [ -n "$l" ] || continue
    while read -r p; do
      [ -n "$p" ] && [ "$l" = "$p" ] && _DEV_OWN_SERVER=1
    done <<EOF
$recorded
EOF
    while read -r p; do
      [ -n "$p" ] || continue
      kill -0 "$p" 2>/dev/null && _dev_is_ancestor "$p" "$l" && _DEV_OWN_SERVER=1
    done <<EOF
$tracked
EOF
  done <<EOF
$listeners
EOF

  while read -r p; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    if ps -p "$p" -o command= 2>/dev/null | grep -qE "$(_dev_cf_pattern "$port")"; then
      keep="$keep$p
"
      _DEV_OWN_TUNNEL="$p"; continue
    fi
    if [ -n "$_DEV_OWN_SERVER" ]; then
      while read -r l; do
        [ -n "$l" ] || continue
        if _dev_is_ancestor "$p" "$l"; then keep="$keep$p
"; break; fi
      done <<EOF
$listeners
EOF
    fi
  done <<EOF
$tracked
EOF

  if [ -n "$keep" ]; then
    printf '%s' "$keep" > "$pidfile"
  else
    rm -f "$pidfile"
  fi
  [ -n "$_DEV_OWN_SERVER" ] || { rm -f "$statefile"; _DEV_OWN_DIR=""; }
  [ -n "$_DEV_OWN_TUNNEL" ] || rm -f "/tmp/tunnel-url-$port"
}

devup() {
  local detected port kind
  detected="$(_dev_detect)"
  port="${1:-${detected%% *}}"
  kind="${detected##* }"

  local pidfile="/tmp/devstack-$port.pids"
  local cflog="/tmp/cftunnel-$port.log"
  local srvlog="/tmp/devserver-$port.log"
  local urlfile="/tmp/tunnel-url-$port"

  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found. install it once per machine:  brew install cloudflared"
    return 1
  fi

  # --- what's left over from an earlier run? ---
  _dev_reconcile "$port"
  if [ -n "$_DEV_OWN_SERVER" ] && [ -n "$_DEV_OWN_DIR" ] && [ "$_DEV_OWN_DIR" != "$(pwd -P)" ]; then
    echo "stale server on :$port, started from $_DEV_OWN_DIR. tearing it down"
    devdown "$port"
    _dev_reconcile "$port"
  fi

  # --- server ---
  local started=""
  if [ -n "$(_dev_listeners "$port")" ]; then
    if [ -n "$_DEV_OWN_SERVER" ]; then
      echo "reusing the server devup started on :$port (same folder)"
    else
      echo "something's already on :$port, leaving it be"
    fi
  elif [ "$kind" = npm ]; then
    # detached like the tunnel (disown is what counts): closing this terminal must not take the server down
    nohup npm run dev < /dev/null > "$srvlog" 2>&1 & disown
    echo "$!" >> "$pidfile"; started=1
    echo "npm dev server booting on :$port"
  else
    if [ "$(pwd -P)" = "$(cd "$HOME" && pwd -P)" ]; then
      echo "refusing to serve \$HOME publicly. cd into the project folder first"; return 1
    fi
    # -I keeps a stray http.py etc. in the served folder from being imported
    if command -v python3 >/dev/null 2>&1; then
      nohup python3 -I -c "$_DEV_STATIC_PY" "$port" < /dev/null > "$srvlog" 2>&1 & disown
    else
      echo "need python3 to serve static files"; return 1
    fi
    echo "$!" >> "$pidfile"; started=1
    echo "static server booting on :$port (serving $(pwd))"
    [ -f index.html ] || echo "  heads up: no index.html here — are you in the right folder?"
    # dotfiles 404 at the handler, so this is just a nudge, not a block
    ls -A | grep -qE '^\.env(\.|$)' && echo "  heads up: .env file here. it's blocked from the tunnel, but everything else in this folder is public"
  fi

  # --- wait for the server to actually answer (max ~30s) ---
  local i=0
  until curl -s -o /dev/null "http://localhost:$port"; do
    i=$((i+1))
    if [ "$i" -ge 60 ]; then
      echo "server never came up on :$port, NOT opening a tunnel. last log lines:"
      tail -15 "$srvlog" 2>/dev/null
      return 1
    fi
    sleep 0.5
  done
  echo ":$port is live"
  # remember who we started and where, so a later devup can recognise it
  [ -n "$started" ] && printf 'dir=%s\nlisteners=%s\n' "$(pwd -P)" "$(_dev_listeners "$port" | tr '\n' ' ')" > "/tmp/devstack-$port.state"

  # --- dial the loopback address the server really answers on ---
  # -g stops curl reading [::1] as a glob pattern
  local origin="" h
  for h in 127.0.0.1 "[::1]"; do
    if curl -sg -o /dev/null --max-time 1 "http://$h:$port"; then
      origin="http://$h:$port"; break
    fi
  done
  [ -z "$origin" ] && origin="http://localhost:$port"

  # --- tunnel ---
  # Only count tunnels THIS devup started (tracked in the pidfile). A stray
  # cloudflared started by something else (e.g. Claude Code) must not suppress
  # ours — theirs is likely QUIC and therefore dead on this network.
  _dev_reconcile "$port"
  local mine="$_DEV_OWN_TUNNEL"

  if [ -n "$mine" ]; then
    echo "tunnel for :$port already running (pid $mine)"
  else
    # warn about foreign tunnels so a stale one doesn't confuse the URL
    local foreign
    foreign=$(pgrep -f "$(_dev_cf_pattern "$port")" 2>/dev/null | tr '\n' ' ')
    [ -n "$foreign" ] && echo "  note: other cloudflared on :$port ($foreign) — run devdown $port to clear"

    : > "$cflog"
    # cloudflared forwards the public hostname as the Host header, which Vite and
    # Storybook refuse. Present as localhost instead. The flag goes before --url
    # so the command line still ends in the origin (see _dev_cf_pattern).
    if [ "${DEV_TUNNEL_HOST:-}" = public ]; then
      nohup cloudflared tunnel --protocol http2 --url "$origin" < /dev/null > "$cflog" 2>&1 & disown
    else
      nohup cloudflared tunnel --protocol http2 --http-host-header "localhost:$port" --url "$origin" < /dev/null > "$cflog" 2>&1 & disown
    fi
    echo "$!" >> "$pidfile"
  fi

  # --- wait for the URL ---
  local url="" j=0
  while [ "$j" -lt 15 ]; do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$cflog" 2>/dev/null | tail -1)
    [ -n "$url" ] && break
    sleep 1; j=$((j+1))
  done
  if [ -z "$url" ]; then
    echo "tunnel didn't produce a URL — check $cflog"
    return 1
  fi

  # --- don't hand over a hostname that isn't resolving yet ---
  local host k=0
  host="${url#https://}"
  until nslookup "$host" >/dev/null 2>&1; do
    k=$((k+1))
    [ "$k" -ge 20 ] && { echo "tunnel URL not resolving yet, opening anyway: $url"; break; }
    sleep 1
  done

  printf '%s' "$url" > "$urlfile"
  echo "public URL:  $url  (tunnel -> $origin)"
  command -v pbcopy >/dev/null 2>&1 && printf '%s' "$url" | pbcopy && echo "  (copied to clipboard)"
  if command -v open >/dev/null 2>&1; then
    case "${DEV_OPEN:-tunnel}" in
      local) open "http://localhost:$port" ;;
      none)  ;;
      *)     open "$url" ;;
    esac
  fi
}

devdown() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local p
  local pidfile="/tmp/devstack-$port.pids"

  # kill what we started, by tracked PID
  if [ -f "$pidfile" ]; then
    while read -r p; do
      [ -n "$p" ] && kill "$p" 2>/dev/null
    done < "$pidfile"
    rm -f "$pidfile"
  fi

  # kill any OTHER cloudflared pointed at this port (orphans from elsewhere).
  # Scoped to the port, so a tunnel for another project is never touched.
  pkill -f "$(_dev_cf_pattern "$port")" 2>/dev/null

  # kill whatever actually holds the port — catches the next-server grandchild
  # that a parent kill would miss. escalate to -9 if it clings.
  # Listeners only: a browser connected to the port is a client, not a holder.
  local pids
  pids=$(_dev_listeners "$port")
  if [ -n "$pids" ]; then _dev_kill_list TERM "$pids"; sleep 1; fi
  pids=$(_dev_listeners "$port")
  [ -n "$pids" ] && _dev_kill_list KILL "$pids"

  rm -f "/tmp/tunnel-url-$port" "/tmp/devstack-$port.state"
  echo "killed server + tunnel on :$port"
}

tunnel() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local urlfile="/tmp/tunnel-url-$port"
  if [ -s "$urlfile" ]; then
    cat "$urlfile"; echo
    command -v pbcopy >/dev/null 2>&1 && printf '%s' "$(cat "$urlfile")" | pbcopy
  else
    echo "no tunnel URL recorded for :$port — is one running?"
  fi
}

# Launch Claude Code with the stack up before and torn down after.
# `claude` runs in the current shell, in the foreground, with the terminal
# attached (no subshell, no backgrounding). The stack comes down once, when
# claude is done, however that happens: /exit, a double Ctrl+C, a closed
# terminal window, or SIGTERM. Nothing tears it down while Claude Code runs.
# The traps and options cc sets are local to it: afterwards the shell has
# exactly the ones it had before. The port is DEV_PORT if set, else detected.
#
# What interactive zsh actually does (checked with a real pty, see
# tests/dev-aliases/check.sh):
#   - claude dies of SIGINT: zsh aborts the running function, so only an
#     `always` block is sure to run afterwards. A claude that handles Ctrl+C
#     and exits on its own just returns normally.
#   - SIGHUP (window closed): untrapped, zsh exits at once and runs the EXIT
#     trap. A HUP *trap* would wait until claude returns, so cc does not set one.
#   - SIGTERM: interactive zsh ignores it. cc traps it, but zsh only runs the
#     trap once claude has returned, so teardown follows claude, not the signal.
# bash has no local traps, so there cc saves the old ones and puts them back.
cc() {
  local port
  port="${DEV_PORT:-$(_dev_detect | awk '{print $1}')}"
  if [ -n "${ZSH_VERSION:-}" ]; then
    _dev_cc_zsh "$port" "$@"
  else
    _dev_cc_bash "$port" "$@"
  fi
}

# zsh: `always` is a zsh-only construct, so it goes through eval and bash never
# has to parse it.
if [ -n "${ZSH_VERSION:-}" ]; then
  eval '
_dev_cc_zsh() {
  setopt localoptions localtraps
  local port=$1 rc=0 quiet=""
  shift
  trap "devdown \"$port\"" EXIT
  trap "return 143" TERM
  {
    if ! devup "$port"; then
      echo "no preview this time, launching Claude only"
      quiet=1
    fi
    claude "$@"
    rc=$?
  } always {
    # a second Ctrl+C or HUP must not cut teardown short, and EXIT must not
    # run it a second time
    trap "" INT HUP TERM
    trap - EXIT
    if [ -n "$quiet" ]; then devdown "$port" >/dev/null; else devdown "$port"; fi
  }
  return $rc
}'
fi

# bash (3.2 safe): traps are global, so save the caller's, set ours, restore.
_dev_cc_bash() {
  local port=$1 rc=0 saved sig
  shift
  saved=$(trap -p INT HUP TERM EXIT)
  _DEV_CC_DOWN=""
  trap '_dev_cc_down_once "$port"' EXIT
  for sig in INT HUP TERM; do
    # shellcheck disable=SC2064
    trap "_dev_cc_down_once '$port'; _dev_cc_restore \"\$saved\"; kill -s $sig \$\$" "$sig"
  done
  _DEV_CC_QUIET=""
  if ! devup "$port"; then
    echo "no preview this time, launching Claude only"
    _DEV_CC_QUIET=1
  fi
  claude "$@"
  rc=$?
  _dev_cc_down_once "$port"
  _dev_cc_restore "$saved"
  unset _DEV_CC_DOWN _DEV_CC_QUIET
  return $rc
}

_dev_cc_down_once() {
  [ -n "$_DEV_CC_DOWN" ] && return 0
  _DEV_CC_DOWN=1
  if [ -n "${_DEV_CC_QUIET:-}" ]; then devdown "$1" >/dev/null; else devdown "$1"; fi
}

_dev_cc_restore() {
  trap - INT HUP TERM EXIT
  [ -n "$1" ] && eval "$1"
  return 0
}
