#!/bin/bash
# TaskCompleted hook (async): nudges Claude to update progress.md when it's stale.
# Outputs a systemMessage to stdout only when progress.md is stale.
# No LLM call — just a file stat check.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

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
    if [ "$AGE" -le 300 ]; then
      tandem_log debug "progress fresh, no nudge"
      exit 0
    fi
  fi
fi

# Progress is stale or missing — output nudge
SUBJECT_MSG=""
if [ -n "$TASK_SUBJECT" ]; then
  SUBJECT_MSG="Task '${TASK_SUBJECT}' was just completed. "
fi

tandem_log debug "progress nudge sent"
echo "{\"systemMessage\": \"${SUBJECT_MSG}Update progress.md in your auto-memory directory with what was done and key decisions.\"}"

exit 0
