#!/usr/bin/env bash
# skills/spec/tests/check.sh
#
# What this proves: the skill's instructions are complete. SKILL.md carries the
# frontmatter, the refusal rule, the eight headings and the Atelier-home paths,
# and a reference reducer (the same rule the skill states in prose) accepts the
# fixture SPEC and rejects an incomplete one.
# What it does not prove: that the model follows the instructions. The loop
# dry-run before switch-on covers that.
#
# Run: bash skills/spec/tests/check.sh   (python3 standard library only)

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL="$HERE/../SKILL.md"
FIX="$HERE/fixture-SPEC.md"
BAD="$HERE/fixture-incomplete-SPEC.md"
TRANSCRIPT="$HERE/fixture-transcript.md"
TEMPLATE="$HERE/../../../templates/SPEC.md"

exec python3 -I - "$SKILL" "$FIX" "$BAD" "$TRANSCRIPT" "$TEMPLATE" <<'PY'
import re, sys

skill_p, fix_p, bad_p, tr_p, tpl_p = sys.argv[1:6]
HEADINGS = ["Goal", "User and core tension", "Acceptance criteria", "States to cover",
            "Visual baseline", "Out of scope and protected paths", "Definition of done",
            "Open questions"]
PROTECTED = ["auth/", "api/", "payments/", "lib/shared/"]
fails = 0

def check(name, ok, detail=""):
    global fails
    if ok:
        print("PASS " + name)
    else:
        fails += 1
        print("FAIL " + name + (": " + detail if detail else ""))

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def sections(text):
    """Reference reducer: map each ## heading to its body, comments removed."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    out, order, cur = {}, [], None
    for line in text.splitlines():
        m = re.match(r"^## (.+?)\s*$", line)
        if m:
            cur = m.group(1)
            order.append(cur)
            out[cur] = []
        elif cur is not None:
            out[cur].append(line)
    return order, out

def meaningful(lines):
    keep = []
    for l in lines:
        s = l.strip()
        if not s or re.fullmatch(r"-( \[ \])?", s):
            continue
        keep.append(s)
    return keep

def spec_gate(text):
    """The refusal rule from SKILL.md: returns the list of what is missing."""
    order, body = sections(text)
    missing = []
    if order != HEADINGS:
        missing.append("headings")
    for h in ("Acceptance criteria", "States to cover"):
        if not meaningful(body.get(h, [])):
            missing.append(h)
    return missing

skill = read(skill_p)
fm = re.match(r"^---\n(.*?)\n---\n", skill, flags=re.S)
check("SKILL.md has frontmatter", bool(fm))
fmt = fm.group(1) if fm else ""
check("frontmatter name is spec", re.search(r"^name: spec$", fmt, flags=re.M) is not None)
check("frontmatter has a description", re.search(r"^description: \S", fmt, flags=re.M) is not None)
desc = (re.search(r"^description: (.*)$", fmt, flags=re.M) or [None, ""])[1]
check("description limits the trigger to explicit requests",
      "Do not use it on your own initiative" in desc and "/spec" in desc)
check("description has no vague-idea trigger", "vague idea that needs pinning down" not in desc)
check("SKILL.md states the refusal rule",
      "No SPEC.md is written while `Acceptance criteria` or `States to cover` is empty" in skill)
check("SKILL.md names all eight headings", all(("**" + h + ".**") in skill for h in HEADINGS))
check("SKILL.md reads the template under the Atelier home",
      "~/.claude/atelier/templates/SPEC.md" in skill)
check("SKILL.md reads quality.md under the Atelier home", "~/.claude/atelier/quality.md" in skill)
check("SKILL.md has no bare repo-relative template path",
      re.search(r"(?<![/\w])templates/SPEC\.md", skill.replace("~/.claude/atelier/templates/SPEC.md", "")) is None)
check("SKILL.md writes into the host repo, never the Atelier checkout",
      "current working directory" in skill and "Never write it into the Atelier checkout" in skill)
check("SKILL.md asks before overwriting", "ask before overwriting" in skill)
check("SKILL.md works standalone and from Eames", "Eames" in skill and "on its own" in skill)

check("fixture transcript exists and has questions", read(tr_p).count("\nQ:") >= 6)

fix = read(fix_p)
order, body = sections(fix)
check("fixture SPEC has the eight headings in order", order == HEADINGS, str(order))
states = [l.strip() for l in body.get("States to cover", []) if l.strip()]
check("fixture SPEC states are a plain bullet list", all(re.fullmatch(r"- [a-z][a-z ]*", s) for s in states), str(states))
check("fixture SPEC has at least three states", len(states) >= 3, str(len(states)))
check("fixture SPEC lists all four protected paths",
      all(("`" + p + "`") in "\n".join(body["Out of scope and protected paths"]) for p in PROTECTED))
check("fixture SPEC acceptance lines are checkboxes",
      all(re.match(r"- \[ \] ", s) for s in meaningful(body["Acceptance criteria"])))
check("reference gate accepts the fixture SPEC", spec_gate(fix) == [], str(spec_gate(fix)))

bad_missing = spec_gate(read(bad_p))
check("reference gate refuses the incomplete SPEC and names what is missing",
      bad_missing == ["Acceptance criteria"], str(bad_missing))

tpl = read(tpl_p)
check("template has the eight headings in order", sections(tpl)[0] == HEADINGS)
check("template States to cover is bullets only",
      all(re.fullmatch(r"- [a-z]+", l.strip()) for l in sections(tpl)[1]["States to cover"] if l.strip()))
check("no em dashes in skill files", chr(0x2014) not in skill and chr(0x2014) not in fix)

sys.exit(1 if fails else 0)
PY
