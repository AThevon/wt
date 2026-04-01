#!/bin/bash

# =============================================================================
# wt - Git Worktree Manager avec fzf
# =============================================================================
# Le script retourne UNIQUEMENT le path vers lequel naviguer sur stdout
# Tous les messages vont sur stderr pour ne pas polluer le résultat
# =============================================================================

VERSION="2.0.1"

# =============================================================================
# Options de ligne de commande
# =============================================================================

if [[ "$1" == "--version" || "$1" == "-v" ]]; then
  echo "wt $VERSION" >&2
  exit 0
fi

# Self-update: download latest version from GitHub
if [[ "$1" == "--update" ]]; then
  _REPO="AThevon/wt"
  _RAW_URL="https://raw.githubusercontent.com/$_REPO/main/wt.sh"

  # Colors
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    _GREEN=$'\033[32m' _RED=$'\033[31m' _CYAN=$'\033[36m' _BOLD=$'\033[1m' _RESET=$'\033[0m'
  else
    _GREEN='' _RED='' _CYAN='' _BOLD='' _RESET=''
  fi
  _msg() { echo -e "$@" >&2; }

  # Detect brew installs
  if command -v brew &>/dev/null && brew list wt &>/dev/null 2>&1; then
    _msg ""
    _msg "${_RED}[!!]${_RESET} wt is installed via Homebrew."
    _msg "     Update with: ${_CYAN}brew upgrade wt${_RESET}"
    _msg ""
    exit 1
  fi

  # Find wt-core location
  _wt_path=$(command -v wt-core 2>/dev/null)
  if [[ -z "$_wt_path" ]]; then
    _wt_path="${HOME}/.local/bin/wt-core"
  fi
  # Resolve symlink to actual file
  if [[ -L "$_wt_path" ]]; then
    _wt_path=$(readlink -f "$_wt_path" 2>/dev/null || realpath "$_wt_path" 2>/dev/null || echo "$_wt_path")
  fi

  _msg ""
  _msg "Checking for updates..."

  # Download to temp file
  _tmp=$(mktemp)
  trap 'rm -f "$_tmp"' EXIT

  if command -v curl &>/dev/null; then
    curl -fsSL "$_RAW_URL" -o "$_tmp" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -qO "$_tmp" "$_RAW_URL" 2>/dev/null
  else
    _msg "${_RED}[!!]${_RESET} Neither curl nor wget found"
    exit 1
  fi

  _latest=$(grep -m1 'VERSION=' "$_tmp" | cut -d'"' -f2)

  if [[ -z "$_latest" ]]; then
    _msg "${_RED}[!!]${_RESET} Failed to fetch latest version"
    exit 1
  fi

  if [[ "$VERSION" == "$_latest" ]]; then
    _msg "${_GREEN}[ok]${_RESET} Already up to date (v${VERSION})"
    _msg ""
    exit 0
  fi

  _msg "  ${_CYAN}v${VERSION}${_RESET} → ${_GREEN}v${_latest}${_RESET}"
  _msg ""

  # Replace wt-core
  if [[ -w "$_wt_path" ]]; then
    cp "$_tmp" "$_wt_path"
    chmod +x "$_wt_path"
  elif [[ -w "$(dirname "$_wt_path")" ]]; then
    cp "$_tmp" "$_wt_path"
    chmod +x "$_wt_path"
  else
    _msg "Updating ${_CYAN}${_wt_path}${_RESET} (requires sudo)..."
    sudo cp "$_tmp" "$_wt_path"
    sudo chmod +x "$_wt_path"
  fi

  _msg "${_GREEN}${_BOLD}Updated to v${_latest}!${_RESET}"
  _msg ""
  _msg "Restart your terminal or run: ${_CYAN}source ~/.$(basename "$SHELL")rc${_RESET}"
  _msg ""
  exit 0
fi

# Mode dev: génère une fonction shell pointant vers ce script local
if [[ "$1" == "--dev" ]]; then
  local_script="$(cd "$(dirname "$0")" && pwd)/wt.sh"
  cat <<EOF
# wt - Dev Mode (local script)
unalias wt 2>/dev/null
function wt() {
  if [[ "\$1" == "--release" ]]; then
    eval "\$(wt-core --shell-init)"
    echo "Switched to release mode: wt-core"
    return
  fi
  if [[ "\$1" == "--dev" ]]; then
    echo "Already in dev mode: $local_script"
    return
  fi

  local output=\$(WT_WRAPPED=1 "$local_script" "\$@")
  local target=""
  local claude_cmd=""

  while IFS= read -r line; do
    if [[ "\$line" == CLAUDE:* ]]; then
      claude_cmd="\$line"
    elif [[ -n "\$line" && -d "\$line" ]]; then
      target="\$line"
    fi
  done <<< "\$output"

  if [[ -n "\$target" ]]; then
    local current_wt=\$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "\$current_wt" && "\$current_wt" != "\$target" ]]; then
      echo "\$current_wt" > ~/.wt_prev
    fi
    cd "\$target"
    echo "Navigated to: \$target"
  fi
}
echo "Switched to dev mode: $local_script"
EOF
  exit 0
fi

if [[ "$1" == "--shell-init" ]]; then
  cat <<'EOF'
# wt - Git Worktree Manager
unalias wt 2>/dev/null
function wt() {
  # Handle --dev: switch to local script from current worktree
  if [[ "$1" == "--dev" ]]; then
    local local_script="$(git rev-parse --show-toplevel 2>/dev/null)/wt.sh"
    if [[ -f "$local_script" ]]; then
      eval "$("$local_script" --dev)"
      echo "Switched to dev mode: $local_script"
    else
      echo "No wt.sh found in current worktree" >&2
    fi
    return
  fi
  # Handle --release: switch back to wt-core from PATH
  if [[ "$1" == "--release" ]]; then
    eval "$(wt-core --shell-init)"
    echo "Switched to release mode: wt-core"
    return
  fi

  local output=$(WT_WRAPPED=1 wt-core "$@")
  local target=""
  local claude_cmd=""

  while IFS= read -r line; do
    if [[ "$line" == CLAUDE:* ]]; then
      claude_cmd="$line"
    elif [[ -n "$line" && -d "$line" ]]; then
      target="$line"
    fi
  done <<< "$output"

  if [[ -n "$target" ]]; then
    # Save current worktree before switching (for wt -)
    # Only save if we're in a git worktree (don't save random dirs)
    local current_wt=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$current_wt" && "$current_wt" != "$target" ]]; then
      echo "$current_wt" > ~/.wt_prev
    fi
    local _wt_auto_cd=true
    if [[ -f "${HOME}/.config/wt/config" ]]; then
      local _val
      _val=$(grep '^WT_AUTO_CD=' "${HOME}/.config/wt/config" 2>/dev/null | cut -d= -f2 | tr -d "\"'")
      [[ "$_val" == "false" ]] && _wt_auto_cd=false
    fi
    if [[ "$_wt_auto_cd" == "true" ]]; then
      cd "$target"
      echo "Navigated to: $target"
    fi

    # Launch claude if marker present
    # Formats: CLAUDE:type:num:mode or CLAUDE:issue-auto:num
    if [[ -n "$claude_cmd" && "$claude_cmd" == CLAUDE:* ]]; then
      local type=$(echo "$claude_cmd" | cut -d: -f2)
      local num=$(echo "$claude_cmd" | cut -d: -f3)
      local mode=$(echo "$claude_cmd" | cut -d: -f4)

      local claude_flags=""
      local prompt=""
      local pr_term=$(wt-core --get-pr-term 2>/dev/null || echo "PR")

      # Handle auto-resolve (always forced, no mode param)
      if [[ "$type" == "issue-auto" ]]; then
        claude_flags="--dangerously-skip-permissions"
        echo ""
        echo ">> AUTO-RESOLVE: Issue #$num"
        echo "   Claude will plan, implement, and create a $pr_term automatically."
        echo ""

      elif [[ "$type" == "ci-fix" ]]; then
        claude_flags="--dangerously-skip-permissions"
        echo ""
        echo ">> AUTO-FIX CI: $pr_term #$num"
        echo "   Claude will fetch CI logs, fix the issues, and push."
        echo ""

      else
        # Build flags based on mode
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
      prompt=$(wt-core --generate-prompt "$type" "$num")
      [[ -n "$prompt" ]] && claude $claude_flags "$prompt"
    fi
  fi
}
EOF
  exit 0
fi

# Switch to dev mode (use local script instead of wt-core)
if [[ "$1" == "--dev" ]]; then
  # Find wt.sh in current worktree
  local_script="$(git rev-parse --show-toplevel 2>/dev/null)/wt.sh"
  if [[ ! -f "$local_script" ]]; then
    echo "No wt.sh found in current worktree" >&2
    exit 1
  fi
  echo "# wt dev mode: $local_script"
  "$local_script" --shell-init | sed "s|wt-core|$local_script|g"
  exit 0
fi

# Switch back to release mode (use wt-core from PATH)
if [[ "$1" == "--release" ]]; then
  echo "# wt release mode: wt-core"
  wt-core --shell-init
  exit 0
fi

if [[ "$1" == "--setup" ]]; then
  # Colors for setup (defined early since msg() isn't available yet)
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    _GREEN=$'\033[32m'
    _RED=$'\033[31m'
    _RESET=$'\033[0m'
  else
    _GREEN='' _RED='' _RESET=''
  fi
  _msg() { echo -e "$@" >&2; }

  _msg ""
  _msg "wt setup"
  _msg "--------"
  _msg ""

  # Detect shell
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)
      _msg "[!!] Unsupported shell: $shell_name"
      _msg "     Supported: zsh, bash"
      exit 1
      ;;
  esac
  _msg "[ok] Shell: $shell_name"
  _msg "[ok] Config: $rc_file"
  _msg ""

  # Check dependencies
  _msg "Dependencies:"
  deps_ok=true
  for dep in fzf gum jq; do
    if command -v "$dep" &>/dev/null; then
      _msg "  ${_GREEN}●${_RESET} $dep  installed"
    else
      _msg "  ${_RED}●${_RESET} $dep  ${_RED}missing${_RESET} — install with: brew install $dep"
      deps_ok=false
    fi
  done
  for dep in gh glab claude; do
    if command -v "$dep" &>/dev/null; then
      _msg "  ${_GREEN}●${_RESET} $dep  installed"
    else
      _msg "  ○ $dep  optional"
    fi
  done
  _msg ""

  if [[ "$deps_ok" == false ]]; then
    _msg "[!!] Install required dependencies first"
    exit 1
  fi

  # Check if wt-core is available
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if ! command -v wt-core &>/dev/null; then
    _msg "Setting up wt-core command..."

    # Determine install location
    if [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
      install_dir="/usr/local/bin"
    elif [[ -d "$HOME/.local/bin" ]]; then
      install_dir="$HOME/.local/bin"
    else
      mkdir -p "$HOME/.local/bin"
      install_dir="$HOME/.local/bin"
    fi

    # Create symlink
    ln -sf "$script_path" "$install_dir/wt-core"
    _msg "[ok] Created: $install_dir/wt-core -> $script_path"

    # Check if install_dir is in PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
      _msg ""
      _msg "[!!] $install_dir is not in your PATH"
      _msg "     Add this to your $rc_file:"
      _msg ""
      _msg "     export PATH=\"$install_dir:\$PATH\""
      _msg ""
    fi
  else
    _msg "[ok] wt-core already in PATH"
  fi

  # Check if already configured
  init_line='command -v wt-core &>/dev/null && eval "$(wt-core --shell-init)"'
  if grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
    _msg "[ok] Already configured in $rc_file"
  else
    _msg ""
    _msg "Adding wt to $rc_file..."
    echo "" >> "$rc_file"
    echo "# wt - Git Worktree Manager" >> "$rc_file"
    echo "$init_line" >> "$rc_file"
    _msg "[ok] Added to $rc_file"
  fi

  _msg ""
  _msg "--------"
  _msg "${_GREEN}Setup complete!${_RESET}"
  _msg ""
  _msg "To activate now, run:"
  _msg ""
  _msg "  source $rc_file"
  _msg ""
  _msg "Or restart your terminal."
  _msg ""
  exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat >&2 <<EOF
wt - Git Worktree Manager with fzf

Usage: wt [options] [name]

Arguments:
  name             Quick switch: fuzzy match on worktrees
  -                Switch to previous worktree (like cd -)
  .                Switch to main worktree

Options:
  --help, -h       Show this help message
  --version, -v    Show version number
  --setup          Install wt (add to shell, create symlinks)
  --wizard         Re-run the first-time setup wizard
  --update         Update wt to the latest version
  --dev            Switch to dev mode (use wt.sh from current worktree)
  --release        Switch back to release mode (use wt-core from PATH)

Keyboard shortcuts:
  Ctrl+E           Open in editor
  Ctrl+N           New worktree
  Ctrl+P           List PRs/MRs
  Ctrl+G           List issues
  Ctrl+D           Delete worktree(s)

Features:
  - Create worktrees from branch, PR/MR, or issue
  - GitHub (gh) and GitLab (glab) support with auto-detection
  - Multi-select delete with Space
  - Dirty indicator (*) for uncommitted changes
  - Claude Code integration (forced/ask/plan modes)

Platform detection:
  Auto-detected from git remote URL (gitlab.* -> GitLab, else GitHub).
  Override with: WT_PLATFORM=github|gitlab

Quick start:
  wt --setup       One-time installation
  wt               Interactive menu
  wt <name>        Quick switch to worktree
  wt -             Switch to previous worktree (like cd -)
  wt .             Switch to main worktree

Dependencies: fzf, gum, jq (required), gh/glab, claude (optional)
EOF
  exit 0
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Vérifier qu'on est dans un repo git (sauf pour wt -)
  if [[ "$1" != "-" ]] && ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not in a git repository" >&2
    exit 1
  fi
  
  # REPO_ROOT = worktree actuel (peut être secondaire)
  # MAIN_REPO = worktree principal (toujours le premier dans la liste)
  REPO_ROOT=$(git rev-parse --show-toplevel)
  MAIN_REPO=$(git worktree list --porcelain | grep "^worktree " | head -1 | cut -d' ' -f2-)
  REPO_NAME=$(basename "$MAIN_REPO")
  SCRIPT_PATH="${BASH_SOURCE[0]}"
fi


# =============================================================================
# Source lib/ modules
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# Nix install: lib/ is a sibling of bin/, not inside bin/
if [[ ! -d "$LIB_DIR" ]]; then
  LIB_DIR="$(dirname "$SCRIPT_DIR")/lib/wt"
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/git.sh"
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/prompts.sh"
source "$LIB_DIR/menus.sh"
source "$LIB_DIR/stash.sh"

# =============================================================================
# Menu principal
# =============================================================================

main_menu() {
  local missing_deps=()
  has_fzf || missing_deps+=("fzf")
  has_gum || missing_deps+=("gum")
  has_jq  || missing_deps+=("jq")
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    msg_error "Missing required dependencies: ${missing_deps[*]}"
    msg "Install with: brew install ${missing_deps[*]}"
    exit 1
  fi

  # Display logo on first launch
  print_logo

  while true; do
    local worktrees_formatted=$(format_all_worktrees)
    local secondary_count=$(get_secondary_worktrees | wc -l | tr -d ' ')
    local worktree_count=$(get_worktrees | wc -l | tr -d ' ')

    # Construire les actions
    local actions=""
    actions+=$'\n'""  # Ligne vide comme séparateur
    actions+=$'\n'"${C_GREEN}+${C_RESET} Create a worktree"
    actions+=$'\n'"${C_ORANGE}⧉${C_RESET} Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"${C_RED}✕${C_RESET} Delete worktree(s)"
    fi
    actions+=$'\n'"${C_DIM}⚙${C_RESET} Settings"
    actions+=$'\n'"${C_DIM}↩${C_RESET} Quit"

    local menu="${worktrees_formatted}${actions}"

    # Header avec nom du repo
    local pr_term=$(get_pr_term)
    local header="${C_ORANGE}wt${C_RESET} ${C_DIM}v${VERSION}${C_RESET} ${C_DIM}│${C_RESET} ${C_BOLD}${REPO_NAME}${C_RESET}"
    local footer="^E editor │ ^N new │ ^P ${pr_term}s │ ^G issues │ ^D delete"

    local result=$(echo "$menu" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --ansi \
          --delimiter=$'\t' \
          --with-nth=1 \
          --header="$header" \
          --footer="$footer" \
          --expect=ctrl-e,ctrl-n,ctrl-p,ctrl-g,ctrl-d \
          --preview="
            line={}
            # Skip divider
            if [[ \"\$line\" == \"<<>>\"* ]]; then
              exit 0
            fi
            # Clean line (remove icon only for actions, not worktrees)
            if [[ \"\$line\" == \"+\"* || \"\$line\" == \"⧉\"* || \"\$line\" == \"✕\"* || \"\$line\" == \"↩\"* || \"\$line\" == \"⚙\"* ]]; then
              clean_line=\$(echo \"\$line\" | sed -E 's/^[^A-Za-z]*//')
            else
              clean_line=\"\$line\"
            fi
            if [[ \"\$clean_line\" == \"Quit\"* ]]; then
              echo '> Exit wt'
            elif [[ \"\$clean_line\" == \"Create\"* ]]; then
              echo '> Create a new worktree'
              echo ''
              echo 'Options:'
              echo '  - New branch'
              echo '  - From existing branch'
              echo '  - From current (quick copy)'
              echo '  - From issue'
              echo '  - From $pr_term'
              echo ''
              echo 'Tip: ^N for quick access'
            elif [[ \"\$clean_line\" == \"Delete\"* ]]; then
              echo '> Delete worktree(s)'
              echo ''
              echo 'Select one or multiple worktrees to delete.'
              echo 'Use Space to toggle selection.'
              echo ''
              echo 'Secondary worktrees ($secondary_count):'
              /usr/bin/git worktree list --porcelain | /usr/bin/grep '^worktree ' | /usr/bin/cut -d' ' -f2- | /usr/bin/tail -n +2 | while read wt; do
                echo \"  - \${wt/#\$HOME/~}\"
              done
            elif [[ \"\$clean_line\" == \"Manage stashes\"* ]]; then
              echo '> Manage git stashes'
              echo ''
              stash_count=\$(/usr/bin/git stash list 2>/dev/null | wc -l | tr -d ' ')
              echo \"Current stashes: \$stash_count\"
              echo ''
              if [[ \$stash_count -gt 0 ]]; then
                /usr/bin/git stash list 2>/dev/null | /usr/bin/head -5
              else
                echo 'No stashes found'
              fi
            elif [[ \"\$clean_line\" == \"Settings\"* ]]; then
              echo '> Manage wt preferences'
              echo ''
              echo 'Configure:'
              echo '  IDE, Platform, Worktree dir'
              echo '  Auto-CD, Feature prefix'
              echo '  Auto-fetch, Claude mode'
              echo '  PR/Issue limit'
              echo ''
              echo 'Config: ~/.config/wt/config'
            else
              path=\$(echo \"\$line\" | /usr/bin/awk -F'\t' '{print \$2}' | /usr/bin/sed \"s|^~|\$HOME|\")
              if [[ -d \"\$path\" ]]; then
                branch=\$(/usr/bin/git -C \"\$path\" branch --show-current 2>/dev/null || echo 'detached')
                default_branch=\$(/usr/bin/git -C \"$MAIN_REPO\" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | /usr/bin/sed 's@^refs/remotes/origin/@@')
                [[ -z \"\$default_branch\" ]] && default_branch=\"main\"

                # Header with merge status
                printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                if [[ \"\$branch\" != \"\$default_branch\" && \"\$branch\" != \"detached\" ]]; then
                  if /usr/bin/git -C \"$MAIN_REPO\" branch --merged \"\$default_branch\" 2>/dev/null | /usr/bin/grep -qE \"^[[:space:]*+]*\$branch\$\"; then
                    printf '  Branch: %s  \033[32m✓ merged\033[0m\n' \"\$branch\"
                  else
                    printf '  Branch: %s  \033[33m○ not merged\033[0m\n' \"\$branch\"
                  fi
                else
                  printf '  Branch: %s\n' \"\$branch\"
                fi
                printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'

                # Uncommitted changes
                changes=\$(/usr/bin/git -C \"\$path\" status --porcelain 2>/dev/null)
                if [[ -n \"\$changes\" ]]; then
                  printf '  \033[33mUncommitted changes:\033[0m\n'
                  echo \"\$changes\" | /usr/bin/head -8
                  echo ''
                fi

                # Sync status with remote
                tracking=\$(/usr/bin/git -C \"\$path\" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
                if [[ -n \"\$tracking\" ]]; then
                  ahead=\$(/usr/bin/git -C \"\$path\" rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
                  behind=\$(/usr/bin/git -C \"\$path\" rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)
                  if [[ \$ahead -gt 0 && \$behind -gt 0 ]]; then
                    printf '  ↑%s ↓%s  (diverged from %s)\n' \"\$ahead\" \"\$behind\" \"\$tracking\"
                  elif [[ \$ahead -gt 0 ]]; then
                    printf '  ↑%s ahead of %s\n' \"\$ahead\" \"\$tracking\"
                  elif [[ \$behind -gt 0 ]]; then
                    printf '  ↓%s behind %s\n' \"\$behind\" \"\$tracking\"
                  else
                    printf '  ✓ In sync with %s\n' \"\$tracking\"
                  fi
                  echo ''
                fi

                # Recent commits
                printf '  Recent commits:\n'
                /usr/bin/git -C \"\$path\" log --oneline --graph --color=always -8 2>/dev/null
                echo ''

                # PR/MR status (at the end, can be slow)
                if [[ \"\$branch\" != \"\$default_branch\" && \"\$branch\" != \"detached\" ]]; then
                  bash \"$SCRIPT_PATH\" --pr-status-preview \"\$branch\"
                fi
              else
                echo 'Invalid path'
              fi
            fi
          " \
          --preview-window=right:50%)

    # Parse key and selection from fzf --expect output
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    # Handle keyboard shortcuts
    case "$key" in
      ctrl-e)
        if [[ -n "$selected" && "$selected" != "───"* && "$selected" != "+"* && "$selected" != "⧉"* && "$selected" != "✕"* && "$selected" != "↩"* && "$selected" != "⚙"* ]]; then
          local path=$(echo "$selected" | awk -F'\t' '{print $2}' | sed "s|^~|$HOME|")
          if [[ -d "$path" ]]; then
            local editor=$(get_editor)
            msg "Opening in $editor: $path"
            "$editor" "$path" &
          fi
        fi
        continue
        ;;
      ctrl-n)
        local output
        output=$(menu_create_worktree)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-p)
        local output
        output=$(menu_review_pr)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-g)
        local output
        output=$(menu_from_issue)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-d)
        local path
        path=$(action_delete_worktrees)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        continue
        ;;
    esac

    # If fzf was cancelled (Escape/Ctrl+C) and no shortcut was pressed, exit
    if [[ -z "$key" && ( -z "$selected" || "$selected" =~ ^[[:space:]]*$ ) ]]; then
      return 0
    fi

    # Skip divider line
    if [[ "$selected" == "<<>>"* ]]; then
      continue
    fi

    # Clean action lines (remove icon only for actions, not worktrees)
    local clean_selected
    if [[ "$selected" == "+"* || "$selected" == "⧉"* || "$selected" == "✕"* || "$selected" == "↩"* || "$selected" == "⚙"* ]]; then
      clean_selected=$(echo "$selected" | sed -E 's/^[^A-Za-z]*//')
    else
      clean_selected="$selected"
    fi

    case "$clean_selected" in
      "Create"*)
        local output
        output=$(menu_create_worktree)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        ;;
      "Manage stashes"*)
        menu_stash
        ;;
      "Settings"*)
        menu_settings
        ;;
      "Delete"*)
        local path
        path=$(action_delete_worktrees)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        ;;
      "Quit"|"")
        return 0
        ;;
      *)
        # C'est un worktree existant - extraire et retourner le path
        local path=$(echo "$selected" | awk -F'\t' '{print $2}' | sed "s|^~|$HOME|")
        if [[ -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        ;;
    esac
  done
}

# =============================================================================
# Point d'entrée
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

load_config

if [[ "$1" == "--wizard" ]]; then
  rm -f "$WT_CONFIG_FILE"
  run_preferences_wizard
  exit 0
fi

if [[ "$1" == "--pr-preview" ]]; then
  pr_preview "$2"
  exit 0
fi

if [[ "$1" == "--issue-preview" ]]; then
  issue_preview "$2"
  exit 0
fi

if [[ "$1" == "--pr-status-preview" ]]; then
  cli_pr_status "$2"
  exit 0
fi

if [[ "$1" == "--generate-prompt" ]]; then
  generate_prompt "$2" "$3"
  exit 0
fi

if [[ "$1" == "--get-pr-term" ]]; then
  get_pr_term
  exit 0
fi

if [[ "$1" == "--get-platform-name" ]]; then
  get_platform_name
  exit 0
fi

# Switch to previous worktree (like cd -)
if [[ "$1" == "-" ]]; then
  if [[ -f ~/.wt_prev ]]; then
    prev=$(cat ~/.wt_prev)
    if [[ -d "$prev" ]]; then
      echo "$prev"
      exit 0
    else
      msg "Previous worktree no longer exists: $prev"
      exit 1
    fi
  else
    msg "No previous worktree (run 'wt --setup' to enable this feature)"
    exit 1
  fi
fi

# Switch to main worktree
if [[ "$1" == "." ]]; then
  main_wt=$(git worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2-)
  if [[ -n "$main_wt" && -d "$main_wt" ]]; then
    echo "$main_wt"
    exit 0
  else
    msg "Could not find main worktree"
    exit 1
  fi
fi

# Quick switch: wt <name> fuzzy matches on worktrees
if [[ -n "$1" && "$1" != "--"* ]]; then
  # Format worktrees for matching
  worktrees_list=$(format_all_worktrees)
  match=$(echo "$worktrees_list" | fzf --filter="$1" | head -1)
  if [[ -n "$match" ]]; then
    path=$(echo "$match" | awk -F'\t' '{print $2}' | sed "s|^~|$HOME|")
    if [[ -d "$path" ]]; then
      echo "$path"
      exit 0
    fi
  fi
  msg "No worktree matching '$1'"
  exit 1
fi

# First-time setup wizard
if [[ -z "$1" ]] && [[ -t 2 ]]; then
  if ! command -v wt-core &>/dev/null; then
    run_install_wizard || true
  elif [[ ! -f "$WT_CONFIG_FILE" ]]; then
    run_preferences_wizard
  fi
fi

# Run main menu and capture result
result=$(main_menu)

if [[ -n "$result" ]]; then
  echo "$result"
fi


fi
