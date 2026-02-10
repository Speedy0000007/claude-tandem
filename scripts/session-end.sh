#!/bin/bash
# SessionEnd hook: runs compaction (Recall) then extraction (Grow) sequentially.
# Both depend on progress.md — this script ensures ordering and single cleanup.

command -v jq &>/dev/null || { echo "[Tandem] Error: jq required but not found" >&2; exit 0; }

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

# ─── Phase 1: Recall — compact MEMORY.md ───────────────────────────────────

recall_compact() {
  # Verify claude CLI is available
  if ! command -v claude &>/dev/null; then
    echo "[Tandem Recall] Error: claude CLI not found on PATH. Skipping compaction." >&2
    return 1
  fi

  PROGRESS_CONTENT=$(cat "$MEMORY_DIR/progress.md")
  MEMORY_CONTENT=""
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    MEMORY_CONTENT=$(cat "$MEMORY_DIR/MEMORY.md")
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
- Preserve and update the `## Promotion Candidates` section:
  - If a theme from progress.md matches an existing candidate, increment its count
  - If a new theme recurs (appeared in 2+ recent sessions), add it with count and suggested promotion target
  - Suggested targets: `~/.claude/CLAUDE.md` (user prefs), `.claude/CLAUDE.md` (project conventions), `.claude/rules/*.md` (scoped rules)
- Leave any `## User Context` section completely intact (user-authored, not for compaction)
- Do NOT reference or modify other files in the memory/ directory
- Output ONLY the new MEMORY.md content — no explanation, no code fences, no preamble

PROMPT_EOF
  )

  PROMPT="${PROMPT}

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
    echo "[Tandem Recall] Warning: compaction LLM call failed." >&2
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

  # Atomic write via temp file
  mkdir -p "$MEMORY_DIR"
  TMPFILE=$(mktemp "$MEMORY_DIR/MEMORY.md.XXXXXX")
  echo "$RESULT" > "$TMPFILE"
  mv "$TMPFILE" "$MEMORY_DIR/MEMORY.md"

  # Write compaction marker for SessionStart indicator
  date +%s > "$MEMORY_DIR/.tandem-last-compaction"
}

# ─── Phase 2: Grow — extract pattern cards ──────────────────────────────────

grow_extract() {
  # Check for Concepts section in progress.md
  if ! grep -q '## Concepts' "$MEMORY_DIR/progress.md" 2>/dev/null; then
    return 0
  fi

  # Verify claude CLI is available
  if ! command -v claude &>/dev/null; then
    echo "[Tandem Grow] Error: claude CLI not found on PATH. Skipping extraction." >&2
    return 1
  fi

  # Extract the Concepts section from progress.md
  CONCEPTS=$(sed -n '/^## Concepts$/,/^## /{/^## /d;p;}' "$MEMORY_DIR/progress.md")
  [ -z "$CONCEPTS" ] && return 0

  # Read existing pattern card names for deduplication
  EXISTING_CARDS=""
  if [ -d "$PROFILE_DIR" ]; then
    EXISTING_CARDS=$(grep -h '^### ' "$PROFILE_DIR"/*.md 2>/dev/null)
  fi

  # Read career context if available
  CAREER_CONTEXT=""
  if [ -f "$PROFILE_DIR/career-context.md" ]; then
    CAREER_CONTEXT=$(cat "$PROFILE_DIR/career-context.md")
  fi

  # Build the extraction prompt
  PROMPT=$(cat <<'PROMPT_EOF'
You are a learning extraction agent. Your job is to formalise concept notes into pattern cards and optionally generate a learning nudge.

You will receive:
1. Concept notes from a coding session
2. Existing pattern card names (for deduplication)
3. Career context (optional — for nudge relevance)

## Pattern Card Format

For each genuinely new concept, output a pattern card:

### [Concept Name]
**When:** [situation where this applies]
**Why over alternatives:** [tradeoff reasoning]
**Code ref:** [file/commit reference from the concept note]

## Instructions

- Skip concepts already covered by existing cards (check by name)
- If a concept matches an existing card but has a newer code ref, output ONLY: `UPDATE: [Concept Name] ref: [new ref]`
- Group cards by topic. Output a topic header as: `FILE: [topic-slug]` before its cards
- Only formalise concepts with genuine educational depth — skip trivial ones
- Output ONLY pattern cards and FILE headers — no explanation, no preamble

## Learning Nudge

After the pattern cards, if you identify a HIGH-IMPACT learning opportunity (the user repeatedly struggled with something, or there's a clear gap aligned with their career goals), output:

NUDGE: [single sentence — what to learn and why it would help, referencing specific friction they experienced]

Only output a NUDGE if it's genuinely high-signal. Most sessions won't warrant one.

PROMPT_EOF
  )

  PROMPT="${PROMPT}

<concepts>
${CONCEPTS}
</concepts>

<existing_card_names>
${EXISTING_CARDS}
</existing_card_names>

<career_context>
${CAREER_CONTEXT}
</career_context>

Extract pattern cards now."

  # Call claude -p with haiku and budget cap
  RESULT=$(echo "$PROMPT" | claude -p --model haiku --max-budget-usd 0.05 2>/dev/null)

  [ $? -ne 0 ] || [ -z "$RESULT" ] && return 1

  # Ensure profile directory exists
  mkdir -p "$PROFILE_DIR"

  # Parse the result: split by FILE: headers and write to appropriate files
  CURRENT_FILE=""
  CURRENT_CONTENT=""
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
        echo "$CURRENT_CONTENT" >> "$PROFILE_DIR/$CURRENT_FILE"
      fi
      # Strip whitespace, ensure .md extension (avoid double .md)
      SLUG=$(echo "${line#FILE: }" | xargs)
      SLUG="${SLUG%.md}"
      CURRENT_FILE="${SLUG}.md"
      CURRENT_CONTENT=""
      continue
    fi

    # Check for update directive
    if [[ "$line" == UPDATE:* ]]; then
      continue
    fi

    # Accumulate content
    if [ -n "$CURRENT_FILE" ]; then
      CURRENT_CONTENT="${CURRENT_CONTENT}${line}
"
    fi
  done <<< "$RESULT"

  # Write final file's content
  if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_CONTENT" ]; then
    echo "$CURRENT_CONTENT" >> "$PROFILE_DIR/$CURRENT_FILE"
  fi

  # Write nudge for next session if present
  if [ -n "$NUDGE" ]; then
    mkdir -p "$HOME/.tandem"
    echo "$NUDGE" > "$HOME/.tandem/next-nudge"
  fi
}

# ─── Execute phases ─────────────────────────────────────────────────────────

recall_compact
grow_extract

# Clean up progress.md after both phases have had their chance to read it
rm -f "$MEMORY_DIR/progress.md"

exit 0
