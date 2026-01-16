# wt - Git Worktree Manager
# Add this to your .zshrc: eval "$(wt-core --shell-init)"
# Or source this file directly

unalias wt 2>/dev/null

function wt() {
  local output=$(WT_WRAPPED=1 wt-core "$@")
  local target=""
  local claude_cmd=""

  # Parse output: path on first line, optional CLAUDE marker on second
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
      echo "Tip: Ask Claude to run 'gh issue view $issue_num' to read the issue"
      echo ""
      claude
    elif [[ "$claude_cmd" == CLAUDE:pr:* ]]; then
      local pr_num="${claude_cmd#CLAUDE:pr:}"
      echo ""
      echo "Starting Claude Code for PR #$pr_num review..."
      echo "Tip: Ask Claude to run 'gh pr view $pr_num' and 'gh pr diff $pr_num'"
      echo ""
      claude
    fi
  fi
}
