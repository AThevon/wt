#!/bin/bash

# =============================================================================
# wt - Universal Installer
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/AThevon/wt/main/install.sh | bash
# =============================================================================

set -e

REPO="AThevon/wt"
RAW_URL="https://raw.githubusercontent.com/$REPO/main/wt.sh"
INSTALL_DIR="${HOME}/.local/bin"
INSTALL_PATH="${INSTALL_DIR}/wt-core"

# Colors
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  CYAN=$'\033[36m'
  DIM=$'\033[2m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  GREEN='' RED='' CYAN='' DIM='' BOLD='' RESET=''
fi

info()  { echo "${GREEN}[ok]${RESET} $*"; }
warn()  { echo "${RED}[!!]${RESET} $*"; }
dim()   { echo "${DIM}$*${RESET}"; }

echo ""
echo "${BOLD}wt${RESET} — Git Worktree Manager"
echo "─────────────────────────"
echo ""

# --- Dependencies -----------------------------------------------------------

echo "Dependencies:"

install_pkg() {
  local cmd="$1" pkg="$2"
  if command -v apt &>/dev/null; then
    sudo apt update -qq && sudo apt install -y "$pkg"
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y "$pkg"
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm "$pkg"
  elif command -v brew &>/dev/null; then
    brew install "$pkg"
  else
    warn "$cmd not found — install it manually: $pkg"
    return 1
  fi
}

# Required deps (auto-install)
for dep in fzf gum jq; do
  if command -v "$dep" &>/dev/null; then
    info "$dep"
  else
    echo "  [..] $dep (required) — installing..."
    if install_pkg "$dep" "$dep"; then
      info "$dep installed"
    else
      warn "Could not install $dep — install it manually: brew install $dep"
      exit 1
    fi
  fi
done

# Optional deps (check only)
for dep in gh glab claude; do
  if command -v "$dep" &>/dev/null; then
    info "$dep"
  else
    dim "  [--] $dep (optional)"
  fi
done
echo ""

# --- Download ----------------------------------------------------------------

echo "Installing wt..."

mkdir -p "$INSTALL_DIR"

if command -v curl &>/dev/null; then
  curl -fsSL "$RAW_URL" -o "$INSTALL_PATH"
elif command -v wget &>/dev/null; then
  wget -qO "$INSTALL_PATH" "$RAW_URL"
else
  warn "Neither curl nor wget found — cannot download"
  exit 1
fi

chmod +x "$INSTALL_PATH"

VERSION=$(grep -m1 'VERSION=' "$INSTALL_PATH" | cut -d'"' -f2)
info "wt v${VERSION} installed to ${CYAN}${INSTALL_PATH}${RESET}"
echo ""

# --- PATH --------------------------------------------------------------------

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "Adding ${CYAN}${INSTALL_DIR}${RESET} to PATH..."

  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)    rc_file="$HOME/.profile" ;;
  esac

  path_line="export PATH=\"$INSTALL_DIR:\$PATH\""
  if ! grep -qF "$INSTALL_DIR" "$rc_file" 2>/dev/null; then
    echo "" >> "$rc_file"
    echo "# wt - PATH" >> "$rc_file"
    echo "$path_line" >> "$rc_file"
    info "Added PATH to ${CYAN}${rc_file}${RESET}"
  fi
fi

# --- Shell init --------------------------------------------------------------

shell_name=$(basename "$SHELL")
case "$shell_name" in
  zsh)  rc_file="$HOME/.zshrc" ;;
  bash) rc_file="$HOME/.bashrc" ;;
  *)    rc_file="$HOME/.profile" ;;
esac

init_line='command -v wt-core &>/dev/null && eval "$(wt-core --shell-init)"'

if grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
  info "Shell init already configured"
else
  echo "" >> "$rc_file"
  echo "# wt - Git Worktree Manager" >> "$rc_file"
  echo "$init_line" >> "$rc_file"
  info "Added init to ${CYAN}${rc_file}${RESET}"
fi

echo ""
echo "─────────────────────────"
echo "${GREEN}${BOLD}Installation complete!${RESET}"
echo ""
echo "To activate now:"
echo ""
echo "  ${CYAN}source ${rc_file}${RESET}"
echo ""
echo "To update later:"
echo ""
echo "  ${CYAN}wt --update${RESET}"
echo ""
