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
  assert_output --partial 'Questions to resolve'
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

# ─── CLARIFY intent extraction ────────────────────────────────────────────────

@test "CLARIFY output contains restructured intent" {
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'Intent (restructured from user input)'
  assert_output --partial 'user authentication'
}

@test "quiet mode: CLARIFY output contains intent" {
  export TANDEM_CLARIFY_QUIET=1
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'Intent:'
  assert_output --partial 'user authentication'
}

@test "CLARIFY with no intent lines falls back to default" {
  # Create a fixture with CLARIFY but no intent line (just questions)
  local fixture_dir="${BATS_TEST_DIR}/fixtures/claude-responses"
  cat > "$fixture_dir/clarify-no-intent.txt" <<'EOF'
CLARIFY
Q: What framework should we use?
Q: What database do you want?
EOF
  _install_mock_claude_fixture "clarify-no-intent.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial "the user's request"
  rm -f "$fixture_dir/clarify-no-intent.txt"
}

# ─── Case-insensitive detection ──────────────────────────────────────────────

@test "case-insensitive: lowercase 'skip' is detected as SKIP" {
  _install_mock_claude "skip"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "case-insensitive: mixed case 'Skip' is detected as SKIP" {
  _install_mock_claude "Skip"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "case-insensitive: lowercase 'clarify' is detected as CLARIFY" {
  local fixture_dir="${BATS_TEST_DIR}/fixtures/claude-responses"
  cat > "$fixture_dir/clarify-lowercase.txt" <<'EOF'
clarify
The user wants to add a feature.
Q: Which approach?
EOF
  _install_mock_claude_fixture "clarify-lowercase.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  assert_output --partial 'Questions to resolve'
  rm -f "$fixture_dir/clarify-lowercase.txt"
}

# ─── Stats increment ────────────────────────────────────────────────────────

@test "non-skip outcome increments clarifications counter" {
  create_stats 5 2 1 0
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local count
  count=$(jq -r '.clarifications' "$HOME/.tandem/state/stats.json")
  [ "$count" -eq 1 ]
}

@test "CLARIFY outcome increments clarifications counter" {
  create_stats 5 2 1 3
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local count
  count=$(jq -r '.clarifications' "$HOME/.tandem/state/stats.json")
  [ "$count" -eq 4 ]
}

@test "SKIP outcome does not increment clarifications counter" {
  create_stats 5 2 1 3
  _install_mock_claude_fixture "clarify-skip.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local count
  count=$(jq -r '.clarifications' "$HOME/.tandem/state/stats.json")
  [ "$count" -eq 3 ]
}

@test "stats increment works without pre-existing clarifications field" {
  # Create stats without clarifications field (backwards compat)
  cat > "$HOME/.tandem/state/stats.json" <<'EOF'
{
  "total_sessions": 10,
  "compactions": 2,
  "profile_updates": 1,
  "milestones_hit": [],
  "profile_total_lines": 0
}
EOF
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local count
  count=$(jq -r '.clarifications' "$HOME/.tandem/state/stats.json")
  [ "$count" -eq 1 ]
}

# ─── Logging ──────────────────────────────────────────────────────────────────

@test "logs to clarify.jsonl after non-skip result" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  [ -f "$HOME/.tandem/logs/clarify.jsonl" ]
}

@test "clarify.jsonl entries are compact JSONL (one line per entry)" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local line_count
  line_count=$(wc -l < "$HOME/.tandem/logs/clarify.jsonl" | tr -d ' ')
  [ "$line_count" -eq 1 ]
}

@test "clarify.jsonl entry is valid JSON" {
  _install_mock_claude_fixture "clarify-restructure.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  jq . "$HOME/.tandem/logs/clarify.jsonl" >/dev/null 2>&1
  [ $? -eq 0 ]
}

@test "CLARIFY log entry includes intent field" {
  _install_mock_claude_fixture "clarify-clarify.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local intent
  intent=$(jq -r '.intent' "$HOME/.tandem/logs/clarify.jsonl")
  [ -n "$intent" ]
  [[ "$intent" == *"user authentication"* ]]
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

# ─── Skill hints ──────────────────────────────────────────────────────────────

@test "SKIP-with-skills outputs hookSpecificOutput" {
  _install_mock_claude_fixture "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
  assert_output --partial 'Consider loading these skills'
}

@test "SKIP-with-skills context contains skill names" {
  _install_mock_claude_fixture "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local context
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" == *"brainstorming"* ]]
  [[ "$context" == *"x-post"* ]]
}

@test "SKIP-with-skills does not increment clarifications counter" {
  create_stats 5 2 1 3
  _install_mock_claude_fixture "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local count
  count=$(jq -r '.clarifications' "$HOME/.tandem/state/stats.json")
  [ "$count" -eq 3 ]
}

@test "SKIP without skills stays silent (no hookSpecificOutput)" {
  _install_mock_claude_fixture "clarify-skip.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "CLARIFY with skill hints appends skills to context" {
  local fixture_dir="${BATS_TEST_DIR}/fixtures/claude-responses"
  cat > "$fixture_dir/clarify-clarify-skills.txt" <<'EOF'
CLARIFY
The user wants to build a Twitter bot.
Q: Which API version?
SKILLS: x-post, x-research
EOF
  _install_mock_claude_fixture "clarify-clarify-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'Questions to resolve'
  assert_output --partial 'Relevant skills to consider loading: x-post, x-research'
  rm -f "$fixture_dir/clarify-clarify-skills.txt"
}

@test "RESTRUCTURE with skill hints appends skills to context" {
  local fixture_dir="${BATS_TEST_DIR}/fixtures/claude-responses"
  cat > "$fixture_dir/clarify-restructure-skills.txt" <<'EOF'
Please implement a Twitter posting system with OAuth2 support.
SKILLS: x-post
EOF
  _install_mock_claude_fixture "clarify-restructure-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial 'restructured version'
  assert_output --partial 'Relevant skills to consider loading: x-post'
  rm -f "$fixture_dir/clarify-restructure-skills.txt"
}

@test "SKILLS line stripped from CLARIFY output body" {
  local fixture_dir="${BATS_TEST_DIR}/fixtures/claude-responses"
  cat > "$fixture_dir/clarify-clarify-skills.txt" <<'EOF'
CLARIFY
The user wants to build a Twitter bot.
Q: Which API version?
SKILLS: x-post, x-research
EOF
  _install_mock_claude_fixture "clarify-clarify-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  # SKILLS line should not appear in the questions/intent section
  local context
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  # The SKILLS: line should NOT appear verbatim in the question block
  refute_output --partial 'Q: SKILLS:'
  rm -f "$fixture_dir/clarify-clarify-skills.txt"
}

@test "JSONL entry includes skills field when hints present" {
  _install_mock_claude_fixture "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local skills
  skills=$(jq -r '.skills' "$HOME/.tandem/logs/clarify.jsonl")
  [[ "$skills" == *"brainstorming"* ]]
}

@test "JSONL entry has no skills field without hints" {
  _install_mock_claude_fixture "clarify-skip.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  local has_skills
  has_skills=$(jq 'has("skills")' "$HOME/.tandem/logs/clarify.jsonl")
  [ "$has_skills" = "false" ]
}

@test "skill discovery: user skills appear in LLM prompt" {
  # Create mock skills in test HOME
  mkdir -p "$HOME/.claude/skills/mock-twitter-skill"
  cat > "$HOME/.claude/skills/mock-twitter-skill/SKILL.md" <<'SKILL_EOF'
---
name: mock-twitter-skill
description: "Use when posting tweets to Twitter."
---
# Mock
SKILL_EOF

  # Dispatch: if prompt contains skill name, return SKIP+skills; otherwise plain SKIP
  _install_mock_claude_dispatch "mock-twitter-skill" "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  # Dispatch matched = SKIP+skills = hookSpecificOutput present
  assert_output --partial '"hookSpecificOutput"'
}

@test "skill discovery: falls back to directory name when no name field" {
  mkdir -p "$HOME/.claude/skills/dir-name-skill"
  cat > "$HOME/.claude/skills/dir-name-skill/SKILL.md" <<'SKILL_EOF'
---
description: "Use when testing directory name fallback."
---
# Test
SKILL_EOF

  # Dispatch: if prompt contains "dir-name-skill", return SKIP+skills
  _install_mock_claude_dispatch "dir-name-skill" "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
}

@test "skill discovery: plugin skills included" {
  # Plugin skills are at $PLUGIN_ROOT/skills/*/SKILL.md
  # The clarify skill already exists there, so dispatch on its name
  _install_mock_claude_dispatch "clarify" "clarify-skip-skills.txt"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "$LONG_PROMPT")"
  assert_success
  assert_output --partial '"hookSpecificOutput"'
}
