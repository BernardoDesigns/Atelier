#!/usr/bin/env python3
"""Record /taste-review answers in taste-review/state.json. The model never edits that file by hand.

Usage (python3 standard library only, run as: python3 -I -B record.py ...):
    record.py <WT> <key> <status> [--text "<final main line>"] [--field "<Field>=<text>"]...
    record.py <WT> --summary
    record.py <WT> --next

<WT> is the taste-review worktree. The state file is <WT>/taste-review/state.json.
<key> is "<file>#<id>", for example taste.md#T4. <status> is one of:
pending, approved, edited, rewritten, cut, skipped.

Record: validates the key and status, sets "updated" to today's ISO date, writes the
file with the same serialisation gen-state.py uses (2-space indent, key order kept,
trailing newline) and prints a one-line running tally. An unknown key, an unknown
status or a malformed option exits 2 and changes nothing.
--summary prints the counts, then the IDs under each status.
--next prints the key of the first pending item in file order, or "none".
"""
import datetime
import json
import sys

STATUSES = ["approved", "edited", "rewritten", "cut", "skipped", "pending"]


def die(msg):
    sys.stderr.write("record.py: " + msg + "\n")
    sys.exit(2)


def load(wt):
    path = wt.rstrip("/") + "/taste-review/state.json"
    try:
        with open(path, encoding="utf-8") as f:
            return path, json.load(f)
    except (OSError, ValueError) as ex:
        die("cannot read " + path + ": " + str(ex))


def tally(state):
    counts = {s: 0 for s in STATUSES}
    for e in state["items"].values():
        counts[e["status"]] += 1
    return counts


def tally_line(state):
    c = tally(state)
    return ", ".join("%s %d" % (s, c[s]) for s in STATUSES)


def main(argv):
    if len(argv) < 2:
        die("usage: record.py <WT> <key> <status> [--text T] [--field F=T]... | <WT> --summary | <WT> --next")
    wt, rest = argv[0], argv[1:]
    path, state = load(wt)

    if rest == ["--next"]:
        nxt = next((k for k, e in state["items"].items() if e["status"] == "pending"), None)
        print(nxt if nxt else "none")
        return
    if rest == ["--summary"]:
        print(tally_line(state))
        for s in STATUSES:
            ids = [k for k, e in state["items"].items() if e["status"] == s]
            print("%s: %s" % (s, ", ".join(ids) if ids else "none"))
        return

    if len(rest) < 2:
        die("need <key> and <status>")
    key, status, opts = rest[0], rest[1], rest[2:]
    if key not in state["items"]:
        die("unknown key: " + key)
    if status not in STATUSES:
        die("unknown status: " + status + " (one of " + ", ".join(STATUSES) + ")")
    text, fields, i = None, {}, 0
    while i < len(opts):
        if opts[i] == "--text" and i + 1 < len(opts):
            text = opts[i + 1]
            i += 2
        elif opts[i] == "--field" and i + 1 < len(opts) and "=" in opts[i + 1]:
            name, _, val = opts[i + 1].partition("=")
            if not name.strip():
                die("empty field name")
            fields[name.strip()] = val
            i += 2
        else:
            die("bad option: " + opts[i])

    entry = {"status": status, "text": text, "updated": datetime.date.today().isoformat()}
    if fields:
        entry["fields"] = fields
    state["items"][key] = entry
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(state, indent=2) + "\n")
    print(key + " " + status + " | " + tally_line(state))


if __name__ == "__main__":
    main(sys.argv[1:])
