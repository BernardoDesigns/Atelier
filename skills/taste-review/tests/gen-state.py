#!/usr/bin/env python3
"""Generate the initial taste-review state from the four contract files.

Usage (python3 standard library only, run isolated):
    python3 -I gen-state.py <repo-root>           print state JSON to stdout
    python3 -I gen-state.py --ids <repo-root>     print one state key per line
    python3 -I gen-state.py --sync <repo-root>    create taste-review/state.json, or add
                                                  missing keys to it as pending (never deletes)

The same parser is imported by check.sh, so the generator and the test cannot
disagree about what an item is.

Item sources, in review order:
    quality.md      table rows G1..G10 (gates) and P1..P5 (principles)
    taste.md        ### T<n> blocks
    conventions.md  ### C<n> blocks
    failures.md     ### F<n> blocks
State key: "<file>#<id>", for example "taste.md#T4" or "quality.md#G7".
"""
import json
import re
import sys

FILES = ["quality.md", "taste.md", "conventions.md", "failures.md"]
FIELD = re.compile(
    r"^(Name|Trap|Shows up as|Instead|Source|Status|Applied as|Check|Verify):\s*(.*)$")
HEAD = {"taste.md": re.compile(r"^### (T\d+)\s*$"),
        "conventions.md": re.compile(r"^### (C\d+)\s*$"),
        "failures.md": re.compile(r"^### (F\d+)\s*$")}
ROW = re.compile(r"^\|\s*([GP]\d+)\s*\|")


def read(root, name):
    with open(root.rstrip("/") + "/" + name, encoding="utf-8") as f:
        return f.read()


def parse_blocks(name, text):
    """Items of a ### file: dicts with id, key, main, fields, start, end (line indexes)."""
    lines = text.split("\n")
    heads = [(i, HEAD[name].match(l).group(1)) for i, l in enumerate(lines) if HEAD[name].match(l)]
    items = []
    for i, ident in heads:
        end = len(lines)
        for j in range(i + 1, len(lines)):
            if lines[j].startswith("## ") or lines[j].startswith("### "):
                end = j
                break
        fields, free = {}, []
        for l in lines[i + 1:end]:
            m = FIELD.match(l)
            if m:
                fields[m.group(1)] = m.group(2)
            elif l.strip():
                free.append(l.strip())
        main = fields.get("Trap") if name == "failures.md" else (free[0] if free else "")
        items.append({"file": name, "id": ident, "key": name + "#" + ident, "main": main,
                      "fields": fields, "start": i, "end": end})
    return items


def parse_quality(text):
    items = []
    for i, l in enumerate(text.split("\n")):
        m = ROW.match(l)
        if not m:
            continue
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        ident = m.group(1)
        # gates: ID | Gate | Pass bar | Checked by | Status
        # principles: ID | Principle | In short | Status
        main = cells[2] if len(cells) >= 3 else ""
        items.append({"file": "quality.md", "id": ident, "key": "quality.md#" + ident,
                      "main": main, "fields": {"Name": cells[1], "Status": cells[-1]},
                      "start": i, "end": i + 1})
    return items


def parse_all(root):
    items = parse_quality(read(root, "quality.md"))
    for name in FILES[1:]:
        items += parse_blocks(name, read(root, name))
    return items


def initial_state(root):
    return {"version": 1, "files": FILES,
            "items": {it["key"]: {"status": "pending", "text": None, "updated": None}
                      for it in parse_all(root)}}


def sync(root):
    """Write <root>/taste-review/state.json: create it, or add keys it lacks as pending.

    Existing entries and their order are kept, including cut items whose items are gone
    from the files. New keys are appended. Returns the list of keys added."""
    path = root.rstrip("/") + "/taste-review/state.json"
    fresh = initial_state(root)
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        state = {"version": 1, "files": FILES, "items": {}}
    added = [k for k in fresh["items"] if k not in state["items"]]
    for k in added:
        state["items"][k] = fresh["items"][k]
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(state, indent=2) + "\n")
    return added


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--sync":
        added = sync(args[1])
        print("added %d new item(s)" % len(added))
        sys.exit(0)
    ids_only = bool(args) and args[0] == "--ids"
    if ids_only:
        args = args[1:]
    if len(args) != 1:
        sys.exit("usage: gen-state.py [--ids | --sync] <repo-root>")
    state = initial_state(args[0])
    if ids_only:
        print("\n".join(state["items"]))
    else:
        print(json.dumps(state, indent=2))
