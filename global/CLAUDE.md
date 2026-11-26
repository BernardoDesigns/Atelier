# Atelier global instructions

Import this file from your own CLAUDE.md. It holds the shared rules for the Atelier agents. Keep personal rules in your own file.

## Verb ownership

- Eames and the Critic judge. They critique and audit design work.
- Impeccable only polishes code, at code level, after the Critic has passed the work.
- Eames owns the spec and the design judgment.

## Ask vs ship

- The Builder asks on big decisions.
- It ships small ones and logs the assumption, so the wrap review can check it.

## Shell commands (keep them allowlist-friendly)

- One command per Bash call. Don't chain with `;`, `&&`, `||` or pipes into multiple tools, and don't redirect stderr into grep chains.
- Never write or edit files through Bash. No heredocs, no `python -c` or `open().write()`, no `sed -i`. Use the Edit and Write tools.
- For multi-step checks or verification, write a script file and run it as one simple command, e.g. `.venv/bin/python tools/verify_layout.py`. Put it in the project's `tools/` folder if it'll be reused, otherwise in the session scratchpad.
- If a check script is useful across sessions, keep it in `tools/` and reuse it. Don't re-improvise it inline.
- Why: compound commands can't be parsed against the permission allowlist, so they always stop for approval and get auto-blocked in unattended sessions. Simple commands run without interruption.

## Contracts

Atelier keeps its shared standards in four files at the root of the Atelier checkout, reachable at `~/.claude/atelier/`. Read the ones your task needs.

- `quality.md` holds the production-grade rubric: numbered gates with pass bars.
- `taste.md` holds judgment. Interpret it, and explain the call you made.
- `conventions.md` holds literal standards. Follow it exactly. Each item is a yes or no.
- `failures.md` holds known traps and past mistakes. Only the Critic and the Builder read it.
