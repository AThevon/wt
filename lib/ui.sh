#!/usr/bin/env bash
# lib/ui.sh — UI functions using gum (Charmbracelet)
# Requires: gum in PATH, core.sh sourced first (for C_* color vars)

ui_success() {
  gum log --level info "$@" >&2
}

ui_warn() {
  gum log --level warn "$@" >&2
}

ui_error() {
  gum log --level error "$@" >&2
}

ui_spin() {
  local title="$1"
  shift
  gum spin --spinner dot --title "$title" -- "$@"
}

# Like ui_spin but for bash functions (not external commands).
# Runs the function in background, shows spinner, returns stdout.
ui_spin_fn() {
  local title="$1"; shift
  local _tmpfile
  _tmpfile=$(mktemp)
  "$@" > "$_tmpfile" &
  local _pid=$!
  gum spin --spinner dot --title "$title" -- bash -c "while kill -0 $_pid 2>/dev/null; do sleep 0.1; done" >&2
  wait "$_pid"
  local _ret=$?
  cat "$_tmpfile"
  rm -f "$_tmpfile"
  return $_ret
}

ui_confirm() {
  gum confirm "$@"
}

ui_input() {
  local prompt="${1:-}"
  local placeholder="${2:-}"
  local args=()
  [[ -n "$prompt" ]] && args+=(--prompt "$prompt ")
  [[ -n "$placeholder" ]] && args+=(--placeholder "$placeholder")
  gum input "${args[@]}"
}

ui_header() {
  gum style --border rounded --foreground 208 --border-foreground 208 --padding "0 1" "$@" >&2
}

ui_box() {
  gum style --border rounded --padding "0 1" "$@" >&2
}

# Print the logo — chafa render of tiger PNG if available, fallback to text
print_logo() {
  local logo_img="$SCRIPT_DIR/assets/logo.png"
  # Nix install: assets/ is a sibling of bin/
  if [[ ! -f "$logo_img" ]]; then
    logo_img="$(dirname "$SCRIPT_DIR")/assets/logo.png"
  fi

  if command -v chafa &>/dev/null && [[ -f "$logo_img" ]]; then
    local cols=$(( $(tput cols 2>/dev/null || echo 80) / 3 ))
    [[ $cols -lt 15 ]] && cols=15
    [[ $cols -gt 40 ]] && cols=40
    chafa --format=symbols --size="${cols}x" --symbols=block "$logo_img" >&2
  else
    echo -e "\033[1;38;5;208m  wt\033[0m" >&2
  fi

  echo -e "\033[2mGit Worktree Manager v$VERSION\033[0m" >&2
  msg ""
}
