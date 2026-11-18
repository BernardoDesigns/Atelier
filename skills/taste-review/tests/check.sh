#!/usr/bin/env bash
# skills/taste-review/tests/check.sh
#
# What this proves: the skill's instructions are complete. SKILL.md contains
# every step, option and rule the review needs, the contract files and
# state.json are well formed, and a reference reducer (the same rules the skill
# states in prose) replays a recorded five-answer session over a fixture and
# produces the expected state, summary and file changes.
# What it does not prove: that the model follows the instructions. Watching one
# real run covers that.
#
# Run: bash skills/taste-review/tests/check.sh   (python3 standard library only)

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

exec python3 -B -I - "$ROOT" "$HERE" <<'PY'
import importlib.util, json, re, sys

root, here = sys.argv[1], sys.argv[2]
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

spec = importlib.util.spec_from_file_location("gen_state", here + "/gen-state.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

# ---------- 1. the contract files ----------
TAGS = {"principle", "spec-convention", "plan"}
def tag_ok(t):
    return t in TAGS or re.fullmatch(r"log:[A-Z]+\d+", t) is not None

for name, prefix in (("taste.md", "T"), ("conventions.md", "C"), ("failures.md", "F")):
    items = gen.parse_blocks(name, read(root + "/" + name))
    nums = [int(i["id"][1:]) for i in items]
    check(name + " item numbers are unique and increasing", nums == sorted(set(nums)) and len(nums) > 0)
    bad = [i["id"] for i in items
           if not i["fields"].get("Source")
           or not all(tag_ok(t.strip()) for t in i["fields"]["Source"].split(","))]
    check(name + " every item has a valid source tag", not bad, str(bad))
    bad = [i["id"] for i in items if i["fields"].get("Status") not in ("draft", "approved")]
    check(name + " every item has Status draft or approved", not bad, str(bad))
    need = {"taste.md": ["Applied as"], "conventions.md": ["Check"],
            "failures.md": ["Name", "Trap", "Shows up as", "Instead"]}[name]
    bad = [i["id"] for i in items if any(not i["fields"].get(f) for f in need)]
    check(name + " every item has " + ", ".join(need), not bad, str(bad))

q = gen.parse_quality(read(root + "/quality.md"))
ids = [i["id"] for i in q]
check("quality.md has G1 to G10 and P1 to P5",
      ids == ["G%d" % n for n in range(1, 11)] + ["P%d" % n for n in range(1, 6)], str(ids))

# ---------- 2. state.json ----------
state = json.loads(read(root + "/taste-review/state.json"))
STATUS = {"pending", "approved", "edited", "rewritten", "cut", "skipped"}
check("state.json version is 1", state.get("version") == 1)
check("state.json files list is the four contract files", state.get("files") == gen.FILES)
items = state.get("items", {})
def entry_ok(k, e):
    return (re.fullmatch(r"[a-z]+\.md#[A-Z]\d+", k) is not None
            and set(e) - {"fields"} == {"status", "text", "updated"}
            and e["status"] in STATUS
            and (e["text"] is None or isinstance(e["text"], str))
            and (e["updated"] is None or re.fullmatch(r"\d{4}-\d{2}-\d{2}.*", e["updated"]) is not None)
            and (("fields" not in e) or isinstance(e["fields"], dict)))
bad = [k for k, e in items.items() if not entry_ok(k, e)]
check("state.json entries match the schema", not bad, str(bad[:5]))

found = [i["key"] for i in gen.parse_all(root)]
extra = [k for k in items if k not in found]
missing = [k for k in found if k not in items]
check("state.json has every ID the generator finds", not missing, str(missing[:5]))
check("state.json extras are cut items only", all(items[k]["status"] == "cut" for k in extra), str(extra[:5]))
untouched = all(e["status"] == "pending" and e["text"] is None and e["updated"] is None for e in items.values())
if untouched:
    check("state.json has exactly the generator's IDs, all pending", sorted(items) == sorted(found))
    check("state.json matches generator output byte for byte",
          read(root + "/taste-review/state.json").rstrip("\n") == json.dumps(gen.initial_state(root), indent=2))
else:
    print("PASS state.json already in use (review started), exact-match checks skipped")

# ---------- 3. reference reducers over the fixture ----------
FIX = here + "/fixture"
ACTION = {"approve": "approved", "edit": "edited", "rewrite": "rewritten", "cut": "cut", "skip": "skipped"}

def replay(state, session_text, today="2026-01-01"):
    """Serve the first pending item, apply the answer, as SKILL.md steps 6 to 8 say."""
    for line in session_text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        head, _, text = line.partition("|")
        key, action = head.split()
        first = next(k for k, e in state["items"].items() if e["status"] == "pending")
        assert first == key, "answer for %s but first pending is %s" % (key, first)
        e = state["items"][key]
        e["status"] = ACTION[action]
        e["text"] = text.strip() if text.strip() else None
        e["updated"] = today
    return state

def summary(state):
    c = {s: 0 for s in ("approved", "edited", "rewritten", "cut", "skipped", "pending")}
    for e in state["items"].values():
        c[e["status"]] += 1
    return c

def set_row(line, text, status):
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if text is not None:
        cells[2] = text
    cells[-1] = status
    return "| " + " | ".join(cells) + " |"

def apply_decisions(name, text, state):
    """SKILL.md step 11: flip status, replace wording, remove cuts and keep the numbering gaps."""
    lines = text.split("\n")
    its = gen.parse_quality(text) if name == "quality.md" else gen.parse_blocks(name, text)
    for it in reversed(its):
        e = state["items"].get(it["key"])
        if not e:
            continue
        if e["status"] == "cut":
            del lines[it["start"]:it["end"]]
        elif e["status"] in ("approved", "edited", "rewritten"):
            if name == "quality.md":
                lines[it["start"]] = set_row(lines[it["start"]], e["text"], "approved")
                continue
            done_main = False
            for n in range(it["start"] + 1, it["end"]):
                l = lines[n]
                if l == "Status: draft":
                    lines[n] = "Status: approved"
                    continue
                m = gen.FIELD.match(l)
                if m and m.group(1) in e.get("fields", {}):
                    lines[n] = m.group(1) + ": " + e["fields"][m.group(1)]
                    continue
                is_main = (m and m.group(1) == "Trap") if name == "failures.md" else (not m and l.strip())
                if is_main and not done_main:
                    done_main = True
                    if e["text"] is not None:
                        lines[n] = ("Trap: " + e["text"]) if name == "failures.md" else e["text"]
    return "\n".join(lines)

fixstate = gen.initial_state(FIX)
check("fixture state lists six items, all pending",
      len(fixstate["items"]) == 6 and all(e["status"] == "pending" for e in fixstate["items"].values()),
      str(list(fixstate["items"])))

session = read(FIX + "/session")
answers = [l for l in session.splitlines() if l.strip() and not l.startswith("#")]
check("recorded session has five answers, one of each option",
      len(answers) == 5 and {ACTION[l.partition("|")[0].split()[1]] for l in answers}
      == {"approved", "edited", "rewritten", "cut", "skipped"})

try:
    done = replay(fixstate, session)
    check("replay serves items in file order", True)
except AssertionError as ex:
    done = None
    check("replay serves items in file order", False, str(ex))

if done:
    it = done["items"]
    check("approve is recorded", it["quality.md#G1"]["status"] == "approved")
    check("edit keeps the final wording",
          it["quality.md#P1"]["status"] == "edited"
          and it["quality.md#P1"]["text"] == "Every element earns its place, and cutting is the default.")
    check("cut is recorded", it["taste.md#T1"]["status"] == "cut")
    check("rewrite keeps the final wording",
          it["taste.md#T2"]["status"] == "rewritten"
          and it["taste.md#T2"]["text"] == "Name every state in the words a user would say.")
    check("skip is recorded", it["conventions.md#C1"]["status"] == "skipped")
    check("every answer is dated", all(it[k]["updated"] for k in list(it)[:5]))
    nxt = next(k for k, e in it.items() if e["status"] == "pending")
    check("resume picks the first pending item", nxt == "failures.md#F1", nxt)
    s = summary(done)
    printed = "approved %d, edited %d, rewritten %d, cut %d, skipped %d" % (
        s["approved"], s["edited"], s["rewritten"], s["cut"], s["skipped"])
    print("     summary: " + printed + " (pending %d)" % s["pending"])
    check("summary counts are 1, 1, 1, 1, 1", printed == "approved 1, edited 1, rewritten 1, cut 1, skipped 1")

    out = {n: apply_decisions(n, read(FIX + "/" + n), done) for n in gen.FILES}
    check("apply: approved gate flips to approved", re.search(r"^\| G1 .*\| approved \|$", out["quality.md"], re.M) is not None)
    check("apply: edited principle gets the final wording and approved",
          re.search(r"^\| P1 \| Restraint \| Every element earns its place, and cutting is the default\. \| approved \|$",
                    out["quality.md"], re.M) is not None)
    check("apply: cut item is removed and its number is not reused",
          "### T1" not in out["taste.md"] and "### T2" in out["taste.md"])
    check("apply: rewritten item has the final wording and approved",
          "Name every state in the words a user would say." in out["taste.md"]
          and "Name states in plain words." not in out["taste.md"]
          and out["taste.md"].count("Status: approved") == 1)
    check("apply: skipped item stays draft", "Status: draft" in out["conventions.md"] and "approved" not in out["conventions.md"])
    check("apply: pending item stays draft", "Status: draft" in out["failures.md"] and "approved" not in out["failures.md"])
    check("apply: other fields are untouched",
          "Check: Does every icon button have an accessible name?" in out["conventions.md"]
          and "Verify: that the label pattern" in out["conventions.md"])

# ---------- 4. SKILL.md text ----------
skill = read(here + "/../SKILL.md")
fm = re.match(r"^---\n(.*?)\n---\n", skill, flags=re.S)
check("SKILL.md has name and description frontmatter",
      bool(fm) and re.search(r"^name: taste-review$", fm.group(1), re.M) is not None
      and re.search(r"^description: \S", fm.group(1), re.M) is not None)
opts = re.search(r"## The five options\n(.*?)\n## ", skill, re.S).group(1)
names = re.findall(r"^\d\. \*\*(.+?)\.?\*\*", opts, re.M)
check("SKILL.md lists exactly the five options", names == ["Approve", "Edit", "Rewrite", "Cut", "Skip for now"], str(names))
steps = skill.split("## Steps", 1)[1]
nums = [int(n) for n in re.findall(r"^(\d+)\. ", steps, re.M)]
check("SKILL.md steps are numbered 1 to N without gaps", nums == list(range(1, len(nums) + 1)), str(nums))
for label, needle in [
    ("fetches origin", "git -C ATELIER fetch origin"),
    ("reuses an existing taste-review worktree", "refs/heads/taste-review"),
    ("checks the remote for the branch", "ls-remote --exit-code --heads origin taste-review"),
    ("resumes from the remote branch on a second machine", "worktree add -b taste-review ~/LocalDev/atelier-worktrees/taste-review origin/taste-review"),
    ("creates the branch from current main", "origin/main"),
    ("pulls the remote branch", "pull --ff-only origin taste-review"),
    ("writes state after every answer", "After EVERY answer"),
    ("commits state.json by file name", "git -C WT add taste-review/state.json"),
    ("pushes after every answer", "push -u origin taste-review"),
    ("never edits the live checkout", "Never edit, stage or commit anything in its working tree"),
    ("works only under the worktree", "happens under `WT`"),
    ("opens one pull request", "ONE pull request"),
    ("uses gh pr create against main", "gh pr create --base main --head taste-review"),
    ("never merges", "Never merge it"),
    ("leaves numbering gaps on Cut", "Leave the numbering gap"),
    ("does not renumber", "Do not renumber"),
    ("Skip leaves drafts", "Skip and pending: leave the item as it is, `draft`"),
    ("summary before apply", "Do not touch any contract file before the summary is confirmed"),
    ("serves Verify lines", "Verify before approving"),
    ("serves Check lines for conventions", "`Check:`"),
    ("covers G and P IDs", "G1 to G10"),
    ("state key format", "`<file>#<id>`"),
    ("schema documented", "\"status\": \"pending | approved | edited | rewritten | cut | skipped\""),
    ("generator referenced", "gen-state.py"),
]:
    check("SKILL.md " + label, needle in skill, needle)
check("SKILL.md never stages everything", "git add -A" not in skill and "git add ." not in skill)
check("SKILL.md never uses rm", re.search(r"\brm\b", skill) is None)
check("no em dashes in SKILL.md", chr(0x2014) not in skill)

sys.exit(1 if fails else 0)
PY
