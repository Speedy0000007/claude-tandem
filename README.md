<p align="center">
  <img src="assets/logo.png" alt="Tandem logo" width="320">
</p>

<h1 align="center">Tandem</h1>

<p align="center">
  <strong>Compound learning for Claude Code — every session makes the next one better.</strong>
</p>

<p align="center">
  <sub>Claude gets sharper. You get smarter.</sub>
</p>

```bash
claude "Let's work in Tandem"
```

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/version-v1.2.1-green.svg" alt="Version: v1.2.1">
  <img src="https://img.shields.io/badge/platform-Claude%20Code-blueviolet.svg" alt="Platform: Claude Code">
  <img src="https://img.shields.io/badge/shell-bash-orange.svg" alt="Shell: bash">
  <a href="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml"><img src="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
</p>

---

## What it does

Tandem is a Claude Code plugin with four features:

<table>
  <tr>
    <td align="center" width="25%"><strong>Clarify</strong><br>Clarifies input</td>
    <td align="center" width="25%"><strong>Recall</strong><br>Recalls working memory</td>
    <td align="center" width="25%"><strong>Commit</strong><br>Commits durable memory</td>
    <td align="center" width="25%"><strong>Grow</strong><br>Enhances both user and model</td>
  </tr>
</table>

Each feature is independently valuable. Combined, they compound: better input leads to a smarter agent, richer commit history captures the reasoning permanently, and learning compounds across every session.

---

## Install

See [INSTALL.md](INSTALL.md) for detailed setup instructions.

**Quick start:**

```bash
# Add the marketplace
/plugin marketplace add github.com/jonny981/claude-tandem

# Install
/plugin install tandem
```

Then start your first session:

```bash
claude "Let's work in Tandem"
```

Tandem provisions itself on first run and you'll see the startup display immediately. Run `/tandem:status` to verify everything is working.

To start a session without Tandem features, use `claude "Skip Tandem"` instead.

**Documentation:**
- [INSTALL.md](INSTALL.md) — detailed installation and setup
- [CONFIGURATION.md](CONFIGURATION.md) — configuration options and customization
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — common issues and solutions

---

## Philosophy: enhance, never replace

Claude Code already has auto-memory, MEMORY.md, context compaction, and a hook system. Tandem doesn't build parallel infrastructure — it makes the native systems work better.

- **Auto-memory writes MEMORY.md.** Tandem compacts it to stay under the 200-line loading limit.
- **Claude Code has no cross-project awareness.** Tandem adds a lightweight rolling log so sessions in one repo know what you've been doing elsewhere.
- **Claude Code has no session bridge.** Tandem adds progress.md alongside MEMORY.md — same directory, same conventions.
- **Git is already the permanent record.** Tandem enriches commit messages with session context so nothing is lost to compaction. Your thinking persists in `git log` forever.
- **Rules files, hooks, skills** — all use Claude Code's native plugin system. No MCP servers, no background processes, no databases.

If Claude Code ships a native version of something Tandem does, Tandem should get out of the way. The goal is to fill gaps, not compete.

---

## Features

### Clarify

Garbage in, garbage out — the oldest engineering principle. Clarify fixes the input.

A UserPromptSubmit hook detects long, unstructured input (dictation, brain dumps, walls of text) and automatically restructures it using an 8-section prompt framework backed by Anthropic's official prompting best practices.

**What you see:** Your messy input executes cleanly. A `Clarified.` indicator appears when restructuring happened.

**Configurable thresholds:**
- `PREPROCESSOR_MIN_LENGTH` — minimum characters before checking structure (default: 500)
- `PREPROCESSOR_MAX_STRUCTURE` — max structural markers before skipping (default: 2)
- `TANDEM_CLARIFY_SHOW=1` — print the restructured version before executing (default: off)

### Recall

Claude already remembers. Recall makes it *good* at remembering.

- **Session bridge** — maintains `progress.md` alongside MEMORY.md, surviving context compaction within a session
- **Pre-compaction safety net** — a PreCompact hook captures the precise "where are we right now" before compaction compresses in-memory context. After compaction, SessionStart surfaces this snapshot so Claude picks up exactly where it left off
- **Memory compaction** — at session end, rewrites MEMORY.md to stay under 200 lines (the native loading limit). Keeps what's relevant, lets stale details decay
- **Cross-project context** — at session end, logs a summary of what happened to a global rolling log (`~/.tandem/memory/global.md`, 30 entries max). At session start, Claude sees recent activity from other projects for cross-repo awareness
- **Progress nudges** — when a task completes and progress.md is stale, an async nudge reminds Claude to record what happened
- **Pattern promotion** — recurring patterns are surfaced as candidates for CLAUDE.md with suggested promotion targets

**What you see:** `Recalled.` at session start means the previous session's memory was compacted. `Recent work in other projects:` shows what you've been doing elsewhere. After compaction, `Resuming. Before compaction you were: ...` restores your exact position. If a session ends abnormally, stale progress is detected and recovered next time.

### Commit

Git is the only permanent record. Progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

Tandem treats every commit as a context restoration point. Not just what changed, but why: what process led here, what was considered, what constraints existed, what was known and unknown at the time.

- **Commit body enforcement** — a PreToolUse hook ensures every commit has a body that captures the developer's thinking. Subject line follows Conventional Commits. Body captures the why, the what-else, the what-next.
- **Session checkpoints** — at session end, before memory compaction, Tandem auto-commits a checkpoint that preserves the full session context in git. Only commits when there are actual staged changes.
- **`## Last Session` continuation** — every memory compaction writes a `## Last Session` section to MEMORY.md with what was being worked on, where it left off, and what comes next. The next session picks up immediately, even when no code was changed.
- **Creative safety net** — when context is always preserved, you can be brave. Try things. Explore freely. If you revert, the reasoning that led to the attempt is still in the commit history.

The result: `git log` becomes a complete, queryable history of every AI session. Combined with any tool that can read git history, you can ask "why is this code the way it is?" at any point and get the full reasoning from the session that wrote it.

**What you see:** If you try to commit without a body, the hook blocks it and feeds you session context to write from. At session end, `Session captured` confirms the checkpoint was written. MEMORY.md always has a `## Last Session` section with continuation context.

**Configurable:**
- `TANDEM_AUTO_COMMIT=0` — disable auto-commits at session end (default: enabled)

### Grow

The user gets smarter. Learns as they go.

- **Natural concept mentions** — Claude weaves technical concepts into responses as a senior colleague would
- **Pattern cards** — concepts are captured during sessions and formalised into searchable cards in `~/.tandem/profile/`
- **Gap analysis** — `/tandem:grow gaps` cross-references your pattern cards against friction data from `/insights` and your career goals to identify what would make the biggest difference to learn next

**Commands:**
- `/tandem:grow` — summary of all pattern cards
- `/tandem:grow search [topic]` — find cards by topic
- `/tandem:grow prep [topic]` — prepare for technical discussions
- `/tandem:grow gaps` — identify high-impact learning priorities

**Profile directory:** `~/.tandem/profile/` (override with `TANDEM_PROFILE_DIR`)

---

## Status

```
/tandem:status
```

Reports which features are installed, hook health, memory stats, and profile stats.

---

## How it works

### No background processes

Tandem uses Claude Code's native hook system. Zero background services, zero databases, zero file pollution in your repos.

| Event | Script | Purpose |
|-------|--------|---------|
| PreToolUse | `validate-commit.sh` | Conventional commit format + body enforcement |
| UserPromptSubmit | `detect-raw-input.sh` | Clarify detection |
| SessionStart | `session-start.sh` | Provisioning, post-compaction state recovery, cross-project context, stale progress detection |
| SessionEnd | `session-end.sh` | Session checkpoint (phase 0) + memory compaction (phase 1) + pattern extraction (phase 2) + global log (phase 3) |
| PreCompact | `pre-compact.sh` | Current state snapshot + progress safety net |
| TaskCompleted | `task-completed.sh` | Async progress nudge when progress.md is stale |

### Cost

LLM-calling hooks use `claude -p --model haiku` with budget caps:
- **SessionEnd** — `--max-budget-usd 0.05`. Only fires when there's a `progress.md` to process. Typical cost: $0.001-0.01 per session end.
- **PreCompact** — `--max-budget-usd 0.03`. Fires before each compaction to capture current state. Typical cost: $0.01-0.02 per compaction.
- **TaskCompleted** — no LLM call. Just a file stat check (milliseconds).

### Files created

Tandem creates zero files in your repositories. Everything lives in:
- `~/.claude/rules/tandem-*.md` — behavioural rules including commit body enforcement (install = copy, uninstall = delete)
- `~/.claude/projects/{project}/memory/progress.md` — session bridge (alongside native MEMORY.md)
- `~/.tandem/profile/` — learning profile
- `~/.tandem/memory/global.md` — cross-project activity log (30 entries max)

---

## Uninstall

**Remove plugin:**

```bash
/plugin uninstall tandem
```

This removes the plugin (skills, hooks, scripts). Your data is preserved.

**Complete removal (including all data):**

1. **Remove rules files:**
   ```bash
   rm ~/.claude/rules/tandem-*.md
   ```

2. **Remove CLAUDE.md section:**
   Open `~/.claude/CLAUDE.md` and delete the section between `<!-- tandem:start -->` and `<!-- tandem:end -->` (inclusive).

3. **Remove data directories:**
   ```bash
   # Profile and pattern cards
   rm -rf ~/.tandem/profile/

   # State files and recurrence data
   rm -rf ~/.tandem/state/

   # Global cross-project memory
   rm -rf ~/.tandem/memory/

   # Provisioning marker
   rm -rf ~/.tandem/.provisioned
   ```

4. **Remove project memory files:**
   ```bash
   # progress.md files from all projects
   find ~/.claude/projects -name progress.md -delete

   # Tandem session markers
   find ~/.claude/projects -name .tandem-last-compaction -delete
   ```

**Partial disable:**

To disable individual features without full uninstall:
- **Disable Clarify:** `rm ~/.claude/rules/tandem-clarify.md`
- **Disable Recall:** `rm ~/.claude/rules/tandem-recall.md` + remove CLAUDE.md section
- **Disable Commit:** `rm ~/.claude/rules/tandem-commits.md` + set `TANDEM_AUTO_COMMIT=0`
- **Disable Grow:** `rm ~/.claude/rules/tandem-grow.md`

---

## License

MIT
