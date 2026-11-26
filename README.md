# Atelier

Atelier: a studio of design agents (Design Director, Eames, Rand) and the tooling that turns their work into production-grade prototypes built on contemporary engineering practices for absorbing prototypes into production codebases.

**Version-controlled and synced across machines.** It holds a small team of design agents, a one-command dev environment, and Aurora Usage, a pair of plan-usage gauges. Clone it anywhere, run `setup.sh`, and the whole kit is wired in.

Built by [Bernardo Garcia](https://www.bellwetherdesigns.io), a product designer who builds with AI every day.

---

## Release notes

What each version brought, in plain English. Newest first. The full technical detail is in [CHANGELOG.md](CHANGELOG.md). Every new version gets an entry here; [RELEASING.md](RELEASING.md) has the checklist.

**[2.1.1](https://github.com/BernardoDesigns/atelier/releases/tag/v2.1.1), November 22, 2026: a code check that can't be fooled**

While the agents build, an automatic check reads every change for coding mistakes and stops them when it finds one. On one common kind of project that check was looking in the wrong place. It found nothing to read, and reported that everything was fine, while the project had more than a hundred mistakes in it. Now it runs the same full check the project's own tools run, and if it can't run at all it says so instead of passing. It also notes the mistakes a project already has when work starts, so the agents are only stopped for the ones they add, including a mistake in a file they never opened but broke from somewhere else.

**[2.1.0](https://github.com/BernardoDesigns/atelier/releases/tag/v2.1.0), November 22, 2026: lessons from a second design system**

Until now the agents had only ever built with one design system, the kit of ready-made buttons, switches and colors a product team builds its screens from. So I had them build the same screen with a different one, to see what they had been taking for granted. They coped well, and the test showed where the tools needed work. The camera that photographs each screen used to recognize dark mode in only one way, and now each project can tell it how to check. At the end of a session, when the agents propose lessons worth keeping, an unclear reply from me can no longer be taken as "keep nothing", and the proposals are saved so they can't get lost. The preview server no longer shuts down when I close the window I started it from, and the shareable preview link now works with more kinds of projects without extra setup.

**[2.0.2](https://github.com/BernardoDesigns/atelier/releases/tag/v2.0.2), November 20, 2026: tuning after the first exam**

We tested the reviewer agent by hiding 11 known mistakes in finished work. It found 10 of them and raised no false alarms. This release acts on what that test taught us. My design taste is now the official baseline the agents work to, written in my own words. The reviewer got stricter, so a serious problem can no longer get a passing grade, and less repetitive, so each problem is reported once. The spec template now asks what should happen to unsaved work when someone leaves halfway through. The outside tools the agents rely on are pinned to exact versions, so every computer gets the same set.

**[2.0.1](https://github.com/BernardoDesigns/atelier/releases/tag/v2.0.1), November 19, 2026: small fixes**

Ending a work session now always shuts down the preview server, even if you quit abruptly or close the window. The Design Director agent can now be installed in the Claude app, alongside Eames and Rand. The practice assignments were tightened to match the app they're built in.

**[2.0.0](https://github.com/BernardoDesigns/atelier/releases/tag/v2.0.0), November 19, 2026: the agents start building**

The big one. Until now the agents could design and describe. Now they build real, working screens. One agent builds from a written spec. A camera then photographs every state of the screen in light and dark mode, at phone, tablet and desktop sizes. A separate reviewer agent grades the result against a quality checklist and has to show evidence for every problem it finds. The builder gets up to three tries, and I make the final call. Safety rails stop any work from being submitted until the photos, tests and review all exist. The old hand-kept learning log is retired. Instead, each session ends with suggested lessons, and only the ones I approve are kept.

**[1.2.1](https://github.com/BernardoDesigns/atelier/releases/tag/v1.2.1), November 18, 2026: a backup fix**

The setup script could overwrite the backup of your settings if two of its steps ran in the same second. Backups now never replace each other, and setup tells you where each one is.

**[1.2.0](https://github.com/BernardoDesigns/atelier/releases/tag/v1.2.0), November 18, 2026: groundwork for testing**

A list of 24 known traps and how to avoid them. A spec template, plus an interview that won't write a spec until it's complete. A tool for reviewing my taste rules one at a time. Eames and Rand packaged for the Claude app. Five practice assignments, and a set of planted mistakes to measure how well the reviewer catches problems.

**[1.1.0](https://github.com/BernardoDesigns/atelier/releases/tag/v1.1.0), November 18, 2026: the rulebook and the seatbelts**

Written quality standards: ten pass-or-fail checks and five design principles. A file of my design taste and a file of house rules for the agents to follow. Safety rails that ask before anything risky, like deleting files, editing outside the project or contacting unknown websites. The usage gauge also learned to say "time to stop" when the plan runs low.

**[1.0.1](https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.1), November 17, 2026: a new name**

The project became Atelier and got an open source license.

**[1.0.0](https://github.com/BernardoDesigns/atelier/releases/tag/v1.0.0), November 17, 2026: the first version**

A small studio of AI design agents: a director who routes each request, Eames for product design and Rand for brand. It also included a one-command preview that shares work in progress to any device, and Aurora, a usage gauge that shows how much of my plan is left.

---

## The design agents

Three slash commands in `commands/` that work as one system: a router, two specialists, and a set of contract files they all work to.

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
/wrap ──▶ verdict line ──▶ learning proposals ──▶ I approve which ones to keep ──▶ a pull request into the contract files
```

- **One router, no keyword fights.** Instead of guessing from keywords, the Director presents a triage card and I choose which lens leads. The other lens still informs the work.
- **Each specialist knows its blind spot.** Eames is told to stay brand-aware, and Rand is told to respect interaction states and engineering limits.
- **Contract files, not a memory.** The agents work to `quality.md`, `taste.md`, `conventions.md` and `failures.md`. They read the same files every session, so nothing depends on what a past session happened to remember.
- **A learning loop with a human gate.** `/wrap` closes a session with a one-line verdict from me, then proposes learnings drawn only from what I corrected. I pick which ones to keep. Accepted lines reach the contract files only through a pull request, never by a direct edit.

---

## The build loop

`/build <SPEC>` is the default way to make something. It runs make, render, judge:

```
SPEC.md ──▶ Builder ──▶ render harness ──▶ Critic ──▶ verdict
              ▲                                          │
              └────────── revise (up to 3 passes) ◀──────┘
```

- **Builder** (`agents/builder.md`, Sonnet): reads the SPEC in a fresh session, builds it on a branch with the host design system, keeps an assumptions log, and renders every state. It writes files with Write and Edit only, and reports changed lines at every hand-back. Over about 400 lines of source it hands back a split proposal instead of continuing.
- **Render harness** (`render/`): screenshots every state in light and dark at 375, 768 and 1280, runs axe on each shot, and writes a manifest. Shots are clipped to the viewport width, and horizontal overflow is reported in the manifest (`overflowX`, `overflowBy`), not hidden. It never starts a server. For a Storybook story of a wide component, skip `layout: "centered"` if you want to see it in a narrow container, because a centred story root shrinks to its content.
- **Critic** (`agents/critic.md`, Opus, read-only): scores the ten gates and five principles, leads with the core tension, and cites a screenshot or a diff location for every finding.
- **`/wrap`**: Critic review, assumption check, a one-line verdict (`1 fix, 2 disagree, A2 wrong`), learning proposals, then the build PR.
- **Never makes a PR on its own.** `/build` stops at a report. The PR comes at the end of `/wrap`.

The loop is proven end to end on one benchmark ticket. The rest of the benchmark and the Critic calibration run come in v2.0.x, and hosted previews, a feature-flag provider and a `NEXT.md` handoff note from `/wrap` are planned for v2.1.

### Guardrails

Hooks installed by `setup.sh` (`guardrails/install.sh --enforce`) keep the loop honest. The build-session ones act only in a session that opened a build with `/build`, bound by the marker `.atelier/session.json`. Another session in the same checkout is not affected.

| Guardrail | What it does | Needs |
|---|---|---|
| Conventions injector | Adds `conventions.md` to context before UI file edits | `--enforce`, a `/build` session |
| Fast gate | Runs the repo's real typecheck (`tsc -b --force --noEmit` for a solution-style tsconfig, `tsc --noEmit` otherwise) and lints the edited file, and reports only the errors the Builder added, measured against a baseline taken when the build opened | `--enforce`, a `/build` session |
| Bash write nudge | Blocks a Bash command that writes a file into the repo and points at Write and Edit | `--enforce`, a `/build` session |
| Definition-of-done gates | The Stop gate nudges once; the PR gate blocks `gh pr create` until screenshots, assumptions, a recorded passing test run, a reviewed critique and a clean lane exist | `--enforce`, a `/build` session |
| Lane guard | Blocks edits to `auth/`, `api/`, `payments/`, `lib/shared/` and any extra `protected` paths in `.claude/lane-rules.json` | `--enforce` for the hook, `guardrails/lane-guard-init.sh` for the deny rules |

When `/build` opens a build, whatever an earlier build left in `.atelier/` moves to `.atelier/archive/<timestamp>-<branch>/`, so an old build can't satisfy the gates. The archive is yours to keep or delete.

To turn the build-session hooks off, run `bash guardrails/install.sh --relax`. To protect a project's paths, run `bash guardrails/lane-guard-init.sh <path-to-repo>` on the repo root. Run `bash guardrails/tests/run.sh` to test the hooks and installer (one-time first: `cd guardrails/tests && npm ci`, which installs the pinned TypeScript the fast gate tests use; without it those cases fail), and `bash agents/tests/check.sh` for the agents and commands. `guardrails/VETTING.md` is the checklist for reading a third-party skill, mod or MCP server before you install it.

---

## Breaking changes in 2.0.0

- **`setup.sh` now installs the enforcing hooks.** In a session that opened a build with `/build`: conventions are injected before UI file edits, the fast gate runs after each Write or Edit, a Bash command that writes a file into the repo is blocked with a pointer to Write and Edit, the Stop gate nudges once while artefacts are missing, and `gh pr create` is blocked until screenshots, assumptions, a recorded passing test run, a reviewed critique and a clean lane (no changed file under a protected path) exist. Other sessions in the same checkout are not affected. The lane guard denies edits to `auth/`, `api/`, `payments/` and `lib/shared/` only in a repo where you ran `guardrails/lane-guard-init.sh`. To undo: `bash guardrails/install.sh --relax`.
- **The Decision Log debrief is retired** from `/design-director`, `/eames` and `/rand`. No memory reads at session start, no Session Debrief, no consolidation pass. The contract files and `/wrap` replace it. Old memory files are no longer read or written, and nothing deletes them.
- **Re-upload Eames, Rand and Design Director to claude.ai.** The packaged skills are now translated from the commands, not copied. Run `bash packaging/build.sh` and upload `dist/eames.zip`, `dist/rand.zip` and `dist/design-director.zip`. The Design Director on claude.ai from before 2.0.0 still describes the retired Decision Log.

---

## Shared rules: `global/CLAUDE.md`

`global/CLAUDE.md` holds the rules the agents share: verb ownership, when to ask and when to ship, and pointers to the contract files. It's short on purpose, because it loads into every session in every repo. It also points at `failures.md` and the Critic agent.

To use it, add one line to your own `~/.claude/CLAUDE.md`:

```
@~/.claude/atelier/global/CLAUDE.md
```

`setup.sh` creates the `~/.claude/atelier` link to your checkout. Personal rules stay in your own file, which is never part of this repo.

### The contract files

Four files at the root hold the standards the agents work to:

| File | What it is |
|---|---|
| `quality.md` | Production-grade rubric: gates G1 to G10 and principles P1 to P5 |
| `taste.md` | Judgment items, interpreted rather than followed literally |
| `conventions.md` | Literal standards, each answerable yes or no |
| `failures.md` | Known traps: things models get wrong, and tool behavior that bites |

**These are drafts.** Every item in `taste.md`, `conventions.md` and `failures.md` and every threshold in `quality.md` is marked draft until my review, which happens in v2.0.x. They are working rules, not settled standards.

The only way these files change is a pull request: `/wrap` proposes new items, and `/taste-review` walks the drafts.

### The failure ledger: `failures.md`

Each entry has the trap, how it shows up, and what to do instead. There are 28 so far, all drafts. It's the file you add to when the same mistake happens twice.

---

## From idea to SPEC

### The SPEC template

`templates/SPEC.md` is the handoff document for a build: eight headings (goal, user and core tension, acceptance criteria, states to cover, visual baseline, out of scope and protected paths, definition of done, open questions). The states list is the one the render plan and the Critic read, so it's not optional.

### `/spec`

The `spec` skill interviews you and writes a `SPEC.md` into the repo you're in. It runs when you type `/spec` or ask for a spec, and not otherwise. It won't write one while acceptance criteria or states are missing, because a spec without those is just a wish.

### `/taste-review`

Walks through every draft item in the contract files, one at a time, and records your call on each. It's resumable: state lives in `taste-review/state.json` on a long-lived `taste-review` branch, so you can stop and pick it up on either machine. It runs only when you ask for it. Start it from a session opened in the Atelier checkout. It works in a worktree under `.claude/worktrees/`, never edits the main checkout, and ends in one pull request.

---

## Packaging for claude.ai

```bash
bash packaging/build.sh
```

Builds `dist/eames.zip`, `dist/rand.zip` and `dist/design-director.zip`, one skill folder in each. Eames and Rand hold `SKILL.md`, `taste.md` and `conventions.md`. Design Director is a router, so it ships `SKILL.md` only. The same input gives the same bytes. The commands are translated for claude.ai, not copied: the Claude Code only parts (`/wrap`, the `~/.claude` paths, the `quality.md` mention) are dropped, and the bundled `taste.md` and `conventions.md` lose the `/taste-review` sentence. The build fails loudly if a translation finds nothing to change. `dist/` is git-ignored; the zips are build output. If you uploaded Eames, Rand or Design Director before 2.0.0, upload the new zips. The zip layout is confirmed: all three uploaded to claude.ai as built.

---

## Evals

`evals/` is how I find out whether the system is getting better or just feeling better.

- `evals/tickets/`: five benchmark tickets, each a SPEC, to run through the build loop the same way every time. They are written against a host app with a design system, an e2e folder and a feature-flag helper. The render shots stand in for a hosted preview until v2.1.
- `evals/metrics/`: a schema and an append-only log, one row per benchmark run (CI result, invented components, axe violations, Critic score, review minutes, cost and whether the PR was accepted). The log is empty in the repo: the benchmark runs are committed through a pull request, and the remaining four come in v2.0.x.
- `evals/calibration/`: 15 seeded defects and 3 decoys, plus a scoring sheet, for checking how much of what's wrong the Critic catches. The calibration run itself comes in v2.0.x.

Run the checks with `bash evals/tests/check.sh`.

---

## Daily rhythm

From inside any project with a `package.json` and a `dev` script:

```bash
cc        # starts the dev server + a Cloudflare tunnel, then launches Claude Code
/exit     # quits Claude Code and tears down the server + tunnel
```

- The public tunnel URL is copied to the clipboard and opened in the browser, so I can share a live preview right away. `DEV_OPEN=local` opens `localhost` instead (skips Chrome's Local Network Access prompt), `DEV_OPEN=none` opens nothing.
- The tunnel dials whichever loopback address the server actually answers on (`127.0.0.1` or `::1`), so it works with static, Next and Vite servers whichever loopback line they bind.
- Host header: by default the tunnel presents itself to your dev server as `localhost`, so the Vite and Storybook host checks ("Blocked request", "Invalid host") do not block it. A Next project on its detected dev port keeps the old behavior and forwards the tunnel hostname, as a precaution: Next Server Actions compare the browser's `Origin` with the Host, and localhost could break that (not a proven failure). `DEV_TUNNEL_HOST=local` forces localhost, `DEV_TUNNEL_HOST=public` forces the tunnel hostname, and any other value means the default. A tunnel that is already running keeps the mode it was started with until `devdown`. Next still needs `allowedDevOrigins` either way (see `failures.md` F19).
- Works the same on a fresh start or a resume (`cc --resume`, `cc --continue`).
- The port is auto-detected: a `-p` or `--port` in the `dev` script wins, otherwise 5173 if the script mentions Vite and 3000 if not. With no `dev` script it serves the folder statically on 8000.

| Command | What it does |
|---|---|
| `cc` | Launch Claude Code with the dev stack up before and torn down after. Passes args through |
| `devup [port]` | Start server + tunnel manually. Port is auto-detected unless you pass one. Cleans up its own leftovers first: reuses a server it started from this folder, replaces one it started from another folder, and never touches anything it didn't start. The server runs detached, like the tunnel, so closing the terminal that ran `devup` leaves the stack up |
| `devdown [port]` | Kill the server + tunnel on that port. It stops whatever is listening on that port, including a server `devup` did not start. After a plain `devup` it is the off switch, since nothing else stops the stack (`cc` calls it for you) |

**Implementation note:** `cc` runs Claude Code in the current shell, in the foreground, and calls `devdown` once when it is done, however that happens: `/exit`, a double Ctrl+C, a closed terminal window or SIGTERM. Nothing is torn down while Claude Code is still running. The traps and options `cc` sets are local to it, so your shell is left exactly as it was. Claude Code's session hooks don't fire reliably on resume or quit, so I don't depend on them. `DEV_PORT=4000 cc` overrides the detected port. `bash tests/dev-aliases/check.sh` drives all of this in a real pseudo-terminal with stubbed `claude` and `cloudflared`.

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
- links the `spec` and `taste-review` skills into `~/.claude/skills/`, one folder each, and `agents/builder.md` and `agents/critic.md` into `~/.claude/agents/`, one file each, beside whatever is already there. It never replaces those folders, leaves a same-named file or folder of yours alone with a warning, accepts a link that already points at the right file, and skips this from a worktree too
- installs and registers the MCP servers in `mcp/servers.json` (today: Awwwards) at user scope, at pinned versions, with their skills and preferences. Skip it with `bash setup.sh --no-mcp`; details in `mcp/README.md`
- installs the render harness dependencies (`npm install` and a Chromium download, inside `render/` only) when `npm` is there, so `/build` can take screenshots. It says up front that the download is about 150MB and how to skip it (`bash setup.sh --no-render`), then starts without asking; if it is skipped or fails, it prints the one line to run by hand: `cd render && npm install && npx playwright install chromium`
- adds a source line to `.zshrc`
- adds the Aurora billboard to `env.CLAUDE_CODE_PLUGIN_DIRS` (and removes retired mod folders from it) in `~/.claude/settings.json` without touching any other key, and removes the old `statusLine` entry if it's still there
- merges the guardrails into `~/.claude/settings.json`: ask before destructive commands, before any write outside the current repo, and before curl/wget reaches anything but localhost or a `cc` tunnel. It also installs the build-session hooks (`--enforce`, see Breaking changes above; undo with `bash guardrails/install.sh --relax`)
- builds the Aurora HUD and starts it at login (skip with `bash setup.sh --no-hud`)
- backs up any existing file it would replace (timestamped), and is safe to re-run

**Heads up on the guardrails.** The network hook is a `python3` script. If `python3` is missing, every Bash tool call is blocked ("Atelier network guardrail failed, so this is blocked. Check python3, or re-run guardrails/install.sh") until you install it or remove the hook. `setup.sh` also edits `~/.claude/settings.json` now, so it applies to every repo on the machine. It adds ask rules for destructive commands, a few allow rules (curl to local hosts only, scripts in a project's `tools/` run with `.venv/bin/python` or `node`, and `npm test`, `npm run lint`, `npm run build`), and two hooks: one for writes outside the current repo, one for curl or wget to anything that isn't local. It removes the broad allow rules listed in `guardrails/permissions-retired.json`, from that file and from `~/.claude/settings.local.json`. A file that changes is backed up beside the original as `.bak.<date>-<time>-<step>`; no backup means that file wasn't touched. To undo, restore a backup (the commands below take the newest one) and start a new Claude Code session:

```bash
cp "$(ls -t ~/.claude/settings.json.bak.* | head -1)" ~/.claude/settings.json
# only if a settings.local.json backup exists:
cp "$(ls -t ~/.claude/settings.local.json.bak.* | head -1)" ~/.claude/settings.local.json
```

Open the backup first: if it still mentions `net-host-guard`, take the next one down. To put `settings.json` back exactly as it was before a `setup.sh` run, restore the backup listed under "Your files as they were before this run" at the end of that run. If that run added the Aurora entry in `env.CLAUDE_CODE_PLUGIN_DIRS` (it does the first time), this removes it too. Restoring a later backup puts back the permission rules and hooks only. The symlinks `setup.sh` made stay either way.

## Keeping machines in sync

The repo is the single source of truth. Everything is symlinked or loaded straight from the repo, so a `git pull` on any machine picks up changes instantly. The HUD is the exception: it's compiled, so re-run `setup.sh` after pulling changes to `main.swift`. MCP servers are installed, not linked, so after pulling a change to `mcp/servers.json` run `bash mcp/install.sh`. claude.ai connectors sync through your account and don't live here. Re-run `setup.sh` only on a new machine or when the install logic itself changes.

## What's in the repo

| File | Purpose |
|---|---|
| `commands/design-director.md` | Router agent |
| `commands/eames.md` | Product design specialist |
| `commands/rand.md` | Brand design specialist |
| `commands/build.md` | `/build <SPEC>`: Builder and Critic loop, up to 3 passes, then a report |
| `commands/wrap.md` | `/wrap`: Critic review, assumptions, verdict line, learning proposals, then the PR |
| `agents/builder.md` | Builds a SPEC on a branch, logs assumptions, runs the render loop |
| `agents/critic.md` | Read-only critic, scores a build against the rubric and principles |
| `agents/tests/check.sh` | Checks for the agents and the two commands, run with `bash agents/tests/check.sh` |
| `quality.md` | Production-grade rubric (gates G1 to G10, principles P1 to P5), draft thresholds |
| `taste.md` | Judgment items, each tagged with its source, draft |
| `conventions.md` | Literal standards, each with a yes/no check, draft |
| `global/CLAUDE.md` | Shared agent rules, imported from your own CLAUDE.md |
| `failures.md` | Known traps and how to avoid them, read by the Critic and the Builder, draft |
| `templates/SPEC.md` | SPEC template, eight headings |
| `templates/assumptions.md`, `templates/critique.md` | Output formats for the Builder's assumptions log and the Critic's critique |
| `render/` | Render harness. `node render/cli.mjs --plan .atelier/render-plan.json` screenshots every target in light and dark at 375, 768 and 1280, runs axe, and writes the manifest. Exit 0 ok, 1 axe failure, 2 usage, nothing at the base URL, or no shot rendered ok. Details in `render/README.md` |
| `skills/spec/` | `spec` skill: interview that produces a SPEC.md |
| `skills/taste-review/` | `taste-review` skill: one-item-at-a-time review of the contract files |
| `taste-review/state.json` | Review state, resumable on any machine |
| `packaging/build.sh` | Builds the claude.ai skill zips for eames, rand and design-director into `dist/`. Run `bash packaging/build.sh`; the output is not committed |
| `packaging/tests/` | `check.sh` checks the built zips, `retire-check.sh` fails if `commands/` still mentions the Decision Log, a debrief or memory files |
| `evals/tickets/` | Five benchmark SPECs for the regression suite |
| `evals/metrics/` | Per-run metrics schema, sample row and append-only log |
| `evals/calibration/` | Seeded defects, decoys and the scoring sheet for the Critic |
| `evals/tests/check.sh` | Checks for the evals folder, run with `bash evals/tests/check.sh` |
| `RELEASING.md` | Release checklist: CHANGELOG entry, plain-English README release note, checks, tag |
| `tests/release-notes/check.sh` | Fails if a CHANGELOG version has no README release note, or the newest isn't first. Run before every tag |
| `dev-aliases.sh` | `cc`, `devup`, `devdown` |
| `aurora-usage/aurora-billboard/` | Usage billboard mod for Claude Code |
| `aurora-usage/aurora-hud/` | Floating usage HUD for macOS (`main.swift` + build scripts) |
| `aurora-usage/aurora`, `profiles.json` | `aurora profile <name>`: swap threshold profiles (`default`, `fable-run`) |
| `guardrails/` | Ask and allow rules, the outside-repo write hook, the curl/wget host hook, the build-session hooks (conventions injector, fast gate, Stop and PR gates, lane guard), the session scripts `/build` and `/wrap` use, `run-tests.sh`, `VETTING.md`, tests, and the installer (`--enforce`, `--relax`) |
| `mcp/servers.json` | Pinned manifest of the MCP servers Claude Code installs locally |
| `mcp/install.sh` | Installs and registers them at user scope (`--dry-run` to preview). Tests: `bash mcp/tests/check.sh` |
| `mcp/awwwards/preferences.json` | Awwwards MCP preferences, copied to a new machine only if it has none |
| `mcp/awwwards/VETTED.md` | Vetting record for the pinned Awwwards version: what was read, provenance, flags. Re-vet on every bump |
| `setup.sh` | Idempotent installer |
