"""Negative build tests. Run as: python3 -I negative_build.py <repo> <build_skills.py>

Each case builds from a temp copy of the commands folder whose eames.md was
reworded, and expects the build to exit non-zero with a message naming the cause.
"""

import os
import subprocess
import sys
import tempfile

repo, helper = sys.argv[1], sys.argv[2]


def build(mutate):
    tmp = tempfile.mkdtemp(prefix="atelier-pack-neg-")
    os.makedirs(os.path.join(tmp, "commands"))
    for name in ("eames", "rand"):
        with open(os.path.join(repo, "commands", name + ".md"), encoding="utf-8") as handle:
            text = handle.read()
        if name == "eames":
            text = mutate(text)
        with open(os.path.join(tmp, "commands", name + ".md"), "w", encoding="utf-8") as handle:
            handle.write(text)
    for shipped in ("taste.md", "conventions.md"):
        with open(os.path.join(repo, shipped), "rb") as src, open(os.path.join(tmp, shipped), "wb") as dst:
            dst.write(src.read())
    stage = tempfile.mkdtemp(prefix="atelier-pack-stage-")
    dist = tempfile.mkdtemp(prefix="atelier-pack-dist-")
    proc = subprocess.run([sys.executable, "-I", helper, tmp, stage, dist], capture_output=True, text=True)
    return proc.returncode, proc.stderr + proc.stdout, dist


def expect_fail(label, mutate, needle):
    code, out, dist = build(mutate)
    assert code != 0, f"{label}: build succeeded"
    assert needle in out, f"{label}: message lacks {needle!r}: {out!r}"
    assert not os.listdir(dist), f"{label}: dist not empty after failure"
    print(f"ok   {label}: build exits {code}, message names {needle!r}")


expect_fail(
    "unbundled contract file elsewhere in the body",
    lambda t: t.replace("## Working Style", "Also read `~/.claude/atelier/failures.md`.\n\n## Working Style"),
    "failures.md",
)
expect_fail(
    "quality.md named elsewhere in the body",
    lambda t: t.replace("## Working Style", "Also read `~/.claude/atelier/quality.md`.\n\n## Working Style"),
    "quality.md",
)
expect_fail(
    "contract sentence reworded",
    lambda t: t.replace("(the production bar)", "(the bar)"),
    "three-file shape",
)
expect_fail(
    "contract sentence lost a file",
    lambda t: t.replace(" and `~/.claude/atelier/quality.md` (the production bar)", ""),
    "three-file shape",
)
expect_fail(
    "user request section renamed",
    lambda t: t.replace("## User Request", "## Request"),
    "User Request",
)
expect_fail(
    "close section renamed",
    lambda t: t.replace("## Closing a Session", "## Wrapping Up"),
    "Closing a Session",
)
expect_fail(
    "figma hint reworded",
    lambda t: t.replace("(load the `figma-use` skill first)", "(see the figma-use skill)"),
    "figma-use",
)
expect_fail(
    "slash command left in body",
    lambda t: t.replace("## Working Style", "Run /build next.\n\n## Working Style"),
    "/build",
)
code, out, _ = build(lambda t: t)
assert code == 0, out
print("ok   unmodified sources still build")
