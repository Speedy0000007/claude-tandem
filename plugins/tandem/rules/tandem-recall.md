<!-- tandem v1.3.0 -->
# Tandem Recall

Maintain progress.md in your auto-memory directory as a hybrid working state + session log. The Tandem SessionEnd hook reads this file.

**Init:** Create progress.md on your first significant action if it doesn't exist. Start with the frontmatter and Working State template below.

## Structure

progress.md has frontmatter plus two body parts:

### Frontmatter

```yaml
---
framework: default
project: tandem
type: session-progress
target: <project-directory-name>
depends_on: []
feeds: [MEMORY.md]
---
```

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

## CLAUDE.md promotion

The data funnel flows: progress.md → MEMORY.md → CLAUDE.md. Each level is less contextual and more instructional.

- **progress.md** — what's happening right now, high context, ephemeral
- **MEMORY.md** — what we've learned recently, project knowledge, compacted regularly
- **CLAUDE.md** — permanent knowledge and instructions, biased toward directives. Commands, gotchas, do's and don'ts, conventions, and key facts about the project. The culmination of everything learned across sessions, refined into guidance for future agents.

Proactively promote stable [P1] patterns from MEMORY.md to CLAUDE.md. Prefer instructions over observations: distill knowledge into rules, constraints, and conventions where possible. Pure facts (e.g., "we use Postgres", "the API is REST") belong too, but the bulk should be actionable.

**What qualifies:**
- Gotchas that burned time and should never recur (e.g., "macOS grep doesn't support `-oP`")
- Conventions confirmed across sessions (e.g., "always use Conventional Commits")
- Specific commands or patterns to use or avoid
- Architectural constraints that shape how to build

**Which CLAUDE.md to target:**
- **Global** (applies across all projects) → `~/.claude/CLAUDE.md`
- **Project** (applies to this repo) → project root `CLAUDE.md`
- **Subdomain** (cohesive project area, e.g., frontend, API, database) → nested `CLAUDE.md` in that directory. Only create when the subdomain has enough distinct conventions to warrant it.

When promoting, remove or downgrade the MEMORY.md entry. CLAUDE.md is the permanent instruction set; MEMORY.md is the working buffer.
