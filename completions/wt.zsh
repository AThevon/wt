#!/usr/bin/env zsh
# worktigre - Git Worktree Manager
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
    if [[ -n "$claude_cmd" ]]; then
      local type=$(echo "$claude_cmd" | cut -d: -f2)
      local num=$(echo "$claude_cmd" | cut -d: -f3)
      local mode=$(echo "$claude_cmd" | cut -d: -f4)

      local claude_flags=""
      local pr_term=$(wt-core --get-pr-term 2>/dev/null || echo "PR")

      if [[ "$type" == "issue-auto" || "$type" == "ci-fix" ]]; then
        claude_flags="--dangerously-skip-permissions"
        if [[ "$type" == "issue-auto" ]]; then
          echo ""
          echo ">> AUTO-RESOLVE: Issue #$num"
          echo "   Claude will plan, implement, and create a $pr_term automatically."
          echo ""
        else
          echo ""
          echo ">> AUTO-FIX CI: $pr_term #$num"
          echo "   Claude will fetch CI logs, fix the issues, and push."
          echo ""
        fi
      else
        case "$mode" in
          forced)
            claude_flags="--dangerously-skip-permissions"
            echo ""
            echo ">> Starting Claude in FORCED mode..."
            ;;
          ask)
            claude_flags=""
            echo ""
            echo "?> Starting Claude in ASK mode..."
            ;;
          plan)
            claude_flags="--permission-mode=plan"
            echo ""
            echo "## Starting Claude in PLAN mode..."
            ;;
        esac
        echo ""
      fi

      # Generate prompt dynamically (supports GitHub & GitLab)
      local prompt=$(wt-core --generate-prompt "$type" "$num")
      [[ -n "$prompt" ]] && claude $claude_flags "$prompt"
    fi
  fi
}
