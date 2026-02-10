#!/bin/bash
# UserPromptSubmit hook: detect raw, unstructured input and inject pre-processing context.
#
# Tuneable thresholds (override via env vars):
MIN_LENGTH=${PREPROCESSOR_MIN_LENGTH:-500}    # chars before checking structure
MAX_STRUCTURE=${PREPROCESSOR_MAX_STRUCTURE:-2} # max structural markers before skipping

command -v jq &>/dev/null || { echo "[Tandem] Error: jq required but not found" >&2; exit 0; }

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Bail if no prompt or too short
[ -z "$PROMPT" ] && exit 0
LENGTH=${#PROMPT}
[ "$LENGTH" -lt "$MIN_LENGTH" ] && exit 0

# Count structural markers (headers, bullets, code blocks, numbered lists)
HEADERS=$(echo "$PROMPT" | grep -c '^#')
BULLETS=$(echo "$PROMPT" | grep -c '^\s*[-*+] ')
CODE_BLOCKS=$(echo "$PROMPT" | grep -c '```')
NUMBERED=$(echo "$PROMPT" | grep -c '^\s*[0-9]\+[.)]\s')
STRUCTURE=$((HEADERS + BULLETS + CODE_BLOCKS + NUMBERED))

# If well-structured already, skip
[ "$STRUCTURE" -gt "$MAX_STRUCTURE" ] && exit 0

# Zero-structure prose needs a higher threshold to reduce false positives
if [ "$STRUCTURE" -eq 0 ] && [ "$LENGTH" -lt 800 ]; then
  exit 0
fi

# Check chars-per-line ratio (high ratio = wall of text / dictation)
NEWLINES=$(echo "$PROMPT" | wc -l | tr -d ' ')
[ "$NEWLINES" -eq 0 ] && NEWLINES=1
CHARS_PER_LINE=$((LENGTH / NEWLINES))

if [ "$CHARS_PER_LINE" -gt 150 ] || [ "$STRUCTURE" -eq 0 ]; then
  echo "This input appears to be raw, unstructured dictation. Apply the tandem:clarify skill: parse the intent, restructure using the Prompt Structure Template, and execute immediately without showing the restructured version."
fi

exit 0
