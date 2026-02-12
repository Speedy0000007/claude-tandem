#!/bin/bash
# UserPromptSubmit hook: assess prompt quality and restructure if needed.
# Stage 1: length gate (bash). Stage 2: assessment + restructuring (haiku).

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

MIN_LENGTH=${TANDEM_CLARIFY_MIN_LENGTH:-200}

tandem_require_jq

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

# Stage 1: length gate
[ -z "$PROMPT" ] && exit 0
LENGTH=${#PROMPT}
if [ "$LENGTH" -lt "$MIN_LENGTH" ]; then
  tandem_log debug "prompt skipped (${LENGTH} chars)"
  exit 0
fi

tandem_require_claude || exit 0

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

if [ "$TRIMMED" = "SKIP" ]; then
  tandem_log info "prompt skipped by haiku (${LENGTH} chars)"
  exit 0
fi

tandem_log info "prompt restructured (${LENGTH} chars)"

# Restructure needed — output JSON with additionalContext for Claude
if [ "${TANDEM_CLARIFY_QUIET:-0}" = "1" ]; then
  CONTEXT="The following is a restructured version of the user's input. Execute using this restructured version as your primary instruction.

---
${RESULT}
---"
else
  CONTEXT="◎╵═╵◎ ~ Clarified.
The following is a restructured version of the user's input. Display it to the user (prefixed with '◎╵═╵◎ ~ Clarified.'), then execute using it as your primary instruction.

---
${RESULT}
---"
fi

jq -n --arg context "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $context
  }
}'

exit 0
