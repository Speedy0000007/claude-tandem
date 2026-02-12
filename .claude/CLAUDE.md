# Tandem — Claude Code Plugin

## What this is

A Claude Code plugin with four features: Clarify (input quality), Recall (memory management), Commit (durable memory), Grow (user learning). Ships as shell scripts + SKILL.md files — no Node, no Python, no background processes.

## Core ethos: enhance, never replace

Claude Code already has auto-memory, MEMORY.md, context compaction, and a hook system. Tandem fills gaps in the native systems — it never builds parallel infrastructure. If Claude Code ships a native version of something Tandem does, Tandem should get out of the way. Every feature should trace back to: "Claude Code doesn't do X natively, so we add it using Claude Code's own conventions."

## Architecture constraints

- **Shell scripts only** — all scripts in `scripts/` are bash. No runtime dependencies beyond `jq` and `claude` CLI (or `curl` for URL backends).
- **Shared library** — `lib/tandem.sh` provides `tandem_log`, `tandem_print`, `tandem_header`, `tandem_require_jq`, `tandem_require_llm`, `tandem_llm_call`. Source at top of every script.
- **Silent logging** — all diagnostics go to `~/.tandem/logs/tandem.log`. Never write to stderr from hook scripts. Use `tandem_log <level> <message>` (levels: error, warn, info, debug; threshold: `TANDEM_LOG_LEVEL` env var, default info).
- **Branded output** — all user-facing output uses `tandem_print "message"` which outputs `tandem ~ message`. No ANSI in hooks (stdout becomes plain-text system messages). `status.sh` (skill, runs in terminal) may use ANSI.
- **`${CLAUDE_PLUGIN_ROOT}`** — all paths in `hooks/hooks.json` use this env var. Scripts that need plugin-relative paths (e.g., `session-start.sh` for provisioning) resolve it via `CLAUDE_PLUGIN_ROOT` with a fallback to `$(dirname "$(dirname "$0")")`.
- **Auto-memory directory** — computed from CWD: `~/.claude/projects/$(echo "$CWD" | sed 's|/|-|g')/memory/`. This matches Claude Code's native convention. Every script that touches progress.md or MEMORY.md uses this pattern.
- **Zero repo files** — Tandem never creates files inside user repositories. All data goes to `~/.claude/` (rules, memory) or `~/.tandem/` (profile).
- **Built to be forked** — Tandem is open source and designed for customisation. `lib/tandem.sh` is a shared foundation that community scripts can source. Skills, hooks, and rules are modular. The architecture choices (shell scripts, no runtime deps, `CLAUDE_PLUGIN_ROOT` paths, atomic writes) exist so that anyone comfortable with bash can read, modify, and extend Tandem.
- **PreToolUse hook** — `validate-commit.sh` enforces conventional commit format + body presence on all git commits. Sources `lib/tandem.sh`. Reads progress.md to feed context back in denial messages. 5s timeout.
- **PreToolUse hook** — `squash-autocommits.sh` squashes consecutive Tandem auto-commits into the next user commit (via `git reset --soft`) and denies pushes that contain auto-commits in the push range. Controlled by `TANDEM_AUTO_SQUASH` env var (default: enabled). 5s timeout.
- **SessionEnd hooks** — sync hook with fast exit. Prints informational message (visible to user), then spawns a detached worker (`nohup ... </dev/null &>/dev/null & disown`) for Phase 0 (checkpoint commit) + LLM calls via `tandem_llm_call`. PID lockfile (`~/.tandem/state/.worker.lock`) prevents overlapping workers.
- **Swappable LLM backend** — all background LLM calls go through `tandem_llm_call()` in `lib/tandem.sh`. Default: `claude -p` with haiku. Set `TANDEM_LLM_BACKEND` to an OpenAI-compatible URL (e.g. Ollama, LM Studio) for zero-cost local inference. Config lives in `~/.tandem/.env`. The function handles claude CLI specifics (budget, system-prompt stripping) and curl-based OpenAI API calls transparently.
- **`claude -p` budget floor** — `claude -p` has a base cost of ~$0.06 even with empty system prompt. `tandem_llm_call` defaults to `--max-budget-usd 0.15`. Budget exceeded returns exit 0 with "Error: Exceeded USD budget" on stdout, handled internally by `tandem_llm_call`.
- **PreCompact hook** — captures current state snapshot + progress safety net before compaction. Uses `--max-budget-usd 0.15` with `TANDEM_WORKER=1` inline. Always fires (state snapshot), but only extracts progress when progress.md is stale (>2 min).
- **TaskCompleted hook** — async, no LLM call. Just checks progress.md staleness (>5 min) and outputs a `systemMessage` nudge if stale.
- **`TANDEM_AUTO_COMMIT`** — env var controlling session-end auto-commits. Default: enabled (1). Set to `0` to disable checkpoint commits. Only commits when there are actual staged changes (no empty commits).
- **`TANDEM_AUTO_SQUASH`** — env var controlling auto-commit squash on commit. Default: enabled (1). Set to `0` to disable squash-on-commit. The push guard is always active regardless of this setting: pushes are always denied if auto-commits are in the push range.
- **`TANDEM_WORKER` guard** — `claude -p` fires hooks during its lifecycle. All hook scripts exit early when `TANDEM_WORKER` is set in the environment (exported by the worker). This prevents recursive hook firing and inflated session counts. Heredocs in prompts must use unquoted delimiters (`<<EOF` not `<<'EOF'`) because `/bin/bash` 3.2 (macOS default) cannot parse apostrophes inside single-quoted heredocs in command substitutions.
- **Rules files** — provisioned to `~/.claude/rules/tandem-*.md` by `session-start.sh`. Install = copy, uninstall = delete. Never patch user's CLAUDE.md. Includes `tandem-commits.md` for commit body enforcement. When editing source rules in `plugins/tandem/rules/`, also update the provisioned copy at `~/.claude/rules/` so changes take effect in the current session.
- **Skill naming** — SKILL.md frontmatter uses short `name` (e.g., `clarify`), no prefix. The plugin system adds `tandem:` automatically.

## Build conventions

- Hook definitions live in `hooks/hooks.json`, not in individual scripts
- SessionStart fires on `startup|resume|compact` — fully idempotent, handles post-compaction state recovery
- SessionEnd runs a single `session-end.sh`: prints summary to user (sync), then backgrounds checkpoint commit (phase 0) + compaction (phase 1) + extraction (phase 2) + global log (phase 3) in a subshell
- PreCompact writes ephemeral `## Pre-compaction State` to progress.md — consumed by SessionStart, never reaches SessionEnd
- TaskCompleted is async (`"async": true`) — no blocking, nudge delivered on next turn
- Scripts exit 0 on all paths — hook failures should be silent to the user
- Scripts exit early when preconditions aren't met (no progress.md = no LLM call)
- Atomic writes: write to temp file, then `mv` to target

## File layout

All plugin code lives under `plugins/tandem/` in the repo root:

```
plugins/tandem/
  .claude-plugin/     Plugin manifests
  hooks/              Hook wiring (hooks.json)
  lib/                Shared library (tandem.sh)
  scripts/            All executable hook scripts
  skills/             SKILL.md files (clarify, grow, logs, reload, status)
  rules/              Source rules files (provisioned to ~/.claude/rules/)
  templates/          Profile bootstrap templates

Runtime data (outside repo):
~/.tandem/profile/          User's technical profile (Grow)
~/.tandem/state/            Recurrence themes, state files
~/.tandem/logs/tandem.log   Unified log file (silent, never stderr)
~/.tandem/memory/global.md  Cross-project activity log (30 entries max)
```

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) with bats-support, bats-assert, and bats-file (git submodules in `test/lib/`).

```bash
make test              # run all tests (unit + integration)
make test-unit         # unit tests only
make test-integration  # integration tests only
make lint              # shellcheck
```

- 204 tests: 187 unit + 17 integration across 13 test files
- HOME isolation: every test runs in a temp HOME, no real `~/.tandem/` or `~/.claude/` touched
- LLM mocking: mock `claude` CLI and `curl` on PATH, canned responses in `test/fixtures/`
- Git mocking: real git repos in temp dirs for commit/squash/push tests
- CI: GitHub Actions on ubuntu-latest + macos-latest (bash 3.2 compat)
