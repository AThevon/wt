#!/bin/bash

# Redirect to universal installer
# Kept for backward compatibility — use install.sh instead

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
  exec "$SCRIPT_DIR/install.sh"
else
  echo "Downloading installer..."
  curl -fsSL https://raw.githubusercontent.com/AThevon/worktigre/main/install.sh | bash
fi
