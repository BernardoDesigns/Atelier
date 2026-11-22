#!/usr/bin/env bash
# Checks for dev-aliases.sh: cc tears the stack down however claude ends, and
# devup recognises its own leftovers. Exits 0 only when every check passes.
#
# Hermetic on purpose. It never starts a real cloudflared, claude or npm and
# never touches the usual dev ports. Stubs sit first on PATH, the only real
# listener is the script's own loopback static server (or a tiny foreign one
# started here) on a free high port, and every process the test starts is
# killed by the PID it recorded. Temp directories are left in place.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
script="${DEV_ALIASES_UNDER_TEST:-$repo/dev-aliases.sh}"
driver="$here/pty_drive.py"

failures=0
fail() { echo "FAIL $*"; failures=$((failures + 1)); }
ok() { echo "ok   $*"; }
check() { # description, then a command
  local what=$1
  shift
  if "$@"; then ok "$what"; else fail "$what"; fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/devalias-test.XXXXXX")"
work="$(cd "$work" && pwd -P)"
stubs="$work/bin"
mkdir -p "$stubs" "$work/zdot" "$work/site" "$work/site2" "$work/foreign" "$work/npmsite"
echo "temp dir: $work (left in place)"

# --- a free high port, never one of the usual dev ports ---
port="$(python3 -I - <<'PY'
import socket
while True:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    if p in (3000, 5173, 6006, 8000) or p < 20000:
        continue
    try:
        t = socket.socket(socket.AF_INET6)
        t.bind(("::1", p))
        t.close()
    except OSError:
        pass
    print(p)
    break
PY
)"
echo "test port: $port"
state_files=("/tmp/devstack-$port.pids" "/tmp/devstack-$port.state" "/tmp/tunnel-url-$port" "/tmp/cftunnel-$port.log" "/tmp/devserver-$port.log")

# --- stubs ---
cat > "$stubs/cloudflared" <<'EOF'
#!/bin/sh
# fake quick tunnel: prints a URL, then sits there until killed
echo $$ >> "$STUB_DIR/cf.pids"
echo "$*" >> "$STUB_DIR/cf.args"
echo "INF  https://stub-$$-tunnel.trycloudflare.com"
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF
cat > "$stubs/claude" <<'EOF'
#!/usr/bin/env python3
import os, signal, sys, time
d = os.environ["STUB_DIR"]
mode = os.environ.get("CLAUDE_MODE", "wait")
open(d + "/claude.pid", "w").write(str(os.getpid()))
try:
    fg = os.getpgrp() == os.tcgetpgrp(0)
except OSError:
    fg = False
open(d + "/claude.tty", "w").write("tty=%s fg=%s" % (os.isatty(0), fg))
open(d + "/claude.up", "w").close()
if mode == "normal":
    time.sleep(1)
    sys.exit(3)
if mode == "int130":
    signal.signal(signal.SIGINT, lambda *a: sys.exit(130))
elif mode == "intdie":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
ppid = os.getppid()
while True:
    time.sleep(0.2)
    if os.getppid() != ppid:  # the terminal is gone, like the real thing
        sys.exit(1)
EOF
# fake `npm run dev`: like the real thing the server is a grandchild of the
# npm process (npm -> server), so killing npm alone leaves it listening.
# STUB_NPM_MODE=multi makes two processes hold the listening socket.
cat > "$work/srv.py" <<'EOF'
import http.server, os, sys
port, mode = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, *a):
        pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
with open(os.environ["STUB_DIR"] + "/srv.pids", "a") as f:
    f.write("%d\n" % os.getpid())
    f.flush()
    if mode == "multi" and os.fork() == 0:
        f.write("%d\n" % os.getpid())
        f.flush()
s.serve_forever()
EOF
cat > "$stubs/npm" <<'EOF'
#!/bin/sh
echo $$ >> "$STUB_DIR/npm.pids"
python3 -I "$STUB_SRV" "$DEV_PORT" "${STUB_NPM_MODE:-single}" &
wait
EOF
printf '{"scripts":{"dev":"vite"}}\n' > "$work/npmsite/package.json"
printf '#!/bin/sh\nexit 0\n' > "$stubs/open"
printf '#!/bin/sh\ncat > /dev/null\n' > "$stubs/pbcopy"
printf '#!/bin/sh\nexit 0\n' > "$stubs/nslookup"
chmod +x "$stubs"/*

# --- zsh side: a quiet prompt, plus a counter around devdown and a snapshot helper ---
printf "PROMPT='READY> '\nunset RPROMPT\nPS2=''\n" > "$work/zdot/.zshrc"
cat > "$work/setup.zsh" <<EOF
source "$script"
functions[_orig_devdown]=\$functions[devdown]
devdown() { echo x >> "\$COUNT"; _orig_devdown "\$@"; }
_snap() { trap > "\$1.traps" 2>&1; setopt > "\$1.setopt" 2>&1; }
EOF

# --- bookkeeping so cleanup only ever kills what this test started ---
cleanup() {
  local f p
  for f in "$work"/*/cf.pids "$work"/*/claude.pid "$work"/*/npm.pids "$work"/*/srv.pids "$work"/*/client.pid "$work"/foreign.pid; do
    [ -f "$f" ] || continue
    for p in $(cat "$f"); do
      if ps -p "$p" -o command= 2>/dev/null | grep -q "$work"; then kill -9 "$p" 2>/dev/null; fi
    done
  done
  [ -f "$work/foreign.pid" ] && kill -9 "$(cat "$work/foreign.pid")" 2>/dev/null
  # the test port is ours alone: anything on it is a server this test started
  local l
  for l in $(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null); do kill -9 "$l" 2>/dev/null; done
  rm -f "${state_files[@]}"
}
trap cleanup EXIT

alive() { kill -0 "$1" 2>/dev/null; }
wait_dead() { # pid, up to ~6s
  local i=0
  while alive "$1" && [ "$i" -lt 30 ]; do sleep 0.2; i=$((i + 1)); done
  ! alive "$1"
}
wait_port_free() {
  local i=0
  while [ -n "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null)" ] && [ "$i" -lt 30 ]; do sleep 0.2; i=$((i + 1)); done
  [ -z "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null)" ]
}
reset_state() { rm -f "${state_files[@]}"; }

# nothing of ours may be left: no listener, no tunnel, no claude, no state files
assert_clean() { # case dir
  local name=$1 dir=$2 p allgone=1
  check "$name: nothing listens on the test port" wait_port_free
  for p in $(cat "$dir/cf.pids" 2>/dev/null); do wait_dead "$p" || allgone=0; done
  check "$name: stub tunnel process is gone" test "$allgone" = 1
  p="$(cat "$dir/claude.pid" 2>/dev/null)"
  [ -z "$p" ] || check "$name: stub claude is gone" wait_dead "$p"
  check "$name: pidfile is gone" test ! -e "/tmp/devstack-$port.pids"
  check "$name: tunnel URL file is gone" test ! -e "/tmp/tunnel-url-$port"
  check "$name: state file is gone" test ! -e "/tmp/devstack-$port.state"
}

stub_env() { # exports shared by the pty cases
  export STUB_DIR="$1" CLAUDE_MODE="$2" DEV_PORT="$port" DEV_OPEN=none
  export ZDOTDIR="$work/zdot" COUNT="$1/count" PATH="$stubs:$PATH" STUB_SRV="$work/srv.py"
}

# case NAME CLAUDE_MODE ACTION : runs cc in a real zsh on a pty, then checks.
run_case() {
  local name=$1 mode=$2 action=$3 dir="$work/$1"
  mkdir -p "$dir"
  reset_state
  (
    stub_env "$dir" "$mode"
    cd "$work/site" || exit 1
    python3 -I "$driver" "$dir/transcript" "$action" "$dir/claude.up" \
      "source $work/setup.zsh" "cd $work/site" "_snap $dir/before" \
      "@cc" 'echo "RC=$?"' "_snap $dir/after"
  )
  assert_clean "$name" "$dir"
  check "$name: teardown ran exactly once" test "$(wc -l < "$dir/count" 2>/dev/null | tr -d ' ')" = 1
}

same_shell_state() { # case: same traps and options before and after cc
  local dir="$work/$1"
  check "$1: trap output unchanged after cc" cmp -s "$dir/before.traps" "$dir/after.traps"
  check "$1: setopt output unchanged after cc" cmp -s "$dir/before.setopt" "$dir/after.setopt"
}

echo "== syntax"
check "bash -n dev-aliases.sh" bash -n "$script"
check "zsh -n dev-aliases.sh" zsh -n "$script"
check "bash 3.2 is the one on PATH for the bash case" test -x /bin/bash

echo "== cc in interactive zsh (pty)"
run_case normal normal none
same_shell_state normal
check "normal: claude's exit status comes back" grep -q "RC=3" "$work/normal/transcript"
check "normal: claude had the terminal in the foreground" grep -q "tty=True fg=True" "$work/normal/claude.tty"
check "normal: devdown reported once on screen" test "$(grep -c 'killed server + tunnel' "$work/normal/transcript")" = 1

for m in intdie int130; do
  run_case "ctrlc-$m" "$m" int
  same_shell_state "ctrlc-$m"
  check "ctrlc-$m: shell is back at a prompt" grep -q "RC=" "$work/ctrlc-$m/transcript"
  run_case "ctrlc2-$m" "$m" int2
  same_shell_state "ctrlc2-$m"
  check "ctrlc2-$m: shell is back at a prompt" grep -q "RC=" "$work/ctrlc2-$m/transcript"
done

run_case sigterm wait term
check "sigterm: nothing was torn down while claude was still running" grep -q "port-open-while-claude-runs=True" "$work/sigterm/transcript"
same_shell_state sigterm

run_case hup wait hup
check "hup: shell exited" grep -q "shell exited=True" "$work/hup/transcript"

echo "== cc in bash 3.2, non-interactive"
bdir="$work/bash"
mkdir -p "$bdir"
reset_state
(
  stub_env "$bdir" normal
  cd "$work/site" || exit 1
  /bin/bash -c '
    . "$1"
    trap "echo mine" USR1
    trap -p > "$2.before"
    cc
    echo "RC=$?" > "$2.rc"
    trap -p > "$2.after"
  ' _ "$script" "$bdir/traps" > "$bdir/out" 2>&1
)
assert_clean bash "$bdir"
check "bash: claude's exit status comes back" grep -q "RC=3" "$bdir/traps.rc"
check "bash: traps unchanged after cc" cmp -s "$bdir/traps.before" "$bdir/traps.after"
check "bash: devdown reported once" test "$(grep -c 'killed server + tunnel' "$bdir/out")" = 1

leftover_suite() {
  local T=$1 out srv1 tun1 srv2 tun2 dead1 dead2 dead_url site_real site2_real foreign i p
  echo "== devup leftovers and devdown in $T"
  ddir="$work/devup"
  mkdir -p "$ddir"
  reset_state
  runsh() { # run `-c SCRIPT ARGS...` in the shell under test ($T): bash 3.2 or zsh
    case "$T" in
      bash) /bin/bash -c "$@" ;;
      *) zsh -f -c "$@" ;;
    esac
  }
  dev() { # folder: run devup there in a non-interactive shell, output on stdout
    (
      stub_env "$ddir" wait
      runsh '. "$1"; cd "$2" && devup "$3"' _ "$script" "$1" "$port" 2>&1
    )
  }
  down() { (stub_env "$ddir" wait; runsh '. "$1"; devdown "$2"' _ "$script" "$port" >/dev/null 2>&1); }
  alive_count() { # how many of the PIDs listed in file $1 are alive
    local n=0 q
    for q in $(cat "$1" 2>/dev/null); do alive "$q" && n=$((n + 1)); done
    echo "$n"
  }
  # true when pid $1 is pid $2 or an ancestor of it
  is_anc() {
    local cur=$2 n=0
    while [ -n "$cur" ] && [ "$cur" -gt 1 ] && [ "$n" -lt 12 ]; do
      [ "$cur" = "$1" ] && return 0
      cur="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
      n=$((n + 1))
    done
    return 1
  }
  pidline() { sed -n "$1p" "/tmp/devstack-$port.pids" 2>/dev/null; }
  state_dir() { sed -n 's/^dir=//p' "/tmp/devstack-$port.state" 2>/dev/null; }
  has() { echo "$out" | grep -q -- "$1"; }
  url_in() { grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1; }

  # dead PIDs and a dead URL in the state
  ( sleep 0 & echo $! > "$ddir/dead1"; wait ) ; ( sleep 0 & echo $! > "$ddir/dead2"; wait )
  dead1="$(cat "$ddir/dead1")"; dead2="$(cat "$ddir/dead2")"
  printf '%s\n%s\n' "$dead1" "$dead2" > "/tmp/devstack-$port.pids"
  printf '%s' "https://dead-dead.trycloudflare.com" > "/tmp/tunnel-url-$port"
  out="$(dev "$work/site")"
  site_real="$(cd "$work/site" && pwd -P)"
  check "$T: dead PIDs: pruned from the pidfile" test -z "$(grep -E "^($dead1|$dead2)\$" "/tmp/devstack-$port.pids")"
  check "$T: dead PIDs: pruned quietly" test -z "$(echo "$out" | grep -E "$dead1|$dead2|stale|leaving")"
  check "$T: dead URL: not handed out, a new tunnel started" test "$(echo "$out" | url_in)" != "" -a "$(echo "$out" | url_in)" != "https://dead-dead.trycloudflare.com"
  check "$T: dead URL: the URL file holds the new one" test "$(cat "/tmp/tunnel-url-$port")" = "$(echo "$out" | url_in)"
  check "$T: state file records the folder" test "$(state_dir)" = "$site_real"
  srv1="$(pidline 1)"; tun1="$(pidline 2)"
  check "$T: pidfile has a live server and a live tunnel" test -n "$srv1" -a -n "$tun1"
  alive "$srv1" && alive "$tun1" && ok "$T: server and tunnel alive" || fail "$T: server and tunnel alive"

  out="$(dev "$work/site")"
  check "$T: same folder: reused, said so in one line" test "$(echo "$out" | grep -c 'reusing')" = 1
  check "$T: same folder: same server, not restarted" test "$(pidline 1)" = "$srv1" && alive "$srv1"
  check "$T: same folder: same tunnel kept" test "$(pidline 2)" = "$tun1" && alive "$tun1"
  check "$T: same folder: exactly one tunnel process alive" test "$(alive_count "$ddir/cf.pids")" = 1
  check "$T: same folder: pidfile still holds both PIDs" test "$(grep -cE '^[0-9]+$' "/tmp/devstack-$port.pids")" = 2

  out="$(dev "$work/site2")"
  site2_real="$(cd "$work/site2" && pwd -P)"
  check "$T: other folder: called out as stale" has "stale server"
  check "$T: other folder: old server is gone" wait_dead "$srv1"
  check "$T: other folder: old tunnel is gone" wait_dead "$tun1"
  check "$T: other folder: exactly one tunnel process alive" test "$(alive_count "$ddir/cf.pids")" = 1
  check "$T: other folder: new server is up from the new folder" test -n "$(lsof -tiTCP:"$port" -sTCP:LISTEN)" -a "$(state_dir)" = "$site2_real"
  check "$T: other folder: new tunnel URL printed" test -n "$(echo "$out" | url_in)"
  srv2="$(pidline 1)"; tun2="$(pidline 2)"

  # tracked tunnel dead, URL file still there, server alive from the same folder
  kill -9 "$tun2" 2>/dev/null
  wait_dead "$tun2"
  dead_url="$(cat "/tmp/tunnel-url-$port")"
  out="$(dev "$work/site2")"
  check "$T: dead tunnel: server reused" has "reusing"
  check "$T: dead tunnel: a new tunnel started" test -n "$(pidline 2)" -a "$(pidline 2)" != "$tun2"
  check "$T: dead tunnel: the dead URL was not printed" test -z "$(echo "$out" | grep -F "$dead_url")"
  check "$T: dead tunnel: URL file holds the new URL" test "$(cat "/tmp/tunnel-url-$port")" = "$(echo "$out" | url_in)"
  down
  assert_clean "$T-devup-cleanup" "$ddir"

  # a listener we did not start
  reset_state
  ( cd "$work/foreign" && python3 -I -m http.server "$port" --bind 127.0.0.1 < /dev/null > "$work/foreign.log" 2>&1 & echo $! > "$work/foreign.pid" )
  i=0
  while [ -z "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null)" ] && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
  foreign="$(cat "$work/foreign.pid")"
  out="$(dev "$work/site")"
  check "$T: foreign listener: devup says it is leaving it be" has "leaving it be"
  check "$T: foreign listener: still alive afterwards" alive "$foreign"
  check "$T: foreign listener: not in our pidfile" test -z "$(grep -x "$foreign" "/tmp/devstack-$port.pids" 2>/dev/null)"
  check "$T: foreign listener: no state recorded for it" test ! -e "/tmp/devstack-$port.state"
  # only our stub tunnel goes; the foreign server is stopped by its recorded PID
  for p in $(cat "$ddir/cf.pids"); do alive "$p" && kill "$p" 2>/dev/null; done
  kill "$foreign" 2>/dev/null
  wait_dead "$foreign"
  # python3 on macOS can fork the real interpreter, so the recorded PID is only
  # the launcher. The port is ours alone, so stop whatever still holds it.
  for p in $(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null); do kill "$p" 2>/dev/null; done
  check "$T: foreign listener: port is free again" wait_port_free
}

# a server with two processes on the port: devdown must take both down, and
# must leave a client that merely holds a connection to the port alone.
multi_suite() {
  local T=$1 out p n allgone=1 cpid
  echo "== devdown with several holders of the port, in $T"
  reset_state
  : > "$ddir/srv.pids"; : > "$ddir/npm.pids"; : > "$ddir/client.pid"
  out="$(STUB_NPM_MODE=multi dev "$work/npmsite")"
  check "$T: multi: server came up" test -n "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null)"
  n="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' ')"
  check "$T: multi: two processes hold the port" test "$n" -ge 2
  python3 -I -c '
import os, socket, sys, time
socket.create_connection(("127.0.0.1", int(sys.argv[1])))
open(sys.argv[2], "w").write(str(os.getpid()))
time.sleep(120)
' "$port" "$ddir/client.pid" < /dev/null > /dev/null 2>&1 &
  disown
  i=0
  while [ ! -s "$ddir/client.pid" ] && [ "$i" -lt 25 ]; do sleep 0.2; i=$((i + 1)); done
  cpid="$(cat "$ddir/client.pid")"
  down
  for p in $(cat "$ddir/srv.pids"); do wait_dead "$p" || allgone=0; done
  check "$T: multi: every server process is gone" test "$allgone" = 1 -a -s "$ddir/srv.pids"
  check "$T: multi: nothing listens on the test port" wait_port_free
  check "$T: multi: the connected client was not killed" alive "$cpid"
  kill "$cpid" 2>/dev/null
  wait_dead "$cpid"
  assert_clean "$T-multi" "$ddir"
}

# the Host header flag, and _dev_cf_pattern against tunnels with and without it
host_suite() {
  local T=$1 out pat last
  echo "== tunnel Host header, in $T"
  reset_state
  : > "$ddir/cf.args"
  out="$(dev "$work/site")"
  last="$(tail -1 "$ddir/cf.args")"
  check "$T: host: default passes the localhost Host header" test "$(echo "$last" | grep -c -- "--http-host-header localhost:$port ")" = 1
  check "$T: host: default still passes --protocol http2" test "$(echo "$last" | grep -c -- '--protocol http2')" = 1
  check "$T: host: default still passes --url <origin>" test "$(echo "$last" | grep -c -- "--url http://[^ ]*:$port\$")" = 1
  out="$(dev "$work/site")"
  check "$T: host: second devup reuses the tunnel (no new process)" test "$(wc -l < "$ddir/cf.args" | tr -d ' ')" = 1
  check "$T: host: pidfile holds server and tunnel" test "$(grep -cE '^[0-9]+$' "/tmp/devstack-$port.pids")" = 2
  down
  assert_clean "$T-host-default" "$ddir"

  reset_state
  : > "$ddir/cf.args"
  out="$(DEV_TUNNEL_HOST=public dev "$work/site")"
  last="$(tail -1 "$ddir/cf.args")"
  check "$T: host: public mode omits the Host header flag" test "$(echo "$last" | grep -c -- 'http-host-header')" = 0
  check "$T: host: public mode keeps --protocol http2 and --url" test "$(echo "$last" | grep -c -- "--protocol http2 --url http://[^ ]*:$port\$")" = 1
  # a tunnel started the old way is still recognised and reused by a default devup
  out="$(dev "$work/site")"
  check "$T: host: an old-style tunnel is reused" test "$(wc -l < "$ddir/cf.args" | tr -d ' ')" = 1
  check "$T: host: old-style tunnel kept in the pidfile" test "$(grep -cE '^[0-9]+$' "/tmp/devstack-$port.pids")" = 2
  down
  assert_clean "$T-host-public" "$ddir"
}

# _dev_cf_pattern must match a tunnel started with or without the flag, either
# flag order, and nothing for another port
echo "== _dev_cf_pattern"
pat="$(bash -c '. "$1"; _dev_cf_pattern 5555' _ "$script")"
check "pattern: old command line (no flag)" bash -c 'echo "cloudflared tunnel --protocol http2 --url http://[::1]:5555" | grep -qE "$1"' _ "$pat"
check "pattern: flag before --url" bash -c 'echo "cloudflared tunnel --protocol http2 --http-host-header localhost:5555 --url http://127.0.0.1:5555" | grep -qE "$1"' _ "$pat"
check "pattern: flag after --url" bash -c 'echo "cloudflared tunnel --protocol http2 --url http://127.0.0.1:5555 --http-host-header localhost:5555" | grep -qE "$1"' _ "$pat"
check "pattern: another port does not match" bash -c '! echo "cloudflared tunnel --protocol http2 --http-host-header localhost:5556 --url http://127.0.0.1:5556" | grep -qE "$1"' _ "$pat"
check "pattern: a longer port does not match" bash -c '! echo "cloudflared tunnel --protocol http2 --url http://127.0.0.1:55550" | grep -qE "$1"' _ "$pat"

T=bash
leftover_suite bash
multi_suite bash
host_suite bash
T=zsh
leftover_suite zsh
multi_suite zsh
host_suite zsh

echo "== the server outlives the shell that ran devup (pty)"
# case NAME FOLDER ACTION: devup in an interactive zsh, then close the window
# (hup) or type exit (none). The stack must keep running; devdown from a fresh
# shell is the only off switch.
survive_case() {
  local name=$1 folder=$2 action=$3 dir="$work/$1" srv p
  mkdir -p "$dir"
  reset_state
  (
    stub_env "$dir" wait
    cd "$work/$folder" || exit 1
    python3 -I "$driver" "$dir/transcript" "$action" "$dir/none.up" \
      "source $work/setup.zsh" "cd $work/$folder" "devup $port"
  )
  sleep 1
  check "$name: the server is still listening after the shell is gone" test -n "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null)"
  srv="$(sed -n 1p "/tmp/devstack-$port.pids" 2>/dev/null)"
  check "$name: the recorded server PID is alive" test -n "$srv" && alive "$srv"
  # the first PID must still identify the server: the listener or its parent
  check "$name: the recorded PID is the server (or its parent)" is_anc "$srv" "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1)"
  [ "$folder" = npmsite ] && check "$name: the recorded PID is the npm process" test "$srv" = "$(sed -n 1p "$dir/npm.pids" 2>/dev/null)"
  allalive=1
  for p in $(cat "$dir/cf.pids" 2>/dev/null); do alive "$p" || allalive=0; done
  check "$name: the tunnel is still up too" test "$allalive" = 1 -a -s "$dir/cf.pids"
  (stub_env "$dir" wait; zsh -f -c '. "$1"; devdown "$2"' _ "$script" "$port" >/dev/null 2>&1)
  assert_clean "$name-devdown" "$dir"
  if [ "$folder" = npmsite ]; then
    p="$(cat "$dir/srv.pids" 2>/dev/null)"
    allgone=1
    for p in $p; do wait_dead "$p" || allgone=0; done
    check "$name-devdown: the npm server grandchild is gone" test "$allgone" = 1
  fi
}
survive_case survive-static-hup site hup
survive_case survive-static-exit site none
survive_case survive-npm-hup npmsite hup
survive_case survive-npm-exit npmsite none

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS tests/dev-aliases/check.sh"
else
  echo "FAIL tests/dev-aliases/check.sh ($failures failing)"
  exit 1
fi
