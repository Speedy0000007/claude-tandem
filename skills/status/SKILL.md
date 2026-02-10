---
name: status
version: "1.0.0"
description: "Use when the user wants to check which Tandem pillars are installed, verify hooks are configured correctly, or see profile and memory stats."
---

# Tandem Status

Diagnostic check for Tandem installation. Read-only — no writes, no LLM calls.

## What to Report

### Pillars

Check each pillar's installation state:

**Clarify:**
- Hook: Check if `detect-raw-input.sh` is registered as a UserPromptSubmit hook
- Skill: Check if this plugin provides the `clarify` skill
- Status: Installed / Not installed

**Recall:**
- Rules file: Check if `~/.claude/rules/tandem-recall.md` exists
- Hook: Check if `session-end.sh` is registered as a SessionEnd hook
- Status: Installed / Not installed / Partially installed (rules file missing — offer to re-provision)

**Grow:**
- Rules file: Check if `~/.claude/rules/tandem-grow.md` exists
- Hook: Check if `session-end.sh` is registered as a SessionEnd hook
- Skill: Check if this plugin provides the `grow` skill
- Profile directory: Check if `~/.tandem/profile/` exists (or `TANDEM_PROFILE_DIR`)
- Status: Installed / Not installed / Partially installed (rules file or profile missing)

### Memory Stats (if Recall installed)

For the current project's auto-memory directory:
- MEMORY.md: line count, last modified date
- progress.md: exists? last modified date
- Promotion candidates: count of items in `## Promotion Candidates` section

### Profile Stats (if Grow installed)

- Profile directory path
- Pattern card count (total `###` headings across all `.md` files)
- Card count by file/topic
- Career context: filled in / template only / missing

### Re-provisioning

If any rules files are missing, offer to re-provision them by deleting `~/.tandem/.provisioned` and restarting a session. The user may have intentionally deleted rules files to disable a pillar — ask before re-creating.

## Output Format

Use a clean, scannable format:

```
Tandem v1.0.0

Clarify .... installed
Recall ..... installed
Grow ....... installed (profile: 12 cards across 4 topics)

Memory: MEMORY.md 142 lines, last compacted 2h ago
Profile: ~/.tandem/profile/ (career context: filled)
```

Adapt the format based on what's installed — don't show memory stats if Recall isn't installed, etc.
