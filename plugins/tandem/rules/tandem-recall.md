<!-- tandem v1.2.1 -->
# Tandem Recall

Maintain progress.md in your auto-memory directory (alongside MEMORY.md) as a running log. The Tandem SessionEnd hook reads this file.

**Init:** Create progress.md on your first significant action if it doesn't exist.

**When to write:**
- After completing a task or subtask
- After making a non-obvious decision or tradeoff
- After hitting a significant issue or changing approach
- When creating or working on a plan file, note its full path (e.g. "Plan: /path/to/plan-auth-redesign.md")

**Format:** Brief append-only notes. Each entry: what was done + decision rationale + outcome. Don't rewrite earlier entries.

**MEMORY.md:** When discovering user or codebase patterns worth persisting, write them to MEMORY.md. The SessionEnd hook will compact MEMORY.md to stay under 200 lines -- so write freely, knowing stale details will decay naturally.
