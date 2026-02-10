#!/bin/bash
# SessionStart hook: first-run provisioning + stale progress detection + status indicators.
# Outputs to stdout are injected into Claude's context.

command -v jq &>/dev/null || { echo "[Tandem] Error: jq required but not found" >&2; exit 0; }

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Compute auto-memory directory (same convention as Claude Code)
SANITISED=$(echo "$CWD" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"

PROFILE_DIR="${TANDEM_PROFILE_DIR:-$HOME/.tandem/profile}"
RULES_DIR="$HOME/.claude/rules"
MARKER_FILE="$HOME/.tandem/.provisioned"

# --- First-run provisioning (only if never provisioned before) ---

if [ ! -f "$MARKER_FILE" ]; then
  PROVISIONED=0

  # Provision rules files
  if [ -f "$PLUGIN_ROOT/rules/tandem-recall.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-recall.md" "$RULES_DIR/tandem-recall.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-grow.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-grow.md" "$RULES_DIR/tandem-grow.md"
    PROVISIONED=1
  fi

  # Provision profile directory
  if [ ! -d "$PROFILE_DIR" ]; then
    mkdir -p "$PROFILE_DIR"
    if [ -f "$PLUGIN_ROOT/templates/career-context.md" ]; then
      cp "$PLUGIN_ROOT/templates/career-context.md" "$PROFILE_DIR/career-context.md"
    fi
    PROVISIONED=1
  fi

  if [ "$PROVISIONED" -eq 1 ]; then
    mkdir -p "$(dirname "$MARKER_FILE")"
    date +%s > "$MARKER_FILE"
    echo "[Tandem] First run — provisioned rules files and profile directory. Run /tandem:status to verify."
  fi
fi

# --- Version-based rules upgrade ---

PLUGIN_VERSION=$(jq -r '.version // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
if [ -n "$PLUGIN_VERSION" ]; then
  for RULES_FILE in "$RULES_DIR"/tandem-*.md; do
    [ -f "$RULES_FILE" ] || continue
    BASENAME=$(basename "$RULES_FILE")
    SOURCE="$PLUGIN_ROOT/rules/$BASENAME"
    [ -f "$SOURCE" ] || continue

    # Check version comment in installed rules file
    INSTALLED_VER=$(head -1 "$RULES_FILE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
    SOURCE_VER=$(head -1 "$SOURCE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')

    if [ -n "$SOURCE_VER" ] && [ "$INSTALLED_VER" != "$SOURCE_VER" ]; then
      cp "$SOURCE" "$RULES_FILE"
    fi
  done
fi

# --- Status indicators ---

# Recalled. — previous session was compacted
if [ -f "$MEMORY_DIR/.tandem-last-compaction" ]; then
  echo "Recalled."
  rm -f "$MEMORY_DIR/.tandem-last-compaction"
fi

# Grown. — learning nudge from previous session
NUDGE_FILE="$HOME/.tandem/next-nudge"
if [ -f "$NUDGE_FILE" ]; then
  NUDGE_CONTENT=$(cat "$NUDGE_FILE")
  if [ -n "$NUDGE_CONTENT" ]; then
    echo "Grown."
    echo "$NUDGE_CONTENT"
  fi
  rm -f "$NUDGE_FILE"
fi

# --- Stale progress detection ---

if [ -f "$MEMORY_DIR/progress.md" ]; then
  # Check if progress.md was modified before this session (stale = from a previous session)
  PROGRESS_MTIME=$(stat -f '%m' "$MEMORY_DIR/progress.md" 2>/dev/null || stat -c '%Y' "$MEMORY_DIR/progress.md" 2>/dev/null)
  SESSION_START=$(date +%s)

  # If progress.md is more than 5 minutes old, it's from a previous session
  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((SESSION_START - PROGRESS_MTIME))
    if [ "$AGE" -gt 300 ]; then
      echo "[Tandem] Stale progress.md detected from a previous session (SessionEnd hook may not have fired). Contents preserved — review and incorporate relevant context."
    fi
  fi
fi

exit 0
