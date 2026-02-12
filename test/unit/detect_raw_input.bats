#!/usr/bin/env bats
# Tests for detect-raw-input.sh (UserPromptSubmit hook)
# Assesses prompt quality via LLM. Short prompts skip. LLM returns SKIP/CLARIFY/RESTRUCTURE.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="detect-raw-input.sh"
LONG_PROMPT=$(printf 'x%.0s' {1..250})

# ─── Length gate ──────────────────────────────────────────────────────────────

@test "empty prompt: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"prompt":""}'
  assert_success
  assert_output ""
}

@test "short prompt (below MIN_LENGTH): exits 0 with no output" {
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "Fix the bug")"
  assert_success
  assert_output ""
}

@test "TANDEM_CLARIFY_MIN_LENGTH override respected" {
  export TANDEM_CLARIFY_MIN_LENGTH=10
  _install_mock_claude_fixture "clarify-skip.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "This is a 15 char+")"
  assert_success
  # Should have passed the length gate (prompt > 10 chars) and hit the LLM.
  # SKIP means no hookSpecificOutput, but the log file should exist.
  [ -f "$HOME/.tandem/logs/clarify.jsonl" ]
}

# ─── LLM outcomes ────────────────────────────────────────────────────────────

@test "LLM returns SKIP: exits 0 with no hookSpecificOutput" {
  _install_mock_claude_fixture "clarify-skip.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "LLM returns RESTRUCTURE: outputs hookSpecificOutput with restructured text" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  assert_output --partial '"hookEventName"'
  assert_output --partial 'restructured version'
}

@test "LLM returns CLARIFY: outputs hookSpecificOutput with questions" {
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  assert_output --partial 'following questions'
}

# ─── Branding ─────────────────────────────────────────────────────────────────

@test "CLARIFY output contains Clarify branding" {
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'Clarify.'
}

@test "RESTRUCTURE output contains Clarified branding" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'Clarified.'
}

@test "quiet mode (TANDEM_CLARIFY_QUIET=1): RESTRUCTURE omits branding" {
  export TANDEM_CLARIFY_QUIET=1
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  refute_output --partial 'Clarified.'
}

@test "quiet mode: CLARIFY omits branding" {
  export TANDEM_CLARIFY_QUIET=1
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  refute_output --partial 'Clarify.'
}

# ─── Logging ──────────────────────────────────────────────────────────────────

@test "logs to clarify.jsonl after non-skip result" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  [ -f "$HOME/.tandem/logs/clarify.jsonl" ]
}

@test "clarify.jsonl entry is valid JSON" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  # The file may contain pretty-printed JSON objects; validate the whole file
  jq . "$HOME/.tandem/logs/clarify.jsonl" >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── LLM failure modes ───────────────────────────────────────────────────────

@test "LLM missing (tandem_require_llm fails): exits 0" {
  # Build fixture JSON before removing claude from PATH (jq is needed)
  local input_json
  input_json="$(fixture_userpromptsubmit "$LONG_PROMPT")"
  _remove_mock_claude
  # Use /bin/bash explicitly since PATH is clobbered
  run /bin/bash -c "echo '${input_json}' | '$PLUGIN_ROOT/scripts/$SCRIPT'"
  assert_success
}

@test "LLM returns empty: exits 0" {
  _install_mock_claude_fail "empty"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
}

# ─── No stderr ────────────────────────────────────────────────────────────────

@test "no stderr output on all paths" {
  # SKIP path
  _install_mock_claude_fixture "clarify-skip.txt"
  run bash -c "echo '$(fixture_userpromptsubmit "$LONG_PROMPT")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_skip"
  local stderr_skip
  stderr_skip=$(cat "$TEST_TEMP_DIR/stderr_skip")
  [ -z "$stderr_skip" ]

  # RESTRUCTURE path
  _install_mock_claude_fixture "clarify-restructure.txt"
  run bash -c "echo '$(fixture_userpromptsubmit "$LONG_PROMPT")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_restructure"
  local stderr_restructure
  stderr_restructure=$(cat "$TEST_TEMP_DIR/stderr_restructure")
  [ -z "$stderr_restructure" ]
}

# ─── Output structure ─────────────────────────────────────────────────────────

@test "hookSpecificOutput has correct structure" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success

  # Validate structure: hookSpecificOutput.hookEventName == "UserPromptSubmit"
  local event_name
  event_name=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName')
  [ "$event_name" = "UserPromptSubmit" ]

  # Validate structure: hookSpecificOutput.additionalContext is a non-empty string
  local context
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [ -n "$context" ]
}
