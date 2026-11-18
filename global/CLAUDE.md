# Atelier global instructions

Import this file from your own CLAUDE.md. It holds the shared rules for the Atelier agents. Keep personal rules in your own file.

## Verb ownership

- Eames and the Critic judge. They critique and audit design work.
- Impeccable only polishes code, at code level, after the Critic has passed the work.
- Eames owns the spec and the design judgment.

## Ask vs ship

- Ask on big decisions.
- Ship small ones and log the assumption, so the wrap review can check it.

## Contracts

Atelier keeps its shared standards in four files at the repo root. Read the ones your task needs.

- `quality.md` holds the production-grade rubric: numbered gates with pass bars.
- `taste.md` holds judgment. Interpret it, and explain the call you made.
- `conventions.md` holds literal standards. Follow it exactly. Each item is a yes or no.
- `failures.md` holds known traps and past mistakes. Only the Critic and the Builder read it.

## Rules

- Never commit to `main`. Work on a branch, in a worktree when one is set up.
- Stage files by name. Do not stage everything at once.
- Nothing starts a dev server, a Storybook server or a tunnel on its own. Ask the user to start it.
- Do not use `rm`. If a file should go, name it and let the user remove it.
- Before you say work is done, run the checks the repo defines and report what they showed.
