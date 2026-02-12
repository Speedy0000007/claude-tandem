---
description: "Use when the user wants to squash Tandem auto-commits into a clean commit. Also use when the user mentions 'squash auto-commits', 'clean up checkpoints', or 'squash tandem commits'."
---

# Tandem Squash

Squash consecutive Tandem auto-commits from HEAD into a single clean commit.

## Steps

1. Check for consecutive auto-commits from HEAD. A commit is a Tandem auto-commit if its body contains the trailer `Tandem-Auto-Commit: true` or its subject is `chore(tandem): session checkpoint`.

2. Walk HEAD backwards counting consecutive auto-commits. Stop at the first non-auto-commit.

3. If no auto-commits found, tell the user: "No Tandem auto-commits at HEAD. Nothing to squash."

4. If auto-commits found, report what will be squashed:
   - How many auto-commits
   - The short log of those commits

5. Run `git reset --soft HEAD~N` where N is the count.

6. If `$ARGUMENTS` contains a commit message, use it. Otherwise, ask the user what commit message to use. Suggest a message based on the progress notes in the auto-commit bodies.

7. Commit the staged changes with the user's message. The commit must follow conventional commit format with a body (the normal validate-commit hook will enforce this).

8. Confirm: show the new commit's short log entry.
