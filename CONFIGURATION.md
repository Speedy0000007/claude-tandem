# Tandem Configuration

Tandem uses environment variables to control behavior across its three features (Clarify, Recall, Grow). All configuration is optional — defaults are chosen for minimal friction.

## Environment Variables

| Variable | Default | Purpose | Example |
|----------|---------|---------|---------|
| `TANDEM_CLARIFY_MIN_LENGTH` | `200` | Minimum prompt character count before Clarify assessment | `500` (skip short prompts) |
| `TANDEM_CLARIFY_QUIET` | `0` | Suppress "Clarified." status indicator | `1` (silent mode) |
| `TANDEM_PROFILE_DIR` | `~/.tandem/profile` | Location for learning profile files (Grow) | `~/Dropbox/tandem` (sync across machines) |
| `TANDEM_QUIET` | `0` | Suppress all Tandem status output | `1` (dogfooding mode) |

### Setting Environment Variables

**Shell profile (persistent):**

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export TANDEM_CLARIFY_MIN_LENGTH=300
export TANDEM_PROFILE_DIR="$HOME/Dropbox/tandem"
```

**Per-session (temporary):**

```bash
TANDEM_CLARIFY_QUIET=1 claude
```

**Testing specific variables:**

```bash
TANDEM_CLARIFY_MIN_LENGTH=100 echo '{"prompt":"test prompt here"}' | ./plugins/tandem/scripts/detect-raw-input.sh
```

## Hook Input Reference

Tandem hooks receive JSON input via stdin. Each hook reads specific fields:

### UserPromptSubmit Hook (`detect-raw-input.sh`)

**Reads:**
- `prompt` (string) — User's raw input text

**Example:**
```json
{"prompt": "add auth to the api"}
```

**Behavior:**
- If `prompt.length < TANDEM_CLARIFY_MIN_LENGTH`, exits early (no LLM call)
- Otherwise, calls Haiku to assess quality and restructure if needed
- Logs all decisions to `~/.tandem/logs/clarify.jsonl`

### SessionStart Hook (`session-start.sh`)

**Reads:**
- `cwd` (string) — Current working directory

**Example:**
```json
{"cwd": "/Users/jonny/dev/my-project"}
```

**Behavior:**
- First run: provisions rules files to `~/.claude/rules/` and profile directory
- Every run: checks for stale progress.md, version upgrades, CLAUDE.md section injection
- Post-compaction: displays "Resuming" state snapshot
- Computes auto-memory directory: `~/.claude/projects/$(echo "$cwd" | sed 's|/|-|g')/memory/`

### SessionEnd Hook (`session-end.sh`)

**Reads:**
- `cwd` (string) — Current working directory

**Example:**
```json
{"cwd": "/Users/jonny/dev/my-project"}
```

**Behavior:**
- Phase 1: Calls Haiku to compact MEMORY.md (budget: $0.05)
- Phase 2: Calls Haiku to extract learnings to profile (budget: $0.05)
- Phase 3: Updates global activity log (`~/.tandem/memory/global.md`)
- Only fires if `progress.md` exists (trivial sessions skip LLM calls)

### PreCompact Hook (`pre-compact.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `transcript_path` (string) — Path to session transcript JSONL file

**Example:**
```json
{
  "cwd": "/Users/jonny/dev/my-project",
  "transcript_path": "/tmp/claude-session-abc123.jsonl"
}
```

**Behavior:**
- Reads last 20KB of transcript
- Calls Haiku to extract current state snapshot (budget: $0.03)
- Appends `## Pre-compaction State` to progress.md (consumed by SessionStart)
- If progress.md is stale (>2 min), also extracts session progress

### TaskCompleted Hook (`task-completed.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `task_subject` (string, optional) — Completed task title

**Example:**
```json
{
  "cwd": "/Users/jonny/dev/my-project",
  "task_subject": "Add authentication middleware"
}
```

**Behavior:**
- No LLM call — just checks if progress.md is stale (>5 min)
- If stale, outputs systemMessage nudge to update progress.md
- Runs asynchronously (non-blocking)

## Hook Trigger Conditions

From `plugins/tandem/hooks/hooks.json`:

| Hook | Matcher | Timeout | Async |
|------|---------|---------|-------|
| **UserPromptSubmit** | Always | 15s | No |
| **SessionStart** | `startup\|resume\|compact` | Default | No |
| **SessionEnd** | Always | 120s | No |
| **PreCompact** | Always | 30s | No |
| **TaskCompleted** | Always | Default | Yes |

**Notes:**
- SessionStart fires on `startup` (first launch), `resume` (after idle), and `compact` (post-compaction recovery)
- TaskCompleted is async — won't block task completion if hook is slow

## File Locations

Tandem never writes to user repositories. All data goes to Claude Code's native directories:

| Path | Purpose |
|------|---------|
| `~/.claude/rules/tandem-recall.md` | Provisioned rule file (session progress guidelines) |
| `~/.claude/rules/tandem-grow.md` | Provisioned rule file (learning mention guidelines) |
| `~/.claude/CLAUDE.md` | Tandem injects a `<!-- tandem:start -->` section here |
| `~/.claude/projects/<cwd-sanitized>/memory/progress.md` | Session progress log (auto-memory) |
| `~/.claude/projects/<cwd-sanitized>/memory/MEMORY.md` | Compacted memory (native Claude Code convention) |
| `~/.tandem/profile/*.md` | User's learning profile (Grow) |
| `~/.tandem/memory/global.md` | Cross-project activity log (30 entries max) |
| `~/.tandem/state/recurrence.json` | Recurring theme tracker |
| `~/.tandem/logs/clarify.jsonl` | Clarify decision log (for review) |
| `~/.tandem/.provisioned` | First-run marker file |
| `~/.tandem/next-nudge` | Ephemeral learning nudge for next session |

**Auto-memory directory naming:**

Claude Code uses project-scoped directories. For CWD `/Users/jonny/dev/my-project`, the memory directory is:

```
~/.claude/projects/-Users-jonny-dev-my-project/memory/
```

All Tandem scripts follow this convention (see `session-start.sh:15`, `session-end.sh:14`, etc.).

## Budget Caps

Tandem uses conservative LLM budget caps to prevent runaway costs:

| Hook | Model | Budget | Purpose |
|------|-------|--------|---------|
| UserPromptSubmit | Haiku | $0.02 | Prompt restructuring |
| SessionEnd (Recall) | Haiku | $0.05 | MEMORY.md compaction |
| SessionEnd (Grow) | Haiku | $0.05 | Learning extraction |
| PreCompact | Haiku | $0.03 | State snapshot |

Total worst-case per session: **$0.15** (if all hooks fire with substantive content)

Typical session cost: **$0.03-$0.08** (PreCompact + SessionEnd, UserPromptSubmit skipped for short prompts)

## Logs and Debugging

**Clarify decision log:**

Every UserPromptSubmit hook writes a JSON line to `~/.tandem/logs/clarify.jsonl`:

```json
{
  "ts": "2026-02-11T14:23:45Z",
  "action": "restructured",
  "prompt_length": 287,
  "prompt": "add auth to the api",
  "result": "Add authentication to the API.\n\nImplement authentication middleware for the API endpoints..."
}
```

Actions: `skip` (prompt already clear) or `restructured` (Haiku rewrote it)

**Hook failures:**

All scripts exit 0 on all paths — hook failures are silent to avoid interrupting user flow. Check stderr for warnings:

```bash
# Run hooks manually to see stderr
echo '{"cwd":"'$PWD'"}' | ./plugins/tandem/scripts/session-start.sh 2>&1
```

**Memory corruption recovery:**

SessionStart detects corrupted MEMORY.md (< 5 lines, starts with refusal pattern) and rolls back to the latest backup:

```
[Tandem] Corrupted MEMORY.md detected (3 lines, refusal pattern: 1). Rolling back to backup from 2026-02-10 18:42.
```

Backups: `~/.claude/projects/<cwd-sanitized>/memory/.MEMORY.md.backup-<timestamp>` (last 3 kept)

## Advanced Configuration

### Custom Profile Location (Sync Across Machines)

```bash
export TANDEM_PROFILE_DIR="$HOME/Dropbox/Apps/Tandem"
```

Grow will write learning files to this directory. Useful for syncing your technical profile across multiple machines.

### Quiet Mode (Dogfooding)

```bash
export TANDEM_QUIET=1
export TANDEM_CLARIFY_QUIET=1
```

Suppresses all status indicators (`Recalled.`, `Grown.`, `Clarified.`). Used for dogfooding to avoid self-reference loops.

### Aggressive Clarify Threshold

```bash
export TANDEM_CLARIFY_MIN_LENGTH=100
```

Triggers Clarify on shorter prompts (useful if you frequently type stream-of-consciousness requests).

### Disable Clarify Entirely

Clarify fires on UserPromptSubmit. To disable:

1. Edit `~/.claude-plugin/hooks/hooks.json` (if you have overrides)
2. Remove the UserPromptSubmit hook entry
3. Or set a very high threshold: `export TANDEM_CLARIFY_MIN_LENGTH=10000`

## Hook Script Reference

| Script | Purpose | Link |
|--------|---------|------|
| `detect-raw-input.sh` | Clarify: assess and restructure user prompts | [plugins/tandem/scripts/detect-raw-input.sh](/plugins/tandem/scripts/detect-raw-input.sh) |
| `session-start.sh` | Provisioning, state recovery, status indicators | [plugins/tandem/scripts/session-start.sh](/plugins/tandem/scripts/session-start.sh) |
| `session-end.sh` | Recall (compaction) + Grow (extraction) | [plugins/tandem/scripts/session-end.sh](/plugins/tandem/scripts/session-end.sh) |
| `pre-compact.sh` | State snapshot before compaction | [plugins/tandem/scripts/pre-compact.sh](/plugins/tandem/scripts/pre-compact.sh) |
| `task-completed.sh` | Async progress.md staleness check | [plugins/tandem/scripts/task-completed.sh](/plugins/tandem/scripts/task-completed.sh) |

## Next Steps

- **Installation:** See [INSTALL.md](INSTALL.md) for setup instructions
- **Troubleshooting:** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- **Usage:** See [README.md](README.md) for feature overview
