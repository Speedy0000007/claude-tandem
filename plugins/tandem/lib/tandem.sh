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
