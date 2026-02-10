---
name: grow
version: "1.0.0"
description: "Use when the user wants to review their technical profile, search for pattern cards, prepare for technical discussions, or analyse skill gaps. Also use when the user invokes /tandem:grow with any subcommand."
---

# Tandem Grow

Review your technical learning profile, search pattern cards, prepare for discussions, and identify high-impact skill gaps.

## Profile Directory

Default: `~/.tandem/profile/` (override with `TANDEM_PROFILE_DIR` env var).

Pattern cards are stored as markdown files organised by topic (e.g., `react-patterns.md`, `system-design.md`). These are created automatically by the SessionEnd extraction hook.

## Commands

### `/tandem:grow` (no args)

Show a summary of all pattern cards across profile files:
- Count by file/topic
- Recent additions (cards added in the last 7 days, based on file modification time)
- Total card count

Read all `.md` files in the profile directory, parse `###` headings as individual cards.

### `/tandem:grow search [topic]`

Search across all profile files for a topic. Show matching cards with full content. Use case-insensitive grep across the profile directory.

### `/tandem:grow prep [topic]`

Surface relevant pattern cards with discussion framing for design reviews, architecture discussions, or technical conversations. For each relevant card:
- The core concept and tradeoff
- How to bring it up naturally in discussion
- Questions it raises or connects to

### `/tandem:grow gaps`

The flagship command. Cross-references three data sources to produce actionable learning priorities:

1. **Pattern cards** (what you've learned) — from the profile directory
2. **Insights facets** (where you have friction) — from `~/.claude/usage-data/facets/*.json`. One JSON file per session (named by session UUID). Read the files and make use of whatever fields are present — the schema is owned by Claude Code and may evolve. As of early 2025, known fields include `friction_counts`, `goal_categories`, `outcome`, `friction_detail`, `brief_summary`, among others. Don't assume a fixed schema; adapt to what you find.
3. **Career context** (where you want to go) — from `career-context.md` goals

Analysis steps:
1. Read all pattern cards and categorise by technical domain
2. Read recent facet files (last 30 days) and aggregate friction by domain
3. Read career-context.md for stated goals
4. Identify areas where: high friction + few pattern cards + alignment with goals
5. Output a prioritised list: what would make the biggest difference to learn next, and why

Format each gap as:
- **Area**: [technical domain]
- **Signal**: [what the friction data shows — e.g., "wrong_approach in 5 of last 10 database sessions"]
- **Current knowledge**: [how many pattern cards exist in this area]
- **Recommendation**: [specific concept or pattern to learn, with a concrete starting point]
- **Impact**: [why this matters for their stated goals]

If high-friction areas overlap with potential CLAUDE.md rules, note: "Consider also making this a permanent rule via Recall promotion."

## No Profile Yet?

If the profile directory is empty or only contains the career-context template, guide the user:
1. Fill in career-context.md with their background and goals
2. Explain that pattern cards accumulate automatically as they work
3. Suggest running `/tandem:grow gaps` after a few sessions of normal usage
