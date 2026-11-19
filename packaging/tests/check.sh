#!/usr/bin/env bash
# Checks for packaging/build.sh. Exits 0 only when every check passes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
build="$repo/packaging/build.sh"
helper="$repo/packaging/build_skills.py"
dist="$repo/dist"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

# sha256 of each zip via hashlib, so the test does not depend on shasum.
digests() {
  python3 -I -c '
import hashlib, sys
for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        print(hashlib.sha256(handle.read()).hexdigest(), path)
' "$dist/eames.zip" "$dist/rand.zip"
}

echo "== frontmatter: model opus on all three commands"
for name in design-director eames rand; do
  python3 -I - "$repo/commands/$name.md" "$name" <<'PY' || fail "commands/$name.md frontmatter"
import json
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
first="$(digests)"

echo "== build (run 2)"
bash "$build" >/dev/null || fail "build run 2"
second="$(digests)"

echo "== determinism"
if [ "$first" != "$second" ]; then
  echo "$first"
  echo "$second"
  fail "zips differ between runs"
fi
echo "ok   identical sha256 across two runs"
echo "$second"

echo "== zip contents and claude.ai translation"
python3 -I "$here/assert_zips.py" "$repo" "$dist" || fail "zip contents"

echo "== build fails on untranslatable sources (temp commands folder)"
python3 -I "$here/negative_build.py" "$repo" "$helper" || fail "negative build tests"

echo "== quoted description round-trip (temp commands folder)"
python3 -I - "$repo" "$helper" <<'PY' || fail "quoted description round-trip"
import json
import os
import subprocess
import sys
import tempfile
import zipfile

repo, helper = sys.argv[1], sys.argv[2]

# eames: raw value with ": ", quotes and a hash. rand: a value already quoted.
raw_weird = 'Use for: "quoted" words, and # hashes'
quoted_src = '"Quoted source: \\"yes\\""'
expected_rand = 'Quoted source: "yes"'
with tempfile.TemporaryDirectory(prefix="atelier-pack-test-") as root:
    tmp = os.path.join(root, "src")
    stage = os.path.join(root, "stage")
    dist = os.path.join(root, "dist")
    for d in (os.path.join(tmp, "commands"), stage, dist):
        os.makedirs(d)
    for f in os.listdir(os.path.join(repo, "commands")):
        if not f.endswith(".md"):
            continue
        lines = open(os.path.join(repo, "commands", f), encoding="utf-8").read().split("\n")
        value = {"eames.md": raw_weird, "rand.md": quoted_src}.get(f)
        if value is not None:
            lines = [f"description: {value}" if l.startswith("description:") else l for l in lines]
        with open(os.path.join(tmp, "commands", f), "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
    for shipped in ("taste.md", "conventions.md"):
        with open(os.path.join(repo, shipped), "rb") as src, open(os.path.join(tmp, shipped), "wb") as dst:
            dst.write(src.read())
    subprocess.run([sys.executable, "-I", helper, tmp, os.path.join(stage, "s"), dist], check=True, stdout=subprocess.DEVNULL)

    expected = {"eames": raw_weird, "rand": expected_rand}
    for name, want in expected.items():
        with zipfile.ZipFile(os.path.join(dist, name + ".zip")) as archive:
            skill = archive.read(f"{name}/SKILL.md").decode("utf-8")
        line = next(l for l in skill.split("\n") if l.startswith("description: "))
        got = json.loads(line[len("description: "):])
        assert got == want, (name, got, want)
        print(f"ok   {name}: packaged description round-trips to {want!r}")
    assert not [f for f in os.listdir(dist) if f.endswith(".tmp")], "tmp left in dist"
PY

echo "== nothing under dist/ is staged"
staged="$(git -C "$repo" diff --cached --name-only -- dist)"
[ -z "$staged" ] || fail "dist/ is staged: $staged"
echo "ok   no dist/ files staged"

echo "PASS packaging/tests/check.sh"
