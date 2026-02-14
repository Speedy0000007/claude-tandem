<p align="center">
  <img src="assets/logo.png" alt="Tandem — companion plugin for Claude Code with persistent memory, session handover, and developer learning" width="320">
</p>

<h1 align="center">Tandem</h1>

<p align="center">
  <strong>A companion plugin for Claude Code that handles the work around the work.</strong>
</p>

<p align="center">
  <sub>Persistent memory, session handover, input cleanup, context compaction, commit enrichment, and developer learning. Pure bash, one dependency (<code>jq</code>).</sub>
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

MEMORY.md has no structure. It's a flat file with a 200-line cap, no priority tiers, and no awareness of what matters most. Context compaction preserves a summary, but loses the precise "where was I, what was I doing, what's next" detail needed to resume complex multi-session work. There's no session bridge, no cross-project awareness, and no mechanism to promote recurring patterns into permanent knowledge. Commit messages capture what changed but not why. And the developer learns nothing from the process.

Tandem fills these gaps by handling the work that happens around the building: structured memory with priority-based retention, session handover via progress.md, input quality, reasoning preservation in git, and learning. All through Claude Code's native hook system.

---

## What it does

Tandem is a Claude Code plugin that runs alongside your sessions, handling memory, context, input quality, and learning so you can focus on building. Four features, each targeting a different gap in the coding agent workflow:

<table>
  <tr>
    <td align="center" width="25%"><strong>Clarify</strong><br>Clarifies input</td>
    <td align="center" width="25%"><strong>Recall</strong><br>Recalls working memory</td>
    <td align="center" width="25%"><strong>Commit</strong><br>Commits durable memory</td>
    <td align="center" width="25%"><strong>Grow</strong><br>Enhances both user and model</td>
  </tr>
</table>

Each feature is independently valuable. Combined, they compound: better input leads to a smarter agent, richer commit history captures the reasoning permanently, and learning compounds across every session.

### Pure bash. Minimal overhead.

No Node. No Python. No MCP servers. No long-running daemons. No databases. Seven hook scripts, a shared library (`lib/tandem.sh`), and `jq`.

Tandem runs entirely through Claude Code's native hook system. Every feature is a plain bash script that fires on a lifecycle event, does its work, and exits. Session-end spawns a short-lived background worker for memory compaction (seconds, not minutes), but nothing persists between hooks. Nothing phones home. The entire runtime is `~/.tandem/` and a handful of rules files.

Dependencies: `bash 3.2+` and `jq`. That's it. No `npm install`, no `pip install`, no compilation step, no container. Install in seconds, read the entire codebase in an afternoon.

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

## Philosophy: enhance Claude Code's native memory, never replace it

Claude Code already has auto-memory, MEMORY.md, context compaction, and a hook system. Tandem doesn't build parallel infrastructure. It makes the native memory systems work better.

- **Auto-memory writes MEMORY.md.** Tandem compacts it with priority-based retention so architectural decisions persist across compaction cycles while debugging details decay naturally.
- **Claude Code has no cross-project awareness.** Tandem adds a lightweight rolling log so sessions in one repo know what you've been doing elsewhere.
- **Claude Code has no session bridge.** Tandem adds progress.md alongside MEMORY.md — same directory, same conventions.
- **Git is already the permanent record.** Tandem enriches commit messages with session context so nothing is lost to compaction. Your thinking persists in `git log` forever.
- **Rules files, hooks, skills** — all use Claude Code's native plugin system. No MCP servers, no persistent services, no databases.

**Two tracks, one system.** Tandem preserves context through two parallel tracks that reinforce each other:

```
Memory track:    progress.md → MEMORY.md → CLAUDE.md
                  (session)    (project)    (permanent rules)

Git track:       checkpoint commits → squashed into real commits → git log
                  (session context)   (clean history)              (epistemic record)
```

The memory track manages what Claude knows: session notes compact into working memory, working memory compacts into project memory, and proven patterns promote into permanent rules. Each stage increases signal density.

The git track captures how you were thinking. Every commit body is a snapshot of the epistemic state at that moment: what was known, what wasn't, what constraints existed, what alternatives were considered, and why this approach won. Six months later, when someone asks "why is this code the way it is?", the commit body answers with the full reasoning, including the limitations and assumptions that shaped the decision. A change that looks wrong today might have been the right call given what was known at the time. The git track preserves that context.

Neither track depends on the other. Together, they ensure nothing is ever truly lost.

If Claude Code ships a native version of something Tandem does, Tandem should get out of the way. The goal is to fill gaps, not compete.

---

## Features

### Clarify — input quality for better agent output

Garbage in, garbage out. Clarify fixes the input.

A UserPromptSubmit hook detects long, unstructured input (dictation, brain dumps, walls of text) and sends it to a lightweight LLM for assessment. Three outcomes: **SKIP** (already clear), **RESTRUCTURE** (rewritten for clarity), or **CLARIFY** (ambiguity detected, questions generated before work begins). The assessment also discovers relevant skills from your installed skill directories and suggests them alongside the outcome.

**What you see:** Your messy input executes cleanly. A `Clarified.` indicator appears when restructuring happened. If questions are needed, they appear before any work starts. Relevant skills are suggested when applicable.

**Configurable:**
- `TANDEM_CLARIFY_MIN_LENGTH` — minimum characters before assessment triggers (default: 200)
- `TANDEM_CLARIFY_QUIET=1` — suppress branding in Clarify output (default: off)

### Recall — persistent memory across sessions

Claude already remembers. Recall makes it *good* at remembering.

- **Session bridge via progress.md** — maintains a two-part `progress.md` alongside MEMORY.md: a rewritable Working State snapshot (current task, approach, blockers, key files) and an append-only Session Log below. Survives context compaction. progress.md persists across sessions (Working State carries forward to the next session, gets overwritten when fresh work begins).
- **Session registry** — each session registers at `~/.tandem/sessions/<session-id>/` with a `state.json` tracking pid, project, branch, heartbeat, and current task. Sessions heartbeat on every status line render, making them discoverable by sibling sessions. Orphaned sessions (dead pid) are cleaned up automatically. Run `/tandem:sessions` to inspect the registry.
- **Sibling awareness** — at session start, Tandem discovers other active sessions on the same project and reports them. The status line shows concurrent session count in yellow. This is the foundation for safe concurrent compaction (only one session compacts at a time).
- **Pre-compaction safety net** — a PreCompact hook captures the precise "where are we right now" before compaction. When structured Working State markers exist, this is deterministic (no LLM needed). After compaction, SessionStart surfaces this snapshot so Claude picks up exactly where it left off.
- **Priority-based memory compaction** — at session end, rewrites MEMORY.md to stay under 200 lines using three priority tiers: [P1] permanent (architecture, preferences), [P2] active (current state, recent decisions), [P3] ephemeral (debugging details). Each entry carries temporal metadata (observed: YYYY-MM-DD) for evidence-based pruning. After successful compaction, progress.md is truncated to just the Working State (the Session Log has been absorbed into MEMORY.md).
- **Cross-project context** — at session end, logs a summary of what happened to a global rolling log (`~/.tandem/memory/global.md`, 30 entries max). At session start, Claude sees recent activity from other projects for cross-repo awareness.
- **Progress nudges** — when a task completes and progress.md is stale, an async nudge reminds Claude to record what happened.
- **Pattern promotion** — recurring patterns are auto-promoted during compaction and surfaced as candidates for CLAUDE.md. Run `/tandem:recall promote` to manually promote high-recurrence themes.
- **CLAUDE.md promotion** — the data funnel flows `progress.md → MEMORY.md → CLAUDE.md`. High-signal [P1] patterns that prove stable across sessions are proactively promoted to the appropriate CLAUDE.md file (global `~/.claude/CLAUDE.md`, project root, or subdomain). Promoted entries are removed from MEMORY.md to avoid duplication. CLAUDE.md is the permanent record; MEMORY.md is the working buffer.

**What you see:** `Recalled.` at session start means the previous session's memory was compacted. `Recent work in other projects:` shows what you've been doing elsewhere. `Active sessions on this project: N sibling(s)` warns of concurrent sessions. After compaction, `Resuming. Before compaction you were: ...` restores your exact position. If a session ends abnormally, stale progress is detected and recovered next time.

### Commit — epistemic snapshots in git history

Progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

Tandem treats every commit as an epistemic snapshot: the reasoning, assumptions, and knowledge state at the moment of the decision. Not just what changed, but why this approach won, what alternatives were considered, what constraints existed, and what was unknown at the time. A decision that looks wrong in hindsight might have been the right call given the information available. The commit body preserves that context.

- **Commit body enforcement** — a PreToolUse hook ensures every commit has a body that captures the developer's thinking. Subject line follows Conventional Commits. Body captures the why, the what-else, the what-next.
- **Session checkpoints** — at session end, before memory compaction, Tandem auto-commits a checkpoint with a descriptive subject line extracted from your current task: `claude(checkpoint): <what you were doing>`. Only commits when there are actual staged changes.
- **Auto-commit squash** — checkpoint commits are automatically squashed into your next real commit, keeping history clean. If you try to push with un-squashed checkpoints, the push is blocked with guidance on how to resolve it. Run `/tandem:squash` for manual control.
- **`## Last Session` continuation** — every memory compaction writes a `## Last Session` section to MEMORY.md with what was being worked on, where it left off, and what comes next. The next session picks up immediately, even when no code was changed.

The result: `git log` becomes a queryable history of reasoning across every AI session. Ask "why is this code the way it is?" and get the full thought process, including what was known, what wasn't, and what tradeoffs were accepted. Combined with tools that read git history, this turns your commit log into a decision journal.

**What you see:** If you try to commit without a body, the hook blocks it and feeds you session context to write from. At session end, `Session captured` confirms the checkpoint was written. On next session start, you'll see how many auto-commits are pending and whether they'll be auto-squashed.

**Configurable:**
- `TANDEM_AUTO_COMMIT=0` — disable auto-commits at session end (default: enabled)
- `TANDEM_AUTO_SQUASH=0` — disable auto-squash on commit (default: enabled). The push guard stays active regardless.

### Grow — learn alongside your coding agent

The user gets smarter. Learns as they go.

- **Natural concept mentions** — Claude weaves technical concepts into responses as a senior colleague would, naming concepts and explaining why they matter for your work
- **Single profile file** — a lightweight `USER.md` tracks your career context, technical understanding, and growth edges. Updated automatically at session end when the session reveals something about your understanding level
- **Learning nudges** — when a genuine growth edge is detected, a NUDGE appears at the start of your next session with a friendly one-sentence observation
- **Gap analysis** — `/tandem:grow gaps` cross-references your profile against friction data and career goals to identify what would make the biggest difference to learn next

**Commands:**
- `/tandem:grow` — view your profile
- `/tandem:grow gaps` — identify high-impact learning priorities

**Profile:** `~/.tandem/profile/USER.md` (override directory with `TANDEM_PROFILE_DIR`)

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

## How it works — Claude Code hooks, no background agents

Tandem uses Claude Code's native hook system. Every feature is a lifecycle hook that runs, does its work, and exits. No persistent services, no databases, no file pollution in your repos.

| Event | Script | Purpose |
|-------|--------|---------|
| PreToolUse | `validate-commit.sh` | Conventional commit format + body enforcement |
| PreToolUse | `squash-autocommits.sh` | Auto-squash checkpoints on commit, block push with un-squashed checkpoints |
| UserPromptSubmit | `detect-raw-input.sh` | Clarify detection |
| SessionStart | `session-start.sh` | Session registration, orphan cleanup, sibling detection, provisioning, post-compaction state recovery, cross-project context |
| SessionEnd | `session-end.sh` | Checkpoint commit (phase 0) + memory compaction (phase 1) + pattern extraction (phase 2) + global log (phase 3) + session deregistration |
| PreCompact | `pre-compact.sh` | Current state snapshot + progress safety net |
| TaskCompleted | `task-completed.sh` | Async progress nudge when progress.md is stale |

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
- **SessionEnd** — 2 calls (Recall compaction + Grow extraction). Only fires when `progress.md` exists.
- **PreCompact** — 1 call (skipped when structured Working State exists). State snapshot before compaction.
- **UserPromptSubmit** — 1 call. Only fires on prompts longer than 200 characters.
- **TaskCompleted** — no LLM call. Just a file stat check.

Typical session cost: **$0.03-0.08**. With a local LLM backend: **$0**.

### Memory scoping

Tandem stores all memory (progress.md, MEMORY.md) in a directory derived from the **working directory where Claude Code was launched**, not the git root. The path is `~/.claude/projects/{sanitised-cwd}/memory/`.

This means: if you launch Claude Code from `~/dev/` and then work on files in `~/dev/my-project/`, memory is stored under `~/dev/`, not `~/dev/my-project/`. Always start Claude Code from your project root directory so that memory is scoped correctly.

Tandem warns at startup if the current working directory is not a git root.

### Files created

Tandem creates zero files in your repositories. Everything lives in:
- `~/.claude/rules/tandem-*.md` — behavioural rules including commit body enforcement (install = copy, uninstall = delete)
- `~/.claude/projects/{project}/memory/progress.md` — session bridge with structured Working State + Session Log (alongside native MEMORY.md)
- `~/.tandem/sessions/<session-id>/state.json` — session registry (created at start, removed at end, orphans cleaned automatically)
- `~/.tandem/profile/USER.md` — learning profile
- `~/.tandem/memory/global.md` — cross-project activity log (30 entries max)

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
