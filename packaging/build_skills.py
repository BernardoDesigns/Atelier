"""Assemble the claude.ai skill zips for eames and rand.

Run as: python3 -I build_skills.py <repo> <stage_dir> <dist_dir>

Each skill is a folder named after the skill. The folder holds SKILL.md,
taste.md and conventions.md, and is zipped to <dist_dir>/<name>.zip.
Zip entries share one fixed timestamp, fixed permissions, sorted order and
no extra fields, so two runs give identical bytes.

Both skills are staged before any zip is written. Each zip is first written
to <dest>.tmp and then moved into place with os.replace, so a failure never
leaves a truncated or mismatched pair in dist_dir.
"""

import json
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


def unquote(value):
    """Return the string a frontmatter value means. Quoted values are JSON strings."""
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    return value


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
    description = unquote(fields.get("description", ""))
    if not description:
        sys.exit(f"{path}: frontmatter has no description")
    if body and not body.endswith("\n"):
        body += "\n"
    # json.dumps output is a valid YAML double-quoted scalar, so colons,
    # hashes and quotes in the description survive.
    text = (
        "---\n"
        f"name: {name}\n"
        f"description: {json.dumps(description, ensure_ascii=False)}\n"
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


def write_zip(name, folder, dest_path):
    with open(dest_path, "wb") as raw:
        with zipfile.ZipFile(raw, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for filename in sorted(os.listdir(folder)):
                info = zipfile.ZipInfo(f"{name}/{filename}", date_time=ZIP_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = FILE_ATTR
                with open(os.path.join(folder, filename), "rb") as handle:
                    archive.writestr(info, handle.read())
    return dest_path


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: build_skills.py <repo> <stage_dir> <dist_dir>")
    _, repo, stage_root, dist_dir = argv
    os.makedirs(dist_dir, exist_ok=True)

    # Stage every skill before touching dist/.
    folders = {}
    for name in SKILLS:
        folders[name] = os.path.join(stage_root, name)
        stage_skill(repo, name, folders[name])

    # Write every zip to a .tmp file, then move them all into place.
    pairs = [
        (os.path.join(dist_dir, name + ".zip") + ".tmp", os.path.join(dist_dir, name + ".zip"), name)
        for name in SKILLS
    ]
    try:
        for tmp, _, name in pairs:
            write_zip(name, folders[name], tmp)
    except BaseException:
        for tmp, _, _ in pairs:
            if os.path.exists(tmp):
                os.remove(tmp)
        raise
    for tmp, dest, _ in pairs:
        os.replace(tmp, dest)
        print(dest)


if __name__ == "__main__":
    main(sys.argv)
