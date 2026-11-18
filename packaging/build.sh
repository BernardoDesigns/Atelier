#!/usr/bin/env bash
# Build dist/eames.zip and dist/rand.zip, the claude.ai skill uploads.
# Each run stages into a fresh temp directory, which is left behind on purpose.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
stage="$(mktemp -d)"
dist="$repo/dist"

python3 -I "$here/build_skills.py" "$repo" "$stage" "$dist"
echo "staging kept at $stage"
