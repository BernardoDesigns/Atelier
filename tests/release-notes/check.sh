#!/usr/bin/env bash
# Every released version in CHANGELOG.md must have a plain-English entry in
# the README's "Release notes" section, linked to its GitHub release.
# Run before tagging: bash tests/release-notes/check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
changelog="$root/CHANGELOG.md"
readme="$root/README.md"

fail=0
pass=0

if ! grep -q '^## Release notes$' "$readme"; then
  echo "FAIL: README.md has no '## Release notes' section"
  exit 1
fi

# Only the Release notes section of the README counts.
notes="$(awk '/^## Release notes$/{on=1; next} on && /^## /{exit} on' "$readme")"

versions="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

for v in $versions; do
  if grep -qF "**[$v](https://github.com/BernardoDesigns/atelier/releases/tag/v$v)" <<<"$notes"; then
    pass=$((pass + 1))
  else
    echo "FAIL: v$v is in CHANGELOG.md but has no README release note (expected a line starting **[$v](https://github.com/BernardoDesigns/atelier/releases/tag/v$v))"
    fail=$((fail + 1))
  fi
done

# Newest first: the first entry must be the newest CHANGELOG version.
newest="$(head -1 <<<"$versions")"
first="$(grep -oE '^\*\*\[[0-9]+\.[0-9]+\.[0-9]+\]' <<<"$notes" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -n "$newest" && "$first" != "$newest" ]]; then
  echo "FAIL: the first release note is v${first:-none}, but the newest CHANGELOG version is v$newest"
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

# House style: no em dashes in the release notes.
if grep -q '—' <<<"$notes"; then
  echo "FAIL: the release notes contain an em dash"
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

echo "release-notes: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
