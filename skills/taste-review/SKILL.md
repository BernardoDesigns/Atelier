---
name: taste-review
description: Review the Atelier contract files one item at a time (quality gates and principles, taste, conventions, failures) and approve, edit, rewrite, cut or skip each draft. Resumable on any machine, and finishes with one pull request. Use only when the user types /taste-review or explicitly asks for a taste review of the draft rules. Do not use it on your own initiative during ordinary design or build work.
---

# Taste review

You walk the user through every draft item in the four contract files, one at a time, and record each answer. At the end you apply the decisions and open one pull request. You never merge it.

Be brief and peer-level. Show the item, ask, record, move on. No speeches between items.

## Ground rules

- Run `/taste-review` from a session started in the Atelier checkout: the user `cd`s there first. Find the checkout with `git -C ~/.claude/atelier rev-parse --show-toplevel` (call it `ATELIER`) and compare it with `pwd -P`. If the current directory is not inside `ATELIER`, say so, tell the user to start a session from the checkout, and stop. Do nothing else.
- The Atelier checkout at `~/.claude/atelier` is the user's live config. Its main branch changes only through pull requests. Never edit, stage or commit anything in its working tree. In that checkout you only run `git fetch` and `git worktree add`.
- All work happens in a separate git worktree on a long-lived branch named `taste-review`, at `WT` = `ATELIER/.claude/worktrees/taste-review`. Every read and write of `taste-review/state.json` and of the four contract files (`quality.md`, `taste.md`, `conventions.md`, `failures.md`) happens under `WT`.
- Never edit `state.json` by hand. Every answer goes through `WT/skills/taste-review/record.py`, run as `python3 -I -B`.
- Stopping at any point loses nothing: the state file is written, committed and pushed after every answer.
- Never approve an item on the user's behalf. Never touch any other file.

## The five options

Every item is answered with exactly one of these:

1. **Approve.** The wording is right as it stands.
2. **Edit.** The user changes the wording. Show the revised line back and ask for a final OK before recording it.
3. **Rewrite.** The user gives a replacement. Show it back and ask for a final OK before recording it.
4. **Cut.** The item goes. Ask once to confirm.
5. **Skip for now.** Leave it for later. It stays a draft.

## What an item is

State key: `<file>#<id>`, for example `taste.md#T4`, `quality.md#G7`, `failures.md#F12`.

| File | IDs | Main line (the wording Edit and Rewrite change) | Also show |
|---|---|---|---|
| `quality.md` | G1 to G10 (gates), P1 to P5 (principles) | The Pass bar cell (gates) or the In short cell (principles) | Gate or principle name, Checked by column |
| `taste.md` | T<n> | The one-line judgment under the heading | `Applied as:`, `Source:` |
| `conventions.md` | C<n> | The one-line rule under the heading | `Check:`, `Source:` |
| `failures.md` | F<n> | The `Trap:` line | `Name:`, `Shows up as:`, `Instead:`, `Source:` |

Valid `Source:` tags (the check rejects anything else, and several may be joined with commas): `principle`, `spec-convention`, `plan`, `log:<ID>` (an assumption or finding id from a build log, for example `log:A4` or `log:E3`), and `wrap:<yyyy-mm-dd>` optionally followed by ` finding <n>` or ` assumption A<n>` (an item born from a `/wrap` verdict, for example `wrap:2026-11-19 finding 7`).

Where an item has a `Verify:` line, show it as "Verify before approving" and let the user answer it first. Gates and principles keep their status in the table's Status column. Everything else keeps it on its `Status:` line.

If the user wants to change another field (`Check:`, `Applied as:`, `Instead:`, `Shows up as:`), record it under `fields` in the state entry.

## State file

`taste-review/state.json`, under `WT`:

```json
{
  "version": 1,
  "files": ["quality.md", "taste.md", "conventions.md", "failures.md"],
  "items": {
    "<file>#<id>": {
      "status": "pending | approved | edited | rewritten | cut | skipped",
      "text": "<final main line, or null>",
      "updated": "<ISO date, or null>",
      "fields": { "<Field name>": "<final text>" }
    }
  }
}
```

`fields` is optional and only present when another field was changed. Items are served in file order: quality, taste, conventions, failures. Write the file as indented JSON with a trailing newline.

The initial file lists every item as `pending` with `text` and `updated` null. It is generated, never typed by hand: `python3 -I -B WT/skills/taste-review/tests/gen-state.py WT`. After that it changes only through `record.py`:

```
python3 -I -B WT/skills/taste-review/record.py WT <key> <status> [--text "<final main line>"] [--field "<Field>=<text>"]...
python3 -I -B WT/skills/taste-review/record.py WT --summary
python3 -I -B WT/skills/taste-review/record.py WT --next
```

`record.py` checks the key and the status, sets `updated` to today, rewrites the file in the same serialisation as the generator, and prints a one-line tally. An unknown key or status exits non-zero and changes nothing. `--summary` prints the counts and the IDs under each status. `--next` prints the first pending key in file order, or `none`.

## Steps

### Start

1. Check the directory as the first ground rule says, then run `git -C ATELIER fetch origin`.
2. Find the worktree. Run `git -C ATELIER worktree list --porcelain`. If an entry has `branch refs/heads/taste-review`, its path is `WT`. Otherwise create it at `ATELIER/.claude/worktrees/taste-review` (that folder is git-ignored):
   - If the branch exists on the remote (`git -C ATELIER ls-remote --exit-code --heads origin taste-review`), run `git -C ATELIER worktree add -b taste-review ATELIER/.claude/worktrees/taste-review origin/taste-review`. This is how the review resumes on a second machine.
   - If it does not, run `git -C ATELIER worktree add -b taste-review ATELIER/.claude/worktrees/taste-review origin/main`, which starts from the current main.
   - Set `WT` to `ATELIER/.claude/worktrees/taste-review`.
3. Bring the branch up to date inside `WT`. If the branch exists on the remote, run `git -C WT pull --ff-only origin taste-review`. Then run `git -C WT merge --no-edit origin/main`, so contract changes that landed on main are in front of you. Until the final apply step only `taste-review/state.json` differs on this branch, so the merge is clean. If either command fails, stop and tell the user what git said. Do not force anything.
4. Load or create the state with `python3 -I -B WT/skills/taste-review/tests/gen-state.py --sync WT`. It creates `taste-review/state.json` if it is missing, and otherwise adds any item the state lacks as `pending`. It never deletes a key: cut items stay in the state as a record. If `git -C WT status --short taste-review/state.json` shows a change, commit that file by name and push.
5. Say where you are: run `python3 -I -B WT/skills/taste-review/record.py WT --summary` and relay the counts. Resume at the key printed by `record.py WT --next`. If it prints `none`, go to step 10.

### Review loop

6. Serve the item that `record.py WT --next` names (read its fields from the contract file under `WT`). Show: position (for example "14 of 145"), the key, the draft main line, its source tag, and how an agent would apply it (the "Also show" fields above). Show the `Verify:` line if there is one. Then list the five options.
7. Handle the answer.
   - Approve: record `approved`, `text` null.
   - Edit or Rewrite: take the new wording, show it back, ask for a final OK, then record `edited` or `rewritten` with the final main line in `text`. If the user declines the OK, ask again for wording.
   - Cut: confirm once, then record `cut`.
   - Skip: record `skipped`.
   Set `updated` to today's ISO date.
8. After EVERY answer, before serving the next item:
   1. run `python3 -I -B WT/skills/taste-review/record.py WT <key> <status>`, adding `--text "<final main line>"` for Edit and Rewrite and `--field "<Field>=<text>"` for any other changed field. If it exits non-zero, show its message and fix the call. Never edit `state.json` by hand;
   2. run `git -C WT add taste-review/state.json`;
   3. run `git -C WT commit -m "chore(taste-review): <key> <status>"`;
   4. run `git -C WT push -u origin taste-review`.
   If the push fails, say so in one line, keep going, and push again after the next answer. A failed push never blocks the review.
9. Go back to step 6 until no item is `pending`. Then offer to revisit the skipped items. If the user says yes, serve them through steps 6 to 8 the same way (take the keys from the `skipped:` line of `record.py WT --summary`), and any answer replaces `skipped`.

### Summary and apply

10. Print the summary from `python3 -I -B WT/skills/taste-review/record.py WT --summary`: counts of approved, edited, rewritten, cut and skipped, then the IDs under each. Ask the user to confirm it. If they want to change an answer, change it through step 8 and print the summary again. Do not touch any contract file before the summary is confirmed.
11. Apply the decisions in `WT`, to the four contract files only:
    - Approve, Edit and Rewrite: set the item's status to `approved`. If `text` is set, replace the main line with it. If `fields` is set, replace those fields. For `quality.md`, edit the Pass bar or In short cell and the Status cell of that table row.
    - Cut: remove the item (its whole block, or its table row in `quality.md`). Leave the numbering gap. Do not renumber, because other files cite the IDs.
    - Skip and pending: leave the item as it is, `draft`.

    Then verify: run `python3 -I -B WT/skills/taste-review/verify-apply.py WT`. It checks that every approved, edited or rewritten item now shows `Status: approved` with the recorded wording, every cut item is gone, and every skipped or pending item is still `draft`. If it exits non-zero it lists the mismatches. Fix them and run it again. Do not commit until it prints `OK`. (`python3 -I -B WT/skills/taste-review/tests/gen-state.py --ids WT` lists the items now in the files, if you need to look.)
12. Commit by file name, one commit for the contract files that changed (for example `git -C WT add quality.md taste.md conventions.md failures.md`, naming only those that changed) with the message `docs(taste-review): apply review decisions`. Also add `taste-review/state.json` if it changed. Push with `git -C WT push -u origin taste-review`.
13. Open ONE pull request to main in the Atelier repo, with the summary from step 10 in its description. First check for an existing one: `gh pr list --head taste-review --state open`. If one is open, update its description with `gh pr edit` instead of creating a second. Otherwise run `gh pr create --base main --head taste-review --title "Apply taste review decisions" --body-file <file holding the summary>`, run from inside `WT`.
14. Give the user the PR link. Never merge it. Say that skipped and pending items stay as drafts and the next `/taste-review` run picks them up from the same branch.
