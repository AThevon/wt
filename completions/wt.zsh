# wt - Git Worktree Manager
# Add this to your .zshrc: eval "$(wt-core --shell-init)"
# Or source this file directly

unalias wt 2>/dev/null

function wt() {
  local target=$(wt-core "$@")
  if [[ -n "$target" && -d "$target" ]]; then
    cd "$target"
    echo "Navigated to: $target"
  fi
}
