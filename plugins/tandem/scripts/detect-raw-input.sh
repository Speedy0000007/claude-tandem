#!/bin/bash
# UserPromptSubmit hook: assess prompt quality, restructure or generate questions.
# Stage 1: length gate (bash). Stage 2: assessment + action (haiku).

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

tandem_require_llm || exit 0

# Stage 2: haiku assessment
HAIKU_PROMPT="Assess this user prompt. Three possible outcomes:

1. RESTRUCTURE — if the prompt has poor grammar, stream-of-consciousness style, or missing structure BUT the intent and requirements are clear. Output the restructured text only.

2. CLARIFY — if the prompt contains genuine uncertainty, unanswered questions, or signals like \"I can't remember\", \"I think\", \"maybe\", \"not sure\", \"or whether\" where the user needs help resolving ambiguity before work can begin. Output:
CLARIFY
<one-line summary of the topic>
Q: <specific question 1>
Q: <specific question 2>
...

3. SKIP — if the prompt is already clear and well-structured. Output exactly: SKIP

Output ONLY the result (SKIP, restructured text, or CLARIFY block). No preamble.

User prompt:
${PROMPT}"

RESULT=$(tandem_llm_call "$HAIKU_PROMPT")
[ -z "$RESULT" ] && exit 0

# Trim whitespace for comparison
TRIMMED=$(echo "$RESULT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Detect outcome from first line
FIRST_LINE=$(echo "$TRIMMED" | head -1)

if [ "$FIRST_LINE" = "SKIP" ]; then
  LOG_ACTION="skip"
elif [ "$FIRST_LINE" = "CLARIFY" ]; then
  LOG_ACTION="clarify"
else
  LOG_ACTION="restructured"
fi

# Log every haiku decision for review
LOG_DIR="$HOME/.tandem/logs"
mkdir -p "$LOG_DIR" 2>/dev/null
jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg action "$LOG_ACTION" \
      --arg prompt "$PROMPT" \
      --arg result "$TRIMMED" \
      --argjson len "$LENGTH" \
      '{ts: $ts, action: $action, prompt_length: $len, prompt: $prompt, result: $result}' \
      >> "$LOG_DIR/clarify.jsonl" 2>/dev/null

if [ "$LOG_ACTION" = "skip" ]; then
  tandem_log info "prompt skipped by haiku (${LENGTH} chars)"
  exit 0
fi

if [ "$LOG_ACTION" = "clarify" ]; then
  tandem_log info "prompt needs clarification (${LENGTH} chars)"

  # Extract summary (line 2) and questions (Q: lines) from CLARIFY block
  SUMMARY=$(echo "$TRIMMED" | sed -n '2p')
  QUESTIONS=$(echo "$TRIMMED" | grep '^Q: ')

  if [ "${TANDEM_CLARIFY_QUIET:-0}" = "1" ]; then
    CONTEXT="Before proceeding, ask the user these clarifying questions about: ${SUMMARY}

${QUESTIONS}

Wait for answers before beginning any work."
  else
    CONTEXT="◎╵═╵◎ ~ Clarify.
Before proceeding, display the following questions to the user (prefixed with '◎╵═╵◎ ~ Clarify.') and wait for answers before beginning any work.

Topic: ${SUMMARY}
${QUESTIONS}"
  fi
else
  tandem_log info "prompt restructured (${LENGTH} chars)"

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
fi

jq -n --arg context "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $context
  }
}'

exit 0
