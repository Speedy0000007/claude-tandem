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
  local version stats sessions compactions updates
  version=$(jq -r '.version // "?"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "?")
  if [ -f "$HOME/.tandem/state/stats.json" ]; then
    stats=$(cat "$HOME/.tandem/state/stats.json")
    sessions=$(echo "$stats" | jq -r '.total_sessions // 0')
    compactions=$(echo "$stats" | jq -r '.compactions // 0')
    updates=$(echo "$stats" | jq -r '.profile_updates // 0')
  else
    sessions=0 compactions=0 updates=0
  fi
  echo "${_TANDEM_LOGO} ~ Tandem v${version} · ▷ ${sessions} · ↻ ${compactions} · ◆ ${updates}"
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
