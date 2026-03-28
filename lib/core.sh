#!/usr/bin/env bash
# lib/core.sh — Foundation: colors, config, messages, platform detection
# Extracted from wt.sh. Every other module sources this file.

# =============================================================================
# Colors & Style
# =============================================================================

# Colors (only if terminal supports it)
if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_WHITE=$'\033[37m'
  C_ORANGE=$'\033[1;38;5;208m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN=''
  C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE='' C_ORANGE=''
fi

# =============================================================================
# Config
# =============================================================================

WT_CONFIG_FILE="${WT_CONFIG_FILE:-${HOME}/.config/wt/config}"

load_config() {
  if [[ -f "$WT_CONFIG_FILE" ]]; then
    source "$WT_CONFIG_FILE"
  fi
}

save_config_value() {
  local key="$1"
  local value="$2"
  local config_dir
  config_dir=$(dirname "$WT_CONFIG_FILE")

  # Create config dir if needed
  mkdir -p "$config_dir"

  # Create file with header if it doesn't exist
  if [[ ! -f "$WT_CONFIG_FILE" ]]; then
    cat > "$WT_CONFIG_FILE" << 'WTEOF'
# wt — user configuration
# Edit manually or via: wt > ⚙ Settings
WTEOF
  fi

  # Update or append the key
  local tmp_file="${WT_CONFIG_FILE}.tmp"
  if grep -q "^${key}=" "$WT_CONFIG_FILE" 2>/dev/null; then
    # Replace existing key using awk (safe with special chars in value)
    awk -v k="$key" -v v="$value" \
      'BEGIN{FS="="; OFS="="} /^[[:space:]]*#/{print; next} $1==k{print k"="v; next} {print}' \
      "$WT_CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$WT_CONFIG_FILE"
  else
    echo "${key}=${value}" >> "$WT_CONFIG_FILE"
  fi
}

get_config_value() {
  local key="$1"
  local default="$2"
  local value
  value=$(grep "^${key}=" "$WT_CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
  echo "${value:-$default}"
}

get_worktree_base_dir() {
  if [[ -n "${WT_WORKTREE_DIR:-}" ]]; then
    # Expand ~ if present
    echo "${WT_WORKTREE_DIR/#\~/$HOME}"
  else
    echo "$(dirname "$MAIN_REPO")"
  fi
}

has_fzf() {
  command -v fzf &> /dev/null
}

has_gh() {
  command -v gh &> /dev/null && gh auth status &> /dev/null
}

has_claude() {
  command -v claude &> /dev/null
}

get_editor() {
  # Config takes priority
  local configured="${WT_EDITOR:-}"
  if [[ -n "$configured" ]]; then
    echo "$configured"
    return
  fi
  # Auto-detect
  if command -v cursor &>/dev/null; then echo "cursor"
  elif command -v code &>/dev/null; then echo "code"
  elif [[ -n "$EDITOR" ]]; then echo "$EDITOR"
  else echo "vim"
  fi
}

# =============================================================================
# Messages (stderr uniquement)
# =============================================================================

msg() {
  echo -e "$@" >&2
}

msg_success() {
  echo -e "${C_GREEN}✓${C_RESET} $*" >&2
}

msg_error() {
  echo -e "${C_RED}✗${C_RESET} $*" >&2
}

msg_info() {
  echo -e "${C_CYAN}→${C_RESET} $*" >&2
}

msg_warn() {
  echo -e "${C_YELLOW}!${C_RESET} $*" >&2
}

# =============================================================================
# Platform Detection (GitHub / GitLab)
# =============================================================================

_WT_PLATFORM=""

detect_platform() {
  if [[ -n "$_WT_PLATFORM" ]]; then
    echo "$_WT_PLATFORM"
    return
  fi

  # Override via environment variable
  if [[ -n "${WT_PLATFORM:-}" ]]; then
    case "$WT_PLATFORM" in
      github|gitlab)
        _WT_PLATFORM="$WT_PLATFORM"
        echo "$_WT_PLATFORM"
        return
        ;;
    esac
  fi

  # Auto-detect from remote URL
  local remote_url
  remote_url=$(git -C "$MAIN_REPO" remote get-url origin 2>/dev/null)

  case "$remote_url" in
    *gitlab*) _WT_PLATFORM="gitlab" ;;
    *)        _WT_PLATFORM="github" ;;
  esac

  echo "$_WT_PLATFORM"
}

has_cli() {
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    command -v glab &>/dev/null && glab auth status &>/dev/null
  else
    command -v gh &>/dev/null && gh auth status &>/dev/null
  fi
}

get_cli_name() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "glab"; else echo "gh"; fi
}

get_pr_term() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "MR"; else echo "PR"; fi
}

get_pr_term_long() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "Merge Request"; else echo "Pull Request"; fi
}

get_platform_name() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "GitLab"; else echo "GitHub"; fi
}

# =============================================================================
# Additional dependency checks
# =============================================================================

has_gum() {
  command -v gum &>/dev/null
}

has_jq() {
  command -v jq &>/dev/null
}
