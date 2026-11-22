#!/usr/bin/env python3
"""Drive a real interactive zsh through a pseudo-terminal.

usage: python3 -I pty_drive.py TRANSCRIPT ACTION READYFILE LINE...

A LINE that starts with "@" is the blocking line (the one that runs cc). It is
sent, then the driver waits for READYFILE (the stub claude says it is up),
performs ACTION and waits for the shell to come back or exit. Every other LINE
is sent and the driver waits for the prompt.

ACTION is one of: none, int (one Ctrl+C), int2 (two Ctrl+C, 0.15s apart),
term (SIGTERM to the shell, then to the stub claude), hup (close the pty
master, the closed-window case). With no blocking LINE, hup closes the pty after
the last LINE, and none types "exit".

Environment: STUB_DIR (holds claude.pid) and DEV_PORT (probed for term).
Needs a ZDOTDIR whose .zshrc sets PROMPT='READY> '.
"""
import os
import pty
import re
import select
import signal
import socket
import sys
import time

transcript, action, readyfile = sys.argv[1:4]
lines = sys.argv[4:]
buf = b""
TAIL = re.compile(rb"READY> (\x1b\[[0-9;?]*[A-Za-z])*$")

pid, fd = pty.fork()
if pid == 0:
    os.execvp("zsh", ["zsh", "-i"])


def pump(timeout):
    global buf
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        return False
    try:
        data = os.read(fd, 65536)
    except OSError:
        return False
    if not data:
        return False
    buf += data
    return True


def exited():
    try:
        p, _ = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return True
    return p == pid


def wait_prompt(limit):
    end = time.time() + limit
    quiet = time.time()
    while time.time() < end:
        if pump(0.1):
            quiet = time.time()
        elif TAIL.search(buf[-200:]) and time.time() - quiet > 0.4:
            return True
        elif exited():
            return False
    return False


def note(text):
    global buf
    buf += ("\n[driver: %s]\n" % text).encode()


def finish():
    with open(transcript, "wb") as handle:
        handle.write(buf)


def port_open():
    try:
        socket.create_connection(("127.0.0.1", int(os.environ["DEV_PORT"])), 1).close()
        return True
    except OSError:
        return False


wait_prompt(30)
for line in lines:
    if not line.startswith("@"):
        os.write(fd, line.encode() + b"\n")
        wait_prompt(30)
        continue
    os.write(fd, line[1:].encode() + b"\n")
    end = time.time() + 60
    while not os.path.exists(readyfile) and time.time() < end:
        pump(0.1)
    time.sleep(0.5)
    if action == "int":
        os.write(fd, b"\x03")
    elif action == "int2":
        os.write(fd, b"\x03")
        time.sleep(0.15)
        os.write(fd, b"\x03")
    elif action == "term":
        os.kill(pid, signal.SIGTERM)
        time.sleep(2)
        note("port-open-while-claude-runs=%s" % port_open())
        with open(os.path.join(os.environ["STUB_DIR"], "claude.pid")) as handle:
            os.kill(int(handle.read()), signal.SIGTERM)
    elif action == "hup":
        os.close(fd)
        end = time.time() + 30
        while time.time() < end and not exited():
            time.sleep(0.1)
        note("pty master closed, shell exited=%s" % exited())
        finish()
        sys.exit(0)
    if not wait_prompt(30):
        if exited():
            note("shell exited")
            finish()
            sys.exit(0)
        note("no prompt after action")

if action == "hup" and not any(l.startswith("@") for l in lines):
    # no blocking line: close the window once every line has run
    os.close(fd)
    end = time.time() + 30
    while time.time() < end and not exited():
        time.sleep(0.1)
    note("pty master closed, shell exited=%s" % exited())
    finish()
    sys.exit(0)

os.write(fd, b"exit\n")
# with running jobs zsh warns first and only leaves on the second exit
pump(1.5)
try:
    os.write(fd, b"exit\n")
except OSError:
    pass
end = time.time() + 5
while time.time() < end and not exited():
    pump(0.1)
try:
    os.kill(pid, signal.SIGKILL)
except OSError:
    pass
finish()
