# Tandem

**Compound learning for Claude Code — every session makes the next one better.**

Claude gets sharper. You get smarter.

## What it does

Tandem is a Claude Code plugin with three pillars:

| Pillar | What it does | Invocation |
|--------|-------------|------------|
| **Clarify** | Restructures messy, dictated, or stream-of-consciousness input into well-formed prompts — then executes immediately | Auto-detects, or `/tandem:clarify` |
| **Recall** | Keeps your agent's memory sharp — compacts MEMORY.md to stay under 200 lines, maintains a session bridge (progress.md), and surfaces patterns for promotion to CLAUDE.md | Automatic (hooks) |
| **Grow** | Teaches you as you work — captures technical concepts, builds a searchable learning profile, and identifies high-impact skill gaps | `/tandem:grow` |

Each pillar is independently valuable. Combined, they compound — better input leads to a smarter agent, which produces richer learning, which makes you more effective at directing the next session.

## Install

```bash
# Add the marketplace
/plugin marketplace add github.com/jonny981/claude-tandem

# Install
/plugin install tandem
```

First session after install auto-provisions rules files and profile directory. Run `/tandem:status` to verify.

## Pillars

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
- **Memory compaction** — at session end, rewrites MEMORY.md to stay under 200 lines (the native loading limit). Keeps what's relevant, lets stale details decay
- **Pattern promotion** — recurring patterns are surfaced as candidates for CLAUDE.md with suggested promotion targets

**What you see:** `Recalled.` at session start means the previous session's memory was compacted. If a session ends abnormally, stale progress is detected and recovered next time.

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

## Status

```
/tandem:status
```

Reports which pillars are installed, hook health, memory stats, and profile stats.

## How it works

### No background processes

Tandem uses Claude Code's native hook system. Zero background services, zero databases, zero file pollution in your repos.

| Event | Script | Purpose |
|-------|--------|---------|
| UserPromptSubmit | `detect-raw-input.sh` | Clarify detection |
| SessionStart | `session-start.sh` | Provisioning + stale progress recovery |
| SessionEnd | `session-end.sh` | Memory compaction + pattern card extraction |

### Cost

SessionEnd hooks call `claude -p --model haiku --max-budget-usd 0.05`. Only fires when there's a `progress.md` to process — trivial sessions cost nothing. Typical cost: $0.001-0.01 per session end.

### Files created

Tandem creates zero files in your repositories. Everything lives in:
- `~/.claude/rules/tandem-*.md` — behavioural rules (install = copy, uninstall = delete)
- `~/.claude/projects/{project}/memory/progress.md` — session bridge (alongside native MEMORY.md)
- `~/.tandem/profile/` — learning profile

## Uninstall

```bash
/plugin uninstall tandem
```

This removes the plugin (skills, hooks, scripts). Your data is preserved:
- MEMORY.md and progress.md — untouched
- Profile directory and pattern cards — untouched
- Rules files — remain at `~/.claude/rules/tandem-*.md` (delete manually to fully clean up)

## License

MIT
