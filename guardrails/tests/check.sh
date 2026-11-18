#!/usr/bin/env bash
# Checks for the settings.json backups made by setup.sh and guardrails/install.sh.
# Exits 0 only when every check passes. Every run uses a throwaway HOME under
# $TMPDIR; the real ~/.claude is never touched.
#
# ATELIER_REPO=<path> points the checks at another copy of the repo (used to
# show the checks failing against the old code).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${ATELIER_REPO:-$(cd "$here/../.." && pwd)}"

command -v jq >/dev/null 2>&1 || { echo "SKIP jq not found, the settings merge needs it"; exit 0; }

work="$(mktemp -d "${TMPDIR:-/tmp}/atelier-backup-test.XXXXXX")"
failures=0
fail() { echo "FAIL $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok   $*"; }

# A date shim that pins the timestamp format, so two steps always land in the
# same second whatever the machine is doing. Anything else goes to the real date.
mkdir -p "$work/bin"
cat > "$work/bin/date" <<'SH'
#!/bin/sh
if [ "$1" = "+%Y%m%d-%H%M%S" ]; then echo 20261118-101530; else exec /bin/date "$@"; fi
SH
chmod +x "$work/bin/date"

# A settings.json that both the mod wiring and the guardrails step will change.
write_original() {
  cat > "$1" <<'JSON'
{
  "model": "opus",
  "env": { "KEEP_ME": "1" },
  "permissions": { "allow": ["Bash(curl:*)", "Bash(ls:*)"] }
}
JSON
}

new_home() {
  local h="$work/$1"
  mkdir -p "$h/.claude"
  write_original "$h/.claude/settings.json"
  cp "$h/.claude/settings.json" "$work/$1.original.json"
  echo "$h"
}

run_setup() { # <home> -> output on stdout
  HOME="$1" PATH="$work/bin:$PATH" bash "$repo/setup.sh" --no-hud 2>&1
}

backups_of() { ls "$1/.claude/settings.json.bak."* 2>/dev/null; }

echo "== whole flow: both steps in the same second"
h="$(new_home same-second)"
out="$(run_setup "$h")"
count=$(backups_of "$h" | wc -l | tr -d ' ')
[ "$count" -ge 2 ] && ok "two distinct settings backups exist ($count)" \
  || fail "expected 2 settings backups, found $count"
first="$(backups_of "$h" | head -1)"
[ -n "$first" ] && cmp -s "$first" "$work/same-second.original.json" \
  && ok "earliest backup is byte-identical to the original ($(basename "$first"))" \
  || fail "earliest backup is not the original"
identical=0
for b in $(backups_of "$h"); do cmp -s "$b" "$work/same-second.original.json" && identical=$((identical + 1)); done
[ "$identical" -eq 1 ] && ok "exactly one backup holds the original, the other holds the mid-run state" \
  || fail "backups holding the original: $identical (want 1)"
# The final report names the pre-run original, and it is the right file.
named="$(printf '%s\n' "$out" | sed -n 's|^  .*/settings\.json -> ||p' | head -1)"
[ -n "$named" ] && cmp -s "$named" "$work/same-second.original.json" \
  && ok "end of run names the pre-run original" \
  || fail "end of run does not name the pre-run original"
printf '%s\n' "$out" | grep -c 'settings.json.bak' | grep -qv '^0$' \
  && ok "each backup path is printed as it is made" || fail "backup paths not printed"

echo "== whole flow twice, same second both times"
h2="$(new_home twice)"
run_setup "$h2" >/dev/null
# Put a retired rule back so the second run has something to change again.
jq '.permissions.allow += ["Bash(curl:*)"]' "$h2/.claude/settings.json" > "$work/twice.tmp" \
  && cat "$work/twice.tmp" > "$h2/.claude/settings.json"
sums_before="$(for b in $(backups_of "$h2"); do cksum "$b"; done)"
run_setup "$h2" >/dev/null
sums_after="$(for b in $(backups_of "$h2" | head -n "$(printf '%s\n' "$sums_before" | wc -l | tr -d ' ')"); do cksum "$b"; done)"
count2=$(backups_of "$h2" | wc -l | tr -d ' ')
[ "$count2" -gt "$(printf '%s\n' "$sums_before" | wc -l | tr -d ' ')" ] \
  && ok "second run added a backup instead of replacing one ($count2 total)" \
  || fail "second run added no new backup ($count2 total)"
for line in $(printf '%s\n' "$sums_before" | tr ' ' ':'); do
  printf '%s\n' "$sums_after" | tr ' ' ':' | grep -qx "$line" || { fail "an earlier backup changed: $line"; break; }
done
first2="$(backups_of "$h2" | head -1)"
[ -n "$first2" ] && cmp -s "$first2" "$work/twice.original.json" \
  && ok "earliest backup is still the true original" || fail "earliest backup is no longer the original"

echo "== guardrails/install.sh on its own"
h3="$(new_home standalone)"
HOME="$h3" PATH="$work/bin:$PATH" bash "$repo/guardrails/install.sh" >/dev/null 2>&1
b3="$(backups_of "$h3" | head -1)"
[ -n "$b3" ] && cmp -s "$b3" "$work/standalone.original.json" \
  && ok "standalone install.sh made a backup of the original ($(basename "$b3"))" \
  || fail "standalone install.sh backup missing or wrong"

echo "== naming helper, frozen timestamp"
if [ -f "$repo/guardrails/backup-lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$repo/guardrails/backup-lib.sh"
  f="$work/sample.json"; echo '{"a":1}' > "$f"
  export ATELIER_BACKUP_TS=20261118-101530
  p1="$(atelier_backup_path "$f" aurora-mods)"; echo first > "$p1"
  p2="$(atelier_backup_path "$f" guardrails)"; echo second > "$p2"
  p3="$(atelier_backup_path "$f" guardrails)"; echo third > "$p3"
  [ "$p1" != "$p2" ] && [ "$p2" != "$p3" ] && ok "three calls, three distinct names" || fail "names collided: $p1 $p2 $p3"
  [ "$(cat "$p1")" = first ] && [ "$(cat "$p2")" = second ] && ok "no earlier backup was overwritten" \
    || fail "an earlier backup was overwritten"
  case "$p3" in *-guardrails-2) ok "taken name gets a numeric suffix ($(basename "$p3"))" ;; *) fail "unexpected name $p3" ;; esac
  case "$p1" in "$f.bak.20261118-101530-aurora-mods") ok "name keeps the .bak.<timestamp> prefix" ;; *) fail "unexpected name $p1" ;; esac
  # A pre-existing file with the exact name is never reused.
  : > "$f.bak.20261118-101530-x"; echo keep > "$f.bak.20261118-101530-x"
  p4="$(atelier_backup_path "$f" x)"
  [ "$p4" != "$f.bak.20261118-101530-x" ] && [ "$(cat "$f.bak.20261118-101530-x")" = keep ] \
    && ok "an existing target is skipped, not reused" || fail "existing target was reused"
  unset ATELIER_BACKUP_TS
else
  fail "guardrails/backup-lib.sh is missing"
fi

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; exit 0; fi
echo "$failures check(s) failed" >&2
exit 1
