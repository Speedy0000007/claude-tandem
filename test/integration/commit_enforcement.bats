#!/usr/bin/env bats
# Integration: commit validation journey
# Tests validate-commit.sh enforcement of conventional commits + body presence

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Build PreToolUse JSON with safe encoding via jq
_commit_input() {
  local command="$1"
  jq -n --arg cmd "$command" --arg cwd "$TEST_CWD" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}'
}

# Run validate-commit with a git command, using jq-encoded JSON piped via file
_run_validate() {
  local command="$1"
  local json
  json=$(_commit_input "$command")
  local tmpfile="$TEST_TEMP_DIR/input.json"
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh'"
}

# ─── Tests ────────────────────────────────────────────────────────────────────

@test "commit enforcement: bad subject denied, then good format allowed" {
  # Bad format: missing type prefix
  _run_validate 'git commit -m "add new feature

This adds a feature."'

  assert_failure 2
  assert_output --partial "deny"
  assert_output --partial "Conventional Commits"

  # Good format with body (heredoc style)
  _run_validate "git commit -m \"\$(cat <<'EOF'
feat: add new feature

This adds a feature for user authentication.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""

  assert_success
}

@test "commit enforcement: missing body denied, then body added passes" {
  # Good subject but no body (just Co-Authored-By, which is stripped)
  _run_validate "git commit -m \"\$(cat <<'EOF'
feat(auth): add OAuth2 login

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""

  assert_failure 2
  assert_output --partial "deny"
  assert_output --partial "body is missing"

  # Same subject with real body
  _run_validate "git commit -m \"\$(cat <<'EOF'
feat(auth): add OAuth2 login

Implements OAuth2 authorization code flow with PKCE.
Chose this over implicit grant for better security in SPAs.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""

  assert_success
}

@test "commit enforcement: deny output is parseable JSON with required fields" {
  _run_validate 'git commit -m "bad commit"'

  assert_failure 2

  # Output must be valid JSON
  echo "$output" | jq empty

  # Must have decision and reason fields
  local decision
  decision=$(echo "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]

  local reason
  reason=$(echo "$output" | jq -r '.reason')
  [ -n "$reason" ]
}

@test "commit enforcement: all quote format variants work with body" {
  # Heredoc format (single-quoted EOF)
  _run_validate "git commit -m \"\$(cat <<'EOF'
fix(api): handle null response

Guard against null API responses that caused crashes in production.
Added fallback to empty object when response body is missing.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""
  assert_success

  # Double-quote heredoc format (double-quoted EOF)
  _run_validate "git commit -m \"\$(cat <<\"EOF\"
refactor(db): extract query builder

Moved shared query logic into a dedicated QueryBuilder class.
Reduces duplication across 4 repository files.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""
  assert_success

  # Unquoted heredoc format
  _run_validate "git commit -m \"\$(cat <<EOF
docs: update API reference

Added missing endpoint documentation for /api/v2/users.
Includes request/response examples and error codes.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""
  assert_success
}
