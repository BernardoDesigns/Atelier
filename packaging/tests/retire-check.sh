#!/usr/bin/env bash
# Checks that the Decision Log is gone from the design commands. Exits 0 only when every check passes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
commands="$repo/commands"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

echo "== retired terms in commands/"
set +e
hits="$(grep -r -i -n -E 'decision log|debrief|update_doc|token budget|figma_execute' "$commands/")"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "$hits"
  fail "commands/ still mentions a retired term"
elif [ "$rc" -ne 1 ]; then
  fail "grep failed with status $rc"
fi
echo "ok   no retired terms in commands/"

echo "== each design command points at /wrap"
for name in design-director eames rand; do
  grep -q -F '/wrap' "$commands/$name.md" || fail "commands/$name.md does not mention /wrap"
  echo "ok   $name mentions /wrap"
done

echo "== no memory-file reads left in the design commands"
set +e
memory="$(grep -i -n -E 'memory|tagged `?(eames|rand|general)' "$commands/design-director.md" "$commands/eames.md" "$commands/rand.md")"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "$memory"
  fail "a design command still refers to memory files"
elif [ "$rc" -ne 1 ]; then
  fail "grep failed with status $rc"
fi
echo "ok   no memory-file references"

echo "PASS packaging/tests/retire-check.sh"
