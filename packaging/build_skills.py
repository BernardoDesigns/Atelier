"""Assemble the claude.ai skill zips for eames and rand.

Run as: python3 -I build_skills.py <repo> <stage_dir> <dist_dir>

Each skill is a folder named after the skill. The folder holds SKILL.md,
taste.md and conventions.md, and is zipped to <dist_dir>/<name>.zip.

commands/*.md are written for Claude Code. This build owns the translation to
claude.ai skills: see the translate_* functions below. A translation that finds
nothing to change in a command that should have it fails the build, so a
reworded command cannot silently ship untranslated text.
Zip entries share one fixed timestamp, fixed permissions, sorted order and
no extra fields, so two runs give identical bytes.

Both skills are staged before any zip is written. Each zip is first written
to <dest>.tmp and then moved into place with os.replace, so a failure never
leaves a truncated or mismatched pair in dist_dir.
"""

import json
import os
import re
import sys
import zipfile

SKILLS = ("eames", "rand")
SHIPPED = ("conventions.md", "taste.md")
ZIP_TIME = (2026, 11, 18, 0, 0, 0)
FILE_ATTR = 0o100644 << 16

# Nothing below may survive into a built SKILL.md: none of it exists on claude.ai.
# Slash commands are added by forbidden_slash_commands(): every command and
# skill name in the repo, matched as a whole token.
FORBIDDEN_SKILL = (
    "~/.claude/",
    "figma-use",
    "Closing a Session",
    ".atelier/session.json",
    "$ARGUMENTS",
)
# The bundled files get the same scan, with .atelier/ as a whole.
FORBIDDEN_BUNDLED = ("~/.claude/", ".atelier/")

# taste.md and conventions.md say this on line 5. It is true in Claude Code and
# not on claude.ai, where /taste-review does not exist. Sources keep it; the
# bundled copies lose exactly this sentence.
DRAFT_SENTENCE = "Every item is a draft until `/taste-review` approves it."

# The Contract files sentence as the command sources word it today. quality.md
# is the production bar for the Claude Code build loop (gates on .atelier files,
# /wrap, the render harness) and is not bundled, so its mention is stripped.
CONTRACT_SOURCE = (
    "**Contract files.** Before design work, read `~/.claude/atelier/taste.md` (judgment calls), "
    "`~/.claude/atelier/conventions.md` (literal standards) and `~/.claude/atelier/quality.md` "
    "(the production bar)."
)
CONTRACT_BUILT = (
    "**Contract files.** Before design work, read `taste.md` (judgment calls) "
    "and `conventions.md` (literal standards)."
)
USER_REQUEST_HEADING = "## User Request"
USER_REQUEST_BODY = "$ARGUMENTS"

CONTRACT_PATH = re.compile(r"~/\.claude/atelier/([A-Za-z0-9_.-]+)")
FIGMA_SKILL_HINT = " (load the `figma-use` skill first)"
FIGMA_REPLACEMENT = " when the tool is available"
CLOSE_HEADING = "## Closing a Session"


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


def translate_contract_sentence(body, label):
    """Targets: the "**Contract files.** Before design work, read ..." sentence.

    The source names three files under ~/.claude/atelier/. Two are bundled and
    get bare names. The third, quality.md, is dropped from the sentence. The
    exact three-file shape is required, so a reworded sentence fails the build
    instead of shipping untranslated.
    """
    if CONTRACT_SOURCE not in body:
        sys.exit(f"{label}: the Contract files sentence no longer has the expected three-file shape (taste.md, conventions.md, quality.md under ~/.claude/atelier/); update build_skills.py")
    return body.replace(CONTRACT_SOURCE, CONTRACT_BUILT)


def check_contract_paths(body, label):
    """Targets: any other ~/.claude/atelier/<file> mention left in the body.

    A bundled file is rewritten to its bare name. Anything else, quality.md
    included, fails the build rather than shipping a dangling pointer.
    """
    for filename in CONTRACT_PATH.findall(body):
        if filename not in SHIPPED:
            sys.exit(f"{label}: names ~/.claude/atelier/{filename}, which is not bundled (shipped: {', '.join(SHIPPED)}). Bundle it or drop the mention.")
    return CONTRACT_PATH.sub(lambda m: m.group(1), body)


def translate_session_close(body, label):
    """Targets: the "## Closing a Session" section ("Close the session with `/wrap`...").

    /wrap is a Claude Code command. The whole section goes, from its heading up
    to the next "## " heading. That span includes the rule that closes the
    section, so the rule before the heading stays as the only separator.
    """
    lines = body.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if l.rstrip("\r\n") == CLOSE_HEADING), None)
    if start is None:
        sys.exit(f"{label}: no '{CLOSE_HEADING}' section to drop; the command was reworded, update build_skills.py")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), None)
    if end is None:
        # Last section: drop to the end, and the rule that opened it.
        kept = lines[:start]
        while kept and kept[-1].strip() in ("", "---"):
            kept.pop()
        return "".join(kept) + "\n"
    return "".join(lines[:start] + lines[end:])


def translate_figma_skill_hint(body, label):
    """Targets: "Use `use_figma` ... (load the `figma-use` skill first)".

    figma-use is a Claude Code plugin skill. Keep the instruction to use the
    Figma tools, tied to their being available, and drop the skill pointer.
    """
    if FIGMA_SKILL_HINT not in body:
        sys.exit(f"{label}: no '{FIGMA_SKILL_HINT.strip()}' text to translate; the command was reworded, update build_skills.py")
    return body.replace(FIGMA_SKILL_HINT, FIGMA_REPLACEMENT)


def translate_user_request(body, label):
    """Targets: the trailing "## User Request" section whose body is `$ARGUMENTS`.

    $ARGUMENTS is a Claude Code substitution; on claude.ai it would ship as a
    literal. The section goes to the end of the file, along with the rule that
    sat before it, so the file does not end on a dangling rule.
    """
    lines = body.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if l.rstrip("\r\n") == USER_REQUEST_HEADING), None)
    if start is None:
        sys.exit(f"{label}: no '{USER_REQUEST_HEADING}' section to drop; the command was reworded, update build_skills.py")
    section = "".join(lines[start + 1:]).strip()
    if section != USER_REQUEST_BODY:
        sys.exit(f"{label}: '{USER_REQUEST_HEADING}' holds more than {USER_REQUEST_BODY}: {section[:60]!r}; refusing to drop it, update build_skills.py")
    kept = lines[:start]
    while kept and kept[-1].strip() in ("", "---"):
        kept.pop()
    return "".join(kept).rstrip("\n") + "\n"


def translate_draft_sentence(text, label):
    """Targets: "Every item is a draft until `/taste-review` approves it." in taste.md and conventions.md.

    Removes that sentence only. It sits as its own paragraph, so the paragraph
    break after it goes too, leaving one blank line between neighbours.
    """
    if DRAFT_SENTENCE not in text:
        sys.exit(f"{label}: the sentence {DRAFT_SENTENCE!r} is not there to remove; the file was reworded, update build_skills.py")
    if DRAFT_SENTENCE + "\n\n" in text:
        return text.replace(DRAFT_SENTENCE + "\n\n", "", 1)
    if " " + DRAFT_SENTENCE in text:
        return text.replace(" " + DRAFT_SENTENCE, "", 1)
    return text.replace(DRAFT_SENTENCE, "", 1)


def forbidden_slash_commands(repo):
    """Every slash command that does not exist on claude.ai: each commands/*.md
    basename and each skills/<dir> name, as '/<name>'."""
    names = set()
    commands = os.path.join(repo, "commands")
    if os.path.isdir(commands):
        names.update(f[:-3] for f in os.listdir(commands) if f.endswith(".md"))
    skills = os.path.join(repo, "skills")
    if os.path.isdir(skills):
        names.update(d for d in os.listdir(skills) if os.path.isdir(os.path.join(skills, d)))
    return sorted("/" + n for n in names)


def scan_forbidden(text, literals, slash_names, label):
    """Fail on any literal, or any slash command as a whole token: a backtick,
    whitespace or line start before the slash, and a non-word, non-hyphen
    character or line end after the name."""
    for needle in literals:
        if needle in text:
            sys.exit(f"{label}: contains {needle!r}, which does not exist on claude.ai")
    for command in slash_names:
        pattern = r"(?<![^\s`])" + re.escape(command) + r"(?![\w-])"
        if re.search(pattern, text):
            sys.exit(f"{label}: contains the slash command {command}, which does not exist on claude.ai")


def translate_body(body, label):
    body = translate_contract_sentence(body, label)
    body = check_contract_paths(body, label)
    body = translate_session_close(body, label)
    body = translate_user_request(body, label)
    body = translate_figma_skill_hint(body, label)
    return body


def skill_md(repo, name):
    path = os.path.join(repo, "commands", name + ".md")
    fields, body = split_frontmatter(read_text(path), path)
    description = unquote(fields.get("description", ""))
    if not description:
        sys.exit(f"{path}: frontmatter has no description")
    body = translate_body(body, path)
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
    )
    scan_forbidden(text, FORBIDDEN_SKILL, forbidden_slash_commands(repo), f"{path} (built SKILL.md)")
    return text.encode("utf-8")


def stage_skill(repo, name, folder):
    os.makedirs(folder, exist_ok=False)
    with open(os.path.join(folder, "SKILL.md"), "wb") as handle:
        handle.write(skill_md(repo, name))
    for shipped in SHIPPED:
        source = os.path.join(repo, shipped)
        text = translate_draft_sentence(read_text(source), source)
        scan_forbidden(text, FORBIDDEN_BUNDLED, forbidden_slash_commands(repo), f"{source} (bundled copy)")
        with open(os.path.join(folder, shipped), "wb") as handle:
            handle.write(text.encode("utf-8"))


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
