#!/bin/bash
# SessionStart hook: first-run provisioning + stale progress detection + status indicators.
# Outputs to stdout are injected into Claude's context.

if ! command -v jq &>/dev/null; then
  echo "[Tandem] Error: jq not found" >&2
  echo "  Tandem requires jq for JSON parsing." >&2
  echo "  Install: brew install jq (macOS) | apt install jq (Linux)" >&2
  echo "  Verify: jq --version" >&2
  exit 0
fi

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

    cat <<'EOF'

╭─ Welcome to Tandem ──────────────────────────────────╮
│                                                       │
│ Your learning infrastructure is ready:               │
│                                                       │
│ ✓ Clarify — Better prompts, automatically            │
│ ✓ Recall — Memory that compounds across sessions     │
│ ✓ Grow — Technical profile built from your work      │
│                                                       │
│ Getting started:                                      │
│ 1. Fill in ~/.tandem/profile/career-context.md       │
│    (tells Tandem what you want to learn)             │
│                                                       │
│ 2. Just work normally — Tandem runs in background    │
│                                                       │
│ 3. After a few sessions, run /tandem:grow gaps       │
│    to see personalized learning opportunities        │
│                                                       │
│ Run /tandem:status anytime to check what's happening │
│                                                       │
╰──────────────────────────────────────────────────────╯

EOF
  fi
fi

# --- Initialize stats (outside first-run — runs whenever stats.json is missing) ---

if [ ! -f "$HOME/.tandem/state/stats.json" ]; then
  mkdir -p "$HOME/.tandem/state"
  jq -n '{
    total_sessions: 0,
    first_session: (now | strftime("%Y-%m-%d")),
    last_session: (now | strftime("%Y-%m-%d")),
    compactions: 0,
    profile_updates: 0,
    streak_current: 0,
    streak_best: 0,
    milestones_hit: [],
    profile_total_lines: 0
  }' > "$HOME/.tandem/state/stats.json"
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

# --- CLAUDE.md section injection ---

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TANDEM_VERSION="v1.1.0"
TANDEM_SECTION="<!-- tandem:start ${TANDEM_VERSION} -->
## Tandem — Session Progress
After completing significant work steps (features, fixes, decisions), append a brief note to progress.md in your auto-memory directory. Include: what was done, key decisions, outcome. One or two lines per step. Create progress.md on your first significant action if it doesn't exist. This enables memory continuity between sessions.
<!-- tandem:end -->"

if [ ! -f "$CLAUDE_MD" ]; then
  # Create CLAUDE.md with just the Tandem section
  mkdir -p "$(dirname "$CLAUDE_MD")"
  TMPFILE=$(mktemp)
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    echo "[Tandem] Warning: failed to create temp file for CLAUDE.md" >&2
  else
    printf '%s\n' "$TANDEM_SECTION" > "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      echo "[Tandem] Warning: failed to write CLAUDE.md temp file" >&2
      rm -f "$TMPFILE"
    fi
  fi
elif ! grep -q '<!-- tandem:start' "$CLAUDE_MD"; then
  # Marker absent — append the section
  TMPFILE=$(mktemp)
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    echo "[Tandem] Warning: failed to create temp file for CLAUDE.md" >&2
  else
    cp "$CLAUDE_MD" "$TMPFILE"
    printf '\n%s\n' "$TANDEM_SECTION" >> "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      echo "[Tandem] Warning: failed to write CLAUDE.md temp file" >&2
      rm -f "$TMPFILE"
    fi
  fi
else
  # Marker present — check version
  INSTALLED_TANDEM_VER=$(sed -n 's/.*<!-- tandem:start \(v[^ ]*\) -->.*/\1/p' "$CLAUDE_MD")
  if [ "$INSTALLED_TANDEM_VER" != "$TANDEM_VERSION" ]; then
    TMPFILE=$(mktemp)
    if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
      echo "[Tandem] Warning: failed to create temp file for CLAUDE.md version update" >&2
    else
      awk -v section="$TANDEM_SECTION" '
        /<!-- tandem:start/ { skip=1; printed=0; next }
        /<!-- tandem:end -->/ { if (!printed) { print section; printed=1 }; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMPFILE"
      if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$CLAUDE_MD"
      else
        echo "[Tandem] Warning: failed to write CLAUDE.md version update" >&2
        rm -f "$TMPFILE"
      fi
    fi
  fi
fi

# --- Post-compaction state recovery ---

if [ -f "$MEMORY_DIR/progress.md" ] && grep -q '## Pre-compaction State' "$MEMORY_DIR/progress.md"; then
  # Extract the state section content
  STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,/^## /{ /^## Pre-compaction State$/d; /^## /d; p; }' "$MEMORY_DIR/progress.md")
  # If state section is the last section, grab to end of file
  if [ -z "$STATE_CONTENT" ]; then
    STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,$p' "$MEMORY_DIR/progress.md" | tail -n +2)
  fi

  if [ -n "$STATE_CONTENT" ]; then
    echo "Resuming. Before compaction you were:"
    echo "$STATE_CONTENT"
  fi

  # Strip the section from progress.md (atomic rewrite with validation)
  TMPFILE=$(mktemp)
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    echo "[Tandem] Warning: failed to create temp file for progress.md state cleanup" >&2
  else
    sed '/^## Pre-compaction State$/,$d' "$MEMORY_DIR/progress.md" > "$TMPFILE"
    if [ $? -eq 0 ]; then
      # Remove trailing blank lines
      sed -i.bak -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" 2>/dev/null || sed -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" > "${TMPFILE}.clean" && mv "${TMPFILE}.clean" "$TMPFILE"
      rm -f "${TMPFILE}.bak"
      mv "$TMPFILE" "$MEMORY_DIR/progress.md"
    else
      echo "[Tandem] Warning: failed to strip state section from progress.md" >&2
      rm -f "$TMPFILE"
    fi
  fi
fi

# --- Recurrence theme alerts ---

RECURRENCE_FILE="$HOME/.tandem/state/recurrence.json"
if [ -f "$RECURRENCE_FILE" ]; then
  PROMOTIONS=$(jq -r '
    [.themes | to_entries[] | select(.value.count >= 3) | "\(.key) (\(.value.count) sessions)"]
    | join(", ")
  ' "$RECURRENCE_FILE" 2>/dev/null)
  if [ -n "$PROMOTIONS" ]; then
    cat <<EOF

╭─ Recurring Pattern Detected ─────────────────────────╮
│ ${PROMOTIONS}
│
│ These patterns keep showing up across your sessions.
│ Ready to make them permanent in CLAUDE.md?
│
│ This means:
│ → Automatic reminders when relevant
│ → Less repeated friction
│ → Better muscle memory
│
│ Run: /tandem:recall promote <theme-slug>
╰──────────────────────────────────────────────────────╯

EOF
  fi
fi

# --- Session stats tracking and milestones ---

# Function to celebrate milestones
celebrate_milestone() {
  local MILESTONE=$1
  local STATS=$2
  local COMPACTIONS=$(echo "$STATS" | jq -r '.compactions')
  local UPDATES=$(echo "$STATS" | jq -r '.profile_updates')
  local PROFILE_LINES=$(echo "$STATS" | jq -r '.profile_total_lines')

  cat <<EOF

╭─────────────────────────────────────────────────────╮
│ 🎉 ${MILESTONE} Sessions with Tandem!
│
│ Your profile has grown to ${PROFILE_LINES} lines.
│ You've compacted ${COMPACTIONS} times and made ${UPDATES} profile updates.
│
│ That's real momentum. Keep going.
╰─────────────────────────────────────────────────────╯

EOF
}

# Increment session count and check for milestones
STATS_FILE="$HOME/.tandem/state/stats.json"
if [ -f "$STATS_FILE" ]; then
  NEW_STATS=$(jq --arg today "$(date +%Y-%m-%d)" '
    .total_sessions += 1 |
    .last_session = $today |
    if (.last_session == (.previous_session // "")) then
      .streak_current += 1 |
      .streak_best = ([.streak_best, .streak_current] | max)
    else
      .streak_current = 1
    end |
    .previous_session = $today
  ' "$STATS_FILE")

  # Atomic write
  TMPFILE=$(mktemp "$STATS_FILE.XXXXXX")
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    echo "$NEW_STATS" > "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$STATS_FILE"
    else
      rm -f "$TMPFILE"
    fi
  fi

  # Check for milestone celebrations
  TOTAL=$(echo "$NEW_STATS" | jq -r '.total_sessions')
  MILESTONES_HIT=$(echo "$NEW_STATS" | jq -r '.milestones_hit | join(",")')

  for MILESTONE in 10 50 100 500 1000; do
    if [ "$TOTAL" -eq "$MILESTONE" ] && ! echo "$MILESTONES_HIT" | grep -q "$MILESTONE"; then
      celebrate_milestone "$MILESTONE" "$NEW_STATS"
      # Mark milestone as hit
      jq ".milestones_hit += [\"$MILESTONE\"]" "$STATS_FILE" > "$STATS_FILE.tmp"
      mv "$STATS_FILE.tmp" "$STATS_FILE"
    fi
  done

  # Check for learning streak
  STREAK=$(echo "$NEW_STATS" | jq -r '.streak_current')
  if [ "$STREAK" -ge 5 ] && [ $(($STREAK % 5)) -eq 0 ]; then
    cat <<EOF

🔥 ${STREAK}-session learning streak!

Your profile has been updated in ${STREAK} consecutive sessions.
That's how expertise compounds.

EOF
  fi
fi

# --- Last session recap ---

# Show last session recap if available
RECAP_FILE="$HOME/.tandem/.last-session-recap"
if [ -f "$RECAP_FILE" ]; then
  RECAP_DATE=$(grep '^date:' "$RECAP_FILE" | cut -d' ' -f2)
  RECALL=$(grep '^recall_status: 1' "$RECAP_FILE" &>/dev/null && echo 1 || echo 0)
  GROW=$(grep '^grow_status: 1' "$RECAP_FILE" &>/dev/null && echo 1 || echo 0)

  if [ "$RECALL" -eq 1 ] || [ "$GROW" -eq 1 ]; then
    echo ""
    echo "Last session ($RECAP_DATE):"

    if [ "$RECALL" -eq 1 ]; then
      LINES=$(grep '^memory_lines:' "$RECAP_FILE" | cut -d' ' -f2)
      echo "  ✓ Recalled (MEMORY.md: ${LINES} lines)"
    fi

    if [ "$GROW" -eq 1 ]; then
      FILES=$(grep '^profile_files:' "$RECAP_FILE" | cut -d' ' -f2-)
      if [ -n "$FILES" ]; then
        echo "  ✓ Grown (updated: $FILES)"
      else
        echo "  ✓ Grown (profile updated)"
      fi
    fi
    echo ""
  fi

  # Clean up recap file
  rm -f "$RECAP_FILE"
fi

# Check for recent SessionEnd errors
ERROR_LOG="$HOME/.tandem/logs/session-end-errors.log"
if [ -f "$ERROR_LOG" ]; then
  # Check if errors written in last 24h
  RECENT_ERRORS=$(find "$ERROR_LOG" -mtime -1 2>/dev/null)
  if [ -n "$RECENT_ERRORS" ]; then
    ERROR_COUNT=$(tail -100 "$ERROR_LOG" | grep -c '\[Tandem.*Error\]' || echo 0)
    if [ "$ERROR_COUNT" -gt 0 ]; then
      echo "⚠️  SessionEnd errors detected (${ERROR_COUNT} in last 24h)"
      echo "   Check: $ERROR_LOG"
      echo ""
    fi
  fi
fi

# --- Status indicators ---

# Recalled. — previous session was compacted
if [ -f "$MEMORY_DIR/.tandem-last-compaction" ]; then
  # Check if stats available for enhanced indicator
  if [ -f "$HOME/.tandem/state/stats.json" ]; then
    TOTAL_COMPACTIONS=$(jq -r '.compactions' "$HOME/.tandem/state/stats.json")
    PROFILE_LINES=$(jq -r '.profile_total_lines' "$HOME/.tandem/state/stats.json")
    echo "Recalled. (${TOTAL_COMPACTIONS} compactions total, profile: ${PROFILE_LINES} lines)"
  else
    echo "Recalled."
  fi
  rm -f "$MEMORY_DIR/.tandem-last-compaction"
fi

# Grown. — learning nudge from previous session
NUDGE_FILE="$HOME/.tandem/next-nudge"
if [ -f "$NUDGE_FILE" ]; then
  NUDGE_CONTENT=$(cat "$NUDGE_FILE")
  if [ -n "$NUDGE_CONTENT" ]; then
    echo "Grown."
    echo "${NUDGE_CONTENT}"
  fi
  rm -f "$NUDGE_FILE"
fi

# --- Cross-project context ---

GLOBAL_FILE="$HOME/.tandem/memory/global.md"
if [ -f "$GLOBAL_FILE" ]; then
  PROJECT_NAME=$(basename "$CWD")
  # Extract recent entries for OTHER projects (up to 5)
  # Normalize em/en-dash variants to --, then parse with portable awk
  OTHER_ENTRIES=$(sed 's/ [–—] / -- /g' "$GLOBAL_FILE" | awk -v proj="$PROJECT_NAME" '
    /^## / {
      # Parse "## YYYY-MM-DD -- project-name"
      sub(/^## /, "")
      idx = index($0, " -- ")
      if (idx > 0) {
        date = substr($0, 1, idx - 1)
        name = substr($0, idx + 4)
        getline summary
        if (name != proj && count < 5) {
          split(date, d, "-")
          months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"
          split(months, mnames, " ")
          mon = mnames[int(d[2])]
          printf "- %s (%s %s): %s\n", name, mon, int(d[3]), summary
          count++
        }
      }
    }
  ')

  if [ -n "$OTHER_ENTRIES" ]; then
    echo ""
    echo "Context from other projects:"
    echo ""

    # Add visual indicators
    echo "$OTHER_ENTRIES" | while IFS= read -r entry; do
      echo "🔹 $entry"
    done

    echo ""
    echo "(Full global memory: /tandem:status --global)"
  fi
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
      echo "[Tandem] Stale progress.md detected from a previous session (background work may still be running, or SessionEnd hook didn't complete). Contents preserved — review and incorporate relevant context."
    fi
  fi
fi

# --- MEMORY.md corruption detection and rollback ---

if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  REFUSAL_PATTERN=$(head -1 "$MEMORY_DIR/MEMORY.md" | grep -qiE '^(I cannot|I'"'"'m sorry|I am sorry|As an AI)' && echo 1 || echo 0)

  # If MEMORY.md is suspiciously short or starts with a refusal, roll back to latest backup
  if [ "$LINE_COUNT" -lt 5 ] || [ "$REFUSAL_PATTERN" -eq 1 ]; then
    LATEST_BACKUP=$(ls -t "$MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
      echo "[Tandem] Corrupted MEMORY.md detected (${LINE_COUNT} lines, refusal pattern: ${REFUSAL_PATTERN}). Rolling back to backup from $(date -r "$LATEST_BACKUP" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$(stat -c %Y "$LATEST_BACKUP")" '+%Y-%m-%d %H:%M' 2>/dev/null)."
      mv "$LATEST_BACKUP" "$MEMORY_DIR/MEMORY.md"
    else
      echo "[Tandem] Warning: MEMORY.md appears corrupted but no backup available." >&2
    fi
  fi
fi

exit 0
