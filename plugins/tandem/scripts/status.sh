#!/bin/bash
# Tandem status diagnostic. Read-only — no writes, no LLM calls.
# Outputs a formatted status block to stdout.

CWD="${1:-$(pwd)}"
SANITISED=$(echo "$CWD" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"
PROFILE_DIR="${TANDEM_PROFILE_DIR:-$HOME/.tandem/profile}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
HOOKS_FILE="$PLUGIN_ROOT/hooks/hooks.json"
STATS_FILE="$HOME/.tandem/state/stats.json"

source "$PLUGIN_ROOT/lib/tandem.sh"

# --- Logo + Version ---

VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)

printf "\033[38;5;172m◎╵═╵◎\033[0m  \033[31mTandem v%s\033[0m\n" "$VERSION"
echo ""

# --- Pillar status ---

# Clarify: check hook registration
CLARIFY="not installed"
if [ -f "$HOOKS_FILE" ] && grep -q 'detect-raw-input.sh' "$HOOKS_FILE" 2>/dev/null; then
  CLARIFY="installed"
fi

# Recall: check rules + hook
RECALL="not installed"
RECALL_RULES=0
RECALL_HOOK=0
[ -f "$HOME/.claude/rules/tandem-recall.md" ] && RECALL_RULES=1
if [ -f "$HOOKS_FILE" ] && grep -q 'session-end.sh' "$HOOKS_FILE" 2>/dev/null; then
  RECALL_HOOK=1
fi
if [ "$RECALL_RULES" -eq 1 ] && [ "$RECALL_HOOK" -eq 1 ]; then
  RECALL="installed"
elif [ "$RECALL_RULES" -eq 1 ] || [ "$RECALL_HOOK" -eq 1 ]; then
  RECALL="partially installed"
fi

# Grow: check rules + hook + profile
GROW="not installed"
GROW_RULES=0
GROW_HOOK=$RECALL_HOOK  # Same hook
GROW_DETAIL=""
[ -f "$HOME/.claude/rules/tandem-grow.md" ] && GROW_RULES=1
if [ "$GROW_RULES" -eq 1 ] && [ "$GROW_HOOK" -eq 1 ]; then
  GROW="installed"
  # Count profile files and lines
  if [ -d "$PROFILE_DIR" ]; then
    FILE_COUNT=0
    TOTAL_LINES=0
    for f in "$PROFILE_DIR"/*.md; do
      [ -f "$f" ] || continue
      FILE_COUNT=$((FILE_COUNT + 1))
      LINES=$(wc -l < "$f" | tr -d ' ')
      TOTAL_LINES=$((TOTAL_LINES + LINES))
    done
    if [ "$FILE_COUNT" -gt 0 ]; then
      GROW_DETAIL=" (profile: ${FILE_COUNT} file$([ "$FILE_COUNT" -ne 1 ] && echo s), ${TOTAL_LINES} lines)"
    fi
  fi
elif [ "$GROW_RULES" -eq 1 ] || [ "$GROW_HOOK" -eq 1 ]; then
  GROW="partially installed"
fi

printf "Clarify .... %s\n" "$CLARIFY"
printf "Recall ..... %s\n" "$RECALL"
printf "Grow ....... %s%s\n" "$GROW" "$GROW_DETAIL"
echo ""

# --- Memory stats ---

if [ "$RECALL" != "not installed" ]; then
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    MEM_LINES=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
    MEM_MTIME=$(stat -f '%Sm' -t '%b %d' "$MEMORY_DIR/MEMORY.md" 2>/dev/null || stat -c '%y' "$MEMORY_DIR/MEMORY.md" 2>/dev/null | cut -d' ' -f1)
    echo "Memory: MEMORY.md ${MEM_LINES} lines, last updated ${MEM_MTIME}"
  else
    echo "Memory: No MEMORY.md yet"
  fi

  # Progress
  if [ -f "$MEMORY_DIR/progress.md" ]; then
    PROG_LINES=$(wc -l < "$MEMORY_DIR/progress.md" | tr -d ' ')
    echo "Progress: ${PROG_LINES} lines (active)"
  fi

  # Global
  GLOBAL_FILE="$HOME/.tandem/memory/global.md"
  if [ -f "$GLOBAL_FILE" ]; then
    ENTRY_COUNT=$(grep -c '^## ' "$GLOBAL_FILE" 2>/dev/null || echo 0)
    GLOBAL_MTIME=$(stat -f '%Sm' -t '%b %d' "$GLOBAL_FILE" 2>/dev/null || stat -c '%y' "$GLOBAL_FILE" 2>/dev/null | cut -d' ' -f1)
    echo "Global: ${ENTRY_COUNT} entries, last updated ${GLOBAL_MTIME}"
  else
    echo "Global: No cross-project activity logged yet"
  fi

  # Recurrence
  RECURRENCE_FILE="$HOME/.tandem/state/recurrence.json"
  if [ -f "$RECURRENCE_FILE" ]; then
    THEME_COUNT=$(jq '.themes | length' "$RECURRENCE_FILE" 2>/dev/null || echo 0)
    PROMO_COUNT=$(jq '[.themes | to_entries[] | select(.value.count >= 3)] | length' "$RECURRENCE_FILE" 2>/dev/null || echo 0)
    echo "Recurrence: ${THEME_COUNT} themes tracked, ${PROMO_COUNT} with count >= 3"
  fi

  echo ""
fi

# --- Profile stats ---

if [ "$GROW" != "not installed" ] && [ -d "$PROFILE_DIR" ]; then
  # Career context status
  CAREER="missing"
  if [ -f "$PROFILE_DIR/career-context.md" ]; then
    CC_LINES=$(wc -l < "$PROFILE_DIR/career-context.md" | tr -d ' ')
    # Check if it's just the template (< 10 lines of real content)
    CC_CONTENT_LINES=$(grep -cv '^\s*$\|^#' "$PROFILE_DIR/career-context.md" 2>/dev/null || echo 0)
    if [ "$CC_CONTENT_LINES" -gt 3 ]; then
      CAREER="filled (${CC_LINES} lines)"
    else
      CAREER="template only"
    fi
  fi
  echo "Profile: ${PROFILE_DIR}"
  echo "  Career context: ${CAREER}"

  # List non-career-context profile files
  for f in "$PROFILE_DIR"/*.md; do
    [ -f "$f" ] || continue
    FNAME=$(basename "$f")
    [ "$FNAME" = "career-context.md" ] && continue
    FLINES=$(wc -l < "$f" | tr -d ' ')
    echo "  ${FNAME}: ${FLINES} lines"
  done
  echo ""
fi

# --- Stats ---

if [ -f "$STATS_FILE" ]; then
  TOTAL=$(jq -r '.total_sessions' "$STATS_FILE" 2>/dev/null)
  COMPACTIONS=$(jq -r '.compactions' "$STATS_FILE" 2>/dev/null)
  UPDATES=$(jq -r '.profile_updates' "$STATS_FILE" 2>/dev/null)
  echo "Stats: ${TOTAL} sessions, ${COMPACTIONS} compactions, ${UPDATES} profile updates"
fi

# --- Log info ---

TANDEM_LOG="$HOME/.tandem/logs/tandem.log"
echo ""
echo "Log: ${TANDEM_LOG}"
echo "  Level: ${TANDEM_LOG_LEVEL:-info} (set TANDEM_LOG_LEVEL to change)"
if [ -f "$TANDEM_LOG" ]; then
  LOG_LINES=$(wc -l < "$TANDEM_LOG" | tr -d ' ')
  YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '1 day ago' +%Y-%m-%d 2>/dev/null)
  ERROR_COUNT=0
  WARN_COUNT=0
  if [ -n "$YESTERDAY" ]; then
    ERROR_COUNT=$(awk -v cutoff="$YESTERDAY" '$1 >= cutoff && /\[ERROR\]/ { count++ } END { print count+0 }' "$TANDEM_LOG")
    WARN_COUNT=$(awk -v cutoff="$YESTERDAY" '$1 >= cutoff && /\[WARN \]/ { count++ } END { print count+0 }' "$TANDEM_LOG")
  fi
  echo "  Entries: ${LOG_LINES} total, ${ERROR_COUNT} errors / ${WARN_COUNT} warnings (24h)"
else
  echo "  No log file yet"
fi
