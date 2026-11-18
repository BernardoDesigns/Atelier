#!/usr/bin/env python3
"""Verify that the apply step matched the review state.

Usage (python3 standard library only, run as: python3 -I -B verify-apply.py <WT>):
    verify-apply.py <WT>

Reads <WT>/taste-review/state.json and the four contract files under <WT>, then checks:
  approved, edited, rewritten  the item exists, its Status is approved, and its main line
                               equals the recorded text when there is one
  cut                          the item is gone from its file
  skipped, pending             the item exists and its Status is still draft
Prints one line per mismatch and exits 1 if there are any, else prints OK and exits 0.
"""
import importlib.util
import json
import os
import sys


def main(argv):
    if len(argv) != 1:
        sys.exit("usage: verify-apply.py <WT>")
    wt = argv[0]
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("gen_state", here + "/tests/gen-state.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    with open(wt.rstrip("/") + "/taste-review/state.json", encoding="utf-8") as f:
        state = json.load(f)
    found = {it["key"]: it for it in gen.parse_all(wt)}
    bad = []
    for key, e in state["items"].items():
        it = found.get(key)
        st = e["status"]
        if st == "cut":
            if it:
                bad.append(key + ": cut but still in its file")
            continue
        if not it:
            bad.append(key + ": " + st + " but missing from its file")
            continue
        file_status = it["fields"].get("Status")
        if st in ("approved", "edited", "rewritten"):
            if file_status != "approved":
                bad.append(key + ": " + st + " but Status is " + str(file_status))
            if e.get("text") is not None and it["main"] != e["text"]:
                bad.append(key + ": wording does not match the recorded text")
            for name, val in e.get("fields", {}).items():
                if it["fields"].get(name) != val:
                    bad.append(key + ": field " + name + " does not match the recorded text")
        elif file_status != "draft":
            bad.append(key + ": " + st + " but Status is " + str(file_status))
    if bad:
        print("\n".join(bad))
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main(sys.argv[1:])
