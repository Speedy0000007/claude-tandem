#!/bin/bash
# TaskCompleted hook (async): nudges Claude to update progress.md when it's stale.
# Outputs a systemMessage to stdout only when progress.md is stale.
# No LLM call — just a file stat check.

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
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')
[ -z "$CWD" ] && exit 0

# Compute auto-memory directory
SANITISED=$(echo "$CWD" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/${SANITISED}/memory"

# Check if progress.md exists and is recent (< 5 minutes)
if [ -f "$MEMORY_DIR/progress.md" ]; then
  PROGRESS_MTIME=$(stat -f '%m' "$MEMORY_DIR/progress.md" 2>/dev/null || stat -c '%Y' "$MEMORY_DIR/progress.md" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((NOW - PROGRESS_MTIME))
    [ "$AGE" -le 300 ] && exit 0
  fi
fi

# Progress is stale or missing — output nudge
SUBJECT_MSG=""
if [ -n "$TASK_SUBJECT" ]; then
  SUBJECT_MSG="Task '${TASK_SUBJECT}' was just completed. "
fi

echo "{\"systemMessage\": \"${SUBJECT_MSG}Update progress.md in your auto-memory directory with what was done and key decisions.\"}"

exit 0
