"""Assemble the claude.ai skill zips for eames and rand.

Run as: python3 -I build_skills.py <repo> <stage_dir> <dist_dir>

Each skill is a folder named after the skill. The folder holds SKILL.md,
taste.md and conventions.md, and is zipped to <dist_dir>/<name>.zip.
Zip entries share one fixed timestamp, fixed permissions, sorted order and
no extra fields, so two runs give identical bytes.
"""

import os
import sys
import zipfile

SKILLS = ("eames", "rand")
SHIPPED = ("conventions.md", "taste.md")
ZIP_TIME = (2026, 11, 18, 0, 0, 0)
FILE_ATTR = 0o100644 << 16
TAIL = (
    "This skill ships with `taste.md` (judgment, interpreted) and `conventions.md` "
    "(literal standards) in the same folder. Read them before design work."
)


def read_text(path):
    with open(path, encoding="utf-8", newline="") as handle:
        return handle.read()


def read_bytes(path):
    with open(path, "rb") as handle:
        return handle.read()


def split_frontmatter(text, path):
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        sys.exit(f"{path}: missing opening frontmatter fence")
    close = None
    for index in range(1, len(lines)):
        if lines[index].rstrip("\r\n") == "---":
            close = index
            break
    if close is None:
        sys.exit(f"{path}: missing closing frontmatter fence")
    fields = {}
    for line in lines[1:close]:
        key, sep, value = line.rstrip("\r\n").partition(":")
        if not sep:
            sys.exit(f"{path}: unparsable frontmatter line: {line!r}")
        fields[key.strip()] = value.strip()
    return fields, "".join(lines[close + 1:])


def skill_md(repo, name):
    path = os.path.join(repo, "commands", name + ".md")
    fields, body = split_frontmatter(read_text(path), path)
    description = fields.get("description", "")
    if not description:
        sys.exit(f"{path}: frontmatter has no description")
    if body and not body.endswith("\n"):
        body += "\n"
    text = (
        "---\n"
        f"name: {name}\n"
        f"description: {description}\n"
        "---\n"
        + body
        + "\n"
        + TAIL
        + "\n"
    )
    return text.encode("utf-8")


def stage_skill(repo, name, folder):
    os.makedirs(folder, exist_ok=False)
    with open(os.path.join(folder, "SKILL.md"), "wb") as handle:
        handle.write(skill_md(repo, name))
    for shipped in SHIPPED:
        with open(os.path.join(folder, shipped), "wb") as handle:
            handle.write(read_bytes(os.path.join(repo, shipped)))


def write_zip(name, folder, dist_dir):
    dest = os.path.join(dist_dir, name + ".zip")
    # "wb" truncates an existing zip, so each run overwrites in place.
    with open(dest, "wb") as raw:
        with zipfile.ZipFile(raw, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for filename in sorted(os.listdir(folder)):
                info = zipfile.ZipInfo(f"{name}/{filename}", date_time=ZIP_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = FILE_ATTR
                with open(os.path.join(folder, filename), "rb") as handle:
                    archive.writestr(info, handle.read())
    return dest


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: build_skills.py <repo> <stage_dir> <dist_dir>")
    _, repo, stage_root, dist_dir = argv
    os.makedirs(dist_dir, exist_ok=True)
    for name in SKILLS:
        folder = os.path.join(stage_root, name)
        stage_skill(repo, name, folder)
        print(write_zip(name, folder, dist_dir))


if __name__ == "__main__":
    main(sys.argv)
