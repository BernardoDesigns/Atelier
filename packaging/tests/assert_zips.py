"""Assertions on built skill zips. Run as: python3 -I assert_zips.py <repo> <dist_dir>

Kept apart from check.sh so the same checks can be pointed at any dist folder.
"""

import json
import os
import sys
import zipfile

repo, dist = sys.argv[1], sys.argv[2]
BUNDLED = ("taste.md", "conventions.md", "quality.md")
FORBIDDEN = ("~/.claude/", "/wrap", "/build", "figma-use", "Closing a Session", ".atelier/session.json")
TAIL = (
    "This skill ships with `taste.md` (judgment, interpreted), `conventions.md` "
    "(literal standards) and `quality.md` (the production bar) in the same folder. "
    "Read them before design work."
)


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


for name in ("eames", "rand"):
    path = os.path.join(dist, name + ".zip")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        expected = [f"{name}/{f}" for f in ("SKILL.md", "conventions.md", "quality.md", "taste.md")]
        assert names == expected, f"{path}: entries {names}, expected {expected}"
        assert all(not i.is_dir() for i in archive.infolist()), "directory entry"
        assert all(i.extra == b"" for i in archive.infolist()), "extra field"
        assert archive.comment == b"", "zip comment"

        skill = archive.read(f"{name}/SKILL.md").decode("utf-8")
        skill_fields, skill_body = split(skill)
        assert set(skill_fields) == {"name", "description"}, skill_fields
        assert skill_fields["name"] == name, skill_fields
        assert "model" not in skill_fields, "model key kept"

        command = open(os.path.join(repo, "commands", name + ".md"), encoding="utf-8").read()
        cmd_fields, _ = split(command)
        assert unquote(skill_fields["description"]) == unquote(cmd_fields["description"]), "description drift"
        assert skill_body.endswith("\n" + TAIL + "\n"), "tail missing or reworded"

        # Nothing that only exists in Claude Code may reach claude.ai.
        for needle in FORBIDDEN:
            assert needle not in skill, f"{name}/SKILL.md still contains {needle!r}"
        # The contract files are named as bare names, and they are in the zip.
        for bundled in BUNDLED:
            assert f"`{bundled}`" in skill, f"{name}/SKILL.md does not name {bundled}"
            assert f"{name}/{bundled}" in names, f"{bundled} not in zip"
            with open(os.path.join(repo, bundled), "rb") as handle:
                assert archive.read(f"{name}/{bundled}") == handle.read(), f"{bundled} differs"
        # No double rule and no blank-line pileup where the close section was.
        assert "---\n\n---" not in skill, "doubled rule"
        assert "\n\n\n" not in skill, "blank-line pileup"
    print(f"ok   {name}.zip: {', '.join(expected)}")
