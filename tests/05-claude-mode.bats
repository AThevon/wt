#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_CLAUDE_MODE
}

teardown() {
  teardown_config
  unset WT_CLAUDE_MODE
}

@test "select_claude_mode: returns 'forced' immediately when WT_CLAUDE_MODE=forced" {
  export WT_CLAUDE_MODE="forced"
  run select_claude_mode "pr-review" "42"
  assert_success
  assert_output "forced"
}

@test "select_claude_mode: returns 'ask' immediately when WT_CLAUDE_MODE=ask" {
  export WT_CLAUDE_MODE="ask"
  run select_claude_mode "issue-work" "7"
  assert_success
  assert_output "ask"
}

@test "select_claude_mode: returns 'plan' immediately when WT_CLAUDE_MODE=plan" {
  export WT_CLAUDE_MODE="plan"
  run select_claude_mode "pr-work" "1"
  assert_success
  assert_output "plan"
}
