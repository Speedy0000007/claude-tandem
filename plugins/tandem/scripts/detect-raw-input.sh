#!/bin/bash
# UserPromptSubmit hook: assess prompt quality and restructure if needed.
# Stage 1: length gate (bash). Stage 2: assessment + restructuring (haiku).
# All errors are silenced — hook failures must be invisible to the user.

MIN_LENGTH=${TANDEM_CLARIFY_MIN_LENGTH:-200}

# Wrap everything so no error can leak
{
  command -v jq &>/dev/null || exit 0

  INPUT=$(cat)
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

  # Stage 1: length gate
  [ -z "$PROMPT" ] && exit 0
  LENGTH=${#PROMPT}
  [ "$LENGTH" -lt "$MIN_LENGTH" ] && exit 0

  # Stage 2: haiku assessment + restructuring
  HAIKU_PROMPT="Assess the following user prompt for quality issues: unclear intent, poor grammar/spelling, stream-of-consciousness style, or missing structure.

If the prompt has ANY of these issues, restructure it:
- Fix grammar and spelling
- Clarify intent
- Add structure where needed
- Preserve the user's voice and ALL information

Output ONLY the restructured text with no preamble, no explanation, no wrapping.

If the prompt is already clear, well-structured, and free of errors, output exactly: SKIP

User prompt:
${PROMPT}"

  RESULT=$(echo "$HAIKU_PROMPT" | claude -p --model haiku --max-budget-usd 0.02 2>/dev/null)
  [ -z "$RESULT" ] && exit 0

  # Trim whitespace for comparison
  TRIMMED=$(echo "$RESULT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Log every haiku decision for review
  LOG_DIR="$HOME/.tandem/logs"
  mkdir -p "$LOG_DIR" 2>/dev/null
  if [ "$TRIMMED" = "SKIP" ]; then
    LOG_ACTION="skip"
    LOG_RESULT=""
  else
    LOG_ACTION="restructured"
    LOG_RESULT="$TRIMMED"
  fi
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg action "$LOG_ACTION" \
        --arg prompt "$PROMPT" \
        --arg result "$LOG_RESULT" \
        --argjson len "$LENGTH" \
        '{ts: $ts, action: $action, prompt_length: $len, prompt: $prompt, result: $result}' \
        >> "$LOG_DIR/clarify.jsonl" 2>/dev/null

  [ "$TRIMMED" = "SKIP" ] && exit 0

  # Restructure needed — output plain text context for Claude
  if [ "${TANDEM_CLARIFY_QUIET:-0}" = "1" ]; then
    echo "The following is a restructured version of the user's input:"
  else
    echo "Clarified. The following is a restructured version of the user's input:"
  fi
  echo ""
  echo "---"
  echo "$RESULT"
  echo "---"
  echo ""
  if [ "${TANDEM_CLARIFY_QUIET:-0}" = "1" ]; then
    echo "Execute using this restructured version as your primary instruction."
  else
    echo "Display this restructured version to the user (prefixed with 'Clarified.'), then execute using it as your primary instruction."
  fi
} 2>/dev/null

exit 0
