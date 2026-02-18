#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_PLATFORM
}

teardown() {
  teardown_config
  unset WT_PLATFORM
  # Clean up fake repos created in tests
  [[ -n "${_fake_repo:-}" ]] && rm -rf "$_fake_repo"
  unset _fake_repo
}

@test "detect_platform: returns github when WT_PLATFORM=github" {
  export WT_PLATFORM="github"
  run detect_platform
  assert_output "github"
}

@test "detect_platform: returns gitlab when WT_PLATFORM=gitlab" {
  export WT_PLATFORM="gitlab"
  run detect_platform
  assert_output "gitlab"
}

@test "detect_platform: auto-detects github from remote URL" {
  _fake_repo=$(make_fake_repo "https://github.com/user/repo.git")
  export MAIN_REPO="$_fake_repo"
  _WT_PLATFORM=""  # reset cache since we're not using run (run creates subshell)
  run detect_platform
  assert_output "github"
}

@test "detect_platform: auto-detects gitlab from remote URL" {
  _fake_repo=$(make_fake_repo "https://gitlab.com/user/repo.git")
  export MAIN_REPO="$_fake_repo"
  _WT_PLATFORM=""
  run detect_platform
  assert_output "gitlab"
}
