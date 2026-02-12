#!/bin/bash
# JSON input builders for each hook type.
# These mirror the shapes that Claude Code sends to hooks via stdin.

fixture_pretooluse() {
  local command="${1:-ls}"
  local cwd="${2:-$TEST_CWD}"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$command" "$cwd"
}

fixture_pretooluse_tool() {
  local tool_name="${1:-Read}"
  local cwd="${2:-$TEST_CWD}"
  printf '{"tool_name":"%s","tool_input":{},"cwd":"%s"}' "$tool_name" "$cwd"
}

fixture_userpromptsubmit() {
  local prompt="$1"
  # Use jq for safe JSON encoding of the prompt
  jq -n --arg p "$prompt" '{"prompt": $p}'
}

fixture_sessionstart() {
  local cwd="${1:-$TEST_CWD}"
  printf '{"cwd":"%s"}' "$cwd"
}

fixture_sessionend() {
  local cwd="${1:-$TEST_CWD}"
  printf '{"cwd":"%s"}' "$cwd"
}

fixture_precompact() {
  local cwd="${1:-$TEST_CWD}"
  local transcript_path="${2:-/tmp/fake-transcript.jsonl}"
  printf '{"cwd":"%s","transcript_path":"%s"}' "$cwd" "$transcript_path"
}

fixture_taskcompleted() {
  local cwd="${1:-$TEST_CWD}"
  local subject="${2:-}"
  if [ -n "$subject" ]; then
    printf '{"cwd":"%s","task_subject":"%s"}' "$cwd" "$subject"
  else
    printf '{"cwd":"%s"}' "$cwd"
  fi
}
