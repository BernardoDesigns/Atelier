# Atelier

Atelier: a studio of design agents (Eames, Rand) and the tooling that turns their work into production-grade prototypes.

**Version-controlled and synced across machines.** It holds a small team of design agents, a one-command dev environment, and Aurora Usage, a pair of plan-usage gauges. Clone it anywhere, run `setup.sh`, and the whole kit is wired in.

Built by [Bernardo Garcia](https://www.bellwetherdesigns.io), a product designer who builds with AI every day.

---

## The design agents

Three slash commands in `commands/` that work as one system: a router, two specialists, and a shared memory that gets sharper with use.

| Command | Role | Thinks in |
|---|---|---|
| `/design-director` | Router | Reads the brief, shows how each specialist would approach it, and lets me pick |
| `/eames` | Product design specialist | Components, states, edge cases, flows, responsive behavior, engineering handoff |
| `/rand` | Brand design specialist | Visual identity, emotional register, brand consistency, persuasion |

Named after Charles Eames and Paul Rand, because each agent takes on a point of view, not just a task list.

All three commands carry `model: opus` in their frontmatter, so the turn that runs the command is routed to Opus. It applies to that turn only, not to the rest of the conversation.

### How the system works

```
Design request
   │
   ▼
/design-director ──▶ triage card: "Eames would focus on… / Rand would focus on…"
   │                         │
   │        human picks the lead lens (human-in-the-loop)
   ▼                         ▼
/eames  or  /rand  ──▶  does the work using its own method and principles
   │
   ▼
Session debrief ──▶ proposes learnings ──▶ I approve which ones to keep ──▶ shared memory
```

- **One router, no keyword fights.** Instead of guessing from keywords, the Director presents a triage card and I choose which lens leads. The other lens still informs the work.
- **Each specialist knows its blind spot.** Eames is told to stay brand-aware, and Rand is told to respect interaction states and engineering limits.
- **A learning loop with a human gate.** At the end of a session, the agent lists what it learned (patterns, anti-patterns, preferences, principles, edge cases). I pick which ones are worth keeping, and only those get saved to memory, tagged by agent.
- **Memory that stays lean.** When the decision log reaches about 30 entries, the agents suggest a consolidation pass that rolls them up into evolved principles. That keeps the context loaded at the start of each session small.

---

## Shared rules: `global/CLAUDE.md`

`global/CLAUDE.md` holds the rules the agents share: verb ownership, when to ask and when to ship, and pointers to the contract files. It's short on purpose, because it loads into every session in every repo. It also points at `failures.md`, which is here now, and a Critic agent, which arrives in a later release.

To use it, add one line to your own `~/.claude/CLAUDE.md`:

```
@~/.claude/atelier/global/CLAUDE.md
```

`setup.sh` creates the `~/.claude/atelier` link to your checkout. Personal rules stay in your own file, which is never part of this repo.

### The contract files

Three files at the root hold the standards the agents work to:

| File | What it is |
|---|---|
| `quality.md` | Production-grade rubric: gates G1 to G10 and principles P1 to P5 |
| `taste.md` | Judgment items, interpreted rather than followed literally |
| `conventions.md` | Literal standards, each answerable yes or no |

`taste.md` and `conventions.md` are drafts until each item has been reviewed.

### The failure ledger: `failures.md`

A list of known traps: things models get wrong, and tool behavior that bites. Each entry has the trap, how it shows up, and what to do instead. There are 24 so far, all drafts until reviewed. It's the file you add to when the same mistake happens twice.

---

## From idea to SPEC

### The SPEC template

`templates/SPEC.md` is the handoff document for a build: eight headings (goal, user and core tension, acceptance criteria, states to cover, visual baseline, out of scope and protected paths, definition of done, open questions). The states list is the one the render plan and the Critic will read once they exist (both arrive in a later release), so it's not optional.

### `/spec`

The `spec` skill interviews you and writes a `SPEC.md` into the repo you're in. It runs when you type `/spec` or ask for a spec, and not otherwise. It won't write one while acceptance criteria or states are missing, because a spec without those is just a wish.

### `/taste-review`

Walks through every draft item in the contract files, one at a time, and records your call on each. It's resumable: state lives in `taste-review/state.json` on a long-lived `taste-review` branch, so you can stop and pick it up on either machine. It runs only when you ask for it. Start it from a session opened in the Atelier checkout. It works in a worktree under `.claude/worktrees/`, never edits the main checkout, and ends in one pull request.

---

## Packaging for claude.ai

```bash
bash packaging/build.sh
```

Builds `dist/eames.zip` and `dist/rand.zip`, one skill folder in each (`SKILL.md`, `taste.md`, `conventions.md`), and the same input gives the same bytes. `dist/` is git-ignored; the zips are build output. The zip layout is my assumption of what claude.ai wants, so upload one to confirm before you trust it.

---

## Evals

`evals/` is how I find out whether the system is getting better or just feeling better.

- `evals/tickets/`: five benchmark tickets, each a SPEC, to run through the build loop the same way every time.
- `evals/metrics/`: a schema and an append-only log, one row per benchmark run (CI result, invented components, axe violations, Critic score, review minutes, cost and whether the PR was accepted). The Critic and the build loop that produce most of these arrive in a later release; for now the log is empty.
- `evals/calibration/`: 15 seeded defects and 3 decoys, plus a scoring sheet, for checking how much of what's wrong the Critic will actually catch once it exists in a later release.

Run the checks with `bash evals/tests/check.sh`.

---

## Daily rhythm

From inside any project with a `package.json` and a `dev` script:

```bash
cc        # starts the dev server + a Cloudflare tunnel, then launches Claude Code
/exit     # quits Claude Code and tears down the server + tunnel
```

- The public tunnel URL is copied to the clipboard and opened in the browser, so I can share a live preview right away. `DEV_OPEN=local` opens `localhost` instead (skips Chrome's Local Network Access prompt), `DEV_OPEN=none` opens nothing.
- The tunnel dials whichever loopback address the server actually answers on (`127.0.0.1` or `::1`), so it stays steady whether the project is static, Next or Vite.
- Works the same on a fresh start or a resume (`cc --resume`, `cc --continue`).
- The port is auto-detected: a `-p` or `--port` in the `dev` script wins, otherwise 5173 if the script mentions Vite and 3000 if not. With no `dev` script it serves the folder statically on 8000.

| Command | What it does |
|---|---|
| `cc` | Launch Claude Code with the dev stack up before and torn down after. Passes args through |
| `devup [port]` | Start server + tunnel manually. Port is auto-detected unless you pass one |
| `devdown [port]` | Kill the server + tunnel on that port. A fallback for orphaned processes |

**Implementation note:** `cc` runs Claude Code in the current shell and calls `devdown` when it returns. No subshell, no `trap`, so teardown fires on `/exit` and nothing can kill the tunnel mid-session. Claude Code's session hooks don't fire reliably on resume or quit, so I don't depend on them.

---

## Aurora Usage

Two gauges on one fuel tank, so I always know how much of my Max plan is left. Details in [`aurora-usage/README.md`](aurora-usage/README.md).

**The billboard** is a Claude Code mod that draws one thin line above the prompt, in the terminal and the desktop app's Code tab:

```
5h ━━━━━━━━━━━━ 31% ⏰1h38m │ 7d ━━━━━━━━━━━━ 64% ⏰2d15h │ Opus 5.5 ━━━━━━━━━━━━ 42% 420.0k/1.0M │ $1.42
```

- The 5-hour and 7-day windows with reset countdowns, then the model's context fill and the session cost.
- Each cell is colored by its position on the bar, so a fuller bar reaches further into the hot end. `/billboard theme aurora|ember|tide|mono` swaps the palette.
- `⚡ using credits` appears when a window passes 100%, and a window drops back to 0% the moment its reset time passes.
- Toasts at 80% and 95%, once per window.

**The HUD** is a small native macOS panel that floats over everything, so the same 5h and 7d bars are visible while I'm in Chat or Projects. One Swift file, AppKit only. The billboard writes each reading to a small shared file and the HUD reads it, so the two always agree. A refresh button pulls a fresh reading on demand, which covers Chat-only stretches.

Neither piece makes a network call, reads a login token, or pulls in third-party code. I built this instead of installing a usage bar that read my credentials and auto-updated itself.

---

## Sketchpad

A side conversation docked next to the session, where I brainstorm and refine a prompt before sending it to the prompt box. Details in [`sketchpad/`](sketchpad/).

---

## New machine setup

```bash
xcode-select --install   # once, for the Aurora HUD's Swift compiler
brew install cloudflared jq
git clone https://github.com/BernardoDesigns/atelier.git ~/LocalDev/bernardo-claude-config
cd ~/LocalDev/bernardo-claude-config
bash setup.sh
```

Then open a new terminal. `setup.sh`:

- symlinks `~/.claude/commands` and `~/.dev-aliases.sh` to the repo copies, and `~/.claude/atelier` to the checkout (run it from the main checkout, not a git worktree; it skips that link from a worktree and says so)
- links the `spec` and `taste-review` skills into `~/.claude/skills/`, one folder each, beside whatever is already there. It never replaces that folder, leaves a same-named folder of yours alone with a warning, and skips this from a worktree too
- adds a source line to `.zshrc`
- adds the Aurora billboard and Sketchpad to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` without touching any other key, and removes the old `statusLine` entry if it's still there
- merges the guardrails into `~/.claude/settings.json`: ask before destructive commands, before any write outside the current repo, and before curl/wget reaches anything but localhost or a `cc` tunnel
- builds the Aurora HUD and starts it at login (skip with `bash setup.sh --no-hud`)
- backs up any existing file it would replace (timestamped), and is safe to re-run

**Heads up on the guardrails.** The network hook is a `python3` script. If `python3` is missing, every Bash tool call is blocked ("Atelier network guardrail failed, so this is blocked. Check python3, or re-run guardrails/install.sh") until you install it or remove the hook. `setup.sh` also edits `~/.claude/settings.json` now, so it applies to every repo on the machine. It adds ask rules for destructive commands, a few allow rules for curl to local hosts only, and two hooks: one for writes outside the current repo, one for curl or wget to anything that isn't local. It removes the broad allow rules listed in `guardrails/permissions-retired.json`, from that file and from `~/.claude/settings.local.json`. A file that changes is backed up beside the original as `.bak.<date>-<time>-<step>`; no backup means that file wasn't touched. To undo, restore a backup (the commands below take the newest one) and start a new Claude Code session:

```bash
cp "$(ls -t ~/.claude/settings.json.bak.* | head -1)" ~/.claude/settings.json
# only if a settings.local.json backup exists:
cp "$(ls -t ~/.claude/settings.local.json.bak.* | head -1)" ~/.claude/settings.local.json
```

Open the backup first: if it still mentions `net-host-guard`, take the next one down. To put `settings.json` back exactly as it was before a `setup.sh` run, restore the backup listed under "Your files as they were before this run" at the end of that run; that also removes the Aurora and Sketchpad entry in `env.CLAUDE_CODE_PLUGIN_DIRS`. Restoring a later backup puts back the permission rules and hooks only. The symlinks `setup.sh` made stay either way.

## Keeping machines in sync

The repo is the single source of truth. Everything is symlinked or loaded straight from the repo, so a `git pull` on any machine picks up changes instantly. The HUD is the exception: it's compiled, so re-run `setup.sh` after pulling changes to `main.swift`. Re-run `setup.sh` only on a new machine or when the install logic itself changes.

## What's in the repo

| File | Purpose |
|---|---|
| `commands/design-director.md` | Router agent and the shared session debrief protocol |
| `commands/eames.md` | Product design specialist |
| `commands/rand.md` | Brand design specialist |
| `quality.md` | Production-grade rubric (gates G1 to G10, principles P1 to P5) |
| `taste.md` | Judgment items, each tagged with its source |
| `conventions.md` | Literal standards, each with a yes/no check |
| `global/CLAUDE.md` | Shared agent rules, imported from your own CLAUDE.md |
| `failures.md` | Known traps and how to avoid them, read by the Critic and the Builder, which arrive in a later release |
| `templates/SPEC.md` | SPEC template, eight headings |
| `skills/spec/` | `spec` skill: interview that produces a SPEC.md |
| `skills/taste-review/` | `taste-review` skill: one-item-at-a-time review of the contract files |
| `taste-review/state.json` | Review state, resumable on any machine |
| `packaging/build.sh` | Builds the claude.ai skill zips for eames and rand into `dist/`. Run `bash packaging/build.sh`; the output is not committed |
| `evals/tickets/` | Five benchmark SPECs for the regression suite |
| `evals/metrics/` | Per-run metrics schema, sample row and append-only log |
| `evals/calibration/` | Seeded defects, decoys and the scoring sheet for the Critic, which arrives in a later release |
| `evals/tests/check.sh` | Checks for the evals folder, run with `bash evals/tests/check.sh` |
| `dev-aliases.sh` | `cc`, `devup`, `devdown` |
| `aurora-usage/aurora-billboard/` | Usage billboard mod for Claude Code |
| `aurora-usage/aurora-hud/` | Floating usage HUD for macOS (`main.swift` + build scripts) |
| `aurora-usage/aurora`, `profiles.json` | `aurora profile <name>`: swap threshold profiles (`default`, `fable-run`) |
| `sketchpad/` | Side conversation mod for Claude Code, for shaping prompts |
| `guardrails/` | Ask and allow rules, the outside-repo write hook, the curl/wget host hook, and the installer |
| `setup.sh` | Idempotent installer |
