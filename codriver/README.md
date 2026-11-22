# Co-driver

The person in the passenger seat with the map. It's docked next to your Claude Code session and keeps an eye on the road so one prompt never costs you hours or breaks something.

It never touches the build. No tools, no file edits, and it never sends a prompt on its own.

## Use it

Type `/codriver` to open the pane. Esc closes it, and it keeps everything for the rest of the session.

| Control | Does |
| --- | --- |
| **Claude Code output** | Paste what Claude Code just said |
| **Debrief** | Reads it and answers in three parts. Only runs when you press it |
| **Use last answer** | Grabs Claude Code's most recent answer for you, so there's nothing to paste |
| **Ready for Claude Code** | The next prompt, with guardrails built in: files in scope, ask before anything destructive, when to stop and report, a "done when" line |
| **Chat** (Enter) | Push back on the debrief, or ask "what does this mean?". Ask it to change the prompt and the box updates |
| **Send to prompt** | Puts the ready prompt in your prompt box. If you already typed something, it goes underneath. You still press Enter |
| **Opus / Sonnet / Haiku** | Switches the Co-driver model. Opus by default, at medium effort. Your pick is remembered |
| **Session: off / on** | Off: it knows only the pane and your course files. On: it can also see the build session so far, without adding anything to it |
| **Clear** | Starts fresh |

Commands: `/codriver`, `/codriver clear`, `/codriver model opus|sonnet|haiku`

## The debrief

- **What happened**: three plain lines. No jargon, or a quick explanation when a technical word can't be avoided.
- **On course?**: on course, drifting or blocked, and why, checked against your course files.
- **Watch out**: deletes, migrations, force-pushes, protected paths, big rewrites, scope creep, quiet assumptions. Left out when there are none.

## The course

What Co-driver checks the work against, read fresh on every Debrief:

- `CLAUDE.md`
- `NEXT.md`, `STATUS.md` and `next-session-starter.md`, if they exist
- up to 4 plan or status files `CLAUDE.md` points to (a link, a `path`, or an `@import` whose name has plan, status, next, roadmap, progress, todo, spec or handoff in it). Only files inside the project

Each file is capped at 12,000 characters and the whole course at 40,000. The pane's header lists what loaded, with "(trimmed)" on any file that was cut.

## Preflight

Every prompt you type yourself gets a quick check by Haiku before it goes.

- **Green**: it goes through. You see nothing.
- **Amber or red**: it's held back. Your words stay in the prompt box, a line above the prompt says why, and you choose: **Send anyway** (sends it as typed), **Let Co-driver tighten it** (rewrites it with guardrails into the Ready box, and Send to prompt swaps it in), or **Dismiss**. Pressing Enter again on the same words also sends it as-is.

It never blocks. If Haiku takes more than 3 seconds, errors, or answers something unreadable, the prompt goes through as typed. Slash commands, short replies ("yes", "go ahead"), prompts Co-driver wrote, and anything you didn't type yourself skip the check.

## Good to know

- **It draws from your plan limits** like any Claude Code request. A Debrief on Opus costs about what a short build turn does. Preflight on Haiku is tiny, but it runs on most prompts you type.
- **Preflight adds about a second** to prompts it checks.
- **"Session: on" costs more on a long session**, since it reads the whole conversation (mostly from cache).
- **No em dashes.** It's told not to use them, and any that slip through are swapped for commas.
- **Read-only.** It only reads the course files. No network calls of its own and no credentials. It only uses Claude Code's own model API.

## Develop

```sh
claude plugin validate codriver
claude plugin test codriver
claude --plugin-dir codriver   # a session with it loaded
```
