#!/bin/bash
# SessionEnd hook: informs user, then backgrounds compaction (Recall) and extraction (Grow).
# Sync hook with fast exit — heavy LLM work runs as a named background process.
#
# Two modes:
#   (default)   Hook mode — reads stdin, prints summary, spawns worker, exits
#   --worker    Worker mode — runs compaction + extraction in background

# ─── Worker mode: backgrounded by hook mode ───────────────────────────────

if [ "${1:-}" = "--worker" ]; then
  CWD="$2"
  [ -z "$CWD" ] && exit 0
  TANDEM_SESSION_ID="${3:-}"
  export TANDEM_SESSION_ID

  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
  _TANDEM_SCRIPT="session-end"
  source "$PLUGIN_ROOT/lib/tandem.sh"

  SANITISED=$(echo "$CWD" | sed 's|/|-|g')
  MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"
  [ ! -f "$MEMORY_DIR/progress.md" ] && exit 0

  PROFILE_DIR="${TANDEM_PROFILE_DIR:-$HOME/.tandem/profile}"
  STATE_DIR="$HOME/.tandem/state"
  RECURRENCE_FILE="$STATE_DIR/recurrence.json"
  TODAY=$(date +%Y-%m-%d)

  # Functions are defined below — execution continues after function definitions
  # Export so child claude -p processes inherit it (prevents recursive hook firing)
  export TANDEM_WORKER=1

  tandem_log info "worker started (pid $$)"

  # PID lockfile to prevent double-fire
  LOCKFILE="$HOME/.tandem/state/.worker.lock"
  if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
      tandem_log debug "worker already running (pid $LOCK_PID)"
      exit 0
    fi
  fi
  mkdir -p "$(dirname "$LOCKFILE")"
  echo $$ > "$LOCKFILE"
  trap 'rm -f "$LOCKFILE"' EXIT
fi

# ─── Hook mode: parse input, inform user, spawn worker ────────────────────

if [ -n "${TANDEM_WORKER:-}" ] && [ "${1:-}" != "--worker" ]; then
  # Hook fired inside a claude -p call from a running worker — skip
  exit 0
fi

if [ -z "${TANDEM_WORKER:-}" ]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
  source "$PLUGIN_ROOT/lib/tandem.sh"

  tandem_require_jq

  # Read hook input from stdin
  INPUT=$(cat)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  [ -z "$CWD" ] && exit 0

  # Capture session_id for deregistration
  HOOK_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  [ -z "$HOOK_SESSION_ID" ] && HOOK_SESSION_ID="${TANDEM_SESSION_ID:-}"

  # Compute auto-memory directory
  SANITISED=$(echo "$CWD" | sed 's|/|-|g')
  MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"

  # Exit early if no progress.md (trivial session — no LLM calls needed)
  [ ! -f "$MEMORY_DIR/progress.md" ] && exit 0

  # Inform user (synchronous — visible before session exits)
  PROGRESS_LINES=$(wc -l < "$MEMORY_DIR/progress.md" | tr -d ' ')
  tandem_print "Session captured (${PROGRESS_LINES} lines). Compacting memory..."
  tandem_log info "session end: ${PROGRESS_LINES} lines of progress"

  # Spawn detached worker process and exit
  nohup "$0" --worker "$CWD" "$HOOK_SESSION_ID" </dev/null &>/dev/null &
  disown
  exit 0
fi

# ─── Shared: function definitions + worker execution ──────────────────────

# ─── Phase 1: Recall — compact MEMORY.md ───────────────────────────────────

recall_compact() {
  tandem_require_llm || return 1

  PROGRESS_CONTENT=$(cat "$MEMORY_DIR/progress.md")
  MEMORY_CONTENT=""
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    MEMORY_CONTENT=$(cat "$MEMORY_DIR/MEMORY.md")
  fi

  # Read existing recurrence themes for slug reuse and promotion
  EXISTING_THEMES=""
  RECURRENCE_THEMES_WITH_COUNTS=""
  if [ -f "$RECURRENCE_FILE" ]; then
    EXISTING_THEMES=$(jq -r '.themes | keys[]' "$RECURRENCE_FILE" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    RECURRENCE_THEMES_WITH_COUNTS=$(jq -r '.themes | to_entries[] | select(.value.count >= 3) | "\(.key): count=\(.value.count), first=\(.value.first_seen), last=\(.value.last_seen)"' "$RECURRENCE_FILE" 2>/dev/null)
  fi

  # Build the compaction prompt
  PROMPT=$(cat <<PROMPT_EOF
You are a memory compaction agent. Your job is to produce a concise, well-structured MEMORY.md file that stays under 200 lines.

You will receive two inputs:
1. The current MEMORY.md (may be empty)
2. The session progress notes

## Priority-based retention

Classify every piece of information:
- [P1] PERMANENT: Architecture decisions, user preferences, workflow conventions, recurring patterns. Survive indefinitely.
- [P2] ACTIVE: Current project state, recent decisions, in-progress context. Survive 3-5 compactions, then decay.
- [P3] EPHEMERAL: Debugging details, completed task specifics, routine operations. Prune first.

Compaction rules:
- Keep ALL [P1] entries (may rephrase for brevity, never remove)
- Keep [P2] entries from recent sessions. Promote to [P1] if still relevant after 3+ compactions, otherwise prune.
- Prune [P3] entries unless from the current session
- New progress.md information starts as [P2] unless clearly architectural ([P1]) or ephemeral ([P3])
- Prefix every entry with its priority marker

## Temporal context

- Include (observed: YYYY-MM-DD) on each entry or group of entries
- Carry forward existing dates from prior compactions unchanged
- New entries from this session get today's date: $(date +%Y-%m-%d)
- The date is when the fact was first recorded, not when the event occurred

## General instructions

- Start from the existing MEMORY.md content as your base
- Merge in key facts, decisions, patterns, and context from progress.md
- Prune stale or redundant entries — anything no longer relevant to active work
- Stay under 200 lines total (this is the native loading limit — beyond this, content is invisible)
- Leave any \`## User Context\` section completely intact (user-authored, not for compaction)
- Do NOT reference or modify other files in the memory/ directory
- Output ONLY the new MEMORY.md content — no explanation, no code fences, no preamble
- Always include a \`## Last Session\` section at the very end (before the THEMES line). This section is replaced every compaction, never accumulated. It should contain: what was being worked on, where it left off, what comes next. Write it so the next session can continue immediately. 2-5 lines max.
- If progress.md contains a \`<!-- working-state:start/end -->\` section, treat its contents as the most authoritative description of the session's final state. Use it to populate the \`## Last Session\` section.
- Maintain a \`## Active Plans\` section listing file paths to plan documents referenced in the progress notes. Carry forward plans from the existing MEMORY.md. Remove a plan only when the progress notes indicate it was implemented or abandoned. If no plans exist, omit the section entirely.
- Also identify 1-3 recurring themes from this session as lowercase-hyphenated slugs. If a slug matches an existing theme, reuse it. Output the themes on their own line at the very end: \`THEMES: slug-1, slug-2\`

PROMPT_EOF
  )

  # Add recurrence-aware promotion if themes exist
  RECURRENCE_SECTION=""
  if [ -n "$RECURRENCE_THEMES_WITH_COUNTS" ]; then
    RECURRENCE_SECTION="
## Recurrence-aware compaction
These themes have recurred across multiple sessions. If they appear in progress notes but are NOT adequately represented in MEMORY.md, promote them to [P1]:

<recurrence_themes>
${RECURRENCE_THEMES_WITH_COUNTS}
</recurrence_themes>
"
  fi

  PROMPT="${PROMPT}
${RECURRENCE_SECTION}
<existing_theme_slugs>
${EXISTING_THEMES}
</existing_theme_slugs>

<current_memory_md>
${MEMORY_CONTENT}
</current_memory_md>

<session_progress_md>
${PROGRESS_CONTENT}
</session_progress_md>

Produce the compacted MEMORY.md now."

  tandem_log info "compacting memory"

  RESULT=$(tandem_llm_call "$PROMPT")

  if [ $? -ne 0 ] || [ -z "$RESULT" ]; then
    tandem_log error "compaction failed: LLM returned empty"
    return 1
  fi

  # Strip code fences if LLM wrapped the output despite instructions
  if [[ "$(echo "$RESULT" | head -1)" == '```'* ]]; then
    RESULT=$(echo "$RESULT" | tail -n +2)
  fi
  if [[ "$(echo "$RESULT" | tail -1)" == '```'* ]]; then
    RESULT=$(echo "$RESULT" | sed '$ d')
  fi

  # Sanity check: result must be substantive (> 5 lines, no refusal patterns)
  LINE_COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
  if [ "$LINE_COUNT" -lt 5 ]; then
    tandem_log error "compaction failed: result too short (${LINE_COUNT} lines)"
    return 1
  fi
  if echo "$RESULT" | grep -qiE '^(I cannot|I'"'"'m sorry|I am sorry|I apologize|As an AI)'; then
    tandem_log error "compaction failed: LLM returned refusal"
    return 1
  fi

  # Extract THEMES line before writing MEMORY.md
  THEMES_LINE=""
  MEMORY_RESULT="$RESULT"
  LAST_LINE=$(echo "$RESULT" | tail -n 1)
  if [[ "$LAST_LINE" == THEMES:* ]]; then
    THEMES_LINE="$LAST_LINE"
    # Strip the THEMES line from the content to write
    MEMORY_RESULT=$(echo "$RESULT" | sed '$d')
  fi

  # Backup existing MEMORY.md before overwriting
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    mkdir -p "$MEMORY_DIR"
    BACKUP="$MEMORY_DIR/.MEMORY.md.backup-$(date +%s)"
    cp "$MEMORY_DIR/MEMORY.md" "$BACKUP"
    # Keep only last 3 backups to avoid disk bloat
    ls -t "$MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null
  fi

  # Atomic write via temp file
  mkdir -p "$MEMORY_DIR"
  TMPFILE=$(mktemp "$MEMORY_DIR/MEMORY.md.XXXXXX")
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    tandem_log error "failed to create temp file for MEMORY.md"
    return 1
  fi

  if ! echo "$MEMORY_RESULT" > "$TMPFILE" || [ ! -s "$TMPFILE" ]; then
    tandem_log error "failed to write MEMORY.md temp file (disk full?)"
    rm -f "$TMPFILE"
    return 1
  fi

  mv "$TMPFILE" "$MEMORY_DIR/MEMORY.md"

  FINAL_LINES=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  tandem_log info "memory compacted (${FINAL_LINES} lines)"

  # Write compaction marker for SessionStart indicator
  date +%s > "$MEMORY_DIR/.tandem-last-compaction"

  # Update stats: increment compactions
  STATS_FILE="$HOME/.tandem/state/stats.json"
  if [ -f "$STATS_FILE" ]; then
    UPDATED_STATS=$(jq '.compactions += 1' "$STATS_FILE")
    TMPSTATS=$(mktemp "$STATS_FILE.XXXXXX")
    if [ -n "$TMPSTATS" ] && [ -f "$TMPSTATS" ]; then
      if echo "$UPDATED_STATS" > "$TMPSTATS" && [ -s "$TMPSTATS" ]; then
        mv "$TMPSTATS" "$STATS_FILE"
      else
        rm -f "$TMPSTATS"
      fi
    fi
  fi

  # Update recurrence.json with extracted themes
  if [ -n "$THEMES_LINE" ]; then
    # Parse theme slugs from "THEMES: slug-1, slug-2, slug-3"
    THEMES_RAW="${THEMES_LINE#THEMES: }"
    mkdir -p "$STATE_DIR"

    # Read or initialise recurrence.json
    if [ -f "$RECURRENCE_FILE" ]; then
      RECURRENCE=$(cat "$RECURRENCE_FILE")
    else
      RECURRENCE='{"themes":{}}'
    fi

    # Process each theme slug
    IFS=',' read -ra THEME_ARRAY <<< "$THEMES_RAW"
    for theme in "${THEME_ARRAY[@]}"; do
      # Trim whitespace
      theme=$(echo "$theme" | xargs)
      [ -z "$theme" ] && continue

      # Check if theme exists
      EXISTING_COUNT=$(echo "$RECURRENCE" | jq -r ".themes[\"$theme\"].count // 0" 2>/dev/null)
      if [ $? -ne 0 ] || ! [[ "$EXISTING_COUNT" =~ ^[0-9]+$ ]]; then
        tandem_log warn "jq parse failed for theme $theme, skipping"
        continue
      fi

      if [ "$EXISTING_COUNT" -gt 0 ]; then
        RECURRENCE=$(echo "$RECURRENCE" | jq \
          --arg t "$theme" \
          --arg d "$TODAY" \
          '.themes[$t].count += 1 | .themes[$t].last_seen = $d' 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$RECURRENCE" ]; then
          tandem_log warn "jq update failed for theme $theme"
          continue
        fi
      else
        RECURRENCE=$(echo "$RECURRENCE" | jq \
          --arg t "$theme" \
          --arg d "$TODAY" \
          '.themes[$t] = {"count": 1, "first_seen": $d, "last_seen": $d}' 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$RECURRENCE" ]; then
          tandem_log warn "jq add failed for theme $theme"
          continue
        fi
      fi
    done

    # Atomic write recurrence.json
    TMPFILE=$(mktemp "$STATE_DIR/recurrence.json.XXXXXX")
    if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
      tandem_log warn "failed to create temp file for recurrence.json"
    else
      if echo "$RECURRENCE" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$RECURRENCE_FILE"
      else
        tandem_log warn "failed to write recurrence.json temp file"
        rm -f "$TMPFILE"
      fi
    fi
  fi

  # Post-compaction verification: warn if high-recurrence themes aren't in MEMORY.md
  if [ -f "$RECURRENCE_FILE" ] && [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    HIGH_THEMES=$(jq -r '[.themes | to_entries[] | select(.value.count >= 5) | .key] | .[]' \
      "$RECURRENCE_FILE" 2>/dev/null)
    for theme in $HIGH_THEMES; do
      THEME_WORDS="${theme//-/ }"
      if ! grep -qi "$THEME_WORDS" "$MEMORY_DIR/MEMORY.md" 2>/dev/null; then
        tandem_log warn "high-recurrence theme '$theme' (5+ sessions) missing from MEMORY.md"
      fi
    done
  fi
}

# ─── Phase 2: Grow — extract learnings to profile ───────────────────────────

grow_extract() {
  tandem_require_llm || return 1

  PROGRESS_CONTENT=$(cat "$MEMORY_DIR/progress.md")

  # Read current profile
  CURRENT_PROFILE=""
  if [ -f "$PROFILE_DIR/USER.md" ]; then
    CURRENT_PROFILE=$(cat "$PROFILE_DIR/USER.md")
  fi

  # Read recurrence themes
  RECURRENCE_THEMES=""
  if [ -f "$RECURRENCE_FILE" ]; then
    RECURRENCE_THEMES=$(jq -r '.themes | to_entries[] | "\(.key): count=\(.value.count), first=\(.value.first_seen), last=\(.value.last_seen)"' "$RECURRENCE_FILE" 2>/dev/null)
  fi

  # Build the extraction prompt
  PROMPT=$(cat <<PROMPT_EOF
You maintain USER.md, a lightweight profile of this user's technical understanding.
It helps a mentoring system know what the user already understands (so it does not repeat itself) and where growth edges exist (for targeted nudges).

This is not a knowledge base. It is a concise signal about the user's learning trajectory. Keep it under 80 lines.

Rules:
- Only update when the session reveals something about understanding level, not when a task was merely completed
- Do not add project-specific details, debugging notes, or implementation mechanics
- Merge new observations with existing content. Preserve what is already there unless it is clearly outdated
- If the session reveals career context (role, stack, goals), update the Career Context section
- Pay special attention to recurring themes (provided below) -- if a theme keeps appearing but the profile has thin coverage, that is a high-priority area to capture
- If you spot a genuine learning gap worth highlighting, output a NUDGE line before the profile: NUDGE: [friendly one-sentence observation]

Output the full updated USER.md content below. Or if nothing changed: NONE

PROMPT_EOF
  )

  PROMPT="${PROMPT}

<session_progress>
${PROGRESS_CONTENT}
</session_progress>

<current_profile>
${CURRENT_PROFILE}
</current_profile>

<recurrence_themes>
${RECURRENCE_THEMES}
</recurrence_themes>

Review the session and update the profile now."

  tandem_log info "extracting learnings"

  RESULT=$(tandem_llm_call "$PROMPT")

  if [ $? -ne 0 ] || [ -z "$RESULT" ]; then
    tandem_log error "extraction failed: LLM returned empty"
    return 1
  fi

  # Handle NONE response
  if echo "$RESULT" | grep -qx 'NONE'; then
    tandem_log info "no learnings to extract"
    return 0
  fi

  # Ensure profile directory exists
  mkdir -p "$PROFILE_DIR"

  # Extract NUDGE if present
  NUDGE=$(echo "$RESULT" | sed -n 's/^NUDGE: *//p' | head -1)
  CONTENT=$(echo "$RESULT" | sed '/^NUDGE: /d')

  # Strip code fences
  CONTENT=$(echo "$CONTENT" | sed '/^```/d')

  # Validate: must contain a heading
  if ! echo "$CONTENT" | grep -q "^# "; then
    tandem_log warn "extraction returned unexpected format, skipping"
    return 0
  fi

  # Atomic write
  TARGET="$PROFILE_DIR/USER.md"
  TMPFILE=$(mktemp "$PROFILE_DIR/USER.md.XXXXXX")
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    tandem_log warn "failed to create temp file for USER.md"
    return 0
  fi

  if echo "$CONTENT" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
    mv "$TMPFILE" "$TARGET"
    UPDATED_FILES="USER.md"
    tandem_log info "profile updated: USER.md"
  else
    tandem_log warn "failed to write USER.md"
    rm -f "$TMPFILE"
    return 0
  fi

  # Write nudge for next session if present
  if [ -n "$NUDGE" ]; then
    mkdir -p "$HOME/.tandem"
    echo "$NUDGE" > "$HOME/.tandem/next-nudge"
  fi

  # Update stats: increment profile_updates and recalculate total lines
  STATS_FILE="$HOME/.tandem/state/stats.json"
  if [ -f "$STATS_FILE" ]; then
    TOTAL_LINES=0
    if [ -f "$TARGET" ]; then
      TOTAL_LINES=$(wc -l < "$TARGET" | tr -d ' ')
    fi

    UPDATED_STATS=$(jq --arg lines "$TOTAL_LINES" '.profile_updates += 1 | .profile_total_lines = ($lines | tonumber)' "$STATS_FILE")
    TMPSTATS=$(mktemp "$STATS_FILE.XXXXXX")
    if [ -n "$TMPSTATS" ] && [ -f "$TMPSTATS" ]; then
      if echo "$UPDATED_STATS" > "$TMPSTATS" && [ -s "$TMPSTATS" ]; then
        mv "$TMPSTATS" "$STATS_FILE"
      else
        rm -f "$TMPSTATS"
      fi
    fi
  fi
}

# ─── Phase 0: Commits — checkpoint session context to git ─────────────────

checkpoint_commit() {
  [ "${TANDEM_AUTO_COMMIT:-1}" = "0" ] && { tandem_log debug "auto-commit disabled"; return 0; }
  git -C "$CWD" rev-parse --git-dir &>/dev/null || { tandem_log debug "not a git repo, skipping checkpoint"; return 0; }

  local progress
  progress=$(tail -100 "$MEMORY_DIR/progress.md" 2>/dev/null)
  [ -z "$progress" ] && { tandem_log debug "no progress content for checkpoint"; return 0; }

  # Extract current task from working state for a meaningful subject line
  local task_desc
  task_desc=$(sed -n 's/^\*\*Current task:\*\* *//p' "$MEMORY_DIR/progress.md" 2>/dev/null | head -1)
  if [ -z "$task_desc" ]; then
    task_desc="session work in progress"
  fi
  # Lowercase first char, strip trailing period
  task_desc=$(echo "$task_desc" | sed 's/^\(.\)/\L\1/; s/\.$//')
  # Truncate to keep subject under 72 chars (claude(checkpoint): = 20 chars + space)
  if [ ${#task_desc} -gt 51 ]; then
    task_desc="${task_desc:0:51}"
  fi

  local body
  body=$(printf '%s\n\nTandem-Auto-Commit: true' "$progress")

  git -C "$CWD" add -u 2>/dev/null

  if git -C "$CWD" diff --cached --quiet 2>/dev/null; then
    tandem_log info "checkpoint: no staged changes, skipping commit"
    return 0
  else
    tandem_log info "checkpoint: committing staged changes"
    git -C "$CWD" commit \
      -m "$(printf 'claude(checkpoint): %s\n\n%s' "$task_desc" "$body")" 2>/dev/null || {
      tandem_log warn "checkpoint commit failed"
      return 1
    }
  fi
}

# ─── Phase 3: Global activity — cross-project rolling log ─────────────────

global_activity() {
  [ ! -f "$MEMORY_DIR/progress.md" ] && return 0

  PROJECT_NAME=$(basename "$CWD")
  GLOBAL_DIR="$HOME/.tandem/memory"
  GLOBAL_FILE="$GLOBAL_DIR/global.md"

  # Extract 1-2 line summary: first 3 non-empty, non-heading lines, joined, truncated to 120 chars
  SUMMARY=$(grep -v '^\s*$' "$MEMORY_DIR/progress.md" | grep -v '^#' | head -3 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-120)
  [ -z "$SUMMARY" ] && return 0

  ENTRY="## ${TODAY} — ${PROJECT_NAME}
${SUMMARY}
"

  mkdir -p "$GLOBAL_DIR"

  # Prepend new entry and cap at 30 entries
  TMPFILE=$(mktemp "$GLOBAL_DIR/global.md.XXXXXX")
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    tandem_log warn "failed to create temp file for cross-project activity log"
    return 1
  fi

  {
    printf '%s\n' "$ENTRY"
    [ -f "$GLOBAL_FILE" ] && cat "$GLOBAL_FILE"
  } | awk '
    /^## / { count++ }
    count <= 30 { print }
  ' > "$TMPFILE"

  if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
    tandem_log warn "failed to write cross-project activity log"
    rm -f "$TMPFILE"
    return 1
  fi

  mv "$TMPFILE" "$GLOBAL_FILE"
  tandem_log info "cross-project activity logged"
}

# ─── Worker execution (only reached in --worker mode) ──────────────────────

CHECKPOINT_STATUS=0
RECALL_STATUS=0
GROW_STATUS=0
GLOBAL_STATUS=0

checkpoint_commit && CHECKPOINT_STATUS=1   # Phase 0: preserve context to git
recall_compact && RECALL_STATUS=1          # Phase 1: compact MEMORY.md
grow_extract && GROW_STATUS=1              # Phase 2: extract learnings to profile
global_activity && GLOBAL_STATUS=1         # Phase 3: cross-project log

# Keep progress.md for next session continuity (Working State survives,
# gets overwritten when the next session writes a fresh state).
# Only append failure info if compaction failed.
if [ "$RECALL_STATUS" -eq 1 ] && [ "$GROW_STATUS" -eq 1 ]; then
  tandem_log info "session end complete (recall: ok, grow: ok)"
else
  echo "" >> "$MEMORY_DIR/progress.md"
  echo "## Session End Partial Failure ($(date +%Y-%m-%d))" >> "$MEMORY_DIR/progress.md"
  echo "Recall completed: $RECALL_STATUS, Grow completed: $GROW_STATUS" >> "$MEMORY_DIR/progress.md"
  tandem_log warn "session end partial failure (recall: ${RECALL_STATUS}, grow: ${GROW_STATUS})"
fi

# Deregister session
tandem_session_deregister "${TANDEM_SESSION_ID:-}"

# Write recap for next session
RECAP_FILE="$HOME/.tandem/.last-session-recap"
cat > "$RECAP_FILE" <<RECAP_EOF
date: $TODAY
checkpoint_status: $CHECKPOINT_STATUS
recall_status: $RECALL_STATUS
grow_status: $GROW_STATUS
global_status: $GLOBAL_STATUS
RECAP_EOF

if [ "$RECALL_STATUS" -eq 1 ] && [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  echo "memory_lines: $LINE_COUNT" >> "$RECAP_FILE"
fi

if [ "$GROW_STATUS" -eq 1 ] && [ -f "$PROFILE_DIR/USER.md" ]; then
  echo "profile_files: USER.md" >> "$RECAP_FILE"
fi

exit 0
