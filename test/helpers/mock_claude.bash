#!/bin/bash
# Mock builders for claude CLI and curl.
# Sourced by test_helper.bash (via load) or directly in .bats files.

# ─── Mock claude CLI ──────────────────────────────────────────────────────

# Simple mock: always returns the same output
_install_mock_claude() {
  local response_body="${1:-}"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/claude" <<MOCK_EOF
#!/bin/bash
printf '%s' '$response_body'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}

# Mock that returns content of a fixture file
_install_mock_claude_fixture() {
  local fixture_name="$1"
  local fixture_file="${BATS_TEST_DIR}/fixtures/claude-responses/${fixture_name}"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/claude" <<MOCK_EOF
#!/bin/bash
cat "$fixture_file"
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}

# Mock that dispatches based on stdin content keywords
_install_mock_claude_dispatch() {
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  # Build dispatch script from pairs of (keyword, fixture_file)
  local script="#!/bin/bash
STDIN=\$(cat)
"
  while [ $# -ge 2 ]; do
    local keyword="$1"
    local fixture="$2"
    local fixture_file="${BATS_TEST_DIR}/fixtures/claude-responses/${fixture}"
    script="${script}
if echo \"\$STDIN\" | grep -q '${keyword}'; then
  cat '${fixture_file}'
  exit 0
fi"
    shift 2
  done

  script="${script}
echo 'SKIP'
"

  echo "$script" > "$mock_dir/claude"
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}

# Mock that simulates failure modes
_install_mock_claude_fail() {
  local mode="${1:-empty}"  # empty | error | exit
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  case "$mode" in
    empty)
      cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
# Return empty
MOCK_EOF
      ;;
    error)
      cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
echo "Error: Exceeded USD budget"
MOCK_EOF
      ;;
    exit)
      cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
      ;;
  esac

  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}

# Remove claude from PATH to test tandem_require_claude failure
_remove_mock_claude() {
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  rm -f "$mock_dir/claude"
  # Also remove real claude from PATH
  export PATH="$mock_dir"
}

# ─── Mock curl ────────────────────────────────────────────────────────────

# Mock curl that returns a given JSON response
_install_mock_curl() {
  local response_json="$1"
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/curl" <<MOCK_EOF
#!/bin/bash
printf '%s' '$response_json'
MOCK_EOF
  chmod +x "$mock_dir/curl"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}

# Mock curl failure modes
_install_mock_curl_fail() {
  local mode="${1:-timeout}"  # timeout | bad_json | api_error
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"

  case "$mode" in
    timeout)
      cat > "$mock_dir/curl" <<'MOCK_EOF'
#!/bin/bash
exit 28
MOCK_EOF
      ;;
    bad_json)
      cat > "$mock_dir/curl" <<'MOCK_EOF'
#!/bin/bash
echo "not json at all"
MOCK_EOF
      ;;
    api_error)
      cat > "$mock_dir/curl" <<'MOCK_EOF'
#!/bin/bash
echo '{"error":{"message":"model not found","type":"invalid_request_error"}}'
MOCK_EOF
      ;;
  esac

  chmod +x "$mock_dir/curl"
  export PATH="$mock_dir:$ORIGINAL_PATH"
}
