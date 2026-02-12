#!/usr/bin/env bats
# Integration: auto-commit squash journey
# Tests squash-autocommits.sh squash-on-commit and push guard behaviour

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Add a bare remote to the test repo and push initial state
_setup_remote() {
  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  local branch
  branch=$(git -C "$TEST_CWD" rev-parse --abbrev-ref HEAD)
  git -C "$TEST_CWD" push -u origin "$branch" -q 2>/dev/null
}

_commit_count() {
  git -C "$TEST_CWD" rev-list --count HEAD
}

# Run squash script with properly JSON-encoded input via temp file
_run_squash() {
  local command="$1"
  local json
  json=$(jq -n --arg cmd "$command" --arg cwd "$TEST_CWD" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}')
  local tmpfile="$TEST_TEMP_DIR/squash_input.json"
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/squash-autocommits.sh'"
}

# ─── Tests ────────────────────────────────────────────────────────────────────

@test "squash flow: single auto-commit is squashed on next user commit" {
  init_test_git_repo
  local count_before
  count_before=$(_commit_count)

  # Create one auto-commit
  make_auto_commit
  local count_after_auto
  count_after_auto=$(_commit_count)
  [ "$count_after_auto" -eq $((count_before + 1)) ]

  # Run squash hook with a git commit command
  _run_squash 'git commit -m "feat: real feature"'
  assert_success

  # HEAD should have been reset: commit count back to before the auto-commit
  local count_after_squash
  count_after_squash=$(_commit_count)
  [ "$count_after_squash" -eq "$count_before" ]

  # The auto-commit subject should be gone from log
  local head_subject
  head_subject=$(git -C "$TEST_CWD" log -1 --format='%s')
  [ "$head_subject" != "chore(tandem): session checkpoint" ]

  # Staged changes from the auto-commit should still be present (soft reset)
  local staged
  staged=$(git -C "$TEST_CWD" diff --cached --name-only)
  [ -n "$staged" ]
}

@test "squash flow: multiple auto-commits all squashed at once" {
  init_test_git_repo
  local count_before
  count_before=$(_commit_count)

  # Create 3 auto-commits
  make_auto_commit
  make_auto_commit
  make_auto_commit
  local count_after_autos
  count_after_autos=$(_commit_count)
  [ "$count_after_autos" -eq $((count_before + 3)) ]

  # Run squash hook
  _run_squash 'git commit -m "feat: big feature"'
  assert_success

  # All 3 should be squashed: back to original count
  local count_after_squash
  count_after_squash=$(_commit_count)
  [ "$count_after_squash" -eq "$count_before" ]
}

@test "squash flow: push with auto-commits is denied" {
  init_test_git_repo
  _setup_remote

  # Create an auto-commit after pushing clean state
  make_auto_commit

  # Try to push
  _run_squash 'git push'

  assert_failure 2

  # Output is valid deny JSON
  echo "$output" | jq empty
  local decision
  decision=$(echo "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]

  # Reason mentions auto-commits
  assert_output --partial "auto-commit"
}

@test "squash flow: push succeeds after squash and clean commit" {
  init_test_git_repo
  _setup_remote

  # Create auto-commit
  make_auto_commit

  # Squash it via the hook
  _run_squash 'git commit -m "feat: clean commit"'
  assert_success

  # Now make the actual clean commit (the squash hook just did reset --soft,
  # the commit itself hasn't happened yet in this simulation)
  make_commit "feat: clean commit" "Squashed auto-commit into this."

  # Push should be allowed
  _run_squash 'git push'
  assert_success

  # No deny output
  [ -z "$output" ]
}
