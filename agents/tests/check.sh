#!/usr/bin/env bash
# Checks for the Lane 6 agents, the /wrap command and the critique template.
#
#   bash agents/tests/check.sh                          run every check
#   bash agents/tests/check.sh --validate-critique F    validate one critique file
#
# Paths can be overridden for testing:
#   BUILDER, CRITIC, WRAP, BUILD, CRITIQUE_TEMPLATE, ASSUMPTIONS_TEMPLATE
#
# Exits non-zero on any failure. Writes no files.

export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures"

BUILDER="${BUILDER:-$ROOT/agents/builder.md}"
CRITIC="${CRITIC:-$ROOT/agents/critic.md}"
WRAP="${WRAP:-$ROOT/commands/wrap.md}"
BUILD="${BUILD:-$ROOT/commands/build.md}"
CRITIQUE_TEMPLATE="${CRITIQUE_TEMPLATE:-$ROOT/templates/critique.md}"
ASSUMPTIONS_TEMPLATE="${ASSUMPTIONS_TEMPLATE:-$ROOT/templates/assumptions.md}"

# ---- helpers ---------------------------------------------------------------

# Frontmatter body between the first two --- lines.
frontmatter() {
  awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"
}

# Value of one frontmatter key.
fm_value() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1
}

# The tools line as a sorted, space-separated set.
tools_set() {
  fm_value "$1" tools | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | sort | tr '\n' ' '
}

sorted_list() {
  printf '%s\n' "$@" | sort | tr '\n' ' '
}

# Required critique headings, read from the template (Ranking is optional).
template_headings() {
  awk '/^# Example/{exit} /^## /{print substr($0,4)}' "$CRITIQUE_TEMPLATE" | grep -vx 'Ranking'
}

# Validate a critique file against the template. Prints reasons, returns 1 on failure.
validate_critique() {
  local req both=${2-}
  req=$(template_headings | paste -sd'|' -)
  awk -v req="$req" -v need_both="${both:+1}" '
    function fail(m) { print "  " m; bad = 1 }
    function cell(s,   a) { split(s, a, "|"); gsub(/^[ \t]+|[ \t]+$/, "", a[3]); return a[3] }
    BEGIN { n = split(req, R, "|"); h = 0; sec = "" }
    /^## / {
      if (open) fail("finding " lastf " has no evidence line (Screenshot or Diff)")
      open = 0
      name = substr($0, 4)
      if (name == "Ranking") { sec = "Ranking"; next }
      h++; H[h] = name; sec = name; next
    }
    sec == "Findings" && /^[0-9]+\. / {
      if (open) fail("finding " lastf " has no evidence line (Screenshot or Diff)")
      nf++; lastf = nf; open = 1; next
    }
    sec == "Findings" && /^[ ]*Screenshot: [^ ]+\.png[ ]*$/ { if (!open) fail("finding " lastf " has more than one evidence line"); open = 0; shots++; next }
    sec == "Findings" && /^[ ]*Diff: [^ :]+:[0-9]+[ ]*$/ { if (!open) fail("finding " lastf " has more than one evidence line"); open = 0; diffs++; next }
    sec == "Rubric scores" && /^\| G[0-9]+ / {
      g++; s = cell($0)
      if (s !~ /^[1-5]$/) fail("rubric score out of range: " $0)
      next
    }
    sec == "Principle scores" && /^\| P[0-9]+ / {
      p++; s = cell($0)
      if (s !~ /^[1-5]$/) fail("principle score out of range: " $0)
      else if (s + 0 < 3) lowp = 1
      next
    }
    /^Verdict:/ {
      v++
      if ($0 !~ /^Verdict: (pass|revise)$/) fail("bad Verdict line: " $0)
      verdict = $2
    }
    END {
      if (open) fail("finding " lastf " has no evidence line (Screenshot or Diff)")
      if (h != n) fail("expected " n " headings, found " h)
      else for (i = 1; i <= n; i++) if (H[i] != R[i]) fail("heading " i " is \"" H[i] "\", expected \"" R[i] "\"")
      if (nf < 1) fail("no numbered findings")
      if (need_both && (shots < 1 || diffs < 1)) fail("expected at least one Screenshot and one Diff finding")
      if (g != 10) fail("expected 10 gate rows, found " g + 0)
      if (p != 5) fail("expected 5 principle rows, found " p + 0)
      if (v != 1) fail("expected exactly one Verdict line, found " v + 0)
      if (lowp && verdict != "revise") fail("a principle below 3 requires Verdict: revise")
      exit bad
    }
  ' "$1"
}

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; [ -n "${2-}" ] && echo "      $2"; }
# check "name" <command...>: pass when the command exits 0
check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}
# check_not "name" <command...>: pass when the command exits non-zero
check_not() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then bad "$name"; else ok "$name"; fi
}

if [ "${1-}" = "--validate-critique" ]; then
  validate_critique "${2:?file required}" "${3-}"
  exit $?
fi

# ---- frontmatter -----------------------------------------------------------

builder_expected=$(sorted_list Read Write Edit Bash Glob Grep 'mcp__storybook__*')
critic_expected=$(sorted_list Read Grep Glob)

tools_match() { [ "$(tools_set "$1")" = "$2" ]; }
model_is()    { [ "$(fm_value "$1" model)" = "$2" ]; }
name_is()     { [ "$(fm_value "$1" name)" = "$2" ]; }
has_desc()    { [ -n "$(fm_value "$1" description)" ]; }
critic_no_write() { ! tools_set "$1" | grep -Eq '(^| )(Write|Edit|Bash|NotebookEdit)( |$)'; }

check "builder: files exist"            test -f "$BUILDER"
check "builder: name is builder"        name_is "$BUILDER" builder
check "builder: has description"        has_desc "$BUILDER"
check "builder: model is sonnet"        model_is "$BUILDER" sonnet
check "builder: tools are exactly the agreed set" tools_match "$BUILDER" "$builder_expected"
check "builder: under 120 lines"        test "$(wc -l < "$BUILDER")" -lt 120
check "critic: file exists"             test -f "$CRITIC"
check "critic: name is critic"          name_is "$CRITIC" critic
check "critic: has description"         has_desc "$CRITIC"
check "critic: model is opus"           model_is "$CRITIC" opus
check "critic: tools are exactly Read, Grep, Glob" tools_match "$CRITIC" "$critic_expected"
check "critic: no write-capable tool"   critic_no_write "$CRITIC"

# Self-test: the checks above must fail when the critic gains a tool.
# Uses process substitution on a copy, so nothing is written to disk.
check_not "self-test: critic with Bash added fails the tools check" \
  tools_match <(sed 's/^tools: .*/tools: Read, Grep, Glob, Bash/' "$CRITIC") "$critic_expected"
check_not "self-test: critic with Write added fails the no-write check" \
  critic_no_write <(sed 's/^tools: .*/tools: Read, Grep, Glob, Write/' "$CRITIC")
check_not "self-test: builder missing the Storybook entry fails" \
  tools_match <(sed 's/, mcp__storybook__\*//' "$BUILDER") "$builder_expected"

# ---- contract paths and rules in the agent text -----------------------------

has() { grep -Fq -- "$2" "$1"; }
check "builder: names .atelier/session.json"     has "$BUILDER" ".atelier/session.json"
check "builder: names .atelier/assumptions.md"   has "$BUILDER" ".atelier/assumptions.md"
check "builder: names .atelier/render-plan.json" has "$BUILDER" ".atelier/render-plan.json"
check "builder: names .atelier/tests.json"       has "$BUILDER" ".atelier/tests.json"
check "builder: 400-line split rule"             has "$BUILDER" "400"
check "builder: ask only on big decisions"       has "$BUILDER" "Ask only on big decisions"
check "builder: diverge mode, 4 to 6, per-option worktree" \
  bash -c 'grep -Fq "Diverge mode" "$1" && grep -Fq "4 to 6" "$1" && grep -Fq "own git worktree" "$1"' _ "$BUILDER"
check "builder: converge is the default"         has "$BUILDER" "Converge is the default"
check "builder: stops if session.json exists for a different SPEC" \
  has "$BUILDER" "for a different SPEC, stop and ask"
check "builder: names session.closed.json"       has "$BUILDER" ".atelier/session.closed.json"
check "builder: diverge has no marker in the main checkout" \
  has "$BUILDER" 'the main checkout gets no `.atelier/session.json`'

# Every mention of a rule file, template or the render CLI in the agents and
# templates must be a path under ~/.claude/atelier/. No <atelier> placeholder.
no_unprefixed_refs() {
  local f all pre
  for f in "$@"; do
    all=$(grep -o -E '(quality|taste|conventions|failures)\.md|templates/(assumptions|critique)\.md|render/cli\.mjs' "$f" | wc -l)
    pre=$(grep -o -E '~/\.claude/atelier/((quality|taste|conventions|failures)\.md|templates/(assumptions|critique)\.md|render/cli\.mjs)' "$f" | wc -l)
    [ "$all" -eq "$pre" ] || return 1
  done
}
no_placeholder() { ! grep -q '<atelier>' "$@"; }
check "atelier home: no unprefixed rule-file, template or render paths" \
  no_unprefixed_refs "$BUILDER" "$CRITIC" "$CRITIQUE_TEMPLATE" "$ASSUMPTIONS_TEMPLATE"
check "atelier home: no <atelier> placeholder" \
  no_placeholder "$BUILDER" "$CRITIC" "$WRAP" "$BUILD" "$CRITIQUE_TEMPLATE" "$ASSUMPTIONS_TEMPLATE"
check "builder: render harness path under ~/.claude/atelier" \
  has "$BUILDER" "node ~/.claude/atelier/render/cli.mjs --plan .atelier/render-plan.json"

core_before_scoring() {
  local a b
  a=$(grep -n -i 'core tension' "$1" | head -1 | cut -d: -f1)
  b=$(grep -n -i '^## Scoring' "$1" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
check "critic: core tension comes before scoring" core_before_scoring "$CRITIC"
check "critic: finding with neither Screenshot nor Diff is invalid" \
  bash -c 'grep -Fq "Screenshot: .atelier/renders/" "$1" && grep -Fq "Diff: <file>:<line>" "$1" && grep -Fq "A finding with neither is invalid" "$1"' _ "$CRITIC"
check "critic: never claims to have run a tool"  has "$CRITIC" "Never claim to have run a tool"
check "critic: reads .atelier/tests.json"        has "$CRITIC" ".atelier/tests.json"
check "critic: diverge mode ranking"             bash -c 'grep -Fq "Diverge mode" "$1" && grep -Fq "Ranking" "$1"' _ "$CRITIC"

# ---- wrap command -----------------------------------------------------------

wrap_prs() {
  # Exactly two: one under step 4 (Atelier repo), one under step 5 (host repo).
  [ "$(grep -c 'gh pr create' "$WRAP")" -eq 2 ] || return 1
  local s4 s5 a b
  s4=$(grep -n '^## Step 4' "$WRAP" | cut -d: -f1)
  s5=$(grep -n '^## Step 5' "$WRAP" | cut -d: -f1)
  a=$(grep -n 'gh pr create' "$WRAP" | sed -n 1p | cut -d: -f1)
  b=$(grep -n 'gh pr create' "$WRAP" | sed -n 2p | cut -d: -f1)
  [ -n "$s4" ] && [ -n "$s5" ] && [ "$a" -gt "$s4" ] && [ "$a" -lt "$s5" ] && [ "$b" -gt "$s5" ]
}
wrap_marker_close() {
  local s5 m
  s5=$(grep -n '^## Step 5' "$WRAP" | cut -d: -f1)
  m=$(grep -n '^mv .atelier/session.json .atelier/session.closed.json$' "$WRAP" | cut -d: -f1)
  [ -n "$m" ] && [ "$m" -gt "$s5" ] && ! grep -Eq '^[[:space:]]*rm ' "$WRAP"
}
wrap_learn_branch() {
  grep -Fq 'learn/<yyyy-mm-dd>-<short-slug>' "$WRAP" && grep -Fq 'git worktree add' "$WRAP" \
    && grep -Fq 'Never write accepted lines into the working tree of `~/.claude/atelier`' "$WRAP"
}
wrap_reuse_critique() { grep -Fq 'no commits were made on the branch after it was written, reuse it' "$WRAP"; }
wrap_not_addressed() { grep -Fq '"Not addressed"' "$WRAP"; }
wrap_steps_in_order() {
  local got
  got=$(grep -o '^## Step [0-9]' "$WRAP" | tr -d '\n')
  [ "$got" = "## Step 1## Step 2## Step 3## Step 4## Step 5" ]
}
wrap_no_build_skips() { grep -Fq "skip steps 1 to 3" "$WRAP"; }
wrap_targets() {
  grep -Fq '~/.claude/atelier/failures.md' "$WRAP" && grep -Fq '~/.claude/atelier/conventions.md' "$WRAP" && grep -Fq '~/.claude/atelier/taste.md' "$WRAP"
}
wrap_example() { grep -Fq '`1 fix, 2 disagree, 3 later, A2 wrong`' "$WRAP"; }
check "wrap: five steps in order"                wrap_steps_in_order
check "wrap: two gh pr create, one under step 4 (Atelier) and one under step 5 (host)" wrap_prs
check "wrap: step 5 closes the session by renaming the marker, no rm" wrap_marker_close
check "wrap: learning edits go to a learn/ branch in a new worktree" wrap_learn_branch
check "wrap: step 1 reuses a fresh critique" wrap_reuse_critique
check "wrap: untokened findings go under Not addressed" wrap_not_addressed
check "wrap: no-build path skips steps 1 to 3"   wrap_no_build_skips
check "wrap: learning proposals name their target files" wrap_targets
check "wrap: grammar example present"            wrap_example

# ---- build command ----------------------------------------------------------

build_frontmatter_desc_only() {
  [ "$(frontmatter "$BUILD" | sed -n 's/^\([a-z-]*\):.*/\1/p' | tr '\n' ' ')" = "description " ]
}
build_loop_steps() {
  grep -Fq 'Run the `builder` subagent' "$BUILD" && grep -Fq 'Run the `critic` subagent' "$BUILD" \
    && grep -Fq 'git diff main...HEAD' "$BUILD" && grep -Fq '.atelier/critique.md' "$BUILD" \
    && grep -Fq 'If it is `revise`, send the ranked findings back to the Builder' "$BUILD"
}
build_cap() { grep -Fq 'At most 3 Builder passes in total' "$BUILD"; }
build_report() {
  grep -Fq 'Run /wrap to close.' "$BUILD" && grep -Fq 'evidence line' "$BUILD" && grep -Fq 'assumptions count' "$BUILD"
}
build_no_pr_no_server() {
  ! grep -Fq 'gh pr create' "$BUILD" && grep -Fq 'never creates a PR' "$BUILD" && grep -Fq 'Do not start one' "$BUILD"
}
build_diverge() {
  grep -Fq '## Diverge mode' "$BUILD" && grep -Fq 'one Critic call' "$BUILD" && grep -Fq 'top 2 or 3' "$BUILD"
}
check "build: file exists"                       test -f "$BUILD"
check "build: frontmatter is description only"   build_frontmatter_desc_only
check "build: builder, critic, revise loop steps" build_loop_steps
check "build: 3 Builder pass cap"                build_cap
check "build: final report contents"             build_report
check "build: no PR, no server"                  build_no_pr_no_server
check "build: diverge mode ranks with one Critic call" build_diverge
check "build: under 60 lines"                    test "$(wc -l < "$BUILD")" -lt 60

# ---- verdict parser fixtures ------------------------------------------------

PV="$HERE/parse-verdict.sh"
verdict_matches() { # input-file expected-file
  local got
  got=$(bash "$PV" "$(cat "$1")") || return 1
  [ "$got" = "$(cat "$2")" ]
}
verdict_fails() { ! bash "$PV" "$(cat "$1")"; }
for f in "$FIX"/verdict-good*.txt; do
  check "verdict: $(basename "$f") gives expected actions" verdict_matches "$f" "${f%.txt}.expected"
done
for f in "$FIX"/verdict-bad-*.txt; do
  check "verdict: $(basename "$f") is rejected" verdict_fails "$f"
done

# ---- critique template and fixtures -----------------------------------------

template_order_ok() {
  [ "$(template_headings | paste -sd'|' -)" = "Core tension|Findings|Rubric scores|Principle scores|Spec drift" ]
}
ranking_last_optional() {
  local last
  last=$(awk '/^# Example/{exit} /^## /{print substr($0,4)}' "$CRITIQUE_TEMPLATE" | tail -1)
  [ "$last" = "Ranking" ] && grep -Fq "Optional. Diverge mode only" "$CRITIQUE_TEMPLATE"
}
example_validates() { validate_critique <(awk 'f; /^# Example/{f=1}' "$CRITIQUE_TEMPLATE") both; }
template_gate_names() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do grep -q "^| G$i " "$CRITIQUE_TEMPLATE" || return 1; done
  for i in 1 2 3 4 5; do grep -q "^| P$i " "$CRITIQUE_TEMPLATE" || return 1; done
}
template_verdict_line() { grep -Eq '^Verdict: <pass \| revise>$' "$CRITIQUE_TEMPLATE"; }
assumptions_ids() { grep -q '^## A1$' "$ASSUMPTIONS_TEMPLATE" && grep -q '^## A2$' "$ASSUMPTIONS_TEMPLATE"; }

check "template: headings in the agreed order"   template_order_ok
check "template: Ranking is optional and last"   ranking_last_optional
check "template: G1 to G10 and P1 to P5 rows"    template_gate_names
check "template: ends with a Verdict line"       template_verdict_line
check "template: worked example validates"       example_validates
check "assumptions template: ids A1 and A2"      assumptions_ids
check "fixture: critique-good.md validates, with both evidence kinds" validate_critique "$FIX/critique-good.md" both
for f in "$FIX"/critique-bad-*.md; do
  check_not "fixture: $(basename "$f") is rejected" validate_critique "$f"
done

# ---- no em dashes, and rule-file mentions ------------------------------------

no_em_dash() { ! grep -q '—' "$@"; }
check "no em dashes in agents, templates, commands" \
  no_em_dash "$BUILDER" "$CRITIC" "$WRAP" "$BUILD" "$CRITIQUE_TEMPLATE" "$ASSUMPTIONS_TEMPLATE"

# Informational: every mention of the four rule files in agents and templates.
# Review these by hand. Each must be a read, or a "never edit", or a /wrap proposal.
echo
echo "Rule-file mentions (review by hand):"
grep -n -E 'quality\.md|taste\.md|conventions\.md|failures\.md' \
  "$BUILDER" "$CRITIC" "$CRITIQUE_TEMPLATE" "$ASSUMPTIONS_TEMPLATE" \
  | sed "s|$ROOT/||" | sed 's/^/  /'

echo
echo "$PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
