---
description: "Use when the user wants to check which Tandem features are installed, verify hooks are configured correctly, or see profile and memory stats."
---

# Tandem Status

Diagnostic check for Tandem installation. Read-only — no writes, no LLM calls.

## What to Report

### Features

Check each feature's installation state:

**Clarify:**
- Hook: Check if `detect-raw-input.sh` is registered as a UserPromptSubmit hook
- Skill: Check if this plugin provides the `clarify` skill
- Status: Installed / Not installed

**Recall:**
- Rules file: Check if `~/.claude/rules/tandem-recall.md` exists
- CLAUDE.md section: Check if `<!-- tandem:start -->` exists in `~/.claude/CLAUDE.md`
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
- Recurrence themes: count from `~/.tandem/state/recurrence.json`, list themes with count >= 3

### Global Memory

- `~/.tandem/memory/global.md`: entry count, last updated date
- If no entries: "No cross-project activity logged yet"

### Profile Stats (if Grow installed)

- Profile directory path
- File count, total lines across all `.md` files
- Lines by file/topic
- Career context: filled in / template only / missing

### Re-provisioning

If any rules files are missing, offer to re-provision them by deleting `~/.tandem/.provisioned` and restarting a session. The user may have intentionally deleted rules files to disable a feature — ask before re-creating.

To fully uninstall: remove `<!-- tandem:start -->` section from `~/.claude/CLAUDE.md` and delete `~/.claude/rules/tandem-*.md`. Your profile at `~/.tandem/` is yours to keep or remove.

## Execution

Gather ALL data in a single bash call — one script that checks files, counts lines, reads dates. Avoid multiple tool rounds. Read `hooks.json` in the same pass if needed.

## Output Format

Output ONLY the status block below — no preamble, no explanation, no follow-up notes. If something needs attention (missing rules file, empty profile), note it inline.

```
Tandem v1.1.0

Clarify .... installed
Recall ..... installed
Grow ....... installed (profile: 4 files, 156 lines)

Memory: MEMORY.md 142 lines, last compacted 2h ago
Global: 12 entries, last updated today
Recurrence: 8 themes tracked, 3 with count >= 3
Profile: ~/.tandem/profile/ (career context: filled)
```

Adapt based on what's installed — don't show memory stats if Recall isn't installed, etc.
