# Tandem — Claude Code Plugin

## What this is

A Claude Code plugin with three pillars: Clarify (input quality), Recall (memory management), Grow (user learning). Ships as shell scripts + SKILL.md files — no Node, no Python, no background processes.

## Architecture constraints

- **Shell scripts only** — all scripts in `scripts/` are bash. No runtime dependencies beyond `jq` and `claude` CLI.
- **`${CLAUDE_PLUGIN_ROOT}`** — all paths in `hooks/hooks.json` use this env var. Scripts that need plugin-relative paths (e.g., `session-start.sh` for provisioning) resolve it via `CLAUDE_PLUGIN_ROOT` with a fallback to `$(dirname "$(dirname "$0")")`.
- **Auto-memory directory** — computed from CWD: `~/.claude/projects/$(echo "$CWD" | sed 's|/|-|g')/memory/`. This matches Claude Code's native convention. Every script that touches progress.md or MEMORY.md uses this pattern.
- **Zero repo files** — Tandem never creates files inside user repositories. All data goes to `~/.claude/` (rules, memory) or `~/.tandem/` (profile).
- **SessionEnd hooks** — only `type: "command"` is supported. LLM calls use `claude -p --model haiku --max-budget-usd 0.05`.
- **Rules files** — provisioned to `~/.claude/rules/tandem-*.md` by `session-start.sh`. Install = copy, uninstall = delete. Never patch user's CLAUDE.md.
- **Skill naming** — SKILL.md frontmatter uses short `name` (e.g., `clarify`), no prefix. The plugin system adds `tandem:` automatically.

## Build conventions

- Hook definitions live in `hooks/hooks.json`, not in individual scripts
- SessionEnd runs a single `session-end.sh` that executes compaction first (critical), then extraction (best effort), then cleans up progress.md
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
```

## Testing

No test framework. Verify scripts manually:
- `echo '{"prompt":"test"}' | ./scripts/detect-raw-input.sh` — should exit silently (too short)
- `echo '{"cwd":"/tmp/test"}' | ./scripts/session-start.sh` — should provision if first run
- Check exit codes: all scripts should exit 0 regardless of outcome

## Plan reference

Build spec and product docs: `docs/product/`
