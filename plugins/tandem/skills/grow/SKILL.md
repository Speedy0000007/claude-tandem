---
description: "Use when the user wants to review their technical profile, analyse skill gaps, or prepare for technical discussions. Also use when the user invokes /tandem:grow with any subcommand."
---

# Tandem Grow

Review your technical profile built automatically from your sessions and identify high-impact skill gaps.

## Profile

A single `USER.md` file at `~/.tandem/profile/USER.md` (override directory with `TANDEM_PROFILE_DIR`).

Three sections:
- **Career Context** — role, stack, strengths, goals
- **Technical Understanding** — what you know well (Grow won't repeat these)
- **Growth Edges** — where you're building depth (nudge targets)

Updated automatically at session end when the session reveals something about understanding level. Kept under 80 lines.

## Commands

### `/tandem:grow` (no args)

Show the user's profile:
- Read and display `USER.md`
- Show line count and last modified date
- If profile is empty or only contains the template, guide the user to fill in Career Context

### `/tandem:grow gaps`

Cross-references five data sources to produce actionable learning priorities:

1. **Profile** (what you know) — from `USER.md`
2. **Insights facets** (where you have friction) — from `~/.claude/usage-data/facets/*.json`. Read files and adapt to whatever fields are present.
3. **Career context** (where you want to go) — from the Career Context section of `USER.md`
4. **Recurrence** (what keeps coming up) — from `~/.tandem/state/recurrence.json`
5. **Global activity** (what you've been working on across projects) — from `~/.tandem/memory/global.md`

Analysis steps:
1. Read `USER.md` and categorise by technical domain
2. Read recent facet files (last 30 days) and aggregate friction by domain
3. Read recurrence.json for theme counts
4. Read global.md for recent cross-project activity to weight domains by current relevance
5. Identify areas where: high friction + thin profile coverage + alignment with goals + high recurrence = strongest signal
6. Output a prioritised list: what would make the biggest difference to learn next, and why

Format each gap as:
- **Area**: [technical domain]
- **Signal**: [what the friction data shows]
- **Recurrence**: [theme count from recurrence.json, if applicable]
- **Current knowledge**: [how much profile coverage exists]
- **Recommendation**: [specific concept or pattern to learn, with a concrete starting point]
- **Impact**: [why this matters for their stated goals]

## No Profile Yet?

If `USER.md` doesn't exist or only contains the template comments, guide the user:
1. Fill in Career Context with their background and goals
2. Explain that the profile builds automatically as they work
3. Suggest running `/tandem:grow gaps` after a few sessions of normal usage
