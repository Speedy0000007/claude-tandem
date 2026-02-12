#!/usr/bin/env bats
# Tests for task-completed.sh (TaskCompleted hook)
# Outputs a systemMessage nudge when progress.md is stale (>300s) or missing.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="task-completed.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exits 0 with no output" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ────────────────────────────────────────────────────────

@test "empty CWD: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success
  assert_output ""
}

# ─── Missing progress.md ─────────────────────────────────────────────────────

@test "missing progress.md: outputs systemMessage nudge" {
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'Update progress.md'
}

# ─── Stale progress ──────────────────────────────────────────────────────────

@test "stale progress (>300s): outputs systemMessage nudge" {
  create_progress "some old notes" 600
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'Update progress.md'
}

# ─── Fresh progress ──────────────────────────────────────────────────────────

@test "fresh progress (<300s): no output, exits 0" {
  create_progress "recent work" 0
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
  assert_output ""
}

# ─── Task subject ────────────────────────────────────────────────────────────

@test "task subject included in message when provided" {
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  assert_output --partial "Task 'Add auth'"
}

@test "task subject omitted when not provided" {
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
  refute_output --partial "Task '"
  assert_output --partial 'Update progress.md'
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "output is valid JSON" {
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Deploy")"
  assert_success
  # Pipe output through jq to validate
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── Exit code ────────────────────────────────────────────────────────────────

@test "exits 0 on all paths" {
  # Missing progress
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Fresh progress
  create_progress "fresh" 0
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Stale progress
  create_progress "stale" 600
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Empty CWD
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success

  # Worker guard
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
}

# ─── No stderr ────────────────────────────────────────────────────────────────

@test "no stderr output" {
  rm -f "$TEST_MEMORY_DIR/progress.md"
  run bash -c "echo '$(fixture_taskcompleted "$TEST_CWD" "Test")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_out"
  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr_out")
  [ -z "$stderr_content" ]
}
