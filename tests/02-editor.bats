#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_EDITOR
}

teardown() {
  teardown_config
  unset WT_EDITOR
}

@test "get_editor: returns WT_EDITOR when set" {
  export WT_EDITOR="nvim"
  run get_editor
  assert_output "nvim"
}

@test "get_editor: falls back to auto-detection when WT_EDITOR is unset" {
  # Auto-detect returns something non-empty (cursor, code, vim, or $EDITOR value)
  run get_editor
  assert_success
  [[ -n "$output" ]]
}
