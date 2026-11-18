---
name: taste-review
description: Review the Atelier contract files one item at a time (quality gates and principles, taste, conventions, failures) and approve, edit, rewrite, cut or skip each draft. Resumable on any machine, and finishes with one pull request. Use when the user says "taste review", "/taste-review", or wants to approve the draft rules.
---

# Taste review

You walk the user through every draft item in the four contract files, one at a time, and record each answer. At the end you apply the decisions and open one pull request. You never merge it.

Be brief and peer-level. Show the item, ask, record, move on. No speeches between items.

## Ground rules

- The Atelier checkout at `~/.claude/atelier` is the user's live config. Its main branch changes only through pull requests. Never edit, stage or commit anything in its working tree. In that checkout you only run `git fetch` and `git worktree add`.
- All work happens in a separate git worktree on a long-lived branch named `taste-review`. Call its path `WT`. Every read and write of `taste-review/state.json` and of the four contract files (`quality.md`, `taste.md`, `conventions.md`, `failures.md`) happens under `WT`.
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

The initial file lists every item as `pending` with `text` and `updated` null. It is generated, never typed by hand: `python3 -I WT/skills/taste-review/tests/gen-state.py WT`.

## Steps

### Start

1. Find the checkout: `git -C ~/.claude/atelier rev-parse --show-toplevel`. Call it `ATELIER`. Run `git -C ATELIER fetch origin`.
2. Find the worktree. Run `git -C ATELIER worktree list --porcelain`. If an entry has `branch refs/heads/taste-review`, its path is `WT`. Otherwise create it:
   - If the branch exists on the remote (`git -C ATELIER ls-remote --exit-code --heads origin taste-review`), run `git -C ATELIER worktree add -b taste-review ~/LocalDev/atelier-worktrees/taste-review origin/taste-review`. This is how the review resumes on a second machine.
   - If it does not, run `git -C ATELIER worktree add -b taste-review ~/LocalDev/atelier-worktrees/taste-review origin/main`, which starts from the current main.
   - Set `WT` to `~/LocalDev/atelier-worktrees/taste-review`.
3. Bring the branch up to date inside `WT`. If the branch exists on the remote, run `git -C WT pull --ff-only origin taste-review`. Then run `git -C WT merge --no-edit origin/main`, so contract changes that landed on main are in front of you. Until the final apply step only `taste-review/state.json` differs on this branch, so the merge is clean. If either command fails, stop and tell the user what git said. Do not force anything.
4. Load or create the state. If `WT/taste-review/state.json` does not exist, generate it with `python3 -I WT/skills/taste-review/tests/gen-state.py WT`, commit it by file name and push. If it exists, list the current items with `python3 -I WT/skills/taste-review/tests/gen-state.py --ids WT` and add any key the state lacks as `pending`. Never delete a key: cut items stay in the state as a record.
5. Say where you are: how many items are approved, edited, rewritten, cut, skipped and pending. Resume at the first `pending` item in file order.

### Review loop

6. Serve one item. Show: position (for example "14 of 145"), the key, the draft main line, its source tag, and how an agent would apply it (the "Also show" fields above). Show the `Verify:` line if there is one. Then list the five options.
7. Handle the answer.
   - Approve: record `approved`, `text` null.
   - Edit or Rewrite: take the new wording, show it back, ask for a final OK, then record `edited` or `rewritten` with the final main line in `text`. If the user declines the OK, ask again for wording.
   - Cut: confirm once, then record `cut`.
   - Skip: record `skipped`.
   Set `updated` to today's ISO date.
8. After EVERY answer, before serving the next item:
   1. write `WT/taste-review/state.json`;
   2. run `git -C WT add taste-review/state.json`;
   3. run `git -C WT commit -m "chore(taste-review): <key> <status>"`;
   4. run `git -C WT push -u origin taste-review`.
   If the push fails, say so in one line, keep going, and push again after the next answer. A failed push never blocks the review.
9. Go back to step 6 until no item is `pending`. Then offer to revisit the skipped items. If the user says yes, serve them through steps 6 to 8 the same way, and any answer replaces `skipped`.

### Summary and apply

10. Print a summary: counts of approved, edited, rewritten, cut and skipped, then the IDs under each. Ask the user to confirm it. If they want to change an answer, change it through step 8 and print the summary again. Do not touch any contract file before the summary is confirmed.
11. Apply the decisions in `WT`, to the four contract files only:
    - Approve, Edit and Rewrite: set the item's status to `approved`. If `text` is set, replace the main line with it. If `fields` is set, replace those fields. For `quality.md`, edit the Pass bar or In short cell and the Status cell of that table row.
    - Cut: remove the item (its whole block, or its table row in `quality.md`). Leave the numbering gap. Do not renumber, because other files cite the IDs.
    - Skip and pending: leave the item as it is, `draft`.
12. Commit by file name, one commit for the contract files that changed (for example `git -C WT add quality.md taste.md conventions.md failures.md`, naming only those that changed) with the message `docs(taste-review): apply review decisions`. Also add `taste-review/state.json` if it changed. Push with `git -C WT push -u origin taste-review`.
13. Open ONE pull request to main in the Atelier repo, with the summary from step 10 in its description. First check for an existing one: `gh pr list --head taste-review --state open`. If one is open, update its description with `gh pr edit` instead of creating a second. Otherwise run `gh pr create --base main --head taste-review --title "Apply taste review decisions" --body-file <file holding the summary>`, run from inside `WT`.
14. Give the user the PR link. Never merge it. Say that skipped and pending items stay as drafts and the next `/taste-review` run picks them up from the same branch.
