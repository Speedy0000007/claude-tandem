#!/bin/bash
# SessionEnd hook: runs compaction (Recall) then extraction (Grow) sequentially.
# Both depend on progress.md — this script ensures ordering and single cleanup.

if ! command -v jq &>/dev/null; then
  echo "[Tandem] Error: jq not found" >&2
  echo "  Tandem requires jq for JSON parsing." >&2
  echo "  Install: brew install jq (macOS) | apt install jq (Linux)" >&2
  echo "  Verify: jq --version" >&2
  exit 0
fi

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Compute auto-memory directory
SANITISED=$(echo "$CWD" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"

# Exit early if no progress.md (trivial session — no LLM calls needed)
[ ! -f "$MEMORY_DIR/progress.md" ] && exit 0

PROFILE_DIR="${TANDEM_PROFILE_DIR:-$HOME/.tandem/profile}"
STATE_DIR="$HOME/.tandem/state"
RECURRENCE_FILE="$STATE_DIR/recurrence.json"
TODAY=$(date +%Y-%m-%d)

# ─── Phase 1: Recall — compact MEMORY.md ───────────────────────────────────

recall_compact() {
  # Verify claude CLI is available
  if ! command -v claude &>/dev/null; then
    echo "[Tandem Recall] Error: claude CLI not found" >&2
    echo "  Recall requires the Claude CLI for memory compaction." >&2
    echo "  The CLI is installed with Claude Code - check your PATH." >&2
    echo "  Verify: which claude" >&2
    echo "  Skipping compaction." >&2
    return 1
  fi

  PROGRESS_CONTENT=$(cat "$MEMORY_DIR/progress.md")
  MEMORY_CONTENT=""
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    MEMORY_CONTENT=$(cat "$MEMORY_DIR/MEMORY.md")
  fi

  # Read existing recurrence themes for slug reuse
  EXISTING_THEMES=""
  if [ -f "$RECURRENCE_FILE" ]; then
    EXISTING_THEMES=$(jq -r '.themes | keys[]' "$RECURRENCE_FILE" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
  fi

  # Build the compaction prompt
  PROMPT=$(cat <<'PROMPT_EOF'
You are a memory compaction agent. Your job is to produce a concise, well-structured MEMORY.md file that stays under 200 lines.

You will receive two inputs:
1. The current MEMORY.md (may be empty)
2. The session's progress.md

Instructions:
- Start from the existing MEMORY.md content as your base
- Merge in key facts, decisions, patterns, and context from progress.md
- Prune stale or redundant entries — anything no longer relevant to active work
- Stay under 200 lines total (this is the native loading limit — beyond this, content is invisible)
- Leave any `## User Context` section completely intact (user-authored, not for compaction)
- Do NOT reference or modify other files in the memory/ directory
- Output ONLY the new MEMORY.md content — no explanation, no code fences, no preamble
- Also identify 1-3 recurring themes from this session as lowercase-hyphenated slugs. If a slug matches an existing theme, reuse it. Output the themes on their own line at the very end: `THEMES: slug-1, slug-2`

PROMPT_EOF
  )

  PROMPT="${PROMPT}

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

  # Call claude -p with haiku and budget cap
  RESULT=$(echo "$PROMPT" | claude -p --model haiku --max-budget-usd 0.05 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$RESULT" ]; then
    echo "[Tandem Recall] Warning: compaction LLM call failed" >&2
    echo "  This may be due to:" >&2
    echo "  - Network connectivity issues" >&2
    echo "  - API rate limits or budget exhaustion" >&2
    echo "  - Claude CLI configuration problems" >&2
    echo "  Progress.md preserved for next session." >&2
    return 1
  fi

  # Sanity check: result must be substantive (> 5 lines, no refusal patterns)
  LINE_COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
  if [ "$LINE_COUNT" -lt 5 ]; then
    echo "[Tandem Recall] Warning: compaction result too short (${LINE_COUNT} lines). Skipping overwrite." >&2
    return 1
  fi
  if echo "$RESULT" | grep -qiE '^(I cannot|I'"'"'m sorry|I am sorry|I apologize|As an AI)'; then
    echo "[Tandem Recall] Warning: compaction result looks like a refusal. Skipping overwrite." >&2
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

  # Atomic write via temp file with validation
  mkdir -p "$MEMORY_DIR"
  TMPFILE=$(mktemp "$MEMORY_DIR/MEMORY.md.XXXXXX")
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    echo "[Tandem Recall] Error: failed to create temp file" >&2
    return 1
  fi

  echo "$MEMORY_RESULT" > "$TMPFILE"
  if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
    echo "[Tandem Recall] Error: failed to write temp file (disk full?)" >&2
    rm -f "$TMPFILE"
    return 1
  fi

  mv "$TMPFILE" "$MEMORY_DIR/MEMORY.md"

  # Write compaction marker for SessionStart indicator
  date +%s > "$MEMORY_DIR/.tandem-last-compaction"

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

      # Check if theme exists with validation
      EXISTING_COUNT=$(echo "$RECURRENCE" | jq -r ".themes[\"$theme\"].count // 0" 2>/dev/null)
      if [ $? -ne 0 ] || ! [[ "$EXISTING_COUNT" =~ ^[0-9]+$ ]]; then
        echo "[Tandem Recall] Warning: jq parse failed for theme $theme, skipping" >&2
        continue
      fi

      if [ "$EXISTING_COUNT" -gt 0 ]; then
        # Increment count and update last_seen
        RECURRENCE=$(echo "$RECURRENCE" | jq \
          --arg t "$theme" \
          --arg d "$TODAY" \
          '.themes[$t].count += 1 | .themes[$t].last_seen = $d' 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$RECURRENCE" ]; then
          echo "[Tandem Recall] Warning: jq update failed for theme $theme, skipping" >&2
          continue
        fi
      else
        # Add new theme
        RECURRENCE=$(echo "$RECURRENCE" | jq \
          --arg t "$theme" \
          --arg d "$TODAY" \
          '.themes[$t] = {"count": 1, "first_seen": $d, "last_seen": $d}' 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$RECURRENCE" ]; then
          echo "[Tandem Recall] Warning: jq add failed for theme $theme, skipping" >&2
          continue
        fi
      fi
    done

    # Atomic write recurrence.json with validation
    TMPFILE=$(mktemp "$STATE_DIR/recurrence.json.XXXXXX")
    if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
      echo "[Tandem Recall] Warning: failed to create temp file for recurrence.json" >&2
      continue
    fi

    echo "$RECURRENCE" > "$TMPFILE"
    if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
      echo "[Tandem Recall] Warning: failed to write recurrence.json temp file" >&2
      rm -f "$TMPFILE"
      continue
    fi

    mv "$TMPFILE" "$RECURRENCE_FILE"
  fi
}

# ─── Phase 2: Grow — extract learnings to profile ───────────────────────────

grow_extract() {
  # Verify claude CLI is available
  if ! command -v claude &>/dev/null; then
    echo "[Tandem Grow] Error: claude CLI not found" >&2
    echo "  Grow requires the Claude CLI for learning extraction." >&2
    echo "  The CLI is installed with Claude Code - check your PATH." >&2
    echo "  Verify: which claude" >&2
    echo "  Skipping extraction." >&2
    return 1
  fi

  PROGRESS_CONTENT=$(cat "$MEMORY_DIR/progress.md")

  # Read career context if available
  CAREER_CONTEXT=""
  if [ -f "$PROFILE_DIR/career-context.md" ]; then
    CAREER_CONTEXT=$(cat "$PROFILE_DIR/career-context.md")
  fi

  # Read current profile files
  PROFILE_CONTENTS=""
  if [ -d "$PROFILE_DIR" ]; then
    for f in "$PROFILE_DIR"/*.md; do
      [ -f "$f" ] || continue
      FNAME=$(basename "$f")
      FCONTENT=$(cat "$f")
      PROFILE_CONTENTS="${PROFILE_CONTENTS}--- ${FNAME} ---
${FCONTENT}
--- end ---

"
    done
  fi

  # Read recurrence themes
  RECURRENCE_THEMES=""
  if [ -f "$RECURRENCE_FILE" ]; then
    RECURRENCE_THEMES=$(jq -r '.themes | to_entries[] | "\(.key): count=\(.value.count), first=\(.value.first_seen), last=\(.value.last_seen)"' "$RECURRENCE_FILE" 2>/dev/null)
  fi

  # Build the extraction prompt
  PROMPT=$(cat <<'PROMPT_EOF'
You are a learning extraction agent. Review this session's progress and identify what the user learned, practiced, or deepened understanding of.

If there are learnings worth persisting, output changes to their profile directory. No rigid format — organise however best serves this user. Consider their career context if provided.

Rules:
- Only persist genuinely valuable learnings (skip routine operations)
- Don't duplicate what's already in the profile
- Keep entries concise and actionable
- Pay special attention to recurring themes (provided below) — if a theme keeps appearing but the profile has thin coverage, that's a high-priority learning to capture
- If you identify a high-impact learning opportunity, prioritise gaps: recurring themes where the profile has thin or no coverage. A theme appearing in 5+ sessions with no profile entry is a stronger NUDGE candidate than a novel concept from a single session. Output: NUDGE: [one sentence]
- If the session notes mention the user's role, company, tech stack, goals, strengths, or career direction, update career-context.md accordingly. Merge new information with existing content — never overwrite what's already there, only enrich. For career-context.md, output the full updated file (not append).

Output format for each file:
FILE: [filename]
[content to append]
---

For career-context.md specifically (full replacement, not append):
FILE: career-context.md
REPLACE: true
[full updated content]
---

Or if nothing worth persisting: NONE

PROMPT_EOF
  )

  PROMPT="${PROMPT}

<session_progress>
${PROGRESS_CONTENT}
</session_progress>

<current_profile_files>
${PROFILE_CONTENTS}
</current_profile_files>

<career_context>
${CAREER_CONTEXT}
</career_context>

<recurrence_themes>
${RECURRENCE_THEMES}
</recurrence_themes>

Review the session and extract learnings now."

  # Call claude -p with haiku and budget cap
  RESULT=$(echo "$PROMPT" | claude -p --model haiku --max-budget-usd 0.05 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$RESULT" ]; then
    echo "[Tandem Grow] Warning: extraction LLM call failed" >&2
    echo "  This may be due to:" >&2
    echo "  - Network connectivity issues" >&2
    echo "  - API rate limits or budget exhaustion" >&2
    echo "  - Claude CLI configuration problems" >&2
    echo "  Progress.md preserved for next session." >&2
    return 1
  fi

  # Handle NONE response
  if echo "$RESULT" | grep -qx 'NONE'; then
    return 0
  fi

  # Ensure profile directory exists
  mkdir -p "$PROFILE_DIR"

  # Parse the result: handle FILE blocks, REPLACE flag, and NUDGE
  CURRENT_FILE=""
  CURRENT_CONTENT=""
  REPLACE_MODE=false
  NUDGE=""

  while IFS= read -r line; do
    # Check for nudge
    if [[ "$line" == NUDGE:* ]]; then
      NUDGE="${line#NUDGE: }"
      continue
    fi

    # Check for file header
    if [[ "$line" == FILE:* ]]; then
      # Write previous file's content
      if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_CONTENT" ]; then
        SLUG=$(echo "$CURRENT_FILE" | xargs)
        SLUG="${SLUG%.md}"
        TARGET="$PROFILE_DIR/${SLUG}.md"
        if [ "$REPLACE_MODE" = true ]; then
          # Atomic overwrite with validation
          TMPFILE=$(mktemp "$PROFILE_DIR/${SLUG}.md.XXXXXX")
          if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
            echo "[Tandem Grow] Warning: failed to create temp file for ${SLUG}.md" >&2
            continue
          fi
          echo "$CURRENT_CONTENT" > "$TMPFILE"
          if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
            echo "[Tandem Grow] Warning: failed to write ${SLUG}.md temp file" >&2
            rm -f "$TMPFILE"
            continue
          fi
          mv "$TMPFILE" "$TARGET"
        else
          echo "$CURRENT_CONTENT" >> "$TARGET"
        fi
      fi
      CURRENT_FILE="${line#FILE: }"
      CURRENT_CONTENT=""
      REPLACE_MODE=false
      continue
    fi

    # Check for replace flag (must follow immediately after FILE: line)
    if [[ "$line" == "REPLACE: true" ]] && [ -z "$CURRENT_CONTENT" ]; then
      REPLACE_MODE=true
      continue
    fi

    # Check for block separator
    if [[ "$line" == "---" ]] && [ -n "$CURRENT_FILE" ]; then
      # Write current file's content
      if [ -n "$CURRENT_CONTENT" ]; then
        SLUG=$(echo "$CURRENT_FILE" | xargs)
        SLUG="${SLUG%.md}"
        TARGET="$PROFILE_DIR/${SLUG}.md"
        if [ "$REPLACE_MODE" = true ]; then
          # Atomic overwrite with validation
          TMPFILE=$(mktemp "$PROFILE_DIR/${SLUG}.md.XXXXXX")
          if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
            echo "[Tandem Grow] Warning: failed to create temp file for ${SLUG}.md" >&2
            CURRENT_FILE=""
            CURRENT_CONTENT=""
            REPLACE_MODE=false
            continue
          fi
          echo "$CURRENT_CONTENT" > "$TMPFILE"
          if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
            echo "[Tandem Grow] Warning: failed to write ${SLUG}.md temp file" >&2
            rm -f "$TMPFILE"
            CURRENT_FILE=""
            CURRENT_CONTENT=""
            REPLACE_MODE=false
            continue
          fi
          mv "$TMPFILE" "$TARGET"
        else
          echo "$CURRENT_CONTENT" >> "$TARGET"
        fi
      fi
      CURRENT_FILE=""
      CURRENT_CONTENT=""
      REPLACE_MODE=false
      continue
    fi

    # Accumulate content
    if [ -n "$CURRENT_FILE" ]; then
      CURRENT_CONTENT="${CURRENT_CONTENT}${line}
"
    fi
  done <<< "$RESULT"

  # Write final file's content if no trailing ---
  if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_CONTENT" ]; then
    SLUG=$(echo "$CURRENT_FILE" | xargs)
    SLUG="${SLUG%.md}"
    TARGET="$PROFILE_DIR/${SLUG}.md"
    if [ "$REPLACE_MODE" = true ]; then
      # Atomic overwrite with validation
      TMPFILE=$(mktemp "$PROFILE_DIR/${SLUG}.md.XXXXXX")
      if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
        echo "[Tandem Grow] Warning: failed to create temp file for ${SLUG}.md" >&2
        return 0  # Best effort - don't fail the whole function
      fi
      echo "$CURRENT_CONTENT" > "$TMPFILE"
      if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
        echo "[Tandem Grow] Warning: failed to write ${SLUG}.md temp file" >&2
        rm -f "$TMPFILE"
        return 0  # Best effort - don't fail the whole function
      fi
      mv "$TMPFILE" "$TARGET"
    else
      echo "$CURRENT_CONTENT" >> "$TARGET"
    fi
  fi

  # Write nudge for next session if present
  if [ -n "$NUDGE" ]; then
    mkdir -p "$HOME/.tandem"
    echo "$NUDGE" > "$HOME/.tandem/next-nudge"
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

  # Prepend new entry and cap at 30 entries with validation
  TMPFILE=$(mktemp "$GLOBAL_DIR/global.md.XXXXXX")
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    echo "[Tandem] Warning: failed to create temp file for global.md" >&2
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
    echo "[Tandem] Warning: failed to write global.md temp file" >&2
    rm -f "$TMPFILE"
    return 1
  fi

  mv "$TMPFILE" "$GLOBAL_FILE"
}

# ─── Execute phases ─────────────────────────────────────────────────────────

# Track phase success to ensure we don't delete progress.md if critical phases fail
RECALL_STATUS=0
GROW_STATUS=0
GLOBAL_STATUS=0

recall_compact && RECALL_STATUS=1
grow_extract && GROW_STATUS=1
global_activity && GLOBAL_STATUS=1

# Only delete progress.md if both critical phases succeeded
# (global_activity is best-effort, not critical for data safety)
if [ "$RECALL_STATUS" -eq 1 ] && [ "$GROW_STATUS" -eq 1 ]; then
  rm -f "$MEMORY_DIR/progress.md"
else
  # Mark partial failure for next session recovery
  # This lets SessionStart detect and alert the user
  echo "" >> "$MEMORY_DIR/progress.md"
  echo "## Session End Partial Failure ($(date +%Y-%m-%d))" >> "$MEMORY_DIR/progress.md"
  echo "Recall completed: $RECALL_STATUS, Grow completed: $GROW_STATUS" >> "$MEMORY_DIR/progress.md"
fi

# ─── Status output ──────────────────────────────────────────────────────────

# Show what was accomplished (unless TANDEM_QUIET is set)
if [ "${TANDEM_QUIET:-0}" != "1" ]; then
  # Only output status if at least one phase completed
  if [ "$RECALL_STATUS" -eq 1 ] || [ "$GROW_STATUS" -eq 1 ] || [ "$GLOBAL_STATUS" -eq 1 ]; then
    echo "[Tandem] Session complete" >&2

    if [ "$RECALL_STATUS" -eq 1 ]; then
      # Try to show line count reduction if possible
      if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
        LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
        echo "  ✓ Recall: compacted MEMORY.md (${LINE_COUNT} lines)" >&2
      else
        echo "  ✓ Recall: compacted MEMORY.md" >&2
      fi
    fi

    if [ "$GROW_STATUS" -eq 1 ]; then
      echo "  ✓ Grow: updated profile" >&2
    fi

    if [ "$GLOBAL_STATUS" -eq 1 ]; then
      echo "  ✓ Global: logged activity" >&2
    fi
  fi
fi

exit 0
