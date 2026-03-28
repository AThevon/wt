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

# Print the new logo — WT ANSI Shadow + tiger eyes band
print_logo() {
  local use_color=false
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    use_color=true
  fi

  if $use_color; then
    echo -e "\033[1;38;5;208m" >&2
  fi

  cat >&2 << 'LOGO'
 █████   ███   █████ ███████████
░░███   ░███  ░░███ ░█░░░███░░░█    ▓▓▒▒▒  ▒▒▒▒       ▓▓▓███▓▓▓▓▓ ▓▓▓▓▓▓▓▓▓ ▓▓▓▓▓███▓▓▓       ▒▒▒▒  ▒▒▒▓▓
 ░███   ░███   ░███ ░   ░███  ░     ▓▓▒▒▒  ▒▒▒▒▒           ▓██▓▓▓ ▓▓▓▓▓▓▓▓▓ ▓▓▓▓▓▓           ▒▒▒▒▒  ▒▒▒▓▓
 ░███   ░███   ░███     ░███        ▓▓▒▒▒  ▒▒▒▒▒▒▓   ░▒▓▓    ▒█▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ▓▓▒    ▓▒▒▒▒▒▒  ▒▒▒▓▓
 ░░███  █████  ███      ░███        ▓▓▒▒▒  ▒▒ ▒▒▒▓▓   ▒▒▓  ▓   ▒▓▓▓▓▓▓▓▓▓▓▓▓▓▒   ▓  ▓▒▒   ▓▓▒▒▒ ▒▒  ▒▒▒▓▓
  ░░░█████░█████░       ░███        ▓▓▒▒▒  ▒▒  ▒▒▒▓▓    ▒▒▒▒    ▒▒▓▓▓▓▓▓▓▓▓▒▒    ▒▒▒▒    ▓▓▒▒▒  ▒▒  ▒▒▒▓▓
    ░░███ ░░███         █████       ▓▓▒▒▒  ▒▒  ▒▒▒▒▓▓▓█         ▒▒▓▓▓▓▓▓▓▓▓▒▒         █▓▓▓▒▒▒▒  ▒▒  ▒▒▒▓▓
     ░░░   ░░░         ░░░░░
LOGO

  if $use_color; then
    echo -e "\033[0m\033[2mGit Worktree Manager v$VERSION\033[0m" >&2
  else
    msg "Git Worktree Manager v$VERSION"
  fi
  msg ""
}
