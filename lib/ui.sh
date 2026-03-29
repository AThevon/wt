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
  gum confirm \
    --selected.background 208 \
    --selected.foreground 0 \
    --unselected.background "" \
    --unselected.foreground 208 \
    "$@"
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

# Print the logo — pre-rendered ANSI tiger, fallback to text
print_logo() {
  local logo_ansi="$SCRIPT_DIR/assets/logo.ansi"
  # Nix install: assets/ is at $out/assets/wt/
  if [[ ! -f "$logo_ansi" ]]; then
    logo_ansi="$(dirname "$SCRIPT_DIR")/assets/wt/logo.ansi"
  fi

  if [[ -f "$logo_ansi" ]] && [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    # Center the logo horizontally
    local term_cols=$(tput cols 2>/dev/null || echo 80)
    # Get visible width of first non-empty line (strip ANSI escapes)
    local logo_width
    logo_width=$(head -1 "$logo_ansi" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    local pad=$(( (term_cols - logo_width) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    local padding=""
    printf -v padding '%*s' "$pad" ''
    while IFS= read -r line; do
      echo -e "${padding}${line}" >&2
    done < "$logo_ansi"
  else
    echo -e "\033[1;38;5;208m  wt\033[0m" >&2
  fi
}
