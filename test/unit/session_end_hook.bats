#!/usr/bin/env bats
# Tests for session-end.sh hook mode (default, no --worker arg).
# The hook reads stdin JSON, prints a branded message, and spawns a worker.
# We test the sync behaviour only (output, exit code, early exits).

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── 1. TANDEM_WORKER set: exit 0, no output ────────────────────────────────

@test "TANDEM_WORKER set: exit 0, no output" {
  export TANDEM_WORKER=1
  create_progress "some progress notes"

  run_script_with_input "session-end.sh" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output ""
}

# ─── 2. No CWD in input: exit 0, no output ──────────────────────────────────

@test "no CWD in input: exit 0, no output" {
  create_progress "some progress notes"

  run_script_with_input "session-end.sh" '{"cwd":""}'

  assert_success
  assert_output ""
}

# ─── 3. No progress.md: exit 0, no output ───────────────────────────────────

@test "no progress.md: exit 0, no output" {
  rm -f "$TEST_MEMORY_DIR/progress.md"

  run_script_with_input "session-end.sh" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output ""
}

# ─── 4. With progress.md: outputs branded message ───────────────────────────

@test "with progress.md: outputs branded session captured message" {
  create_progress "line one
line two
line three"

  run_script_with_input "session-end.sh" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output --partial "Session captured"
  assert_output --partial "lines"
}

# ─── 5. Output contains correct line count ───────────────────────────────────

@test "output contains correct line count" {
  printf 'line 1\nline 2\nline 3\nline 4\nline 5\n' > "$TEST_MEMORY_DIR/progress.md"

  run_script_with_input "session-end.sh" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output --partial "5 lines"
}

# ─── 6. No stderr output ────────────────────────────────────────────────────

@test "no stderr output" {
  create_progress "progress notes here"

  run bash -c "echo '$(fixture_sessionend "$TEST_CWD")' | '$PLUGIN_ROOT/scripts/session-end.sh' 2>'$TEST_TEMP_DIR/stderr.txt'"

  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr.txt")
  [ -z "$stderr_content" ]
}
