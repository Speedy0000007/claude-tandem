#!/bin/bash
# Tandem shared library. Source at top of every script:
#   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
#   source "$PLUGIN_ROOT/lib/tandem.sh"

# ─── Log directory ────────────────────────────────────────────────────────────

_TANDEM_LOG_DIR="$HOME/.tandem/logs"
_TANDEM_LOG_FILE="$_TANDEM_LOG_DIR/tandem.log"

# ─── Log levels ───────────────────────────────────────────────────────────────

_TANDEM_LEVEL_ERROR=0
_TANDEM_LEVEL_WARN=1
_TANDEM_LEVEL_INFO=2
_TANDEM_LEVEL_DEBUG=3

# Resolve numeric threshold once at source time
_tandem_level_num() {
  case "$1" in
    error) echo 0 ;; warn) echo 1 ;; info) echo 2 ;; debug) echo 3 ;; *) echo 2 ;;
  esac
}
_TANDEM_THRESHOLD=$(_tandem_level_num "${TANDEM_LOG_LEVEL:-info}")

# Auto-detect script name from caller
_TANDEM_SCRIPT="${_TANDEM_SCRIPT:-$(basename "${BASH_SOURCE[1]}" .sh 2>/dev/null || echo "unknown")}"

# Plugin version (read once at source time)
_TANDEM_VERSION=$(jq -r '.version // "?"' "${PLUGIN_ROOT:-.}/.claude-plugin/plugin.json" 2>/dev/null || echo "?")

# ─── Silent logging ──────────────────────────────────────────────────────────

tandem_log() {
  local level="$1" message="$2"
  local level_num
  level_num=$(_tandem_level_num "$level")
  [ "$level_num" -gt "$_TANDEM_THRESHOLD" ] && return 0

  local label
  case "$level" in
    error) label="ERROR" ;; warn) label="WARN " ;; info) label="INFO " ;; debug) label="DEBUG" ;; *) label="INFO " ;;
  esac

  mkdir -p "$_TANDEM_LOG_DIR" 2>/dev/null
  printf '%s [%s] [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label" "$_TANDEM_VERSION" "$_TANDEM_SCRIPT" "$message" >> "$_TANDEM_LOG_FILE" 2>/dev/null
}

# ─── User-facing output ──────────────────────────────────────────────────────

_TANDEM_LOGO="◎╵═╵◎"

tandem_print() {
  echo "${_TANDEM_LOGO} ~ $1"
}

tandem_header() {
  local version stats sessions clarifications compactions updates
  version=$(jq -r '.version // "?"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "?")
  if [ -f "$HOME/.tandem/state/stats.json" ]; then
    stats=$(cat "$HOME/.tandem/state/stats.json")
    sessions=$(echo "$stats" | jq -r '.total_sessions // 0')
    clarifications=$(echo "$stats" | jq -r '.clarifications // 0')
    compactions=$(echo "$stats" | jq -r '.compactions // 0')
    updates=$(echo "$stats" | jq -r '.profile_updates // 0')
  else
    sessions=0 clarifications=0 compactions=0 updates=0
  fi
  echo "${_TANDEM_LOGO} ~ Tandem v${version} · ▷ ${sessions} · ✎ ${clarifications} · ↻ ${compactions} · ◆ ${updates}"
}

# ─── Cross-platform helpers ───────────────────────────────────────────────────

# Returns file modification time as epoch seconds.
# Linux stat -c works first; macOS stat -f as fallback.
tandem_file_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null
}

# ─── Dependency helpers ───────────────────────────────────────────────────────

tandem_require_jq() {
  if ! command -v jq &>/dev/null; then
    tandem_log error "jq not found — install: brew install jq (macOS) | apt install jq (Linux)"
    exit 0
  fi
}

tandem_require_claude() {
  if ! command -v claude &>/dev/null; then
    tandem_log error "claude CLI not found — check PATH or reinstall Claude Code"
    return 1
  fi
}

# ─── Session registry ────────────────────────────────────────────────────────

TANDEM_SESSIONS_DIR="$HOME/.tandem/sessions"

# Register a new session. Sets TANDEM_SESSION_ID.
# Usage: tandem_session_register <project_path> [session_id]
tandem_session_register() {
  local project="$1"
  local session_id="${2:-$$-$(date +%s)}"
  local project_slug
  project_slug=$(basename "$project")

  TANDEM_SESSION_ID="$session_id"
  export TANDEM_SESSION_ID

  local session_dir="$TANDEM_SESSIONS_DIR/$session_id"
  mkdir -p "$session_dir"

  local branch=""
  if git -C "$project" rev-parse --git-dir &>/dev/null 2>&1; then
    branch=$(git -C "$project" --no-optional-locks branch --show-current 2>/dev/null)
  fi

  local state
  state=$(jq -n \
    --arg sid "$session_id" \
    --arg pid "$$" \
    --arg ppid "$PPID" \
    --arg project "$project" \
    --arg slug "$project_slug" \
    --arg branch "$branch" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg heartbeat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      session_id: $sid,
      pid: ($pid | tonumber),
      ppid: ($ppid | tonumber),
      project: $project,
      project_slug: $slug,
      branch: $branch,
      started: $started,
      last_heartbeat: $heartbeat,
      status: "active",
      current_task: ""
    }')

  echo "$state" > "$session_dir/state.json"
  tandem_log info "session registered: $session_id (project: $project_slug)"
}

# Update session heartbeat and optional fields.
# Usage: tandem_session_heartbeat [task] [branch]
tandem_session_heartbeat() {
  local task="${1:-}"
  local branch="${2:-}"
  local session_id="${TANDEM_SESSION_ID:-}"
  [ -z "$session_id" ] && return 0

  local state_file="$TANDEM_SESSIONS_DIR/$session_id/state.json"
  [ ! -f "$state_file" ] && return 0

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local updates=".last_heartbeat = \"$now\""
  [ -n "$task" ] && updates="$updates | .current_task = \"$task\""
  [ -n "$branch" ] && updates="$updates | .branch = \"$branch\""

  local updated
  updated=$(jq "$updates" "$state_file" 2>/dev/null)
  [ -z "$updated" ] && return 0

  echo "$updated" > "$state_file"
}

# Deregister a session (mark ended, then clean up directory).
# Usage: tandem_session_deregister [session_id]
tandem_session_deregister() {
  local session_id="${1:-${TANDEM_SESSION_ID:-}}"
  [ -z "$session_id" ] && return 0

  local session_dir="$TANDEM_SESSIONS_DIR/$session_id"
  [ ! -d "$session_dir" ] && return 0

  # Mark as ended before removal (in case cleanup is delayed)
  if [ -f "$session_dir/state.json" ]; then
    local updated
    updated=$(jq '.status = "ended"' "$session_dir/state.json" 2>/dev/null)
    [ -n "$updated" ] && echo "$updated" > "$session_dir/state.json"
  fi

  rm -rf "$session_dir"
  tandem_log info "session deregistered: $session_id"
}

# List active session directories (heartbeat < 5min, pid alive).
# Outputs one session_id per line.
tandem_active_sessions() {
  [ ! -d "$TANDEM_SESSIONS_DIR" ] && return 0

  local now
  now=$(date +%s)
  local max_age=300  # 5 minutes

  for session_dir in "$TANDEM_SESSIONS_DIR"/*/; do
    [ ! -d "$session_dir" ] && continue
    local state_file="$session_dir/state.json"
    [ ! -f "$state_file" ] && continue

    local pid heartbeat_str status
    pid=$(jq -r '.pid // empty' "$state_file" 2>/dev/null)
    heartbeat_str=$(jq -r '.last_heartbeat // empty' "$state_file" 2>/dev/null)
    status=$(jq -r '.status // empty' "$state_file" 2>/dev/null)

    [ "$status" = "ended" ] && continue
    [ -z "$pid" ] && continue

    # Check if pid is still alive
    if ! kill -0 "$pid" 2>/dev/null; then
      continue
    fi

    # Check heartbeat freshness
    if [ -n "$heartbeat_str" ]; then
      local heartbeat_epoch
      heartbeat_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$heartbeat_str" +%s 2>/dev/null || date -d "$heartbeat_str" +%s 2>/dev/null || echo 0)
      local age=$((now - heartbeat_epoch))
      if [ "$age" -gt "$max_age" ]; then
        continue
      fi
    fi

    basename "$session_dir"
  done
}

# List active sessions for the same project (matching CWD).
# Usage: tandem_sibling_sessions <project_path> [exclude_session_id]
tandem_sibling_sessions() {
  local project="$1"
  local exclude="${2:-}"
  [ ! -d "$TANDEM_SESSIONS_DIR" ] && return 0

  for sid in $(tandem_active_sessions); do
    [ "$sid" = "$exclude" ] && continue
    local state_file="$TANDEM_SESSIONS_DIR/$sid/state.json"
    [ ! -f "$state_file" ] && continue

    local sess_project
    sess_project=$(jq -r '.project // empty' "$state_file" 2>/dev/null)
    if [ "$sess_project" = "$project" ]; then
      echo "$sid"
    fi
  done
}

# Count active sessions.
tandem_session_count() {
  tandem_active_sessions | wc -l | tr -d ' '
}

# Clean up orphaned sessions (stale heartbeat + dead pid).
tandem_cleanup_orphans() {
  [ ! -d "$TANDEM_SESSIONS_DIR" ] && return 0

  local now
  now=$(date +%s)
  local max_age=300

  for session_dir in "$TANDEM_SESSIONS_DIR"/*/; do
    [ ! -d "$session_dir" ] && continue
    local state_file="$session_dir/state.json"
    [ ! -f "$state_file" ] && continue

    local pid heartbeat_str
    pid=$(jq -r '.pid // empty' "$state_file" 2>/dev/null)
    heartbeat_str=$(jq -r '.last_heartbeat // empty' "$state_file" 2>/dev/null)

    [ -z "$pid" ] && { rm -rf "$session_dir"; continue; }

    # Dead pid = orphan
    if ! kill -0 "$pid" 2>/dev/null; then
      local sid
      sid=$(basename "$session_dir")
      tandem_log info "cleaning orphaned session: $sid (pid $pid dead)"
      rm -rf "$session_dir"
      continue
    fi

    # Stale heartbeat + alive pid = skip (might just be idle)
  done
}

# ─── .env loading ────────────────────────────────────────────────────────────

[ -f "$HOME/.tandem/.env" ] && source "$HOME/.tandem/.env"

# ─── LLM backend abstraction ────────────────────────────────────────────────

tandem_require_llm() {
  local backend="${TANDEM_LLM_BACKEND:-claude}"
  if [ "$backend" = "claude" ]; then
    tandem_require_claude
  else
    if ! command -v curl &>/dev/null; then
      tandem_log error "curl not found — required for URL-based LLM backend"
      return 1
    fi
    if ! command -v jq &>/dev/null; then
      tandem_log error "jq not found — required for URL-based LLM backend"
      return 1
    fi
    if [ -z "${TANDEM_LLM_MODEL:-}" ]; then
      tandem_log error "TANDEM_LLM_MODEL is required when using a URL backend (e.g. llama3.2, mistral)"
      return 1
    fi
  fi
}

tandem_llm_call() {
  local prompt="$1"
  local budget="${2:-0.15}"
  local backend="${TANDEM_LLM_BACKEND:-claude}"
  local model="${TANDEM_LLM_MODEL:-haiku}"

  if [ "$backend" = "claude" ]; then
    local result
    result=$(echo "$prompt" | claude -p --model "$model" --max-budget-usd "$budget" --system-prompt "" --tools "" 2>/dev/null)
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$result" ]; then
      tandem_log error "LLM call failed: empty response (claude backend)"
      return 1
    fi
    if [[ "$result" == Error:* ]]; then
      tandem_log error "LLM call failed: ${result}"
      return 1
    fi

    printf '%s' "$result"
  else
    local url="${backend}/v1/chat/completions"
    local payload
    payload=$(jq -n \
      --arg model "$model" \
      --arg content "$prompt" \
      '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 4096}')

    local curl_args=(-s -S --max-time 120 -H "Content-Type: application/json")
    if [ -n "${TANDEM_LLM_API_KEY:-}" ]; then
      curl_args+=(-H "Authorization: Bearer ${TANDEM_LLM_API_KEY}")
    fi

    local response
    response=$(curl "${curl_args[@]}" -d "$payload" "$url" 2>/dev/null)
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$response" ]; then
      tandem_log error "LLM call failed: curl error (rc=$rc) for $url"
      return 1
    fi

    local result
    result=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [ -z "$result" ]; then
      local err_msg
      err_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
      tandem_log error "LLM call failed: ${err_msg:-no content in response} ($url)"
      return 1
    fi

    printf '%s' "$result"
  fi
}
