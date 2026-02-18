#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_WORKTREE_DIR
  export MAIN_REPO="/tmp/projects/myrepo"
}

teardown() {
  teardown_config
  unset WT_WORKTREE_DIR
}

@test "get_worktree_base_dir: returns WT_WORKTREE_DIR when set" {
  export WT_WORKTREE_DIR="/custom/worktrees"
  run get_worktree_base_dir
  assert_output "/custom/worktrees"
}

@test "get_worktree_base_dir: expands tilde in WT_WORKTREE_DIR" {
  export WT_WORKTREE_DIR="~/worktrees"
  run get_worktree_base_dir
  assert_output "${HOME}/worktrees"
}

@test "get_worktree_base_dir: falls back to dirname of MAIN_REPO when unset" {
  run get_worktree_base_dir
  assert_output "/tmp/projects"
}
