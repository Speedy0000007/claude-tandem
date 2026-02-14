<p align="center">
  <img src="assets/logo.png" alt="Tandem — companion plugin for Claude Code" width="320">
</p>

<h1 align="center">Tandem</h1>

<p align="center">
  <strong>A companion plugin for Claude Code that handles the work around the work.</strong>
</p>

<p align="center">
  <sub>Structured memory, session handover, input clarity, commit reasoning, and developer learning. Pure bash, one dependency (<code>jq</code>).</sub>
</p>

```bash
claude "Let's work in Tandem"
```

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/version-v1.3.0-green.svg" alt="Version: v1.3.0">
  <img src="https://img.shields.io/badge/platform-Claude%20Code-blueviolet.svg" alt="Platform: Claude Code">
  <img src="https://img.shields.io/badge/shell-bash-orange.svg" alt="Shell: bash">
  <a href="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml"><img src="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
</p>

---

## The problem

Claude Code has memory. MEMORY.md persists across sessions, auto-memory writes to it, CLAUDE.md is always loaded, and project rules carry forward. But there are gaps.

MEMORY.md is a flat file with a 200-line cap, no priority tiers, and no awareness of what matters most. Context compaction preserves a summary but loses the precise "where was I, what was I doing, what's next" detail needed to resume complex multi-session work. There's no session bridge, no cross-project awareness, and no mechanism to promote recurring patterns into permanent knowledge. Commit messages default to what changed, not why. And there's no structured way to surface what the developer is learning along the way.

Tandem fills these gaps through Claude Code's native hook system.

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
- [INSTALL.md](INSTALL.md): detailed installation and setup
- [CONFIGURATION.md](CONFIGURATION.md): configuration options and customization
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): common issues and solutions

---

## Features

Four features, each targeting a gap in the coding agent workflow:

<table>
  <tr>
    <td align="center" width="25%"><strong>Clarify</strong><br>Improves input</td>
    <td align="center" width="25%"><strong>Recall</strong><br>Structures memory</td>
    <td align="center" width="25%"><strong>Commit</strong><br>Preserves reasoning</td>
    <td align="center" width="25%"><strong>Grow</strong><br>Surfaces learning</td>
  </tr>
</table>

Each feature is independently valuable. Together, better input produces better agent output, structured memory carries context forward, enriched commits capture reasoning permanently, and learning surfaces naturally over time.

### Clarify

A UserPromptSubmit hook detects long or unstructured input (dictation, brain dumps, walls of text) and sends it to a lightweight LLM for assessment. Three outcomes: **SKIP** (already clear), **RESTRUCTURE** (rewritten for clarity), or **CLARIFY** (ambiguity detected, questions generated before work begins). The assessment also discovers relevant skills from your installed skill directories and suggests them alongside the outcome.

**What you see:** A `Clarified.` indicator appears when restructuring happened. If questions are needed, they appear before any work starts. Relevant skills are suggested when applicable.

**Configurable:**
- `TANDEM_CLARIFY_MIN_LENGTH`: minimum characters before assessment triggers (default: 200)
- `TANDEM_CLARIFY_MAX_LENGTH`: maximum characters before assessment is skipped (default: 5000)
- `TANDEM_CLARIFY_QUIET=1`: suppress branding in Clarify output (default: off)

### Recall

Claude Code has auto-memory and context compaction. Recall adds structure on top: priority tiers, session bridging, cross-project awareness, and safe compaction.

- **Session bridge via progress.md** maintains a two-part `progress.md` alongside MEMORY.md: a rewritable Working State snapshot (current task, approach, blockers, key files) and an append-only Session Log below. Survives context compaction. Persists across sessions, with Working State carrying forward until fresh work begins.
- **Session registry** tracks each session at `~/.tandem/sessions/<session-id>/` with pid, project, branch, heartbeat, and current task. Orphaned sessions (dead pid) are cleaned up automatically. Run `/tandem:sessions` to inspect.
- **Sibling awareness** discovers other active sessions on the same project at startup. The status line shows concurrent session count in yellow.
- **Pre-compaction safety net** captures the precise "where are we right now" before compaction via a PreCompact hook. When structured Working State markers exist, this is deterministic (no LLM needed).
- **Priority-based memory compaction** rewrites MEMORY.md at session end to stay under 200 lines using three priority tiers: [P1] permanent (architecture, preferences), [P2] active (current state, recent decisions), [P3] ephemeral (debugging details). Each entry carries temporal metadata (`observed: YYYY-MM-DD`) for evidence-based pruning.
- **Cross-project context** logs a summary to a global rolling log (`~/.tandem/memory/global.md`, 30 entries max) at session end. At session start, Claude sees recent activity from other projects.
- **Progress nudges** remind Claude to update progress.md when a task completes and the file is stale.
- **Pattern promotion** auto-promotes recurring patterns during compaction and surfaces them as candidates for CLAUDE.md. Run `/tandem:recall-promote` to manually promote high-recurrence themes.

**What you see:** `Recalled.` at session start means the previous session's memory was compacted. `Recent work in other projects:` shows cross-repo activity. `Active sessions on this project: N sibling(s)` warns of concurrent sessions. After compaction, `Resuming. Before compaction you were: ...` restores your position.

### Commit

Progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

Tandem treats every commit as an epistemic snapshot: the reasoning, assumptions, and knowledge state at the moment of the decision. Not just what changed, but why this approach won, what alternatives were considered, what constraints existed, and what was unknown at the time. A decision that looks wrong in hindsight might have been the right call given what was known. The commit body preserves that context.

- **Commit body enforcement** ensures every commit has a substantive body via a PreToolUse hook. Subject line follows Conventional Commits. Body captures the why, the what-else, the what-next.
- **Session checkpoints** auto-commit at session end with a descriptive subject: `claude(checkpoint): <current task>`. Only commits when there are actual staged changes.
- **Auto-commit squash** folds checkpoint commits into your next real commit, keeping history clean. Pushing with un-squashed checkpoints is blocked with guidance. Run `/tandem:squash` for manual control.
- **Last Session continuation** writes a `## Last Session` section to MEMORY.md at every compaction: what was being worked on, where it left off, what comes next. The next session picks up immediately.

The result: `git log` becomes a queryable history of reasoning across AI sessions. Combined with tools that read git history, your commit log becomes a decision journal.

**What you see:** Commits without a body are blocked, with session context fed back to write from. At session end, `Session captured` confirms the checkpoint. On next session start, pending auto-commits and squash status are shown.

**Configurable:**
- `TANDEM_AUTO_COMMIT=0`: disable auto-commits at session end (default: enabled)
- `TANDEM_AUTO_SQUASH=0`: disable auto-squash on commit (default: enabled). The push guard stays active regardless.

### Grow

- **Profile injection** provides Claude with your technical profile from the first message of every session, so it can calibrate depth, leverage your strengths, and match your working style. Only injects when the profile has real content (>15 lines), skipping empty templates.
- **Expanded profile** (`USER.md`) tracks six dimensions: Core Identity, Core Superpowers, Domain Expertise, Working Style, Values & Principles, and Growth Edges. Updated automatically at session end (150-line limit) with emphasis on how you think, not just what tasks were completed.
- **Natural concept mentions** weave technical concepts into responses as a senior colleague would, naming concepts and explaining why they matter for the current work.
- **Learning nudges** appear at the start of your next session when a genuine growth edge is detected, with a brief observation.
- **Gap analysis** via `/tandem:grow gaps` cross-references your profile against friction data and career goals to identify high-impact learning priorities.

**Commands:**
- `/tandem:grow`: view your profile
- `/tandem:grow gaps`: identify learning priorities

**Profile:** `~/.tandem/profile/USER.md` (override directory with `TANDEM_PROFILE_DIR`)

---

## Approach

Tandem enhances Claude Code's native memory. It never replaces it.

Auto-memory, MEMORY.md, context compaction, hooks: all Claude Code native. Tandem adds structure on top. If Claude Code ships a native version of something Tandem does, Tandem gets out of the way.

**Two tracks, one system.** Context is preserved through two parallel tracks:

```
Memory track:    progress.md → MEMORY.md → CLAUDE.md
                  (session)    (project)    (permanent rules)

Git track:       checkpoint commits → squashed into real commits → git log
                  (session context)   (clean history)              (permanent record)
```

The memory track manages what Claude knows. Session notes compact into working memory, working memory into project memory, proven patterns promote into permanent rules. Each stage increases signal density.

The git track captures reasoning. Every commit body snapshots the epistemic state: what was known, what constraints existed, what alternatives were considered, why this approach won.

Neither track depends on the other. Together, they ensure nothing is lost to compaction.

---

## Status

```
/tandem:status
```

Reports which features are installed, hook health, memory stats, and profile stats.

```
/tandem:sessions
```

Lists active sessions grouped by project, identifies orphans (dead PIDs), and offers cleanup. Use `/tandem:sessions clean` to force-clean orphans.

---

## How it works

Seven hook scripts, a shared library (`lib/tandem.sh`), and `jq`. No Node. No Python. No MCP servers. No daemons. No databases.

Every feature is a lifecycle hook that runs, does its work, and exits. Session-end spawns a short-lived background worker for memory compaction (seconds, not minutes), but no processes persist between hooks. State files persist in `~/.tandem/` and `~/.claude/`. Nothing phones home.

| Event | Script | Purpose |
|-------|--------|---------|
| PreToolUse | `validate-commit.sh` | Conventional commit format + body enforcement |
| PreToolUse | `squash-autocommits.sh` | Auto-squash checkpoints on commit, block push with un-squashed checkpoints |
| UserPromptSubmit | `detect-raw-input.sh` | Clarify detection |
| SessionStart | `session-start.sh` | Session registration, orphan cleanup, sibling detection, provisioning, profile injection, post-compaction state recovery, cross-project context |
| SessionEnd | `session-end.sh` | Checkpoint commit (phase 0) + memory compaction (phase 1) + pattern extraction (phase 2) + global log (phase 3) + session deregistration |
| PreCompact | `pre-compact.sh` | Current state snapshot + progress safety net |
| TaskCompleted | `task-completed.sh` | Async progress nudge when progress.md is stale |

Dependencies: `bash 3.2+` and `jq`. No `npm install`, no `pip install`, no compilation step, no container.

### LLM backend

By default, all background LLM calls use `claude -p --model haiku` with a $0.15 budget cap per call. These are low-reasoning admin tasks (memory compaction, learning extraction, prompt assessment) that don't need frontier models.

You can point Tandem at any OpenAI-compatible endpoint instead, useful for local models or cheaper hosted alternatives:

```bash
# ~/.tandem/.env
TANDEM_LLM_BACKEND=http://localhost:11434   # Ollama
TANDEM_LLM_MODEL=llama3.2
```

A 7-8B parameter local model works well. See [CONFIGURATION.md](CONFIGURATION.md) for full backend options.

### Cost

With the default Haiku backend, each LLM call has a $0.15 budget cap. Only hooks with substantive content make LLM calls:
- **SessionEnd**: 2 calls (Recall compaction + Grow extraction). Only fires when `progress.md` exists.
- **PreCompact**: 1 call, skipped when structured Working State markers exist.
- **UserPromptSubmit**: 1 call. Only fires on prompts between 200 and 5000 characters.
- **TaskCompleted**: no LLM call. File stat check only.

Typical session cost: **$0.03-0.08**. With a local LLM backend: **$0**.

### Memory scoping

Tandem stores all memory (progress.md, MEMORY.md) in a directory derived from the **working directory where Claude Code was launched**, not the git root. The path is `~/.claude/projects/{sanitised-cwd}/memory/`.

This means: if you launch Claude Code from `~/dev/` and then work on files in `~/dev/my-project/`, memory is stored under `~/dev/`, not `~/dev/my-project/`. Always start Claude Code from your project root directory so that memory is scoped correctly.

Tandem warns at startup if the current working directory is not a git root.

### Files created

Tandem creates zero files in your repositories. Everything lives in:
- `~/.claude/rules/tandem-*.md`: behavioural rules (5 files: recall, grow, display, commits, debugging)
- `~/.claude/CLAUDE.md`: injected section between `<!-- tandem:start -->` and `<!-- tandem:end -->` markers
- `~/.claude/projects/{project}/memory/progress.md`: session bridge (alongside native MEMORY.md)
- `~/.claude/projects/{project}/memory/.MEMORY.md.backup-*`: rolling backups (up to 3)
- `~/.tandem/sessions/<session-id>/state.json`: session registry (created at start, removed at end)
- `~/.tandem/profile/USER.md`: learning profile
- `~/.tandem/memory/global.md`: cross-project activity log (30 entries max)
- `~/.tandem/state/stats.json`: session counters and milestones
- `~/.tandem/state/recurrence.json`: pattern recurrence tracking
- `~/.tandem/logs/tandem.log`: structured log
- `~/.tandem/logs/clarify.jsonl`: Clarify decision log

---

## Configuration

All configuration is via environment variables, set in `~/.tandem/.env` (loaded on every hook invocation). Copy the sample:

```bash
cp .env.sample ~/.tandem/.env
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `TANDEM_LLM_BACKEND` | `claude` | LLM endpoint. Set to an OpenAI-compatible URL for local models. |
| `TANDEM_LLM_MODEL` | `haiku` | Model name. Required for URL backends (e.g. `llama3.2`, `mistral`). |
| `TANDEM_LLM_API_KEY` | (none) | Bearer token for remote endpoints. Not needed for local models. |
| `TANDEM_AUTO_COMMIT` | `1` | Enable session-end auto-commits. Set to `0` to disable. |
| `TANDEM_AUTO_SQUASH` | `1` | Auto-squash checkpoints into next commit. Set to `0` to disable. Push guard stays active. |
| `TANDEM_CLARIFY_MIN_LENGTH` | `200` | Minimum prompt length (chars) before Clarify triggers. |
| `TANDEM_CLARIFY_MAX_LENGTH` | `5000` | Maximum prompt length (chars) before Clarify is skipped. |
| `TANDEM_CLARIFY_QUIET` | `0` | Suppress Clarify branding in output. |
| `TANDEM_LOG_LEVEL` | `info` | Log verbosity: `error`, `warn`, `info`, `debug`. |
| `TANDEM_PROFILE_DIR` | `~/.tandem/profile` | Location for Grow profile files. |

See [CONFIGURATION.md](CONFIGURATION.md) for advanced options, hook input schemas, and file locations.

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
   # User profile
   rm -rf ~/.tandem/profile/

   # State files and recurrence data
   rm -rf ~/.tandem/state/

   # Session registry
   rm -rf ~/.tandem/sessions/

   # Global cross-project memory
   rm -rf ~/.tandem/memory/

   # Logs
   rm -rf ~/.tandem/logs/

   # Provisioning marker and env file
   rm -f ~/.tandem/.provisioned ~/.tandem/.env
   rm -f ~/.tandem/.last-session-recap ~/.tandem/next-nudge
   ```

4. **Remove project memory files:**
   ```bash
   # progress.md files and backups from all projects
   find ~/.claude/projects -name progress.md -delete
   find ~/.claude/projects -name '.MEMORY.md.backup-*' -delete
   find ~/.claude/projects -name .tandem-last-compaction -delete
   ```

**Partial disable:**

To disable individual features without full uninstall:
- **Disable Clarify:** set `TANDEM_CLARIFY_MIN_LENGTH=999999` in `~/.tandem/.env`
- **Disable Recall:** `rm ~/.claude/rules/tandem-recall.md` + remove CLAUDE.md section
- **Disable Commit:** `rm ~/.claude/rules/tandem-commits.md` + set `TANDEM_AUTO_COMMIT=0`
- **Disable Grow:** `rm ~/.claude/rules/tandem-grow.md`

---

## License

MIT
