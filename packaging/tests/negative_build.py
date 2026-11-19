"""Negative build tests. Run as: python3 -I negative_build.py <repo> <build_skills.py>

Each case builds from a temp copy of the repo's commands folder (with eames.md
or taste.md reworded) and expects the build to exit non-zero with a message
naming the cause. Temp dirs are TemporaryDirectory, so none are left behind.
"""

import os
import subprocess
import sys
import tempfile

repo, helper = sys.argv[1], sys.argv[2]


def read(*parts):
    with open(os.path.join(repo, *parts), encoding="utf-8", newline="") as handle:
        return handle.read()


def build(mutate_eames=lambda t: t, mutate_taste=lambda t: t):
    """Returns (exit code, output, files left in dist)."""
    with tempfile.TemporaryDirectory(prefix="atelier-pack-neg-") as root:
        src = os.path.join(root, "src")
        os.makedirs(os.path.join(src, "commands"))
        # Same command and skill names as the repo, so the slash-command list matches.
        for f in os.listdir(os.path.join(repo, "commands")):
            if f.endswith(".md"):
                text = read("commands", f)
                if f == "eames.md":
                    text = mutate_eames(text)
                with open(os.path.join(src, "commands", f), "w", encoding="utf-8", newline="") as handle:
                    handle.write(text)
        for d in os.listdir(os.path.join(repo, "skills")):
            if os.path.isdir(os.path.join(repo, "skills", d)):
                os.makedirs(os.path.join(src, "skills", d))
        for shipped in ("taste.md", "conventions.md"):
            text = read(shipped)
            if shipped == "taste.md":
                text = mutate_taste(text)
            with open(os.path.join(src, shipped), "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
        stage = os.path.join(root, "stage")
        dist = os.path.join(root, "dist")
        os.makedirs(stage)
        os.makedirs(dist)
        proc = subprocess.run([sys.executable, "-I", helper, src, stage, dist], capture_output=True, text=True)
        return proc.returncode, proc.stderr + proc.stdout, os.listdir(dist)


def expect_fail(label, needle, **mutations):
    code, out, left = build(**mutations)
    assert code != 0, f"{label}: build succeeded"
    assert needle in out, f"{label}: message lacks {needle!r}: {out!r}"
    assert not left, f"{label}: dist not empty after failure: {left}"
    print(f"ok   {label}: build exits {code}, message names {needle!r}")


def in_working_style(line):
    return lambda t: t.replace("## Working Style", line + "\n\n## Working Style")


expect_fail(
    "unbundled contract file elsewhere in the body", "failures.md",
    mutate_eames=in_working_style("Also read `~/.claude/atelier/failures.md`."),
)
expect_fail(
    "quality.md named elsewhere in the body", "quality.md",
    mutate_eames=in_working_style("Also read `~/.claude/atelier/quality.md`."),
)
expect_fail(
    "contract sentence reworded", "three-file shape",
    mutate_eames=lambda t: t.replace("(the production bar)", "(the bar)"),
)
expect_fail(
    "contract sentence lost a file", "three-file shape",
    mutate_eames=lambda t: t.replace(" and `~/.claude/atelier/quality.md` (the production bar)", ""),
)
expect_fail(
    "user request section renamed", "User Request",
    mutate_eames=lambda t: t.replace("## User Request", "## Request"),
)
expect_fail(
    "user request section holds more than $ARGUMENTS", "holds more than",
    mutate_eames=lambda t: t.rstrip("\n") + "\n\n## Extra\n\nSome real text.\n",
)
expect_fail(
    "close section renamed", "Closing a Session",
    mutate_eames=lambda t: t.replace("## Closing a Session", "## Wrapping Up"),
)
expect_fail(
    "figma hint reworded", "figma-use",
    mutate_eames=lambda t: t.replace("(load the `figma-use` skill first)", "(see the figma-use skill)"),
)
expect_fail(
    "/build left in body", "/build",
    mutate_eames=in_working_style("Run /build next."),
)
expect_fail(
    "/spec handoff left in body", "/spec",
    mutate_eames=in_working_style("Then hand off to `/spec`."),
)
expect_fail(
    "bundled taste.md without the draft sentence", "is not there to remove",
    mutate_taste=lambda t: t.replace("Every item is a draft until `/taste-review` approves it.\n\n", ""),
)

# Whole-token matching: a path or URL that contains a command name is fine.
code, out, _ = build(mutate_eames=in_working_style("See dist/build and https://example.com/build/log."))
assert code == 0, f"path containing build was flagged: {out}"
print("ok   'dist/build' and a URL with /build/ are not flagged")
code, out, _ = build()
assert code == 0, out
print("ok   unmodified sources still build")
