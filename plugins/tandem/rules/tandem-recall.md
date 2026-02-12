<!-- tandem v1.3.0 -->
# Tandem Recall

Maintain progress.md in your auto-memory directory as a hybrid working state + session log. The Tandem SessionEnd hook reads this file.

**Init:** Create progress.md on your first significant action if it doesn't exist. Start with the Working State template below.

## Structure

progress.md has two parts:

### 1. Working State (rewrite as context changes)

<!-- working-state:start -->
## Working State
**Current task:** [what you're actively doing]
**Approach:** [chosen approach and why]
**Blockers:** [unresolved issues, if any]
**Key files:** [files being modified]
<!-- working-state:end -->

Rewrite this section (between the markers) when starting a new task, changing approach, or resolving a blocker. This is a snapshot of "right now", not a log.

### 2. Session Log (append-only, below the markers)

Brief notes after completing work, making decisions, or changing approach. Each entry: what was done + decision rationale + outcome.

When creating or working on a plan file, note its full path.

## Priority annotations

When writing directly to MEMORY.md, prefix entries:
- [P1] architectural decisions, user preferences, recurring patterns
- [P2] current project state, recent decisions
- [P3] one-off details unlikely to survive next compaction

## Dates

Include (observed: YYYY-MM-DD) on MEMORY.md entries to aid temporal reasoning during compaction.

**MEMORY.md:** Write patterns worth persisting to MEMORY.md with [P1]/[P2]/[P3] priority and (observed: YYYY-MM-DD) date. The SessionEnd hook compacts to stay under 200 lines.
