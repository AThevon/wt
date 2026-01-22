#!/usr/bin/env zsh
# wt - Git Worktree Manager
# Add this to your .zshrc: eval "$(wt-core --shell-init)"
# Or source this file directly

unalias wt 2>/dev/null

function wt() {
  local output=$(WT_WRAPPED=1 wt-core "$@")
  local target=""
  local claude_cmd=""

  # Parse output: path and optional CLAUDE marker (can be in any order)
  while IFS= read -r line; do
    if [[ "$line" == CLAUDE:* ]]; then
      claude_cmd="$line"
    elif [[ -n "$line" && -d "$line" ]]; then
      target="$line"
    fi
  done <<< "$output"

  if [[ -n "$target" ]]; then
    cd "$target"
    echo "Navigated to: $target"

    # Launch claude if marker present
    if [[ "$claude_cmd" == CLAUDE:issue:* ]]; then
      local issue_num="${claude_cmd#CLAUDE:issue:}"
      echo ""
      echo "Starting Claude Code for Issue #$issue_num planning..."
      echo ""
      claude "Read issue #$issue_num with 'gh issue view $issue_num', then explore the codebase and propose an implementation plan."
    elif [[ "$claude_cmd" == CLAUDE:pr:* ]]; then
      local pr_num="${claude_cmd#CLAUDE:pr:}"
      echo ""
      echo "Starting Claude Code for PR #$pr_num review..."
      echo ""
      claude "Review PR #$pr_num. Run 'gh pr view $pr_num' and 'gh pr diff $pr_num' to get context, then analyze the code changes for bugs, security issues, and best practices."
    fi
  fi
}
