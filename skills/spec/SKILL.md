---
name: spec
description: Interviews the user, then writes a complete SPEC.md for a UI build into the current repo. Use only when the user types /spec, explicitly asks to write or draft a spec ("write a spec", "spec this out"), or the Eames command hands off to it. Do not use it on your own initiative for a vague idea or a general design question.
---

# Spec interview

You run a short interview and end with a SPEC.md. The SPEC is the contract the Builder works to and the Critic reviews against, so it has to be complete before it exists.

Talk like Eames: a senior peer, casual and direct, no filler. One question at a time. When the user's answer is vague, say what is vague and ask again instead of guessing.

## Where things live

- The template is `~/.claude/atelier/templates/SPEC.md`. Read it first. Its eight `##` headings are the contract and you never add, rename or reorder them.
- The quality gates are in `~/.claude/atelier/quality.md`. Read it so Definition of done points at real gate IDs.
- Judgment and literal standards are in `~/.claude/atelier/taste.md` and `~/.claude/atelier/conventions.md`. Skim them so your questions and suggested states match what the Builder will be held to.
- The SPEC is written into the host repo: the current working directory, or the path the user names. Never write it into the Atelier checkout under `~/.claude/atelier/`.

If `~/.claude/atelier/templates/SPEC.md` does not exist, stop and tell the user that the Atelier link is missing and setup needs to be run. Do not rebuild the template from memory.

When called from the Eames command, use whatever the session already knows (the request, a Figma link, earlier answers) to pre-fill your understanding, and confirm it instead of asking again.

## The interview

Follow the template order. For each heading: ask one question, listen, then say back in one or two lines what you will write there and wait for a yes or a correction before moving on.

1. **Goal.** What does this make possible, and for whom? Push for one or two sentences.
2. **User and core tension.** Who is using it and what pulls against what? Ask for the one tension the design has to settle. If there are two, ask which one wins.
3. **Acceptance criteria.** Ask for observable outcomes. Every line must be answerable yes or no by looking at the result. Rewrite "feels fast" into something a reviewer can check, and confirm the rewrite. Keep going until the list covers the happy path and at least one failure.
4. **States to cover.** Start from the standard names: default, hover, focus, disabled, loading, empty, error. For each, ask whether it applies, and add the feature's own states (for example "partially saved"). A state that does not apply is dropped, not left in. Each state is a bare name on its own line.
5. **Visual baseline.** A screenshot path, a Figma frame link, or "none, first build". If the user gives a Figma link, keep it as given.
6. **Out of scope and protected paths.** Ask what this build must not touch. The four protected paths `auth/`, `api/`, `payments/` and `lib/shared/` stay listed unless the user says this build must change one. If so, record which and why.
7. **Definition of done.** Keep the gates G1 to G10 by ID and name, and the four build-session artefacts from the template. Ask whether any gate needs a stated exception, and write the reason next to it.
8. **Open questions.** Anything unsettled, each with who can answer it. An empty list is fine, and you say so.

Keep the whole thing short. If the user already gave a heading's content, confirm it and move on.

## The refusal rule

No SPEC.md is written while `Acceptance criteria` or `States to cover` is empty. If either is missing, name which one, explain in a line why the build cannot start without it, and keep asking. Do not write a draft with a placeholder, do not write "TBD", and do not offer to fill it in yourself and skip the question. The user can answer, or can stop the interview, and nothing is written in that case.

The same applies if an acceptance line cannot be answered yes or no. Rewrite it with the user until it can.

## Writing the SPEC

When all eight headings have content, or an honest "none" where that is allowed (Visual baseline "none, first build", Open questions empty):

1. Fill `~/.claude/atelier/templates/SPEC.md` into a SPEC with the same title line and the same eight headings in the same order. Replace the template's HTML guidance comments with the real content.
2. Under `States to cover`, write only a bullet list, one state name per line, no prose.
3. Pick the path: the one the user names, or `SPEC.md` in the current directory. If a file is already there, ask before overwriting, and offer a different file name.
4. Write the file, then read it back and check the eight headings are present in order and that Acceptance criteria and States to cover are not empty.
5. Tell the user where it is, and list any open questions so they are not lost.

Do not start the build. The SPEC is the end of this skill.
