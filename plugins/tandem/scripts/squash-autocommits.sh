#!/bin/bash
# PreToolUse hook: squashes consecutive Tandem auto-commits before user commits,
# and guards against pushing with auto-commits in the push range.
# Fires on Bash tool calls. Exits 0 (allow) or 2 (deny with reason).

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

# TANDEM_WORKER guard
[ -n "${TANDEM_WORKER:-}" ] && exit 0

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only care about Bash tool calls
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Only care about git commit or git push
IS_COMMIT=false
IS_PUSH=false
[[ "$COMMAND" == *"git commit"* ]] && IS_COMMIT=true
[[ "$COMMAND" == *"git push"* ]] && IS_PUSH=true
[ "$IS_COMMIT" = false ] && [ "$IS_PUSH" = false ] && exit 0

# Must be a git repo
git -C "$CWD" rev-parse --git-dir &>/dev/null || exit 0

# ─── Helper: check if a commit is a Tandem auto-commit ─────────────────────

is_autocommit() {
  local sha="$1"
  # Primary: check for trailer in commit body
  if git -C "$CWD" log -1 --format='%B' "$sha" 2>/dev/null | grep -q 'Tandem-Auto-Commit: true'; then
    return 0
  fi
  # Fallback: subject match
  local subject
  subject=$(git -C "$CWD" log -1 --format='%s' "$sha" 2>/dev/null)
  [[ "$subject" == claude\(checkpoint\):* ]] && return 0
  [ "$subject" = "chore(tandem): session checkpoint" ] && return 0
  return 1
}

# ─── On git commit: squash consecutive auto-commits from HEAD ──────────────

if [ "$IS_COMMIT" = true ]; then
  # Squash gated by TANDEM_AUTO_SQUASH (push guard is always active)
  [ "${TANDEM_AUTO_SQUASH:-1}" = "0" ] && exit 0
  # Skip amend
  [[ "$COMMAND" == *"--amend"* ]] && exit 0

  # Count consecutive auto-commits from HEAD
  COUNT=0
  while true; do
    SHA=$(git -C "$CWD" rev-parse "HEAD~${COUNT}" 2>/dev/null) || break
    if is_autocommit "$SHA"; then
      COUNT=$((COUNT + 1))
    else
      break
    fi
  done

  if [ "$COUNT" -gt 0 ]; then
    tandem_log info "squashing $COUNT auto-commit(s) into upcoming commit"
    git -C "$CWD" reset --soft "HEAD~${COUNT}" 2>/dev/null || {
      tandem_log error "git reset --soft HEAD~${COUNT} failed"
      # Don't block the commit
    }
  fi

  exit 0
fi

# ─── On git push: deny if auto-commits in push range ──────────────────────

if [ "$IS_PUSH" = true ]; then
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -z "$BRANCH" ] && exit 0

  # Determine push range
  UPSTREAM=$(git -C "$CWD" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -z "$UPSTREAM" ]; then
    UPSTREAM="origin/$BRANCH"
    git -C "$CWD" rev-parse "$UPSTREAM" &>/dev/null || exit 0
  fi

  # Find auto-commits in range
  AUTO_LIST=""
  AUTO_COUNT=0
  while IFS= read -r sha; do
    [ -z "$sha" ] && continue
    if is_autocommit "$sha"; then
      SUBJECT=$(git -C "$CWD" log -1 --format='%s (%h)' "$sha" 2>/dev/null)
      AUTO_LIST="${AUTO_LIST}
  - ${SUBJECT}"
      AUTO_COUNT=$((AUTO_COUNT + 1))
    fi
  done < <(git -C "$CWD" log --format='%H' "${UPSTREAM}..HEAD" 2>/dev/null)

  [ "$AUTO_COUNT" -eq 0 ] && exit 0

  tandem_log info "push blocked: $AUTO_COUNT auto-commit(s) in push range"

  REASON="Push blocked: ${AUTO_COUNT} Tandem auto-commit(s) in push range.
${AUTO_LIST}

These checkpoint commits contain raw progress notes and should be squashed before pushing.

1. Make a clean commit, auto-commits will be squashed into it automatically
2. Manual squash: git reset --soft HEAD~${AUTO_COUNT} && git commit"

  jq -n --arg reason "$REASON" '{"decision": "deny", "reason": $reason}'
  exit 2
fi

exit 0
