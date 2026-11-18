# Atelier global instructions

Import this file from your own CLAUDE.md. It holds the shared rules for the Atelier agents. Keep personal rules in your own file.

## Verb ownership

- Eames and the Critic judge. They critique and audit design work.
- Impeccable only polishes code, at code level, after the Critic has passed the work.
- Eames owns the spec and the design judgment.

## Ask vs ship

- The Builder asks on big decisions.
- It ships small ones and logs the assumption, so the wrap review can check it.

## Contracts

Atelier keeps its shared standards in four files at the root of the Atelier checkout, reachable at `~/.claude/atelier/`. Read the ones your task needs.

- `quality.md` holds the production-grade rubric: numbered gates with pass bars.
- `taste.md` holds judgment. Interpret it, and explain the call you made.
- `conventions.md` holds literal standards. Follow it exactly. Each item is a yes or no.
- `failures.md` holds known traps and past mistakes. Only the Critic and the Builder read it.
