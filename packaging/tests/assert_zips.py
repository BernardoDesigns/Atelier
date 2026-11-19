"""Assertions on built skill zips. Run as: python3 -I assert_zips.py <repo> <dist_dir>

Kept apart from check.sh so the same checks can be pointed at any dist folder.
Every failure is collected and printed before the script exits non-zero, so one
early failure never hides the others.
"""

import json
import os
import sys
import zipfile

repo, dist = sys.argv[1], sys.argv[2]
BUNDLED = ("taste.md", "conventions.md")
# None of this exists on claude.ai, so none of it may appear in a built SKILL.md.
FORBIDDEN_SKILL = (
    "~/.claude/", "/wrap", "/build", "figma-use", "Closing a Session",
    ".atelier/session.json", "$ARGUMENTS",
)
# Bundled files get the same scan, with .atelier/ in place of the one session file.
FORBIDDEN_BUNDLED = ("~/.claude/", "/wrap", "/build", ".atelier/")
CONTRACT = (
    "**Contract files.** Before design work, read `taste.md` (judgment calls) "
    "and `conventions.md` (literal standards)."
)
TAIL = (
    "This skill ships with `taste.md` (judgment, interpreted) and `conventions.md` "
    "(literal standards) in the same folder. Read them before design work."
)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def unquote(value):
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    return value


def split(text):
    lines = text.splitlines(keepends=True)
    close = lines.index("---\n", 1)
    fields = {}
    for line in lines[1:close]:
        key, _, value = line.rstrip("\n").partition(":")
        fields[key.strip()] = value.strip()
    return fields, "".join(lines[close + 1:])


def scan(label, text, needles):
    for number, line in enumerate(text.split("\n"), 1):
        for needle in needles:
            if needle in line:
                failures.append(f"{label}:{number} contains {needle!r}: {line.strip()[:100]}")


for name in ("eames", "rand"):
    path = os.path.join(dist, name + ".zip")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        expected = [f"{name}/{f}" for f in ("SKILL.md", "conventions.md", "taste.md")]
        check(names == expected, f"{path}: entries {names}, expected {expected}")
        check(all(not i.is_dir() for i in archive.infolist()), f"{name}.zip: directory entry")
        check(all(i.extra == b"" for i in archive.infolist()), f"{name}.zip: extra field")
        check(archive.comment == b"", f"{name}.zip: zip comment")

        skill = archive.read(f"{name}/SKILL.md").decode("utf-8")
        scan(f"{name}/SKILL.md", skill, FORBIDDEN_SKILL)
        for bundled in BUNDLED:
            member = f"{name}/{bundled}"
            check(f"`{bundled}`" in skill, f"{name}/SKILL.md does not name {bundled}")
            check(member in names, f"{member} not in zip")
            if member in names:
                data = archive.read(member)
                with open(os.path.join(repo, bundled), "rb") as handle:
                    check(data == handle.read(), f"{member} differs from {bundled}")
                scan(member, data.decode("utf-8"), FORBIDDEN_BUNDLED)
        check(not any(n.endswith("/quality.md") for n in names), f"{name}.zip bundles quality.md")
        check("quality.md" not in skill, f"{name}/SKILL.md mentions quality.md")
        check(CONTRACT in skill, f"{name}/SKILL.md lacks the exact Contract files sentence")

        try:
            fields, body = split(skill)
        except ValueError:
            failures.append(f"{name}/SKILL.md: frontmatter not parsable")
        else:
            check(set(fields) == {"name", "description"}, f"{name}: frontmatter keys {sorted(fields)}")
            check(fields.get("name") == name, f"{name}: frontmatter name {fields.get('name')!r}")
            command = open(os.path.join(repo, "commands", name + ".md"), encoding="utf-8").read()
            cmd_fields, _ = split(command)
            check(unquote(fields.get("description", "")) == unquote(cmd_fields["description"]), f"{name}: description drift")
            check(body.endswith("\n" + TAIL + "\n"), f"{name}/SKILL.md: tail missing or reworded")
            # The file must not end on a horizontal rule: the last non-blank line
            # before the tail is not a rule.
            before_tail = body[: body.rfind(TAIL)] if TAIL in body else body
            last = next((l for l in reversed(before_tail.split("\n")) if l.strip()), "")
            check(last.strip() != "---", f"{name}/SKILL.md ends with a horizontal rule before the tail")
        check("---\n\n---" not in skill, f"{name}/SKILL.md: doubled rule")
        check("\n\n\n" not in skill, f"{name}/SKILL.md: blank-line pileup")

if failures:
    for message in failures:
        print(f"FAIL {message}")
    print(f"{len(failures)} assertion failure(s)")
    sys.exit(1)
print(f"ok   eames.zip, rand.zip: {', '.join(BUNDLED)} plus SKILL.md; translation clean")
