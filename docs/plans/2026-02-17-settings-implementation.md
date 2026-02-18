# Settings Section Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persistent settings system to `wt` with a unified first-time setup wizard and an interactive Settings menu in the main fzf interface.

**Architecture:** Single config file `~/.config/wt/config` with `KEY=VALUE` format, sourced at startup via `load_config()`. A unified wizard runs on first launch (Phase 1: install check, Phase 2: preferences). Settings are editable at any time via `⚙ Settings` in the main menu.

**Tech Stack:** bash, fzf (already used throughout), single-file project (`wt.sh`)

---

## Key File: `wt.sh`

All changes are in a single file. Key line anchors:
- Line ~395: Helpers section (`has_fzf`, `get_editor`, etc.) — add config functions here
- Line ~411: `get_editor()` — modify to check `WT_EDITOR` first
- Line ~507: `cli_pr_list()` — uses `--per-page 20` (GitLab)
- Line ~562: `cli_issue_list()` — uses `--per-page 20` / `--limit 20`
- Line ~1111: `select_claude_mode()` — add `WT_CLAUDE_MODE` bypass
- Line ~1221: `create_from_branch()` — git fetch (check WT_AUTO_FETCH)
- Line ~1269: second git fetch in create branch — same
- Line ~1373: `create_from_issue()` — hardcoded `feature/` prefix
- Line ~1385: worktree path in `create_from_issue()` — add WT_WORKTREE_DIR support
- Line ~2727: `main_menu()` — add `⚙ Settings` entry
- Line ~2980: Entry point — add load_config + wizard trigger
- Line ~24: Shell wrapper (--shell-init output) — add WT_AUTO_CD check

## Testing

**How to test the wizard during dev:**
```bash
# Trigger preferences wizard only
rm ~/.config/wt/config && wt

# Force wizard re-run
wt --wizard

# Test install wizard (simulates fresh install)
# Temporarily rename wt-core in /usr/local/bin, then run ./wt.sh
```

---

## Task 1: Config infrastructure

**Files:** Modify `wt.sh`

**Step 1: Add `WT_CONFIG_FILE` constant and `load_config()` function**

Find the line `has_fzf() {` (around line 399) and add BEFORE it:

```bash
# =============================================================================
# Config
# =============================================================================

WT_CONFIG_FILE="${HOME}/.config/wt/config"

load_config() {
  [[ -f "$WT_CONFIG_FILE" ]] && source "$WT_CONFIG_FILE"
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
    cat > "$WT_CONFIG_FILE" << 'EOF'
# wt — user configuration
# Edit manually or via: wt > ⚙ Settings
EOF
  fi

  # Update or append the key
  if grep -q "^${key}=" "$WT_CONFIG_FILE" 2>/dev/null; then
    # Replace existing key (macOS-compatible sed)
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$WT_CONFIG_FILE"
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
```

**Step 2: Call `load_config()` at the entry point**

Find the comment `# Run main menu and capture result` (around line 3059) and add BEFORE it:

```bash
# Load user configuration
load_config
```

**Step 3: Verify the script still runs**
```bash
./wt.sh --version
# Expected: wt 1.7.1
```

**Step 4: Commit**
```bash
git add wt.sh
git commit -m "feat: add config infrastructure (load_config, save_config_value)"
```

---

## Task 2: Integrate WT_EDITOR into get_editor()

**Files:** Modify `wt.sh` (~line 411)

**Step 1: Modify `get_editor()` to check config first**

Find:
```bash
get_editor() {
  if command -v cursor &>/dev/null; then echo "cursor"
  elif command -v code &>/dev/null; then echo "code"
  elif [[ -n "$EDITOR" ]]; then echo "$EDITOR"
  else echo "vim"
  fi
}
```

Replace with:
```bash
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
```

**Step 2: Test manually**
```bash
# Set WT_EDITOR in a test config
echo "WT_EDITOR=vim" > ~/.config/wt/config
wt  # Press Ctrl+E on a worktree — should open vim
rm ~/.config/wt/config
```

**Step 3: Commit**
```bash
git add wt.sh
git commit -m "feat: get_editor respects WT_EDITOR config"
```

---

## Task 3: Integrate WT_LIST_LIMIT into cli_pr_list() and cli_issue_list()

**Files:** Modify `wt.sh` (~lines 507, 562)

**Step 1: Update `cli_pr_list()` — GitLab branch (line ~507)**

Find: `glab mr list --per-page 20 -F json`
Replace with: `glab mr list --per-page "${WT_LIST_LIMIT:-20}" -F json`

**Step 2: Update `cli_issue_list()` — GitLab branch (line ~562)**

Find: `glab issue list --per-page 20 -F json`
Replace with: `glab issue list --per-page "${WT_LIST_LIMIT:-20}" -F json`

**Step 3: Update `cli_issue_list()` — GitHub branch (line ~567)**

Find: `gh issue list --limit 20 --json`
Replace with: `gh issue list --limit "${WT_LIST_LIMIT:-20}" --json`

**Step 4: Commit**
```bash
git add wt.sh
git commit -m "feat: use WT_LIST_LIMIT for PR/issue list pagination"
```

---

## Task 4: Integrate WT_FEATURE_PREFIX into create_from_issue()

**Files:** Modify `wt.sh` (~line 1373)

**Step 1: Use WT_FEATURE_PREFIX in branch name**

Find:
```bash
  local base_branch_name="feature/${issue_num}-${slug}"
```

Replace with:
```bash
  local _feature_prefix="${WT_FEATURE_PREFIX:-feature/}"
  local base_branch_name="${_feature_prefix}${issue_num}-${slug}"
```

**Step 2: Commit**
```bash
git add wt.sh
git commit -m "feat: use WT_FEATURE_PREFIX for issue branch naming"
```

---

## Task 5: Integrate WT_AUTO_FETCH into git fetch calls

**Files:** Modify `wt.sh` (~lines 1221, 1269)

**Step 1: Wrap first `git fetch --all --prune` in create_from_branch() (line ~1221)**

Find:
```bash
  msg "Fetching branches..."
  git fetch --all --prune >/dev/null 2>&1
```
(first occurrence, ~line 1220)

Replace with:
```bash
  if [[ "${WT_AUTO_FETCH:-true}" != "false" ]]; then
    msg "Fetching branches..."
    git fetch --all --prune >/dev/null 2>&1
  fi
```

**Step 2: Wrap second occurrence (~line 1268)**

Find the second:
```bash
  msg "Fetching branches..."
  git fetch --all --prune >/dev/null 2>&1
```

Replace with the same pattern:
```bash
  if [[ "${WT_AUTO_FETCH:-true}" != "false" ]]; then
    msg "Fetching branches..."
    git fetch --all --prune >/dev/null 2>&1
  fi
```

**Step 3: Commit**
```bash
git add wt.sh
git commit -m "feat: respect WT_AUTO_FETCH setting before git fetch"
```

---

## Task 6: Integrate WT_CLAUDE_MODE into select_claude_mode()

**Files:** Modify `wt.sh` (~line 1111)

**Step 1: Add early return in `select_claude_mode()` if mode is configured**

Find the start of `select_claude_mode()`:
```bash
select_claude_mode() {
  local context_type="$1"  # pr-review, pr-work, issue-work
  local context_num="$2"

  local title
```

Add after the first two lines:
```bash
select_claude_mode() {
  local context_type="$1"  # pr-review, pr-work, issue-work
  local context_num="$2"

  # If a default mode is configured, bypass the picker
  if [[ -n "${WT_CLAUDE_MODE:-}" ]]; then
    case "$WT_CLAUDE_MODE" in
      forced|ask|plan)
        echo "$WT_CLAUDE_MODE"
        return
        ;;
    esac
  fi

  local title
```

**Step 2: Verify behavior**
```bash
# Set mode in config
echo "WT_CLAUDE_MODE=plan" > ~/.config/wt/config
# Open wt, navigate to an issue, press "Launch Claude"
# It should skip the picker and use plan mode directly
rm ~/.config/wt/config
```

**Step 3: Commit**
```bash
git add wt.sh
git commit -m "feat: respect WT_CLAUDE_MODE config to bypass Claude picker"
```

---

## Task 7: Integrate WT_WORKTREE_DIR into worktree creation

**Files:** Modify `wt.sh` (~lines 1203, 1385, ~1300)

The current pattern for worktree path is: `$(dirname "$MAIN_REPO")/${worktree_name}`

Create a helper function to get the worktree base directory.

**Step 1: Add `get_worktree_base_dir()` helper in the Helpers section (after `get_config_value`):**

```bash
get_worktree_base_dir() {
  if [[ -n "${WT_WORKTREE_DIR:-}" ]]; then
    # Expand ~ if present
    echo "${WT_WORKTREE_DIR/#\~/$HOME}"
  else
    echo "$(dirname "$MAIN_REPO")"
  fi
}
```

**Step 2: Use `get_worktree_base_dir()` in `create_from_current()` (~line 1203)**

Find: `local worktree_path="$(dirname "$MAIN_REPO")/${worktree_name}"`
Replace with: `local worktree_path="$(get_worktree_base_dir)/${worktree_name}"`

**Step 3: Use `get_worktree_base_dir()` in `create_from_issue()` (~line 1385)**

Find: `local worktree_path="$(dirname "$MAIN_REPO")/${REPO_NAME}-${sanitized}"`
Replace with: `local worktree_path="$(get_worktree_base_dir)/${REPO_NAME}-${sanitized}"`

**Step 4: Find any other `$(dirname "$MAIN_REPO")/` patterns used for worktree paths**
```bash
grep -n 'dirname.*MAIN_REPO' wt.sh
```
Apply the same replacement to any remaining occurrences that are worktree paths (not repo detection).

**Step 5: Commit**
```bash
git add wt.sh
git commit -m "feat: use WT_WORKTREE_DIR as base path for new worktrees"
```

---

## Task 8: Integrate WT_AUTO_CD into shell wrapper

**Files:** Modify `wt.sh` (~line 24 — the --shell-init output section)

The shell wrapper function (lines ~24-163 in the heredoc) needs to read `WT_AUTO_CD` from the config file and conditionally skip the `cd "$target"`.

**Step 1: Find the cd in the shell wrapper**

Find in the heredoc (around the section starting `if [[ -n "\$target" ]]; then`):
```bash
    cd "\$target"
    echo "Navigated to: \$target"
```

Replace with:
```bash
    local _wt_auto_cd=true
    if [[ -f "\${HOME}/.config/wt/config" ]]; then
      local _val
      _val=\$(grep '^WT_AUTO_CD=' "\${HOME}/.config/wt/config" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"')
      [[ "\$_val" == "false" ]] && _wt_auto_cd=false
    fi
    if [[ "\$_wt_auto_cd" == "true" ]]; then
      cd "\$target"
      echo "Navigated to: \$target"
    fi
```

**Note:** This is in a heredoc, so escaping is critical. The `\$` escaping must be correct. Test carefully.

**Step 2: Test**
```bash
echo "WT_AUTO_CD=false" > ~/.config/wt/config
# Source the new shell function (restart terminal or re-eval --shell-init)
eval "$(./wt.sh --shell-init)"
wt  # Select a worktree — should NOT cd
rm ~/.config/wt/config
```

**Step 3: Commit**
```bash
git add wt.sh
git commit -m "feat: respect WT_AUTO_CD setting in shell wrapper"
```

---

## Task 9: Preferences wizard (run_preferences_wizard)

**Files:** Modify `wt.sh` — add before `main_menu()` (~line 2724)

**Step 1: Add `run_preferences_wizard()` function**

```bash
# =============================================================================
# First-time Preferences Wizard
# =============================================================================

run_preferences_wizard() {
  # Detect available editors
  local available_editors=()
  command -v cursor &>/dev/null && available_editors+=("cursor")
  command -v code &>/dev/null && available_editors+=("code")
  command -v nvim &>/dev/null && available_editors+=("nvim")
  command -v vim &>/dev/null && available_editors+=("vim")
  # Always offer custom
  available_editors+=("custom...")

  # Build editor list for fzf
  local editor_options=""
  local detected_label=""
  for ed in "${available_editors[@]}"; do
    if [[ "$ed" == "custom..." ]]; then
      editor_options+="${ed}"$'\n'
    else
      detected_label=" ${C_DIM}(detected)${C_RESET}"
      editor_options+="${ed}${detected_label}"$'\n'
    fi
  done
  editor_options="${editor_options%$'\n'}"

  # Step 1: IDE
  local header_step1="${C_BOLD}Step 1/2 — Preferred editor${C_RESET}  ${C_DIM}^S skip${C_RESET}"
  local ide_result
  ide_result=$(printf '%s\n' "${available_editors[@]}" | \
    fzf --height=40% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header_step1" \
        --expect=ctrl-s \
        --preview='
          case {} in
            cursor*) echo "Cursor AI Editor"
                     echo ""
                     echo "AI-powered fork of VS Code"
                     echo "from Cursor.sh"
                     ;;
            code*)   echo "Visual Studio Code"
                     echo ""
                     echo "Microsoft'\''s open-source editor"
                     ;;
            nvim*)   echo "Neovim"
                     echo ""
                     echo "Hyperextensible Vim-based editor"
                     ;;
            vim*)    echo "Vim"
                     echo ""
                     echo "Classic terminal editor"
                     ;;
            custom*) echo "Custom editor"
                     echo ""
                     echo "Enter your editor command"
                     echo "(e.g. emacs, nano, subl)"
                     ;;
          esac
          echo ""
          echo "Used when pressing Ctrl+E"
          echo "in the worktree menu."
        ' \
        --preview-window=right:40%)

  local ide_key ide_choice
  ide_key=$(echo "$ide_result" | head -1)
  ide_choice=$(echo "$ide_result" | tail -n +2)
  # Strip ANSI codes from choice
  ide_choice=$(echo "$ide_choice" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

  local selected_editor=""
  if [[ "$ide_key" != "ctrl-s" && -n "$ide_choice" ]]; then
    if [[ "$ide_choice" == "custom..." ]]; then
      msg ""
      msg "Enter your editor command (e.g. emacs, nano, subl):"
      read -r selected_editor </dev/tty
    else
      selected_editor="$ide_choice"
    fi
  fi

  # Step 2: Platform
  local header_step2="${C_BOLD}Step 2/2 — Git platform${C_RESET}  ${C_DIM}^S skip${C_RESET}"
  local current_remote_guess="github"
  local remote_url
  remote_url=$(git -C "${MAIN_REPO:-$PWD}" remote get-url origin 2>/dev/null || echo "")
  [[ "$remote_url" == *gitlab* ]] && current_remote_guess="gitlab"

  local platform_result
  platform_result=$(printf '%s\n' \
    "auto  ${C_DIM}(detect from remote URL)${C_RESET}" \
    "github" \
    "gitlab" | \
    fzf --height=30% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header_step2" \
        --expect=ctrl-s \
        --preview="
          case {} in
            auto*)
              echo 'auto (recommended)'
              echo ''
              echo 'Reads your git remote URL'
              echo 'to detect GitHub vs GitLab.'
              echo ''
              echo \"Detected for this repo: $current_remote_guess\"
              ;;
            github*)
              echo 'GitHub'
              echo ''
              echo 'Forces GitHub mode.'
              echo 'Uses: gh CLI'
              ;;
            gitlab*)
              echo 'GitLab'
              echo ''
              echo 'Forces GitLab mode.'
              echo 'Uses: glab CLI'
              ;;
          esac
        " \
        --preview-window=right:40%)

  local platform_key platform_choice
  platform_key=$(echo "$platform_result" | head -1)
  platform_choice=$(echo "$platform_result" | tail -n +2 | awk '{print $1}')

  local selected_platform="auto"
  if [[ "$platform_key" != "ctrl-s" && -n "$platform_choice" ]]; then
    selected_platform="$platform_choice"
  fi

  # Write config file
  mkdir -p "$(dirname "$WT_CONFIG_FILE")"
  cat > "$WT_CONFIG_FILE" << EOF
# wt — user configuration
# Edit manually or via: wt > ⚙ Settings

WT_EDITOR=${selected_editor}
WT_PLATFORM=${selected_platform}
WT_WORKTREE_DIR=
WT_AUTO_CD=true
WT_FEATURE_PREFIX=feature/
WT_AUTO_FETCH=true
WT_CLAUDE_MODE=
WT_LIST_LIMIT=20
EOF

  # Source the new config
  load_config

  # Success screen
  msg ""
  msg "  ╔══════════════════════════════════════╗"
  msg "  ║  ${C_GREEN}✓${C_RESET}  wt is configured                ║"
  msg "  ╠══════════════════════════════════════╣"
  msg "  ║                                      ║"
  msg "  ║  IDE         ${selected_editor:-auto-detect}$(printf '%*s' $((17 - ${#selected_editor:-auto-detect})) '')║"
  msg "  ║  Platform    ${selected_platform}$(printf '%*s' $((19 - ${#selected_platform})) '')║"
  msg "  ║                                      ║"
  msg "  ║  Config → ~/.config/wt/config        ║"
  msg "  ║                                      ║"
  msg "  ║  Tip: wt > ⚙ Settings to change      ║"
  msg "  ║                                      ║"
  msg "  ╚══════════════════════════════════════╝"
  msg ""
  msg "  Launching wt..."
  msg ""
  sleep 1
}
```

**Step 2: Commit**
```bash
git add wt.sh
git commit -m "feat: add run_preferences_wizard function"
```

---

## Task 10: Install wizard (run_install_wizard)

**Files:** Modify `wt.sh` — add after `run_preferences_wizard()` and before `main_menu()`

**Step 1: Add `run_install_wizard()` function**

```bash
# =============================================================================
# First-time Install Wizard
# =============================================================================

run_install_wizard() {
  # Detect what needs to be installed
  local needs_symlink=false
  local needs_rc=false
  local install_dir="/usr/local/bin"
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if ! command -v wt-core &>/dev/null; then
    needs_symlink=true
    if [[ ! -d "/usr/local/bin" || ! -w "/usr/local/bin" ]]; then
      install_dir="${HOME}/.local/bin"
    fi
  fi

  local shell_name rc_file
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)    rc_file="$HOME/.profile" ;;
  esac

  local init_line='command -v wt-core &>/dev/null && eval "$(wt-core --shell-init)"'
  if ! grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
    needs_rc=true
  fi

  # If nothing to install, skip to preferences
  if [[ "$needs_symlink" == "false" && "$needs_rc" == "false" ]]; then
    run_preferences_wizard
    return
  fi

  # Build what-will-happen list
  local todo_list=""
  [[ "$needs_symlink" == "true" ]] && todo_list+="    ${C_DIM}→${C_RESET} Create symlink  ${C_CYAN}${install_dir}/wt-core${C_RESET}\n"
  [[ "$needs_rc" == "true" ]]      && todo_list+="    ${C_DIM}→${C_RESET} Add init line   ${C_CYAN}${rc_file}${C_RESET}\n"

  # Welcome screen
  msg ""
  msg "  ${C_BOLD}wt${C_RESET} needs a quick one-time setup."
  msg "  This will:"
  msg ""
  echo -e "$(echo -e "$todo_list")" >&2
  msg ""

  local confirm_result
  confirm_result=$(printf '%s\n' \
    "${C_GREEN}●${C_RESET} Yes, set it up" \
    "${C_DIM}○${C_RESET} No, skip for now" | \
    fzf --height=15% \
        --layout=reverse \
        --border \
        --ansi \
        --no-sort \
        --header="${C_BOLD}Install now?${C_RESET}")

  if [[ "$confirm_result" != *"Yes"* ]]; then
    msg ""
    msg "  Skipping install. Run: ${C_CYAN}./wt.sh --setup${C_RESET} to install later."
    msg ""
    return 1
  fi

  # Perform installation
  if [[ "$needs_symlink" == "true" ]]; then
    mkdir -p "$install_dir"
    ln -sf "$script_path" "${install_dir}/wt-core"
    msg "  ${C_GREEN}✓${C_RESET} Created: ${install_dir}/wt-core"
  fi

  if [[ "$needs_rc" == "true" ]]; then
    echo "" >> "$rc_file"
    echo "# wt - Git Worktree Manager" >> "$rc_file"
    echo "$init_line" >> "$rc_file"
    msg "  ${C_GREEN}✓${C_RESET} Added init line to ${rc_file}"
  fi

  msg ""
  msg "  ${C_BOLD}Installation complete!${C_RESET}"
  msg "  Run ${C_CYAN}source ${rc_file}${C_RESET} to activate (or restart your terminal)."
  msg ""
  sleep 1

  # Continue to preferences
  run_preferences_wizard
}
```

**Step 2: Commit**
```bash
git add wt.sh
git commit -m "feat: add run_install_wizard function"
```

---

## Task 11: Wizard trigger logic + `--wizard` flag

**Files:** Modify `wt.sh`

**Step 1: Add `--wizard` flag handler**

Find the block of `if [[ "$1" == "--pr-preview" ]]; then` flags (~line 2984). Add BEFORE it:

```bash
if [[ "$1" == "--wizard" ]]; then
  # Force re-run the preferences wizard regardless of existing config
  rm -f "$WT_CONFIG_FILE"
  run_preferences_wizard
  exit 0
fi
```

**Step 2: Add wizard trigger before `main_menu()`**

Find `# Run main menu and capture result` (~line 3059). The section should now look like:

```bash
# Load user configuration
load_config

# First-time setup wizard
if ! command -v wt-core &>/dev/null || [[ ! -f "$WT_CONFIG_FILE" ]]; then
  # Only show wizard if we're in interactive mode (not a sub-command call)
  if [[ -z "$1" || "$1" == "." || "$1" == "-" ]] && [[ -t 2 ]]; then
    if ! command -v wt-core &>/dev/null; then
      run_install_wizard || true
    elif [[ ! -f "$WT_CONFIG_FILE" ]]; then
      run_preferences_wizard
    fi
  fi
fi

# Run main menu and capture result
result=$(main_menu)
```

**Step 3: Also call `load_config` before the early flags that use config** (e.g., before `--pr-status-preview` which calls `detect_platform`)

Find the comment `# =============================================================================` just before `if [[ "$1" == "--pr-preview" ]];` and add before it:

```bash
# Load user configuration (needed for sub-commands that use platform detection)
load_config
```

Wait — this would double-load. Instead, restructure: move the `load_config` call to just before the entry point flags section. Find the `# Point d'entrée` comment (~line 2980) and add `load_config` right after.

**Step 4: Verify wizard triggers correctly**
```bash
# Test preferences wizard trigger
rm -f ~/.config/wt/config
wt  # Should show preferences wizard, then main menu

# Test --wizard flag
wt --wizard  # Should show preferences wizard directly

# Test normal operation (config exists)
wt  # Should go straight to main menu
```

**Step 5: Commit**
```bash
git add wt.sh
git commit -m "feat: add wizard trigger and --wizard flag"
```

---

## Task 12: Settings menu (menu_settings)

**Files:** Modify `wt.sh` — add before `main_menu()`

**Step 1: Add `menu_settings()` function**

This function shows all configurable settings in a fzf menu with preview. Each selection opens an edit picker.

```bash
# =============================================================================
# Settings Menu
# =============================================================================

menu_settings() {
  while true; do
    # Read current values
    local cur_editor="${WT_EDITOR:-$(get_editor) (auto)}"
    local cur_platform="${WT_PLATFORM:-auto}"
    local cur_worktree_dir="${WT_WORKTREE_DIR:-$(dirname "$MAIN_REPO") (default)}"
    local cur_auto_cd="${WT_AUTO_CD:-true}"
    local cur_feature_prefix="${WT_FEATURE_PREFIX:-feature/}"
    local cur_auto_fetch="${WT_AUTO_FETCH:-true}"
    local cur_claude_mode="${WT_CLAUDE_MODE:-prompt each time}"
    local cur_list_limit="${WT_LIST_LIMIT:-20}"

    local header="${C_BOLD}⚙ Settings${C_RESET}  ${C_DIM}Enter edit · ^R reset${C_RESET}"

    local options
    options=$(printf '%s\n' \
      "IDE              ${C_CYAN}${cur_editor}${C_RESET}" \
      "Platform         ${C_CYAN}${cur_platform}${C_RESET}" \
      "Worktree dir     ${C_CYAN}${cur_worktree_dir}${C_RESET}" \
      "Auto-CD          ${C_CYAN}${cur_auto_cd}${C_RESET}" \
      "Feature prefix   ${C_CYAN}${cur_feature_prefix}${C_RESET}" \
      "Auto-fetch       ${C_CYAN}${cur_auto_fetch}${C_RESET}" \
      "Claude mode      ${C_CYAN}${cur_claude_mode}${C_RESET}" \
      "PR/Issue limit   ${C_CYAN}${cur_list_limit}${C_RESET}" \
      "──────────────────────────────────────" \
      "↺ Reset to defaults")

    local result
    result=$(echo "$options" | \
      fzf --height=60% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
          --expect=ctrl-r \
          --preview='
            case {} in
              IDE*)
                echo "Preferred code editor"
                echo ""
                echo "Used when pressing Ctrl+E"
                echo "in the main worktree menu."
                echo ""
                echo "auto = detect cursor > code > \$EDITOR > vim"
                ;;
              Platform*)
                echo "Git hosting platform"
                echo ""
                echo "auto   = detect from remote URL"
                echo "github = force GitHub (gh CLI)"
                echo "gitlab = force GitLab (glab CLI)"
                ;;
              Worktree*)
                echo "Base directory for new worktrees"
                echo ""
                echo "default = created next to main repo"
                echo "custom  = any absolute path"
                ;;
              Auto-CD*)
                echo "Auto-navigate after worktree selection"
                echo ""
                echo "true  = cd to worktree on selection"
                echo "false = no automatic cd"
                ;;
              Feature*)
                echo "Branch prefix for issues"
                echo ""
                echo "Used when creating a worktree"
                echo "from a GitHub/GitLab issue."
                echo ""
                echo "Examples: feature/ feat/ task/"
                ;;
              Auto-fetch*)
                echo "Fetch before branch operations"
                echo ""
                echo "true  = git fetch --all before showing branches"
                echo "false = use cached branch list"
                ;;
              Claude*)
                echo "Default Claude launch mode"
                echo ""
                echo "prompt each time = show picker (default)"
                echo "forced           = always --dangerously-skip-permissions"
                echo "ask              = always interactive mode"
                echo "plan             = always --permission-mode=plan"
                ;;
              PR\/Issue*)
                echo "Max items in PR and issue lists"
                echo ""
                echo "Higher = more results, slower API call"
                echo "Lower  = fewer results, faster"
                ;;
              *Reset*)
                echo "Reset all settings to defaults"
                echo ""
                echo "This will overwrite ~/.config/wt/config"
                echo "with default values."
                ;;
            esac
          ' \
          --preview-window=right:45%)

    local key selected
    key=$(echo "$result" | head -1)
    selected=$(echo "$result" | tail -n +2)
    selected=$(echo "$selected" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

    # Ctrl+R: Reset to defaults
    if [[ "$key" == "ctrl-r" ]] || [[ "$selected" == "↺" ]]; then
      local confirm
      confirm=$(printf '%s\n' "Yes, reset everything" "No, cancel" | \
        fzf --height=15% --layout=reverse --border --ansi \
            --header="${C_BOLD}Reset all settings to defaults?${C_RESET}")
      if [[ "$confirm" == "Yes"* ]]; then
        rm -f "$WT_CONFIG_FILE"
        run_preferences_wizard
        load_config
        msg_success "Settings reset to defaults"
      fi
      continue
    fi

    [[ -z "$selected" ]] && return 0

    # Edit each setting
    case "$selected" in
      IDE)
        local editors=()
        command -v cursor &>/dev/null && editors+=("cursor")
        command -v code &>/dev/null && editors+=("code")
        command -v nvim &>/dev/null && editors+=("nvim")
        command -v vim &>/dev/null && editors+=("vim")
        editors+=("custom...")

        local choice
        choice=$(printf '%s\n' "${editors[@]}" | \
          fzf --height=30% --layout=reverse --border --ansi \
              --header="${C_BOLD}Select IDE${C_RESET}")
        if [[ -n "$choice" ]]; then
          if [[ "$choice" == "custom..." ]]; then
            msg "Enter editor command:"
            read -r choice </dev/tty
          fi
          [[ -n "$choice" ]] && save_config_value "WT_EDITOR" "$choice" && export WT_EDITOR="$choice"
        fi
        ;;
      Platform)
        local choice
        choice=$(printf '%s\n' "auto" "github" "gitlab" | \
          fzf --height=20% --layout=reverse --border --ansi \
              --header="${C_BOLD}Select platform${C_RESET}")
        [[ -n "$choice" ]] && save_config_value "WT_PLATFORM" "$choice" && export WT_PLATFORM="$choice" && _WT_PLATFORM="$choice"
        ;;
      Worktree)
        msg "Enter base directory for worktrees (empty = default):"
        local dir
        read -r dir </dev/tty
        save_config_value "WT_WORKTREE_DIR" "$dir"
        export WT_WORKTREE_DIR="$dir"
        ;;
      Auto-CD)
        local choice
        choice=$(printf '%s\n' "true" "false" | \
          fzf --height=15% --layout=reverse --border --ansi \
              --header="${C_BOLD}Auto-CD${C_RESET}")
        [[ -n "$choice" ]] && save_config_value "WT_AUTO_CD" "$choice" && export WT_AUTO_CD="$choice"
        ;;
      Feature)
        msg "Enter feature branch prefix (e.g. feature/, feat/, task/):"
        local prefix
        read -r prefix </dev/tty
        [[ -n "$prefix" ]] && save_config_value "WT_FEATURE_PREFIX" "$prefix" && export WT_FEATURE_PREFIX="$prefix"
        ;;
      Auto-fetch)
        local choice
        choice=$(printf '%s\n' "true" "false" | \
          fzf --height=15% --layout=reverse --border --ansi \
              --header="${C_BOLD}Auto-fetch${C_RESET}")
        [[ -n "$choice" ]] && save_config_value "WT_AUTO_FETCH" "$choice" && export WT_AUTO_FETCH="$choice"
        ;;
      Claude)
        local choice
        choice=$(printf '%s\n' \
          "prompt each time" \
          "forced (auto)" \
          "ask (interactive)" \
          "plan (plan first)" | \
          fzf --height=25% --layout=reverse --border --ansi \
              --header="${C_BOLD}Claude mode${C_RESET}")
        if [[ -n "$choice" ]]; then
          local mode_val=""
          case "$choice" in
            "forced"*) mode_val="forced" ;;
            "ask"*)    mode_val="ask" ;;
            "plan"*)   mode_val="plan" ;;
          esac
          save_config_value "WT_CLAUDE_MODE" "$mode_val"
          export WT_CLAUDE_MODE="$mode_val"
        fi
        ;;
      PR/Issue)
        msg "Enter max items in lists (default: 20):"
        local limit
        read -r limit </dev/tty
        if [[ "$limit" =~ ^[0-9]+$ ]]; then
          save_config_value "WT_LIST_LIMIT" "$limit"
          export WT_LIST_LIMIT="$limit"
        fi
        ;;
      "──────────────────────────────────────")
        continue
        ;;
    esac
  done
}
```

**Step 2: Commit**
```bash
git add wt.sh
git commit -m "feat: add menu_settings function"
```

---

## Task 13: Add ⚙ Settings to main_menu()

**Files:** Modify `wt.sh` (~line 2744-2756)

**Step 1: Add Settings entry to the actions list**

Find:
```bash
    actions+=$'\n'"${C_DIM}⬡${C_RESET} Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"${C_DIM}✕${C_RESET} Delete worktree(s)"
    fi
    actions+=$'\n'"${C_DIM}◀${C_RESET} Quit"
```

Replace with:
```bash
    actions+=$'\n'"${C_DIM}⬡${C_RESET} Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"${C_DIM}✕${C_RESET} Delete worktree(s)"
    fi
    actions+=$'\n'"${C_DIM}⚙${C_RESET} Settings"
    actions+=$'\n'"${C_DIM}◀${C_RESET} Quit"
```

**Step 2: Update the fzf preview for Settings**

In the large `--preview` block of `main_menu()`, find the `elif [[ "\$clean_line" == "Manage stashes"* ]]; then` section. Add after it:

```bash
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
```

**Step 3: Add Settings to the case handler**

Find:
```bash
      "Manage stashes"*)
        menu_stash
        ;;
      "Delete"*)
```

Add after the stash case:
```bash
      "Settings"*)
        menu_settings
        ;;
```

**Step 4: Also make Settings icon not conflict with worktree icon detection**

Find the line in main_menu that checks for action icons:
```bash
    if [[ "$selected" == "＋"* || "$selected" == "⬡"* || "$selected" == "✕"* || "$selected" == "◀"* ]]; then
      clean_selected=$(echo "$selected" | sed -E 's/^[^A-Za-z]*//')
```

Add `"⚙"*` to the condition:
```bash
    if [[ "$selected" == "＋"* || "$selected" == "⬡"* || "$selected" == "✕"* || "$selected" == "◀"* || "$selected" == "⚙"* ]]; then
```

Also update the same check in the `--preview` block inline script (there's a similar check around line 2772).

**Step 5: Test the full flow**
```bash
wt
# Navigate to ⚙ Settings
# Test each setting editor
# Test Reset to defaults
# Return to main menu
```

**Step 6: Commit**
```bash
git add wt.sh
git commit -m "feat: add Settings entry to main menu"
```

---

## Task 14: Print logo in wizard + final polish

**Files:** Modify `wt.sh`

**Step 1: Show logo at start of install wizard**

In `run_install_wizard()`, at the very beginning (before the "needs_symlink" check), add:
```bash
  print_logo
```

**Step 2: Add welcome message to preferences wizard**

At the start of `run_preferences_wizard()`, add:
```bash
  msg ""
  msg "  ${C_BOLD}Let's configure wt${C_RESET} in 2 quick steps."
  msg "  ${C_DIM}(Press ^S to skip any step)${C_RESET}"
  msg ""
```

**Step 3: Update `--help` to mention `--wizard`**

Find the `--help` output (~line 312) and add:
```
  --wizard         Re-run the first-time setup wizard
```

**Step 4: Final integration test**
```bash
# Clean slate test
rm -f ~/.config/wt/config
wt  # Should show preferences wizard then main menu

# Test --wizard flag
wt --wizard  # Should re-run wizard

# Test all settings work
wt  # Navigate to ⚙ Settings, test each item

# Test that settings persist after restart
wt --version  # Just to reload; then check ~/.config/wt/config
cat ~/.config/wt/config
```

**Step 5: Final commit**
```bash
git add wt.sh
git commit -m "feat: polish wizard UI and update --help"
```

---

## Summary of All Commits

1. `feat: add config infrastructure (load_config, save_config_value)`
2. `feat: get_editor respects WT_EDITOR config`
3. `feat: use WT_LIST_LIMIT for PR/issue list pagination`
4. `feat: use WT_FEATURE_PREFIX for issue branch naming`
5. `feat: respect WT_AUTO_FETCH setting before git fetch`
6. `feat: respect WT_CLAUDE_MODE config to bypass Claude picker`
7. `feat: use WT_WORKTREE_DIR as base path for new worktrees`
8. `feat: respect WT_AUTO_CD setting in shell wrapper`
9. `feat: add run_preferences_wizard function`
10. `feat: add run_install_wizard function`
11. `feat: add wizard trigger and --wizard flag`
12. `feat: add menu_settings function`
13. `feat: add Settings entry to main menu`
14. `feat: polish wizard UI and update --help`
