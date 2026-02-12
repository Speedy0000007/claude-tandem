# Tandem — Claude Code Plugin

## What this is

A Claude Code plugin with three features: Clarify (input quality), Recall (memory management), Grow (user learning). Ships as shell scripts + SKILL.md files — no Node, no Python, no background processes.

## Core ethos: enhance, never replace

Claude Code already has auto-memory, MEMORY.md, context compaction, and a hook system. Tandem fills gaps in the native systems — it never builds parallel infrastructure. If Claude Code ships a native version of something Tandem does, Tandem should get out of the way. Every feature should trace back to: "Claude Code doesn't do X natively, so we add it using Claude Code's own conventions."

## Architecture constraints

- **Shell scripts only** — all scripts in `scripts/` are bash. No runtime dependencies beyond `jq` and `claude` CLI.
- **`${CLAUDE_PLUGIN_ROOT}`** — all paths in `hooks/hooks.json` use this env var. Scripts that need plugin-relative paths (e.g., `session-start.sh` for provisioning) resolve it via `CLAUDE_PLUGIN_ROOT` with a fallback to `$(dirname "$(dirname "$0")")`.
- **Auto-memory directory** — computed from CWD: `~/.claude/projects/$(echo "$CWD" | sed 's|/|-|g')/memory/`. This matches Claude Code's native convention. Every script that touches progress.md or MEMORY.md uses this pattern.
- **Zero repo files** — Tandem never creates files inside user repositories. All data goes to `~/.claude/` (rules, memory) or `~/.tandem/` (profile).
- **SessionEnd hooks** — sync hook with fast exit. Prints informational message (visible to user), then backgrounds LLM calls (`claude -p --model haiku --max-budget-usd 0.05`) in a subshell and exits immediately.
- **PreCompact hook** — captures current state snapshot + progress safety net before compaction. Uses `--max-budget-usd 0.03`. Always fires (state snapshot), but only extracts progress when progress.md is stale (>2 min).
- **TaskCompleted hook** — async, no LLM call. Just checks progress.md staleness (>5 min) and outputs a `systemMessage` nudge if stale.
- **Rules files** — provisioned to `~/.claude/rules/tandem-*.md` by `session-start.sh`. Install = copy, uninstall = delete. Never patch user's CLAUDE.md.
- **Skill naming** — SKILL.md frontmatter uses short `name` (e.g., `clarify`), no prefix. The plugin system adds `tandem:` automatically.

## Build conventions

- Hook definitions live in `hooks/hooks.json`, not in individual scripts
- SessionStart fires on `startup|resume|compact` — fully idempotent, handles post-compaction state recovery
- SessionEnd runs a single `session-end.sh`: prints summary to user (sync), then backgrounds compaction (critical) + extraction (best effort) + cleanup in a subshell
- PreCompact writes ephemeral `## Pre-compaction State` to progress.md — consumed by SessionStart, never reaches SessionEnd
- TaskCompleted is async (`"async": true`) — no blocking, nudge delivered on next turn
- Scripts exit 0 on all paths — hook failures should be silent to the user
- Scripts exit early when preconditions aren't met (no progress.md = no LLM call)
- Atomic writes: write to temp file, then `mv` to target

## File layout

```
.claude-plugin/     Plugin manifests
hooks/              Hook wiring (hooks.json)
scripts/            All executable hook scripts
skills/             SKILL.md files (clarify, grow, status)
rules/              Source rules files (provisioned to ~/.claude/rules/)
templates/          Profile bootstrap templates

Runtime data (outside repo):
~/.tandem/profile/          User's technical profile (Grow)
~/.tandem/state/            Recurrence themes, state files
~/.tandem/memory/global.md  Cross-project activity log (30 entries max)
```

## Testing

No test framework. Verify scripts manually:
- `echo '{"prompt":"test"}' | ./scripts/detect-raw-input.sh` — should exit silently (too short)
- `echo '{"cwd":"/tmp/test"}' | ./scripts/session-start.sh` — should provision if first run
- `echo '{"cwd":"/tmp/test","task_subject":"Add auth"}' | ./scripts/task-completed.sh` — should output systemMessage if progress.md is stale
- `echo '{"cwd":"/tmp/test","transcript_path":"/path/to/file.jsonl"}' | ./scripts/pre-compact.sh` — should call haiku and append to progress.md
- Check exit codes: all scripts should exit 0 regardless of outcome

## Plan reference

Build spec and product docs: `docs/product/`
