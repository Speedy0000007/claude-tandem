---
description: "Use when the user wants to review their technical profile, search their freeform profile, prepare for technical discussions, or analyse skill gaps. Also use when the user invokes /tandem:grow with any subcommand."
---

# Tandem Grow

Review your freeform technical profile built automatically from your sessions, search for knowledge, prepare for discussions, and identify high-impact skill gaps.

## Profile Directory

Default: `~/.tandem/profile/` (override with `TANDEM_PROFILE_DIR` env var).

Your technical profile is stored as markdown files organised by topic. Content is freeform — the SessionEnd extraction hook organises learnings however best serves you. Files may contain concepts, patterns, tradeoffs, code references, or any other learning worth persisting.

## Commands

### `/tandem:grow` (no args)

Show a summary of the technical profile:
- File count and total lines across all `.md` files
- Lines by file/topic
- Recent changes (files modified in the last 7 days, based on file modification time)

Read all `.md` files in the profile directory.

### `/tandem:grow search [topic]`

Search across all profile files for a topic. Show matching entries with full content. Use case-insensitive grep across the profile directory.

### `/tandem:grow prep [topic]`

Surface relevant knowledge from the profile with discussion framing for design reviews, architecture discussions, or technical conversations. For each relevant entry:
- The core concept and tradeoff
- How to bring it up naturally in discussion
- Questions it raises or connects to

### `/tandem:grow gaps`

The flagship command. Cross-references five data sources to produce actionable learning priorities:

1. **Profile** (what you've learned) — from the profile directory
2. **Insights facets** (where you have friction) — from `~/.claude/usage-data/facets/*.json`. One JSON file per session (named by session UUID). Read the files and make use of whatever fields are present — the schema is owned by Claude Code and may evolve. As of early 2025, known fields include `friction_counts`, `goal_categories`, `outcome`, `friction_detail`, `brief_summary`, among others. Don't assume a fixed schema; adapt to what you find.
3. **Career context** (where you want to go) — from `career-context.md` goals
4. **Recurrence** (what keeps coming up) — from `~/.tandem/state/recurrence.json`
5. **Global activity** (what you've been working on across projects) — from `~/.tandem/memory/global.md`. Shows which projects and technical areas are most active recently, helping weight gaps by relevance to current work.

Analysis steps:
1. Read all profile files and categorise by technical domain
2. Read recent facet files (last 30 days) and aggregate friction by domain
3. Read career-context.md for stated goals
4. Read recurrence.json for theme counts
5. Read `~/.tandem/memory/global.md` for recent cross-project activity to weight domains by current relevance
6. Identify areas where: high friction + thin profile coverage + alignment with goals + **high recurrence count** + **recent cross-project activity** = strongest signal
6. Output a prioritised list: what would make the biggest difference to learn next, and why

Format each gap as:
- **Area**: [technical domain]
- **Signal**: [what the friction data shows — e.g., "wrong_approach in 5 of last 10 database sessions"]
- **Recurrence**: [theme count from recurrence.json, if applicable]
- **Current knowledge**: [how much profile coverage exists in this area]
- **Recommendation**: [specific concept or pattern to learn, with a concrete starting point]
- **Impact**: [why this matters for their stated goals]

If high-friction areas overlap with potential CLAUDE.md rules, note: "Consider also making this a permanent rule via Recall promotion."

## No Profile Yet?

If the profile directory is empty or only contains the career-context template, guide the user:
1. Fill in career-context.md with their background and goals
2. Explain that your profile builds automatically as you work
3. Suggest running `/tandem:grow gaps` after a few sessions of normal usage
