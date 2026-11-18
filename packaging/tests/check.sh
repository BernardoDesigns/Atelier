#!/usr/bin/env bash
# Checks for packaging/build.sh. Exits 0 only when every check passes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
build="$repo/packaging/build.sh"
dist="$repo/dist"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

echo "== frontmatter: model opus on all three commands"
for name in design-director eames rand; do
  python3 -I - "$repo/commands/$name.md" "$name" <<'PY' || fail "commands/$name.md frontmatter"
import sys

path, name = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines()
assert lines and lines[0] == "---", "no opening fence"
close = lines.index("---", 1)
fields = {}
for line in lines[1:close]:
    key, _, value = line.partition(":")
    fields[key.strip()] = value.strip()
assert fields.get("model") == "opus", "model is not opus"
assert fields.get("description"), "no description"
print(f"ok   {name}: model opus, description present")
PY
done

echo "== build (run 1)"
bash "$build" >/dev/null || fail "build run 1"
first="$(shasum -a 256 "$dist/eames.zip" "$dist/rand.zip")"

echo "== build (run 2)"
bash "$build" >/dev/null || fail "build run 2"
second="$(shasum -a 256 "$dist/eames.zip" "$dist/rand.zip")"

echo "== determinism"
if [ "$first" != "$second" ]; then
  echo "$first"
  echo "$second"
  fail "zips differ between runs"
fi
echo "ok   identical shasums across two runs"
echo "$second"

echo "== zip contents"
python3 -I - "$repo" "$dist" <<'PY' || fail "zip contents"
import os
import sys
import zipfile

repo, dist = sys.argv[1], sys.argv[2]
TAIL = (
    "This skill ships with `taste.md` (judgment, interpreted) and `conventions.md` "
    "(literal standards) in the same folder. Read them before design work."
)


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
        expected = [f"{name}/{f}" for f in ("SKILL.md", "conventions.md", "taste.md")]
        assert names == expected, f"{path}: entries {names}"
        assert all(not i.is_dir() for i in archive.infolist()), "directory entry"
        assert all(i.extra == b"" for i in archive.infolist()), "extra field"
        assert archive.comment == b"", "zip comment"

        skill = archive.read(f"{name}/SKILL.md").decode("utf-8")
        skill_fields, skill_body = split(skill)
        assert set(skill_fields) == {"name", "description"}, skill_fields
        assert skill_fields["name"] == name, skill_fields
        assert "model" not in skill_fields, "model key kept"

        command = open(os.path.join(repo, "commands", name + ".md"), encoding="utf-8").read()
        cmd_fields, cmd_body = split(command)
        assert skill_fields["description"] == cmd_fields["description"], "description drift"
        assert skill_body == cmd_body + "\n" + TAIL + "\n", "body is not command body plus tail"

        for shipped in ("taste.md", "conventions.md"):
            with open(os.path.join(repo, shipped), "rb") as handle:
                assert archive.read(f"{name}/{shipped}") == handle.read(), f"{shipped} differs"
    print(f"ok   {name}.zip: {', '.join(expected)}")
PY

echo "== nothing under dist/ is staged"
staged="$(git -C "$repo" diff --cached --name-only -- dist)"
[ -z "$staged" ] || fail "dist/ is staged: $staged"
echo "ok   no dist/ files staged"

echo "PASS packaging/tests/check.sh"
