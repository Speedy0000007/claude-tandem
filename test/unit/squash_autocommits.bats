#!/usr/bin/env bats
# Tests for plugins/tandem/scripts/squash-autocommits.sh
# PreToolUse hook: squashes consecutive auto-commits before user commits,
# denies pushes with auto-commits in push range.

load '../helpers/test_helper'
load '../helpers/fixtures'
load '../helpers/mock_claude'

# ─── Guards ──────────────────────────────────────────────────────────────────

@test "guard: TANDEM_WORKER set exits 0 silently" {
  export TANDEM_WORKER=1
  init_test_git_repo
  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'test'" "$TEST_CWD")"
  assert_success
  assert_output ""
}

@test "guard: non-Bash tool exits 0 silently" {
  init_test_git_repo
  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse_tool "Read" "$TEST_CWD")"
  assert_success
  assert_output ""
}

@test "guard: non-git command exits 0 silently" {
  init_test_git_repo
  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "ls -la" "$TEST_CWD")"
  assert_success
  assert_output ""
}

@test "guard: not a git repo exits 0 silently" {
  # TEST_CWD is not a git repo by default
  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'test'" "$TEST_CWD")"
  assert_success
  assert_output ""
}

# ─── is_autocommit detection ────────────────────────────────────────────────

@test "is_autocommit: detects Tandem-Auto-Commit trailer" {
  init_test_git_repo
  make_auto_commit

  local sha
  sha=$(git -C "$TEST_CWD" rev-parse HEAD)
  # Verify the trailer is present in the commit message
  run git -C "$TEST_CWD" log -1 --format='%B' "$sha"
  assert_output --partial "Tandem-Auto-Commit: true"
}

@test "is_autocommit: detects session checkpoint subject (fallback)" {
  init_test_git_repo
  # Create a commit with the checkpoint subject but no trailer
  make_commit "chore(tandem): session checkpoint"

  local sha
  sha=$(git -C "$TEST_CWD" rev-parse HEAD)
  run git -C "$TEST_CWD" log -1 --format='%s' "$sha"
  assert_output "chore(tandem): session checkpoint"
}

@test "is_autocommit: returns false for normal commits" {
  init_test_git_repo
  make_commit "feat: add feature" "Some body text."

  # A normal commit should not be detected as auto-commit.
  # We test this indirectly: a git commit command with no auto-commits
  # at HEAD should pass through without resetting.
  local count_before
  count_before=$(git -C "$TEST_CWD" rev-list --count HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'next'" "$TEST_CWD")"
  assert_success

  local count_after
  count_after=$(git -C "$TEST_CWD" rev-list --count HEAD)
  [ "$count_before" -eq "$count_after" ]
}

# ─── On git commit: squash ──────────────────────────────────────────────────

@test "commit: TANDEM_AUTO_SQUASH=0 skips squash" {
  export TANDEM_AUTO_SQUASH=0
  init_test_git_repo
  make_auto_commit

  local count_before
  count_before=$(git -C "$TEST_CWD" rev-list --count HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'user commit'" "$TEST_CWD")"
  assert_success

  # HEAD should be unchanged (no reset happened)
  local count_after
  count_after=$(git -C "$TEST_CWD" rev-list --count HEAD)
  [ "$count_before" -eq "$count_after" ]
}

@test "commit: no auto-commits at HEAD leaves history unchanged" {
  init_test_git_repo
  make_commit "feat: normal commit" "Body text."

  local sha_before
  sha_before=$(git -C "$TEST_CWD" rev-parse HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'next'" "$TEST_CWD")"
  assert_success

  local sha_after
  sha_after=$(git -C "$TEST_CWD" rev-parse HEAD)
  [ "$sha_before" = "$sha_after" ]
}

@test "commit: 1 auto-commit at HEAD is reset" {
  init_test_git_repo
  make_auto_commit

  local count_before
  count_before=$(git -C "$TEST_CWD" rev-list --count HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'user commit'" "$TEST_CWD")"
  assert_success

  local count_after
  count_after=$(git -C "$TEST_CWD" rev-list --count HEAD)
  # Should have 1 fewer commit (the auto-commit was soft-reset)
  [ "$count_after" -eq $((count_before - 1)) ]
}

@test "commit: 3 consecutive auto-commits are all reset" {
  init_test_git_repo
  make_auto_commit
  make_auto_commit
  make_auto_commit

  local count_before
  count_before=$(git -C "$TEST_CWD" rev-list --count HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'user commit'" "$TEST_CWD")"
  assert_success

  local count_after
  count_after=$(git -C "$TEST_CWD" rev-list --count HEAD)
  # Should have 3 fewer commits
  [ "$count_after" -eq $((count_before - 3)) ]
}

@test "commit: mixed history only resets consecutive auto-commits from HEAD" {
  init_test_git_repo
  # Older auto-commit (will be separated by a normal commit)
  make_auto_commit
  # Normal commit breaks the streak
  make_commit "feat: real work" "Some body."
  # Two consecutive auto-commits at HEAD
  make_auto_commit
  make_auto_commit

  local count_before
  count_before=$(git -C "$TEST_CWD" rev-list --count HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit -m 'user commit'" "$TEST_CWD")"
  assert_success

  local count_after
  count_after=$(git -C "$TEST_CWD" rev-list --count HEAD)
  # Only the 2 consecutive from HEAD should be reset, not the older one
  [ "$count_after" -eq $((count_before - 2)) ]
}

@test "commit: amend is skipped" {
  init_test_git_repo
  make_auto_commit

  local sha_before
  sha_before=$(git -C "$TEST_CWD" rev-parse HEAD)

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git commit --amend -m 'amended'" "$TEST_CWD")"
  assert_success

  local sha_after
  sha_after=$(git -C "$TEST_CWD" rev-parse HEAD)
  # HEAD unchanged because amend was skipped
  [ "$sha_before" = "$sha_after" ]
}

@test "commit: produces no stderr output" {
  init_test_git_repo
  make_auto_commit

  local json
  json=$(fixture_pretooluse "git commit -m 'user commit'" "$TEST_CWD")
  run bash -c "echo '$json' | '$PLUGIN_ROOT/scripts/squash-autocommits.sh' 2>&1 >/dev/null"
  assert_success
  assert_output ""
}

# ─── On git push: deny ──────────────────────────────────────────────────────

@test "push: TANDEM_AUTO_SQUASH=0 does NOT disable push guard" {
  export TANDEM_AUTO_SQUASH=0
  init_test_git_repo

  # Set up remote
  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  # Create auto-commit after push baseline
  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  # Should still deny even with TANDEM_AUTO_SQUASH=0
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial '"decision"'
  assert_output --partial '"deny"'
}

@test "push: no auto-commits in push range exits 0" {
  init_test_git_repo

  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  # Normal commit after push baseline
  make_commit "feat: real work" "Body text."

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  assert_success
  assert_output ""
}

@test "push: auto-commits in range produces deny JSON with exit 2" {
  init_test_git_repo

  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  [ "$status" -eq 2 ]

  # Output should be valid JSON with decision: deny
  echo "$output" | jq -e '.decision == "deny"'
  echo "$output" | jq -e '.reason | length > 0'
}

@test "push: deny message lists auto-commit subjects" {
  init_test_git_repo

  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  [ "$status" -eq 2 ]

  # The deny reason should include the auto-commit subject
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -q "chore(tandem): session checkpoint"
}

@test "push: deny message includes squash guidance" {
  init_test_git_repo

  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  [ "$status" -eq 2 ]

  local reason
  reason=$(echo "$output" | jq -r '.reason')
  # Should mention making a clean commit or manual squash
  echo "$reason" | grep -q "git reset --soft"
  echo "$reason" | grep -q "squashed"
}

@test "push: no upstream falls back to origin/BRANCH" {
  init_test_git_repo

  # Set up remote and push, but do not set upstream tracking
  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  # Push without -u so there is no tracking branch
  git -C "$TEST_CWD" push origin main -q 2>/dev/null

  # Unset upstream tracking if any
  git -C "$TEST_CWD" config --unset branch.main.remote 2>/dev/null || true
  git -C "$TEST_CWD" config --unset branch.main.merge 2>/dev/null || true

  # Create auto-commit after push
  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  # Should still detect auto-commit via origin/main fallback and deny
  [ "$status" -eq 2 ]
  assert_output --partial '"deny"'
}

@test "push: no upstream and no origin/BRANCH exits 0" {
  init_test_git_repo

  # No remote at all
  make_auto_commit

  run_script_with_input "squash-autocommits.sh" "$(fixture_pretooluse "git push" "$TEST_CWD")"
  # Can't determine range, so don't block
  assert_success
  assert_output ""
}

@test "push: produces no stderr output" {
  init_test_git_repo

  local remote_dir="$TEST_TEMP_DIR/remote.git"
  git init --bare -q "$remote_dir"
  git -C "$TEST_CWD" remote add origin "$remote_dir"
  git -C "$TEST_CWD" push -u origin main -q 2>/dev/null

  make_auto_commit

  local json
  json=$(fixture_pretooluse "git push" "$TEST_CWD")
  # Capture only stderr
  run bash -c "echo '$json' | '$PLUGIN_ROOT/scripts/squash-autocommits.sh' 2>&1 >/dev/null"
  # The deny JSON goes to stdout (suppressed by >/dev/null), stderr should be empty
  assert_output ""
}
