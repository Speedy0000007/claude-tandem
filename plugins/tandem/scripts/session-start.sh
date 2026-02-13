#!/bin/bash
# SessionStart hook: first-run provisioning + stale progress detection + status indicators.
# Outputs to stdout are injected into Claude's context.
#
# Output format: single ◎╵═╵◎ header line, then plain detail lines underneath.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

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

# ==========================================================================
# Phase 1: Silent work (no output)
# ==========================================================================

# --- First-run provisioning ---

FIRST_RUN=0
if [ ! -f "$MARKER_FILE" ]; then
  PROVISIONED=0

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

  if [ -f "$PLUGIN_ROOT/rules/tandem-display.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-display.md" "$RULES_DIR/tandem-display.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-commits.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-commits.md" "$RULES_DIR/tandem-commits.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-debugging.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-debugging.md" "$RULES_DIR/tandem-debugging.md"
    PROVISIONED=1
  fi

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
    tandem_log info "provisioned rules and profile"
    FIRST_RUN=1
  fi
fi

# --- Initialize stats ---

if [ ! -f "$HOME/.tandem/state/stats.json" ]; then
  mkdir -p "$HOME/.tandem/state"
  jq -n '{
    total_sessions: 0,
    first_session: (now | strftime("%Y-%m-%d")),
    last_session: (now | strftime("%Y-%m-%d")),
    clarifications: 0,
    compactions: 0,
    profile_updates: 0,
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

    INSTALLED_VER=$(head -1 "$RULES_FILE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
    SOURCE_VER=$(head -1 "$SOURCE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')

    if [ -n "$SOURCE_VER" ] && [ "$INSTALLED_VER" != "$SOURCE_VER" ]; then
      cp "$SOURCE" "$RULES_FILE"
      tandem_log info "upgraded rules file: $BASENAME ($INSTALLED_VER -> $SOURCE_VER)"
    fi
  done
fi

# --- Provision UserPromptSubmit hook via stable symlink ---
# Workaround: plugin hooks.json UserPromptSubmit entries are registered but never
# execute due to a Claude Code bug. Provisioning into user settings.json works.
# Idempotent: ln -sf updates target, settings.json only modified if entry missing.

mkdir -p "$HOME/.tandem/bin"
ln -sf "$PLUGIN_ROOT/scripts/detect-raw-input.sh" "$HOME/.tandem/bin/detect-raw-input.sh"

SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  HAS_HOOK=$(jq '[.hooks.UserPromptSubmit // [] | .[].hooks[]? | select(.command | test("detect-raw-input"))] | length' "$SETTINGS_FILE" 2>/dev/null)
  if [ "${HAS_HOOK:-0}" = "0" ]; then
    TMPFILE=$(mktemp)
    jq '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks": [{"type": "command", "command": "$HOME/.tandem/bin/detect-raw-input.sh", "timeout": 15}]}])' "$SETTINGS_FILE" > "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$SETTINGS_FILE"
      tandem_log info "provisioned UserPromptSubmit hook in settings.json"
    else
      rm -f "$TMPFILE"
      tandem_log warn "failed to provision UserPromptSubmit hook"
    fi
  fi
fi

# --- CLAUDE.md section injection ---

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TANDEM_VERSION="v${PLUGIN_VERSION:-1.2.0}"
TANDEM_SECTION="<!-- tandem:start ${TANDEM_VERSION} -->
## Tandem — Session Progress
Maintain progress.md in your auto-memory directory with two parts: a rewritable Working State section (between \`<!-- working-state:start/end -->\` markers) capturing current task, approach, blockers, and key files, plus an append-only Session Log below. Create progress.md with the Working State template on your first significant action if it doesn't exist. This enables memory continuity between sessions.
<!-- tandem:end -->"

if [ ! -f "$CLAUDE_MD" ]; then
  mkdir -p "$(dirname "$CLAUDE_MD")"
  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    printf '%s\n' "$TANDEM_SECTION" > "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      tandem_log warn "failed to write CLAUDE.md temp file"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for CLAUDE.md"
  fi
elif ! grep -q '<!-- tandem:start' "$CLAUDE_MD"; then
  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    cp "$CLAUDE_MD" "$TMPFILE"
    printf '\n%s\n' "$TANDEM_SECTION" >> "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      tandem_log warn "failed to write CLAUDE.md temp file"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for CLAUDE.md"
  fi
else
  INSTALLED_TANDEM_VER=$(sed -n 's/.*<!-- tandem:start \(v[^ ]*\) -->.*/\1/p' "$CLAUDE_MD")
  if [ "$INSTALLED_TANDEM_VER" != "$TANDEM_VERSION" ]; then
    TMPFILE=$(mktemp)
    if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
      TANDEM_SECTION="$TANDEM_SECTION" awk '
        /<!-- tandem:start/ { skip=1; printed=0; next }
        /<!-- tandem:end -->/ { if (!printed) { print ENVIRON["TANDEM_SECTION"]; printed=1 }; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMPFILE"
      if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$CLAUDE_MD"
      else
        tandem_log warn "failed to write CLAUDE.md version update"
        rm -f "$TMPFILE"
      fi
    else
      tandem_log warn "failed to create temp file for CLAUDE.md version update"
    fi
  fi
fi

# --- Post-compaction state recovery (outputs directly, before Tandem block) ---

if [ -f "$MEMORY_DIR/progress.md" ] && grep -q '## Pre-compaction State' "$MEMORY_DIR/progress.md"; then
  # Prefer structured Working State over free-form Pre-compaction State
  STATE_CONTENT=""
  if grep -q '<!-- working-state:start -->' "$MEMORY_DIR/progress.md" 2>/dev/null; then
    STATE_CONTENT=$(sed -n '/<!-- working-state:start -->/,/<!-- working-state:end -->/p' \
      "$MEMORY_DIR/progress.md" | grep -v '<!-- working-state')
  fi

  # Fall back to Pre-compaction State if no structured state
  if [ -z "$STATE_CONTENT" ]; then
    STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,/^## /{ /^## Pre-compaction State$/d; /^## /d; p; }' "$MEMORY_DIR/progress.md")
    if [ -z "$STATE_CONTENT" ]; then
      STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,$p' "$MEMORY_DIR/progress.md" | tail -n +2)
    fi
  fi

  if [ -n "$STATE_CONTENT" ]; then
    echo "Resuming. Before compaction you were:"
    echo "$STATE_CONTENT"
  fi

  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    sed '/^## Auto-captured (pre-compaction)$/,$d; /^## Pre-compaction State$/,$d' "$MEMORY_DIR/progress.md" > "$TMPFILE"
    if [ $? -eq 0 ]; then
      sed -i.bak -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" 2>/dev/null || sed -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" > "${TMPFILE}.clean" && mv "${TMPFILE}.clean" "$TMPFILE"
      rm -f "${TMPFILE}.bak"
      mv "$TMPFILE" "$MEMORY_DIR/progress.md"
    else
      tandem_log warn "failed to strip state section from progress.md"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for progress.md state cleanup"
  fi
elif [ -f "$MEMORY_DIR/progress.md" ] && grep -q '<!-- working-state:start -->' "$MEMORY_DIR/progress.md" 2>/dev/null; then
  # Previous session ended without compaction — Working State markers still present
  STATE_CONTENT=$(sed -n '/<!-- working-state:start -->/,/<!-- working-state:end -->/p' \
    "$MEMORY_DIR/progress.md" | grep -v '<!-- working-state')
  if [ -n "$STATE_CONTENT" ]; then
    echo "Continuing from previous session:"
    echo "$STATE_CONTENT"
  fi
fi

# --- Increment session stats (only on startup, not resume/compact/clear) ---

SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
STATS_FILE="$HOME/.tandem/state/stats.json"
if [ -f "$STATS_FILE" ]; then
  if [ "$SOURCE" = "startup" ]; then
    NEW_STATS=$(jq --arg today "$(date +%Y-%m-%d)" '
      .total_sessions += 1 |
      .last_session = $today
    ' "$STATS_FILE")
    tandem_log debug "Session count incremented (source=$SOURCE, new_total=$(echo "$NEW_STATS" | jq -r '.total_sessions'))"

    TMPFILE=$(mktemp "$STATS_FILE.XXXXXX")
    if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
      if echo "$NEW_STATS" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$STATS_FILE"
      else
        rm -f "$TMPFILE"
      fi
    fi
  else
    NEW_STATS=$(cat "$STATS_FILE")
  fi
fi

# --- MEMORY.md corruption detection and rollback ---

if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  REFUSAL_PATTERN=$(head -1 "$MEMORY_DIR/MEMORY.md" | grep -qiE '^(I cannot|I'"'"'m sorry|I am sorry|As an AI)' && echo 1 || echo 0)

  if [ "$LINE_COUNT" -lt 5 ] || [ "$REFUSAL_PATTERN" -eq 1 ]; then
    LATEST_BACKUP=$(ls -t "$MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
      tandem_log warn "corrupted MEMORY.md detected (${LINE_COUNT} lines). Rolling back to backup."
      mv "$LATEST_BACKUP" "$MEMORY_DIR/MEMORY.md"
      MEMORY_ROLLED_BACK=1
    else
      tandem_log warn "corrupted MEMORY.md detected but no backup available"
    fi
  fi
fi

# ==========================================================================
# Phase 2: Output (header line first, then plain detail lines)
# ==========================================================================

# --- Header (always first, always output) ---

tandem_header

# --- Detail lines (plain, no logo) ---

# First run welcome
if [ "$FIRST_RUN" -eq 1 ]; then
  echo "Welcome! Run /tandem:status to get started."
fi

# Corruption rollback notice
if [ "${MEMORY_ROLLED_BACK:-0}" -eq 1 ]; then
  echo "Corrupted MEMORY.md detected. Rolled back to backup."
fi

# Milestones
if [ -n "${NEW_STATS:-}" ]; then
  TOTAL=$(echo "$NEW_STATS" | jq -r '.total_sessions')
  MILESTONES_HIT=$(echo "$NEW_STATS" | jq -r '.milestones_hit | join(",")')

  for MILESTONE in 10 50 100 500 1000; do
    if [ "$TOTAL" -eq "$MILESTONE" ] && ! echo "$MILESTONES_HIT" | grep -q "$MILESTONE"; then
      COMPACTIONS=$(echo "$NEW_STATS" | jq -r '.compactions')
      UPDATES=$(echo "$NEW_STATS" | jq -r '.profile_updates')
      PROFILE_LINES=$(echo "$NEW_STATS" | jq -r '.profile_total_lines')
      echo "Milestone: ${MILESTONE} sessions! Profile: ${PROFILE_LINES} lines, ${COMPACTIONS} compactions, ${UPDATES} profile updates."
      jq ".milestones_hit += [\"$MILESTONE\"]" "$STATS_FILE" > "$STATS_FILE.tmp"
      mv "$STATS_FILE.tmp" "$STATS_FILE"
    fi
  done

fi

# Last session recap
RECAP_FILE="$HOME/.tandem/.last-session-recap"
if [ -f "$RECAP_FILE" ]; then
  RECALL=$(grep '^recall_status: 1' "$RECAP_FILE" &>/dev/null && echo 1 || echo 0)
  GROW=$(grep '^grow_status: 1' "$RECAP_FILE" &>/dev/null && echo 1 || echo 0)

  if [ "$RECALL" -eq 1 ] || [ "$GROW" -eq 1 ]; then
    RECAP_MSG="Last session: "
    if [ "$RECALL" -eq 1 ]; then
      LINES=$(grep '^memory_lines:' "$RECAP_FILE" | cut -d' ' -f2)
      RECAP_MSG="${RECAP_MSG}memory compacted (${LINES} lines)"
    fi
    if [ "$GROW" -eq 1 ]; then
      FILES=$(grep '^profile_files:' "$RECAP_FILE" | cut -d' ' -f2-)
      if [ "$RECALL" -eq 1 ]; then RECAP_MSG="${RECAP_MSG}. "; fi
      if [ -n "$FILES" ]; then
        RECAP_MSG="${RECAP_MSG}Profile updated: ${FILES}"
      else
        RECAP_MSG="${RECAP_MSG}Profile updated"
      fi
    fi
    echo "$RECAP_MSG"
  fi

  rm -f "$RECAP_FILE"
fi

# Health check (only errors from current version)
TANDEM_LOG="$HOME/.tandem/logs/tandem.log"
if [ -f "$TANDEM_LOG" ] && [ -n "$PLUGIN_VERSION" ]; then
  ISSUE_COUNT=$(grep -c "\[$PLUGIN_VERSION\].*\(\[ERROR\]\|\[WARN \]\)" "$TANDEM_LOG" 2>/dev/null)
  ISSUE_COUNT="${ISSUE_COUNT:-0}"
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo "${ISSUE_COUNT} issue(s) logged. Run /tandem:logs errors to review."
  fi
fi

# Recalled/Grown indicators
if [ -f "$MEMORY_DIR/.tandem-last-compaction" ]; then
  if [ -f "$HOME/.tandem/state/stats.json" ]; then
    TOTAL_COMPACTIONS=$(jq -r '.compactions' "$HOME/.tandem/state/stats.json")
    PROFILE_LINES=$(jq -r '.profile_total_lines' "$HOME/.tandem/state/stats.json")
    echo "Recalled. (${TOTAL_COMPACTIONS} compactions total, profile: ${PROFILE_LINES} lines)"
  else
    echo "Recalled."
  fi
  rm -f "$MEMORY_DIR/.tandem-last-compaction"
fi

NUDGE_FILE="$HOME/.tandem/next-nudge"
if [ -f "$NUDGE_FILE" ]; then
  NUDGE_CONTENT=$(cat "$NUDGE_FILE")
  if [ -n "$NUDGE_CONTENT" ]; then
    echo "Grown."
    echo "${NUDGE_CONTENT}"
  fi
  rm -f "$NUDGE_FILE"
fi

# Recurrence alerts
RECURRENCE_FILE="$HOME/.tandem/state/recurrence.json"
if [ -f "$RECURRENCE_FILE" ]; then
  PROMOTIONS=$(jq -r '
    [.themes | to_entries[] | select(.value.count >= 3) | "\(.key) (\(.value.count) sessions)"]
    | join(", ")
  ' "$RECURRENCE_FILE" 2>/dev/null)
  if [ -n "$PROMOTIONS" ]; then
    echo "Recurring: ${PROMOTIONS}. Run /tandem:recall promote to make permanent."
  fi
fi

# Cross-project context
GLOBAL_FILE="$HOME/.tandem/memory/global.md"
if [ -f "$GLOBAL_FILE" ]; then
  PROJECT_NAME=$(basename "$CWD")
  OTHER_ENTRIES=$(sed 's/ [–—] / -- /g' "$GLOBAL_FILE" | awk -v proj="$PROJECT_NAME" '
    /^## / {
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
    echo "$OTHER_ENTRIES"
  fi
fi

# Stale progress detection
if [ -f "$MEMORY_DIR/progress.md" ]; then
  PROGRESS_MTIME=$(tandem_file_mtime "$MEMORY_DIR/progress.md")
  SESSION_START=$(date +%s)

  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((SESSION_START - PROGRESS_MTIME))
    if [ "$AGE" -gt 300 ]; then
      echo "Previous session notes found. Context carried forward."
    fi
  fi
fi

# Tandem checkpoint detection
if git -C "$CWD" rev-parse --git-dir &>/dev/null; then
  LAST_MSG=$(git -C "$CWD" log -1 --format="%s" 2>/dev/null)
  if [[ "$LAST_MSG" == "chore(tandem): session checkpoint" ]] || \
     [[ "$LAST_MSG" == "chore(tandem): session context" ]]; then
    # Count consecutive auto-commits from HEAD
    AC_COUNT=0
    while true; do
      AC_SHA=$(git -C "$CWD" rev-parse "HEAD~${AC_COUNT}" 2>/dev/null) || break
      AC_SUBJ=$(git -C "$CWD" log -1 --format="%s" "$AC_SHA" 2>/dev/null)
      if [[ "$AC_SUBJ" == "chore(tandem): session checkpoint" ]] || \
         [[ "$AC_SUBJ" == "chore(tandem): session context" ]] || \
         git -C "$CWD" log -1 --format='%B' "$AC_SHA" 2>/dev/null | grep -q 'Tandem-Auto-Commit: true'; then
        AC_COUNT=$((AC_COUNT + 1))
      else
        break
      fi
    done
    LAST_HASH=$(git -C "$CWD" log -1 --format="%h" 2>/dev/null)
    LAST_DATE=$(git -C "$CWD" log -1 --format="%ai" 2>/dev/null | cut -d' ' -f1,2 | cut -d: -f1,2)
    if [ "$AC_COUNT" -gt 1 ]; then
      COMMIT_LABEL="${AC_COUNT} auto-commits, latest: ${LAST_DATE} ${LAST_HASH}"
    else
      COMMIT_LABEL="Last auto-commit: ${LAST_DATE} ${LAST_HASH} \"${LAST_MSG}\""
    fi
    if [ "${TANDEM_AUTO_SQUASH:-1}" = "0" ]; then
      echo "${COMMIT_LABEL}. Squash before pushing, or use /tandem:squash."
    else
      echo "${COMMIT_LABEL}. Will be squashed into your next commit."
    fi
  fi
fi

exit 0
