#!/bin/bash
# UserPromptSubmit hook: assess prompt quality, restructure or generate questions.
# Stage 1: length gate (bash). Stage 2: assessment + action (haiku).

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

MIN_LENGTH=${TANDEM_CLARIFY_MIN_LENGTH:-200}
MAX_LENGTH=${TANDEM_CLARIFY_MAX_LENGTH:-5000}
DEBOUNCE_SECS=10

tandem_require_jq

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

# Stage 1: length gate
if [ -z "$PROMPT" ]; then
  tandem_log debug "empty prompt, skipping"
  exit 0
fi
LENGTH=${#PROMPT}
if [ "$LENGTH" -lt "$MIN_LENGTH" ]; then
  tandem_log debug "prompt skipped (${LENGTH} chars)"
  exit 0
fi
# Reject full-context prompts (cascade prevention). Real user messages won't exceed MAX_LENGTH.
if [ "$LENGTH" -gt "$MAX_LENGTH" ]; then
  tandem_log debug "prompt too long, likely full context (${LENGTH} chars)"
  exit 0
fi

# Debounce: skip if we fired recently (prevents cascade from additionalContext re-triggering)
DEBOUNCE_FILE="$HOME/.tandem/state/.clarify-last-fire"
if [ -f "$DEBOUNCE_FILE" ]; then
  LAST_FIRE=$(cat "$DEBOUNCE_FILE" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$LAST_FIRE" ] && [ $((NOW - LAST_FIRE)) -lt "$DEBOUNCE_SECS" ]; then
    tandem_log debug "debounced (${LENGTH} chars, last fire ${LAST_FIRE})"
    exit 0
  fi
fi
mkdir -p "$HOME/.tandem/state" 2>/dev/null
date +%s > "$DEBOUNCE_FILE"

if ! tandem_require_llm; then
  tandem_log warn "LLM unavailable, skipping clarify"
  exit 0
fi

tandem_log debug "hook fired (${LENGTH} chars)"

# Skill discovery: build list for LLM awareness
SKILL_LIST=""
for skill_file in "$HOME/.claude/skills"/*/SKILL.md "$PLUGIN_ROOT/skills"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  SNAME=$(grep -m1 '^name:' "$skill_file" | sed 's/^name: *//;s/^"//;s/"$//')
  if [ -z "$SNAME" ]; then
    SNAME=$(basename "$(dirname "$skill_file")")
  fi
  SDESC=$(sed -n '/^description:/{
    s/^description: *//
    s/^"//;s/"$//
    /^>/{n;s/^ *//;p;q;}
    p;q
  }' "$skill_file")
  SDESC=$(printf '%.60s' "$SDESC")
  SKILL_LIST="${SKILL_LIST}
${SNAME}: ${SDESC}"
done

# Stage 2: haiku assessment
HAIKU_PROMPT="Assess this user prompt for a software development AI assistant.

Three possible outcomes:

1. SKIP -- prompt is clear, well-structured, and sufficiently specified. Output exactly: SKIP

2. RESTRUCTURE -- poorly structured (grammar, stream-of-consciousness, formatting) BUT intent is clear and requirements are complete enough to start work. No important questions to ask. Output the restructured text only.

3. CLARIFY -- there are meaningful questions to ask before work begins. This includes: underspecified requirements, architectural decisions, ambiguous scope, missing context, or implicit assumptions that could lead to rework. Use this regardless of whether the prompt also needs restructuring. Output:
CLARIFY
<clean, restructured summary of what the user wants>
Q: <specific question 1>
Q: <specific question 2>
...

Bias toward CLARIFY over RESTRUCTURE. If you can identify even one question where the answer would change the implementation approach, use CLARIFY. The restructured summary in CLARIFY should capture the user's full intent clearly, even if the original was messy.

Strong CLARIFY signals (especially from dictated/spoken input):
- Filler words and verbal hedging: um, ah, like, kind of, sort of, something like that, you know what I mean, does that make sense, do you get me, not sure, I think maybe
- Trailing uncertainty: questions directed at the assistant (right?, yeah?, make sense?)
- Stream-of-consciousness with multiple ideas jumbled together
- Vague references: that thing, the usual way, however you think is best
These signal the user is thinking out loud and the input needs both restructuring and questions to pin down intent.

Output ONLY the result (SKIP, restructured text, or CLARIFY block). No preamble.

User prompt:
${PROMPT}"

# Append skill awareness to prompt
if [ -n "$SKILL_LIST" ]; then
  HAIKU_PROMPT="${HAIKU_PROMPT}

If any of these skills should be loaded before work begins, append a final line:
SKILLS: name1, name2
Only suggest skills clearly relevant to this prompt.

Available skills:
${SKILL_LIST}"
fi

RESULT=$(tandem_llm_call "$HAIKU_PROMPT")
if [ -z "$RESULT" ]; then
  tandem_log warn "empty LLM response"
  exit 0
fi

# Trim whitespace for comparison
TRIMMED=$(echo "$RESULT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Detect outcome from first line (case-insensitive)
FIRST_LINE=$(echo "$TRIMMED" | head -1)
FIRST_LINE_UPPER=$(echo "$FIRST_LINE" | tr '[:lower:]' '[:upper:]')

if [ "$FIRST_LINE_UPPER" = "SKIP" ]; then
  LOG_ACTION="skip"
elif [ "$FIRST_LINE_UPPER" = "CLARIFY" ]; then
  LOG_ACTION="clarify"
else
  LOG_ACTION="restructured"
fi

# Extract skill hints and strip from result
SKILL_HINTS=$(echo "$TRIMMED" | sed -n 's/^SKILLS: *//p' | head -1)
TRIMMED=$(echo "$TRIMMED" | sed '/^SKILLS: /d')
RESULT=$(echo "$RESULT" | sed '/^SKILLS: /d')

# Log every haiku decision for review (compact JSONL)
LOG_DIR="$HOME/.tandem/logs"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_JSON=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg action "$LOG_ACTION" \
      --arg prompt "$PROMPT" \
      --arg result "$TRIMMED" \
      --argjson len "$LENGTH" \
      '{ts: $ts, action: $action, prompt_length: $len, prompt: $prompt, result: $result}')
if [ "$LOG_ACTION" = "clarify" ]; then
  LOG_INTENT=$(echo "$TRIMMED" | tail -n +2 | sed '/^Q: /,$d' | sed '/^$/d')
  LOG_JSON=$(echo "$LOG_JSON" | jq -c --arg intent "$LOG_INTENT" '. + {intent: $intent}')
fi
if [ -n "$SKILL_HINTS" ]; then
  LOG_JSON=$(echo "$LOG_JSON" | jq -c --arg skills "$SKILL_HINTS" '. + {skills: $skills}')
fi
echo "$LOG_JSON" >> "$LOG_DIR/clarify.jsonl" 2>/dev/null

# Increment stats counter for non-skip outcomes
if [ "$LOG_ACTION" != "skip" ] && [ -f "$HOME/.tandem/state/stats.json" ]; then
  TMPFILE=$(mktemp "$HOME/.tandem/state/stats.json.XXXXXX")
  if jq '.clarifications = ((.clarifications // 0) + 1)' "$HOME/.tandem/state/stats.json" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
    mv "$TMPFILE" "$HOME/.tandem/state/stats.json"
  else
    rm -f "$TMPFILE"
  fi
fi

if [ "$LOG_ACTION" = "skip" ]; then
  if [ -n "$SKILL_HINTS" ]; then
    tandem_log info "prompt skipped with skill hints: ${SKILL_HINTS}"
    CONTEXT="Consider loading these skills before proceeding: ${SKILL_HINTS}"
    jq -n --arg context "$CONTEXT" '{
      "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": $context
      }
    }'
  else
    tandem_log info "prompt skipped by haiku (${LENGTH} chars)"
  fi
  exit 0
fi

if [ "$LOG_ACTION" = "clarify" ]; then
  tandem_log info "prompt needs clarification (${LENGTH} chars)"

  # Extract restructured intent (lines between CLARIFY and first Q:)
  INTENT=$(echo "$TRIMMED" | tail -n +2 | sed '/^Q: /,$d' | sed '/^$/d')
  [ -z "$INTENT" ] && INTENT="the user's request"

  # Extract questions
  QUESTIONS=$(echo "$TRIMMED" | grep '^Q: ')
  if [ -z "$QUESTIONS" ]; then
    # Fallback: all non-empty lines after the intent block
    QUESTIONS=$(echo "$TRIMMED" | tail -n +2 | sed -n '/^Q\|^[0-9]\|^- /p')
  fi

  if [ "${TANDEM_CLARIFY_QUIET:-0}" = "1" ]; then
    CONTEXT="Before proceeding, confirm intent and ask these clarifying questions:

Intent: ${INTENT}

${QUESTIONS}

Wait for answers before beginning any work."
  else
    CONTEXT="◎╵═╵◎ ~ Clarify.

IMPORTANT: You MUST display this to the user before doing anything else. Do not skip this, do not start working. Display it and wait for answers.

I understood your request as:
${INTENT}

Before I start, I need to clarify:
${QUESTIONS}

Wait for the user to answer before beginning any work."
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

IMPORTANT: Display this restructured version to the user before executing. Show it prefixed with the logo line above.

${RESULT}"
  fi
fi

# Append skill hints to context for non-skip outcomes
if [ -n "$SKILL_HINTS" ]; then
  CONTEXT="${CONTEXT}

Relevant skills to consider loading: ${SKILL_HINTS}"
fi

jq -n --arg context "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $context
  }
}'

exit 0
