#!/bin/bash

set -e

echo "Installing wt for Linux/WSL..."
echo ""

# Check for required commands
check_dep() {
  local cmd="$1"
  local pkg="$2"
  local required="$3"

  if command -v "$cmd" &>/dev/null; then
    echo "  [OK] $cmd"
    return 0
  else
    if [[ "$required" == "yes" ]]; then
      echo "  [MISSING] $cmd - installing..."
      sudo apt install -y "$pkg"
    else
      echo "  [MISSING] $cmd (optional) - install with: sudo apt install $pkg"
    fi
  fi
}

echo "Checking dependencies..."
check_dep "fzf" "fzf" "yes"
check_dep "jq" "jq" "yes"
check_dep "gh" "gh" "no"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT_SCRIPT="$SCRIPT_DIR/wt.sh"

if [[ ! -f "$WT_SCRIPT" ]]; then
  echo "Error: wt.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Install to /usr/local/bin
echo "Installing wt-core to /usr/local/bin..."
sudo ln -sf "$WT_SCRIPT" /usr/local/bin/wt-core
echo "  [OK] wt-core installed"
echo ""

echo "Installation complete!"
echo ""
echo "Add this to your ~/.zshrc or ~/.bashrc:"
echo ""
echo '  eval "$(wt-core --shell-init)"'
echo ""
echo "Then restart your terminal or run: source ~/.zshrc"
