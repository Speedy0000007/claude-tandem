#!/usr/bin/env bats
# Tests for v1.3.0 features: priority annotations, temporal metadata,
# structured working memory, and recurrence auto-promotion.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helper: run worker mode directly ────────────────────────────────────────

run_worker() {
  run bash "$PLUGIN_ROOT/scripts/session-end.sh" --worker "$TEST_CWD"
}

# Helper: run session-start with optional source field
run_session_start() {
  local source="${1:-startup}"
  local cwd="${2:-$TEST_CWD}"
  local json
  json=$(printf '{"cwd":"%s","source":"%s"}' "$cwd" "$source")
  local tmpfile="$TEST_TEMP_DIR/input.json"
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/$SCRIPT'"
}

SCRIPT="session-start.sh"

# Create a minimal transcript file
_create_transcript() {
  local path="${1:-$TEST_TEMP_DIR/transcript.jsonl}"
  echo '{"type":"message","content":"hello"}' > "$path"
  echo '{"type":"message","content":"working on auth module"}' >> "$path"
  echo "$path"
}

# ─── Priority annotations in compaction ──────────────────────────────────────

@test "priority: compaction prompt contains priority tier instructions" {
  create_progress "session notes"
  # Capture the prompt sent to claude — save compaction prompt separately
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  echo "$STDIN" > "$HOME/.tandem/state/captured_compaction.txt"
  cat <<'RECALL'
# Project Memory

## Architecture
- [P1] Express API (observed: 2026-01-15)

## Patterns
- [P2] REST conventions (observed: 2026-02-10)

## Last Session
Working on tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_compaction.txt")
  [[ "$captured" == *"[P1] PERMANENT"* ]]
  [[ "$captured" == *"[P2] ACTIVE"* ]]
  [[ "$captured" == *"[P3] EPHEMERAL"* ]]
}

@test "priority: compaction prompt contains temporal context instructions" {
  create_progress "session notes"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  echo "$STDIN" > "$HOME/.tandem/state/captured_compaction.txt"
  cat <<'RECALL'
# Project Memory

## Architecture
- [P1] Express API (observed: 2026-01-15)

## Patterns
- REST

## Last Session
Tests.

THEMES: testing
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_compaction.txt")
  [[ "$captured" == *"observed: YYYY-MM-DD"* ]]
  [[ "$captured" == *"Temporal metadata"* ]]
}

@test "priority: MEMORY.md preserves priority markers from LLM response" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-priority.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output --partial "[P1]"
  assert_output --partial "[P2]"
  assert_output --partial "[P3]"
}

@test "priority: MEMORY.md preserves temporal dates from LLM response" {
  create_progress "session notes"
  _install_mock_claude_dispatch \
    "compaction" "recall-compact-priority.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  run cat "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output --partial "(observed: 2026-01-15)"
  assert_output --partial "(observed: 2026-02-10)"
  assert_output --partial "(observed: 2026-02-12)"
}

# ─── Structured Working State in pre-compact ────────────────────────────────

@test "working-state: pre-compact skips LLM when markers exist and progress is fresh" {
  local transcript
  transcript=$(_create_transcript)

  # Create progress.md with Working State markers (fresh, age=0)
  cat > "$TEST_MEMORY_DIR/progress.md" <<'WS_EOF'
<!-- working-state:start -->
## Working State
**Current task:** implementing auth module
**Approach:** JWT with refresh tokens
**Blockers:** none
**Key files:** src/auth.ts
<!-- working-state:end -->

Built login endpoint. Chose JWT over sessions for statelessness.
WS_EOF

  # Mock claude that records whether it was called
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
echo "CLAUDE_WAS_CALLED" > "$HOME/.tandem/state/claude_called.txt"
printf 'STATE:\n- Working on auth'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  # Claude should NOT have been called (LLM skipped)
  [ ! -f "$HOME/.tandem/state/claude_called.txt" ]
}

@test "working-state: pre-compact writes state section when markers exist" {
  local transcript
  transcript=$(_create_transcript)

  cat > "$TEST_MEMORY_DIR/progress.md" <<'WS_EOF'
<!-- working-state:start -->
## Working State
**Current task:** implementing auth module
**Approach:** JWT with refresh tokens
**Blockers:** none
**Key files:** src/auth.ts
<!-- working-state:end -->

Built login endpoint.
WS_EOF

  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
printf 'STATE:\n- Working on auth'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  run cat "$TEST_MEMORY_DIR/progress.md"
  assert_output --partial "## Pre-compaction State"
  assert_output --partial "implementing auth module"
}

@test "working-state: pre-compact still calls LLM when markers exist but progress is stale" {
  local transcript
  transcript=$(_create_transcript)

  # Create progress with Working State but make it stale (300s old)
  cat > "$TEST_MEMORY_DIR/progress.md" <<'WS_EOF'
<!-- working-state:start -->
## Working State
**Current task:** implementing auth module
**Approach:** JWT with refresh tokens
**Blockers:** none
**Key files:** src/auth.ts
<!-- working-state:end -->

Built login endpoint.
WS_EOF

  # Make it stale
  local past_time
  past_time=$(($(date +%s) - 300))
  touch -t "$(date -r "$past_time" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$past_time" '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_MEMORY_DIR/progress.md" 2>/dev/null || true

  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
echo "CLAUDE_WAS_CALLED" > "$HOME/.tandem/state/claude_called.txt"
printf 'STATE:\n- Working on auth\n\nPROGRESS:\n- Built login endpoint'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  # Claude SHOULD have been called (progress is stale)
  [ -f "$HOME/.tandem/state/claude_called.txt" ]
}

@test "working-state: pre-compact calls LLM when no markers exist" {
  local transcript
  transcript=$(_create_transcript)

  # Create progress without Working State markers (fresh)
  create_progress "regular notes without markers" 0

  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
echo "CLAUDE_WAS_CALLED" > "$HOME/.tandem/state/claude_called.txt"
printf 'STATE:\n- Working on something'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  # Claude SHOULD have been called (no structured markers)
  [ -f "$HOME/.tandem/state/claude_called.txt" ]
}

# ─── Structured Working State in session-start ──────────────────────────────

@test "working-state: session-start displays Working State when no Pre-compaction State exists" {
  # Abnormal exit scenario: Working State markers present but no Pre-compaction State
  cat > "$TEST_MEMORY_DIR/progress.md" <<'WS_EOF'
<!-- working-state:start -->
## Working State
**Current task:** implementing auth module
**Approach:** JWT with refresh tokens
**Blockers:** none
**Key files:** src/auth.ts
<!-- working-state:end -->

Built login endpoint. Chose JWT over sessions for statelessness.
WS_EOF

  run_session_start
  assert_success
  assert_output --partial "Continuing from previous session:"
  assert_output --partial "implementing auth module"
}

@test "working-state: session-start prefers Pre-compaction State over bare Working State" {
  # Create progress.md with both Working State markers AND Pre-compaction State
  cat > "$TEST_MEMORY_DIR/progress.md" <<'WS_EOF'
<!-- working-state:start -->
## Working State
**Current task:** implementing auth module
**Approach:** JWT with refresh tokens
**Blockers:** none
**Key files:** src/auth.ts
<!-- working-state:end -->

Built login endpoint.

## Pre-compaction State
Working on something else entirely from LLM
WS_EOF

  run_session_start
  assert_success
  assert_output --partial "Resuming. Before compaction you were:"
  assert_output --partial "implementing auth module"
  refute_output --partial "Continuing from previous session:"
}

@test "working-state: session-start falls back to Pre-compaction State without markers" {
  create_progress "$(printf '## Earlier Work\n- Did stuff\n\n## Pre-compaction State\nFree-form state from LLM')"

  run_session_start
  assert_success
  assert_output --partial "Resuming. Before compaction you were:"
  assert_output --partial "Free-form state from LLM"
}

@test "cleanup: session-start removes Auto-captured section along with Pre-compaction State" {
  cat > "$TEST_MEMORY_DIR/progress.md" <<'CLEANUP_EOF'
## Session Log

Built the login endpoint.

## Auto-captured (pre-compaction)
LLM captured some state here

## Pre-compaction State
Working on auth module
CLEANUP_EOF

  run_session_start
  assert_success

  run cat "$TEST_MEMORY_DIR/progress.md"
  refute_output --partial "Auto-captured"
  refute_output --partial "Pre-compaction State"
  assert_output --partial "Session Log"
}

# ─── Working State in compaction prompt ──────────────────────────────────────

@test "working-state: compaction prompt references working-state markers" {
  create_progress "session notes"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  echo "$STDIN" > "$HOME/.tandem/state/captured_compaction.txt"
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
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_compaction.txt")
  [[ "$captured" == *"working-state:start/end"* ]]
}

# ─── Recurrence auto-promotion ──────────────────────────────────────────────

@test "recurrence: high-count themes passed to compaction prompt" {
  create_progress "session notes"
  # Create recurrence.json with themes above threshold
  mkdir -p "$HOME/.tandem/state"
  cat > "$HOME/.tandem/state/recurrence.json" <<'EOF'
{
  "themes": {
    "error-handling": {"count": 5, "first_seen": "2026-01-01", "last_seen": "2026-02-10"},
    "testing": {"count": 2, "first_seen": "2026-01-15", "last_seen": "2026-02-05"}
  }
}
EOF

  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
if echo "$STDIN" | grep -q 'compaction'; then
  echo "$STDIN" > "$HOME/.tandem/state/captured_compaction.txt"
  cat <<'RECALL'
# Project Memory

## Architecture
- [P1] Express API (observed: 2026-01-15)

## Patterns
- [P1] Error handling via middleware (observed: 2026-01-01)

## Last Session
Tests.

THEMES: testing, error-handling
RECALL
elif echo "$STDIN" | grep -q 'USER.md'; then
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_compaction.txt")
  # Should include recurrence section with high-count themes (count >= 3)
  [[ "$captured" == *"Recurrence-aware compaction"* ]]
  [[ "$captured" == *"error-handling"* ]]
}

@test "recurrence: no recurrence section when no themes >= 3" {
  create_progress "session notes"
  mkdir -p "$HOME/.tandem/state"
  cat > "$HOME/.tandem/state/recurrence.json" <<'EOF'
{
  "themes": {
    "testing": {"count": 2, "first_seen": "2026-01-15", "last_seen": "2026-02-05"}
  }
}
EOF

  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
STDIN=$(cat)
echo "$STDIN" > "$HOME/.tandem/state/captured_prompt.txt"
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
  printf 'NONE'
fi
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_worker

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_prompt.txt")
  # Should NOT include recurrence section
  [[ "$captured" != *"Recurrence-aware compaction"* ]]
}

@test "recurrence: warns when high-count theme missing from MEMORY.md" {
  create_progress "session notes"
  mkdir -p "$HOME/.tandem/state"
  cat > "$HOME/.tandem/state/recurrence.json" <<'EOF'
{
  "themes": {
    "data-safety": {"count": 6, "first_seen": "2026-01-01", "last_seen": "2026-02-10"},
    "testing": {"count": 2, "first_seen": "2026-01-15", "last_seen": "2026-02-05"}
  }
}
EOF

  _install_mock_claude_dispatch \
    "compaction" "recall-compact-priority.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # Check the log for the warning about missing theme
  run cat "$HOME/.tandem/logs/tandem.log"
  assert_output --partial "high-recurrence theme 'data-safety' (5+ sessions) missing from MEMORY.md"
}

@test "recurrence: no warning when high-count theme is in MEMORY.md" {
  create_progress "session notes"
  mkdir -p "$HOME/.tandem/state"
  # Use "express" as theme — the word appears in the priority fixture body
  cat > "$HOME/.tandem/state/recurrence.json" <<'EOF'
{
  "themes": {
    "express": {"count": 6, "first_seen": "2026-01-01", "last_seen": "2026-02-10"}
  }
}
EOF

  _install_mock_claude_dispatch \
    "compaction" "recall-compact-priority.txt" \
    "USER.md" "grow-extract-none.txt"

  run_worker

  assert_success
  # "express" appears in the fixture body ("Express with TypeScript")
  # so the grep -qi should find it and no warning is logged
  run cat "$HOME/.tandem/logs/tandem.log"
  refute_output --partial "high-recurrence theme 'express'"
}

# ─── Recall-promote skill ──────────────────────────────────────────────────

@test "skill: recall-promote SKILL.md exists with correct frontmatter" {
  [ -f "$PLUGIN_ROOT/skills/recall-promote/SKILL.md" ]
  run head -5 "$PLUGIN_ROOT/skills/recall-promote/SKILL.md"
  assert_output --partial "name: recall-promote"
  assert_output --partial "description:"
}

# ─── Rules file version ────────────────────────────────────────────────────

@test "rules: tandem-recall.md has v1.3.0 version header" {
  run head -1 "$PLUGIN_ROOT/rules/tandem-recall.md"
  assert_output --partial "v1.3.0"
}

@test "rules: tandem-recall.md contains priority annotation instructions" {
  run cat "$PLUGIN_ROOT/rules/tandem-recall.md"
  assert_output --partial "[P1]"
  assert_output --partial "[P2]"
  assert_output --partial "[P3]"
  assert_output --partial "observed: YYYY-MM-DD"
}

@test "rules: tandem-recall.md contains Working State template" {
  run cat "$PLUGIN_ROOT/rules/tandem-recall.md"
  assert_output --partial "working-state:start"
  assert_output --partial "working-state:end"
  assert_output --partial "Current task"
  assert_output --partial "Session Log"
}
