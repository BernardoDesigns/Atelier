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
trap 'rm -rf "$work"' EXIT
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
[ "$count" -eq 2 ] && ok "exactly two settings backups exist" \
  || fail "expected 2 settings backups, found $count"
[ "$(backups_of "$h" | grep -c -- '-aurora-mods$')" -eq 1 ] && [ "$(backups_of "$h" | grep -c -- '-guardrails$')" -eq 1 ] \
  && ok "one backup ends -aurora-mods and one ends -guardrails" || fail "backup labels are not one -aurora-mods and one -guardrails"
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

echo "== helper missing: nothing is edited without a backup"
copy="$work/repo-copy"
mkdir -p "$copy/aurora-usage" "$copy/commands"
cp -R "$repo/guardrails" "$copy/guardrails"
cp "$repo/setup.sh" "$repo/dev-aliases.sh" "$copy/"
cp "$repo/aurora-usage/aurora" "$copy/aurora-usage/aurora"
mv "$copy/guardrails/backup-lib.sh" "$copy/guardrails/backup-lib.sh.away" 2>/dev/null
h4="$(new_home nohelper)"
HOME="$h4" PATH="$work/bin:$PATH" bash "$copy/guardrails/install.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && cmp -s "$h4/.claude/settings.json" "$work/nohelper.original.json" \
  && ok "install.sh exits non-zero and leaves settings untouched (exit $rc)" \
  || fail "install.sh without the helper: exit $rc or settings changed"
out4="$(HOME="$h4" PATH="$work/bin:$PATH" bash "$copy/setup.sh" --no-hud 2>&1)"
cmp -s "$h4/.claude/settings.json" "$work/nohelper.original.json" \
  && ok "setup.sh without the helper leaves settings untouched" || fail "setup.sh edited settings without a backup"
printf '%s\n' "$out4" | grep -q "^Skipped, see the warnings above" \
  && ok "setup.sh summary names the skipped steps" || fail "setup.sh summary does not mention skipped steps"
[ -z "$(backups_of "$h4")" ] && ok "no backup files were claimed" || fail "unexpected backup files"

echo "== copy fails: settings untouched, no empty placeholder left"
mkdir -p "$work/failbin"
cat > "$work/failbin/cp" <<'SH'
#!/bin/sh
for last; do :; done
case "$last" in *.bak.*) exit 1 ;; esac
exec /bin/cp "$@"
SH
cp "$work/bin/date" "$work/failbin/date"
chmod +x "$work/failbin/cp"
h5="$(new_home copyfail)"
out5="$(HOME="$h5" PATH="$work/failbin:$PATH" bash "$repo/setup.sh" --no-hud 2>&1)"
cmp -s "$h5/.claude/settings.json" "$work/copyfail.original.json" \
  && ok "setup.sh leaves settings byte-identical when the copy fails" || fail "settings changed although the backup failed"
[ -z "$(find "$h5/.claude" -type f -name '*.bak.*' -size 0 2>/dev/null)" ] \
  && ok "no 0-byte placeholder left behind" || fail "an empty backup placeholder was left"
printf '%s\n' "$out5" | grep -q "left untouched" \
  && ok "message says the file was left untouched" || fail "no clear message about the failed backup"
h6="$(new_home copyfail-standalone)"
HOME="$h6" PATH="$work/failbin:$PATH" bash "$repo/guardrails/install.sh" >"$work/o6.txt" 2>&1; rc=$?
[ "$rc" -ne 0 ] && cmp -s "$h6/.claude/settings.json" "$work/copyfail-standalone.original.json" \
  && [ -z "$(find "$h6/.claude" -type f -name '*.bak.*' -size 0 2>/dev/null)" ] \
  && grep -q "left untouched" "$work/o6.txt" \
  && ok "install.sh exits non-zero, settings untouched, no placeholder (exit $rc)" \
  || fail "install.sh copy failure handling (exit $rc)"

echo "== copy is damaged: the checksum catches it"
mkdir -p "$work/badbin"
cat > "$work/badbin/cp" <<'SH'
#!/bin/sh
for last; do :; done
/bin/cp "$@" || exit $?
case "$last" in *.bak.*) printf x >> "$last" ;; esac
exit 0
SH
chmod +x "$work/badbin/cp"
cp "$work/bin/date" "$work/badbin/date"
h8="$(new_home badcopy)"
out8="$(HOME="$h8" PATH="$work/badbin:$PATH" bash "$repo/setup.sh" --no-hud 2>&1)"
cmp -s "$h8/.claude/settings.json" "$work/badcopy.original.json" \
  && ok "settings byte-identical when the copy does not match" || fail "settings changed although the copy did not match"
[ -z "$(find "$h8/.claude" -name '*.bak.*' 2>/dev/null)" ] \
  && ok "no incomplete backup left to be restored by mistake" || fail "an incomplete backup was left behind"

echo "== settings.json is a symlink"
h9="$work/symlinked"
mkdir -p "$h9/.claude" "$h9/elsewhere"
write_original "$h9/elsewhere/real.json"
cp "$h9/elsewhere/real.json" "$work/symlinked.original.json"
ln -s "$h9/elsewhere/real.json" "$h9/.claude/settings.json"
out9="$(run_setup "$h9")"
[ -L "$h9/.claude/settings.json" ] && ok "settings.json is still a symlink" || fail "settings.json symlink was replaced"
named9="$(printf '%s\n' "$out9" | sed -n 's|^  .*/settings\.json -> ||p' | head -1)"
[ -n "$named9" ] && cmp -s "$named9" "$work/symlinked.original.json" \
  && ok "first logged backup equals the target's original content" || fail "first backup is not the original content"
[ -n "$named9" ] && [ ! -L "$named9" ] && ok "the backup is a real file, not a link" || fail "backup is a symlink or missing"
jq -e '.hooks.PreToolUse' "$h9/elsewhere/real.json" >/dev/null 2>&1 \
  && ok "the edit went through to the target" || fail "the target was not updated"

echo "== HOME path with a space"
hs="$(new_home "sp ace")"
outs="$(run_setup "$hs")"
nameds="$(printf '%s\n' "$outs" | sed -n 's|^  .*/settings\.json -> ||p' | head -1)"
case "$nameds" in *"sp ace"*"-aurora-mods") ok "summary lists the right backup ($(basename "$nameds"))" ;; *) fail "summary line wrong: $nameds" ;; esac
[ -n "$nameds" ] && cmp -s "$nameds" "$work/sp ace.original.json" \
  && ok "that backup is the original" || fail "spaced-path backup is not the original"

echo "== move fails: the original folder stays put"
mkdir -p "$work/mvbin"
cat > "$work/mvbin/mv" <<'SH'
#!/bin/sh
for last; do :; done
case "$last" in *.bak.*) exit 1 ;; esac
exec /bin/mv "$@"
SH
chmod +x "$work/mvbin/mv"
cp "$work/bin/date" "$work/mvbin/date"
h7="$(new_home movefail)"
mkdir -p "$h7/.claude/commands"; echo keep > "$h7/.claude/commands/mine.md"
echo "my aliases" > "$h7/.dev-aliases.sh"
HOME="$h7" PATH="$work/mvbin:$PATH" bash "$repo/setup.sh" --no-hud >"$work/o7.txt" 2>&1
[ -d "$h7/.claude/commands" ] && [ ! -L "$h7/.claude/commands" ] && [ "$(cat "$h7/.claude/commands/mine.md")" = keep ] \
  && ok "commands folder left in place when it can't be moved aside" || fail "commands folder was replaced"
[ -f "$h7/.dev-aliases.sh" ] && [ ! -L "$h7/.dev-aliases.sh" ] && [ "$(cat "$h7/.dev-aliases.sh")" = "my aliases" ] \
  && [ -z "$(ls "$h7"/.dev-aliases.sh.bak.* 2>/dev/null)" ] \
  && ok ".dev-aliases.sh is still a regular file with no .bak beside it" || fail ".dev-aliases.sh was replaced or left a .bak after a failed move"
[ -z "$(find "$h7" -type f -name '*.bak.*' -size 0 2>/dev/null)" ] && ok "no empty placeholder after a failed move" || fail "placeholder left after failed move"

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; exit 0; fi
echo "$failures check(s) failed" >&2
exit 1
