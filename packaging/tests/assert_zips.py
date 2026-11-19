"""Assertions on built skill zips. Run as: python3 -I assert_zips.py <repo> <dist_dir>

Kept apart from check.sh so the same checks can be pointed at any dist folder.
Every failure is collected and printed before the script exits non-zero, so one
early failure never hides the others. Nothing here imports build_skills.py: the
expectations are computed independently.
"""

import json
import os
import re
import sys
import zipfile

repo, dist = sys.argv[1], sys.argv[2]
BUNDLED = ("taste.md", "conventions.md")
# None of this exists on claude.ai, so none of it may appear in a built SKILL.md.
LITERAL_SKILL = ("~/.claude/", "figma-use", "Closing a Session", ".atelier/session.json", "$ARGUMENTS")
# Bundled files get the same scan, with .atelier/ as a whole.
LITERAL_BUNDLED = ("~/.claude/", ".atelier/")
CONTRACT = (
    "**Contract files.** Before design work, read `taste.md` (judgment calls) "
    "and `conventions.md` (literal standards)."
)
# The one sentence the build removes from the bundled copies of taste.md and conventions.md.
DRAFT_SENTENCE = "Every item is a draft until `/taste-review` approves it."
failures = []


def slash_commands():
    """/<name> for every commands/*.md basename and every skills/<dir>."""
    names = set()
    commands = os.path.join(repo, "commands")
    names.update(f[:-3] for f in os.listdir(commands) if f.endswith(".md"))
    skills = os.path.join(repo, "skills")
    if os.path.isdir(skills):
        names.update(d for d in os.listdir(skills) if os.path.isdir(os.path.join(skills, d)))
    return sorted("/" + n for n in names)


SLASH = slash_commands()


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


def scan(label, text, literals):
    for number, line in enumerate(text.split("\n"), 1):
        for needle in literals:
            if needle in line:
                failures.append(f"{label}:{number} contains {needle!r}: {line.strip()[:100]}")
        for command in SLASH:
            # Whole token: backtick, whitespace or line start before; not a word or hyphen char after.
            if re.search(r"(?<![^\s`])" + re.escape(command) + r"(?![\w-])", line):
                failures.append(f"{label}:{number} contains slash command {command}: {line.strip()[:100]}")


def expected_bundled(source):
    """The source with the one documented removal: the draft sentence and its paragraph break."""
    assert DRAFT_SENTENCE + "\n\n" in source, "source has no draft sentence paragraph"
    return source.replace(DRAFT_SENTENCE + "\n\n", "", 1)


print(f"slash commands scanned for: {', '.join(SLASH)}")
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
        scan(f"{name}/SKILL.md", skill, LITERAL_SKILL)
        for bundled in BUNDLED:
            member = f"{name}/{bundled}"
            check(f"`{bundled}`" in skill, f"{name}/SKILL.md does not name {bundled}")
            check(member in names, f"{member} not in zip")
            if member in names:
                data = archive.read(member).decode("utf-8")
                with open(os.path.join(repo, bundled), encoding="utf-8", newline="") as handle:
                    want = expected_bundled(handle.read())
                check(data == want, f"{member} is not the source minus the draft sentence")
                check(DRAFT_SENTENCE not in data, f"{member} still has the draft sentence")
                check("\n\n\n" not in data, f"{member}: blank-line pileup")
                scan(member, data, LITERAL_BUNDLED)
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
            last = next((l for l in reversed(body.split("\n")) if l.strip()), "")
            check(last.strip() != "---", f"{name}/SKILL.md ends with a horizontal rule")
            check(body.endswith("\n") and not body.endswith("\n\n"), f"{name}/SKILL.md: bad file ending")
        check("---\n\n---" not in skill, f"{name}/SKILL.md: doubled rule")
        check("\n\n\n" not in skill, f"{name}/SKILL.md: blank-line pileup")

if failures:
    for message in failures:
        print(f"FAIL {message}")
    print(f"{len(failures)} assertion failure(s)")
    sys.exit(1)
print(f"ok   eames.zip, rand.zip: {', '.join(BUNDLED)} plus SKILL.md; translation clean")
