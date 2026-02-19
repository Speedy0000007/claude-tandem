#!/usr/bin/env bats
# Tests for session-end.sh worker mode (--worker $CWD).
# Runs Phase 0 (checkpoint), Phase 1 (recall), Phase 2 (grow), Phase 3 (global).

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helper: run worker mode directly ────────────────────────────────────────

run_worker() {
  run bash "$PLUGIN_ROOT/scripts/session-end.sh" --worker "$TEST_CWD"
}

# ─── Lockfile ────────────────────────────────────────────────────────────────

@test "lockfile: no existing lockfile, worker runs normally" {
  rm -f "$HOME/.tandem/state/.worker.lock"
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
}

@test "lockfile: stale lockfile (dead PID), worker runs" {
  mkdir -p "$HOME/.tandem/state"
  echo "99999" > "$HOME/.tandem/state/.worker.lock"
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
}

@test "lockfile: cleaned up on exit" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ ! -f "$HOME/.tandem/state/.worker.lock" ]
}

# ─── Phase 0: checkpoint_commit ─────────────────────────────────────────────

@test "phase 0: git repo with staged changes creates checkpoint commit" {
  init_test_git_repo
  create_progress "built auth module"
  echo "change" >> "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add -u
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # Verify the commit was created
  run git -C "$TEST_CWD" log -1 --pretty=format:%s
  assert_output --partial "claude(checkpoint):"
}

@test "phase 0: commit body includes progress.md content" {
  init_test_git_repo
  create_progress "implemented OAuth2 login flow"
  echo "change" >> "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add -u
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run git -C "$TEST_CWD" log -1 --pretty=format:%b
  assert_output --partial "OAuth2 login flow"
}

@test "phase 0: commit has Tandem-Auto-Commit trailer" {
  init_test_git_repo
  create_progress "session notes"
  echo "change" >> "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add -u
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run git -C "$TEST_CWD" log -1 --pretty=format:%b
  assert_output --partial "Tandem-Auto-Commit: true"
}

@test "phase 0: TANDEM_AUTO_COMMIT=0 skips commit" {
  export TANDEM_AUTO_COMMIT=0
  init_test_git_repo
  create_progress "session notes"
  echo "change" >> "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add -u
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  local before_hash
  before_hash=$(git -C "$TEST_CWD" rev-parse HEAD)

  run_worker

  assert_success
  local after_hash
  after_hash=$(git -C "$TEST_CWD" rev-parse HEAD)
  [ "$before_hash" = "$after_hash" ]
}

@test "phase 0: no git repo, no commit attempt" {
  # TEST_CWD is not a git repo by default
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
}

@test "phase 0: no staged changes, no commit" {
  init_test_git_repo
  create_progress "session notes"
  # Don't modify any files -- nothing to stage
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  local before_hash
  before_hash=$(git -C "$TEST_CWD" rev-parse HEAD)

  run_worker

  assert_success
  local after_hash
  after_hash=$(git -C "$TEST_CWD" rev-parse HEAD)
  [ "$before_hash" = "$after_hash" ]
}

# ─── Phase 1: recall_compact ────────────────────────────────────────────────

@test "phase 1: good LLM response creates new MEMORY.md" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$TEST_MEMORY_DIR/MEMORY.md" ]
}

@test "phase 1: MEMORY.md content matches LLM response (minus THEMES line)" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output --partial "## Architecture"
  assert_output --partial "Express with TypeScript"
  assert_output --partial "## Last Session"
  refute_output --partial "THEMES:"
}

@test "phase 1: existing MEMORY.md backed up" {
  create_memory "old memory content"
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # A backup file should exist
  local backup_count
  backup_count=$(ls "$TEST_MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$backup_count" -ge 1 ]
}

@test "phase 1: only 3 backups kept" {
  create_progress "session notes"
  # Create 4 existing backups with distinct timestamps
  for i in 1 2 3 4; do
    echo "backup $i" > "$TEST_MEMORY_DIR/.MEMORY.md.backup-$((1000000 + i))"
  done
  create_memory "current memory"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  local backup_count
  backup_count=$(ls "$TEST_MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$backup_count" -le 3 ]
}

@test "phase 1: code fences stripped from response" {
  create_progress "session notes"
  # Mock that wraps response in code fences
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  printf '```markdown\n# Project Memory\n\n## Architecture\n- Express API\n- PostgreSQL\n\n## Patterns\n- REST conventions\n- Zod validation\n\n## Last Session\nWorking on tests.\n```'
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  refute_output --partial '```'
  assert_output --partial "# Project Memory"
}

@test "phase 1: refusal response does not overwrite MEMORY.md" {
  create_memory "original memory content"
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-refusal.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output "original memory content"
}

@test "phase 1: short response does not overwrite MEMORY.md" {
  create_memory "original memory content"
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-short.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output "original memory content"
}

@test "phase 1: empty LLM response does not overwrite MEMORY.md" {
  create_memory "original memory content"
  create_progress "session notes"
  # Use dispatch where compaction returns empty
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  # Return empty
  true
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output "original memory content"
}

@test "phase 1: THEMES line extracted and not written to MEMORY.md" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  refute_output --partial "THEMES:"
}

@test "phase 1: recurrence.json updated with themes" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/state/recurrence.json" ]
  run jq -r '.themes | keys[]' "$HOME/.tandem/state/recurrence.json"
  assert_output --partial "api-development"
  assert_output --partial "user-management"
}

@test "phase 1: compaction marker created" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$TEST_MEMORY_DIR/.tandem-last-compaction" ]
}

@test "phase 1: stats compaction count incremented" {
  create_progress "session notes"
  create_stats 5 2 1
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run jq '.compactions' "$HOME/.tandem/state/stats.json"
  assert_output "3"
}

# ─── Phase 2: grow_extract ──────────────────────────────────────────────────

@test "phase 2: NONE response, no profile changes" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  # Ensure profile dir is empty
  rm -rf "$HOME/.tandem/profile"
  mkdir -p "$HOME/.tandem/profile"

  run_worker

  assert_success
  [ ! -f "$HOME/.tandem/profile/USER.md" ]
}

@test "phase 2: profile written to USER.md" {
  create_progress "learned about bats testing"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-profile.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/profile/USER.md" ]
  run cat "$HOME/.tandem/profile/USER.md"
  assert_output --partial "# User Profile"
  assert_output --partial "Bats testing framework"
}

@test "phase 2: existing USER.md replaced with updated content" {
  mkdir -p "$HOME/.tandem/profile"
  echo "# User Profile
## Career Context
Old info" > "$HOME/.tandem/profile/USER.md"
  create_progress "user mentioned their role"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-profile.txt"

  run_worker

  assert_success
  run cat "$HOME/.tandem/profile/USER.md"
  assert_output --partial "Senior Software Engineer"
  refute_output --partial "Old info"
}

@test "phase 2: NUDGE line writes nudge file" {
  create_progress "worked with bash 3.2"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-nudge-profile.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/next-nudge" ]
  run cat "$HOME/.tandem/next-nudge"
  assert_output --partial "shellcheck"
  # NUDGE line should not appear in USER.md
  run cat "$HOME/.tandem/profile/USER.md"
  refute_output --partial "NUDGE:"
}

@test "phase 2: profile stats updated (profile_updates incremented)" {
  create_progress "learned new patterns"
  create_stats 5 2 3
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-profile.txt"

  run_worker

  assert_success
  run jq '.profile_updates' "$HOME/.tandem/state/stats.json"
  assert_output "4"
}

@test "phase 2: code fences stripped from profile response" {
  create_progress "session notes"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  cat <<'RECALL'
# Project Memory

## Architecture
- Express API
- PostgreSQL

## Patterns
- REST conventions

## Last Session
Working on tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  cat <<'GROW'
```markdown
# User Profile

## Career Context
Developer.

## Technical Understanding
- Testing patterns
```
GROW
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/profile/USER.md" ]
  run cat "$HOME/.tandem/profile/USER.md"
  refute_output --partial '```'
  assert_output --partial "# User Profile"
}

@test "phase 2: invalid response (no heading) is skipped gracefully" {
  create_progress "session notes"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  cat <<'RECALL'
# Project Memory

## Architecture
- Express API

## Patterns
- REST

## Last Session
Tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'Some random text without a heading\nAnother line'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  [ ! -f "$HOME/.tandem/profile/USER.md" ]
}

@test "phase 2: empty LLM response does not crash" {
  create_progress "session notes"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  cat <<'RECALL'
# Project Memory

## Architecture
- Express API

## Patterns
- REST

## Last Session
Tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  # Return empty
  true
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
}

# ─── Phase 3: global_activity ───────────────────────────────────────────────

@test "phase 3: prepends entry to global.md" {
  create_progress "built the auth module"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/memory/global.md" ]
  run cat "$HOME/.tandem/memory/global.md"
  assert_output --partial "built the auth module"
}

@test "phase 3: caps at 30 entries" {
  create_progress "new entry here"
  # Pre-populate global.md with 30 entries
  mkdir -p "$HOME/.tandem/memory"
  local global_content=""
  for i in $(seq 1 30); do
    global_content="${global_content}## 2025-01-01 — project-${i}
Entry number ${i}
"
  done
  echo "$global_content" > "$HOME/.tandem/memory/global.md"

  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  local entry_count
  entry_count=$(grep -c '^## ' "$HOME/.tandem/memory/global.md")
  [ "$entry_count" -le 30 ]
}

@test "phase 3: creates global.md if missing" {
  create_progress "first session ever"
  rm -f "$HOME/.tandem/memory/global.md"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/memory/global.md" ]
}

@test "phase 3: deduplicates same-project same-day entry" {
  create_progress "updated work"
  mkdir -p "$HOME/.tandem/memory"
  # Pre-populate with an entry for the same project and today's date
  local today
  today=$(date +%Y-%m-%d)
  cat > "$HOME/.tandem/memory/global.md" <<EOF
## ${today} — project
old summary from earlier session

## 2025-01-01 — other-project
Other project entry

EOF

  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # Should still have exactly 2 entries (replaced, not added)
  local entry_count
  entry_count=$(grep -c '^## ' "$HOME/.tandem/memory/global.md")
  [ "$entry_count" -eq 2 ]
  # Old summary should be gone
  run cat "$HOME/.tandem/memory/global.md"
  refute_output --partial "old summary from earlier session"
  # New summary should be present
  assert_output --partial "updated work"
}

# ─── Orchestration ──────────────────────────────────────────────────────────

@test "orchestration: both recall + grow succeed, progress.md truncated to working state" {
  create_progress "<!-- working-state:start -->
## Working State
**Current task:** session notes
<!-- working-state:end -->

## Session Log
- did some work"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # progress.md should still exist but session log should be stripped
  [ -f "$TEST_MEMORY_DIR/progress.md" ]
  run cat "$TEST_MEMORY_DIR/progress.md"
  assert_output --partial "working-state:start"
  refute_output --partial "Session Log"
}

@test "orchestration: recall fails, grow succeeds, progress.md preserved with failure note" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-refusal.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$TEST_MEMORY_DIR/progress.md" ]
  run cat "$TEST_MEMORY_DIR/progress.md"
  assert_output --partial "Session End Partial Failure"
}

@test "orchestration: recall succeeds, grow fails, progress.md preserved" {
  create_progress "session notes"
  # Mock where extraction returns empty (fails)
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  cat <<'RECALL'
# Project Memory

## Architecture
- Express API

## Patterns
- REST conventions

## Last Session
Working on tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  # Return empty to trigger failure
  true
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  [ -f "$TEST_MEMORY_DIR/progress.md" ]
  run cat "$TEST_MEMORY_DIR/progress.md"
  assert_output --partial "Session End Partial Failure"
}

@test "orchestration: recap file created with phase statuses" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  [ -f "$HOME/.tandem/.last-session-recap" ]
  run cat "$HOME/.tandem/.last-session-recap"
  assert_output --partial "recall_status:"
  assert_output --partial "grow_status:"
  assert_output --partial "checkpoint_status:"
  assert_output --partial "global_status:"
}

@test "orchestration: recap includes memory_lines when recall succeeds" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$HOME/.tandem/.last-session-recap"
  assert_output --partial "recall_status: 1"
  assert_output --partial "memory_lines:"
}

@test "orchestration: recap includes profile_files when grow succeeds" {
  create_progress "learned testing patterns"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-good.txt" \
    "USER.md" "grow-extract-profile.txt"

  run_worker

  assert_success
  run cat "$HOME/.tandem/.last-session-recap"
  assert_output --partial "grow_status: 1"
  assert_output --partial "profile_files: USER.md"
}
