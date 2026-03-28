# Modular Refactoring + Gum Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `wt.sh` (~3800 lines) into `lib/*.sh` modules, integrate `gum` as a required dependency for all UI, replace the logo, and update packaging.

**Architecture:** Extract functions from the monolith into 7 modules sourced by a slim `wt.sh` entry point. A new `ui.sh` module wraps `gum` for all user-facing output. The split is pure extraction — no logic changes except UI upgrades.

**Tech Stack:** Bash, fzf, gum (Charmbracelet), jq, BATS (tests)

**Spec:** `docs/superpowers/specs/2026-03-28-modular-gum-redesign.md`

---

### Task 1: Create `lib/core.sh` — Colors, config, platform, helpers

Extract the foundation that every other module depends on.

**Files:**
- Create: `lib/core.sh`
- Source: `wt.sh:469-659` (Colors, Config, Messages, Platform Detection, has_*(), get_editor)

**What goes in `lib/core.sh`:**
- Lines 469-489: Color variables (`C_RESET`, `C_BOLD`, etc.)
- Lines 495-563: Config functions (`WT_CONFIG_FILE`, `load_config`, `save_config_value`, `get_config_value`, `get_worktree_base_dir`, `has_fzf`, `has_gh`, `has_claude`)
- Lines 565-579: `get_editor()` and editor detection
- Lines 580-599: Message functions (`msg`, `msg_success`, `msg_error`, `msg_info`, `msg_warn`)
- Lines 601-659: Platform detection (`detect_platform`, `has_cli`, `get_cli_name`, `get_pr_term`, `get_pr_term_long`, `get_platform_name`)

- [ ] **Step 1: Create `lib/core.sh` with all extracted functions**

Create `lib/core.sh`. Copy the exact functions from `wt.sh` lines 469-659. Add a `has_gum()` and `has_jq()` check. Do NOT modify any function logic — pure extraction.

```bash
#!/usr/bin/env bash
# lib/core.sh — Colors, config, platform detection, message helpers

# Paste exact content from wt.sh lines 469-659 here
# Add at the end:

has_gum() {
  command -v gum &> /dev/null
}

has_jq() {
  command -v jq &> /dev/null
}
```

- [ ] **Step 2: Verify the file sources cleanly**

Run: `bash -n lib/core.sh`
Expected: no output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add lib/core.sh
git commit -m "extract lib/core.sh: colors, config, platform, helpers"
```

---

### Task 2: Create `lib/ui.sh` — Gum wrappers

New module that replaces all raw `echo`/`msg`/`loader` calls with `gum` equivalents.

**Files:**
- Create: `lib/ui.sh`

- [ ] **Step 1: Create `lib/ui.sh` with all gum wrapper functions**

```bash
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

# Replace loader_start/loader_stop pattern with a single spin call
# Usage: ui_spin "Fetching PRs..." gh pr list
# The spinner runs while the command executes, then disappears.

# Print the new logo
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
```

- [ ] **Step 2: Verify the file sources cleanly**

Run: `bash -n lib/ui.sh`
Expected: no output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add lib/ui.sh
git commit -m "create lib/ui.sh: gum wrappers + new tiger logo"
```

---

### Task 3: Create `lib/cli.sh` — gh/glab abstraction

Extract the CLI abstraction layer for GitHub/GitLab.

**Files:**
- Create: `lib/cli.sh`
- Source: `wt.sh:661-827` (CLI Abstraction) + `wt.sh:814-827` (CLI command helpers)

- [ ] **Step 1: Create `lib/cli.sh`**

Copy the exact content from `wt.sh` lines 661-827. This includes `cli_pr_list()`, `cli_pr_view()`, `cli_issue_list()`, `cli_issue_view()`, `cli_pr_checks()`, etc.

- [ ] **Step 2: Verify syntax**

Run: `bash -n lib/cli.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/cli.sh
git commit -m "extract lib/cli.sh: gh/glab CLI abstraction"
```

---

### Task 4: Create `lib/prompts.sh` — Claude prompt generation

Extract Claude integration code.

**Files:**
- Create: `lib/prompts.sh`
- Source: `wt.sh:828-1017` (Prompt Generation for Claude)

- [ ] **Step 1: Create `lib/prompts.sh`**

Copy exact content from `wt.sh` lines 828-1017. This is the `generate_prompt()` function and its 5 templates (issue-auto, ci-fix, pr-review, pr-work, issue-work).

- [ ] **Step 2: Verify syntax**

Run: `bash -n lib/prompts.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/prompts.sh
git commit -m "extract lib/prompts.sh: Claude prompt generation"
```

---

### Task 5: Create `lib/git.sh` — Worktree operations

Extract all git/worktree functions.

**Files:**
- Create: `lib/git.sh`
- Source: `wt.sh:1089-1244` (CLI Auth, Worktrees, format/branch utils) + `wt.sh:1395-1640` (Worktree creation actions)

**What goes in `lib/git.sh`:**
- Lines 1089-1146: `setup_cli_auth()`
- Lines 1147-1244: `get_default_branch()`, `is_branch_new()`, `is_branch_merged()`, `get_worktrees()`, `get_secondary_worktrees()`, `format_worktree_line()`, `format_all_worktrees()`
- Lines 1395-1640: `create_from_current()`, `create_from_branch()`, `create_new_branch()`, `create_from_pr()`, `create_from_issue()`

- [ ] **Step 1: Create `lib/git.sh`**

Copy exact content from the line ranges above. Keep the functions in the same order.

- [ ] **Step 2: Verify syntax**

Run: `bash -n lib/git.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/git.sh
git commit -m "extract lib/git.sh: worktree operations and creation"
```

---

### Task 6: Create `lib/menus.sh` — All menus except stash

Extract menu functions, PR/issue menus, settings, wizards, delete.

**Files:**
- Create: `lib/menus.sh`
- Source: Multiple sections from `wt.sh`:
  - Lines 1246-1297: PR/MR formatting helpers
  - Lines 1298-1394: Claude mode selection (`select_claude_mode`)
  - Lines 1641-1824: `menu_review_pr()` (Review PR menu)
  - Lines 1825-1974: `menu_from_issue()` (Issue menu)
  - Lines 1975-2068: `menu_create_worktree()` (Create worktree menu)
  - Lines 2818-2958: `action_delete_worktrees()` (Delete menu)
  - Lines 2959-3133: `run_preferences_wizard()`
  - Lines 3134-3223: `run_install_wizard()`
  - Lines 3224-3460: Settings menu

- [ ] **Step 1: Create `lib/menus.sh`**

Copy exact content from all the line ranges listed above, in order.

- [ ] **Step 2: Verify syntax**

Run: `bash -n lib/menus.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/menus.sh
git commit -m "extract lib/menus.sh: PR, issue, create, delete, settings, wizards"
```

---

### Task 7: Create `lib/stash.sh` — Stash management

Extract the entire stash management module.

**Files:**
- Create: `lib/stash.sh`
- Source: `wt.sh:2069-2817` (Stash Management helpers + main menu)

- [ ] **Step 1: Create `lib/stash.sh`**

Copy exact content from `wt.sh` lines 2069-2817. This is ~750 lines covering stash helpers (`format_stash_age`, `count_stash_files`, `get_stash_branch`, `get_stash_message`, `format_stash_list`, `create_partial_stash`) and `menu_stash()`.

- [ ] **Step 2: Verify syntax**

Run: `bash -n lib/stash.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/stash.sh
git commit -m "extract lib/stash.sh: stash management (~750 lines)"
```

---

### Task 8: Rewrite `wt.sh` as entry point

Replace the monolith with a slim entry point that sources modules and handles CLI flags + main menu.

**Files:**
- Modify: `wt.sh` (replace ~3800 lines with ~400 lines)

**What stays in `wt.sh`:**
- Lines 1-10: Shebang, header comment, `VERSION`
- Lines 12-468: CLI flags (`--version`, `--update`, `--dev`, `--release`, `--setup`, `--shell-init`, `--help`, git repo detection) — these run BEFORE modules are sourced
- Lines 3461-3730: `main_menu()` function
- Lines 3732-3838: Entry point logic (config load, flag dispatch, main_menu call)

**What gets removed from `wt.sh`:** Everything that was extracted into `lib/*.sh` (lines 469-3460 approximately).

- [ ] **Step 1: Add module sourcing after the early-exit CLI flags**

After the git repo detection block (line 468), add:

```bash
# =============================================================================
# Load modules
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/git.sh"
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/prompts.sh"
source "$LIB_DIR/menus.sh"
source "$LIB_DIR/stash.sh"
```

- [ ] **Step 2: Remove all extracted code from `wt.sh`**

Delete lines 469-3460 from `wt.sh` (everything between the module sourcing block and `main_menu()`). Keep `main_menu()` and the entry point logic at the bottom.

- [ ] **Step 3: Remove old `loader_start`/`loader_stop`/`print_logo` from `wt.sh`**

These are now in `lib/ui.sh`. Verify they're no longer in `wt.sh` after the extraction.

- [ ] **Step 4: Test the split works**

Run: `bash -n wt.sh` (syntax check)
Run: `./wt.sh --version` (should print version)
Run: `./wt.sh --help` (should print help)

- [ ] **Step 5: Commit**

```bash
git add wt.sh
git commit -m "rewrite wt.sh as slim entry point sourcing lib/ modules"
```

---

### Task 9: Update menu icons

Replace the dim menu action icons with colored ones in `main_menu()`.

**Files:**
- Modify: `wt.sh` (in `main_menu()` function, around line 3483 in original)

- [ ] **Step 1: Update the action icons in `main_menu()`**

Find the actions block in `main_menu()` and replace:

```bash
# Before:
actions+=$'\n'"${C_DIM}›${C_RESET} Create a worktree"
actions+=$'\n'"${C_DIM}◇${C_RESET} Manage stashes"
actions+=$'\n'"${C_DIM}×${C_RESET} Delete worktree(s)"
actions+=$'\n'"${C_DIM}◦${C_RESET} Settings"
actions+=$'\n'"${C_DIM}‹${C_RESET} Quit"

# After:
actions+=$'\n'"${C_GREEN}+${C_RESET} Create a worktree"
actions+=$'\n'"${C_ORANGE}⧉${C_RESET} Manage stashes"
actions+=$'\n'"${C_RED}✕${C_RESET} Delete worktree(s)"
actions+=$'\n'"${C_DIM}⚙${C_RESET} Settings"
actions+=$'\n'"${C_DIM}↩${C_RESET} Quit"
```

- [ ] **Step 2: Update the fzf preview icon matching**

In the same `main_menu()` function, the fzf `--preview` script matches on the old icons to detect actions. Update the match pattern:

```bash
# Before:
if [[ \"\$line\" == \"›\"* || \"\$line\" == \"◇\"* || \"\$line\" == \"×\"* || \"\$line\" == \"‹\"* || \"\$line\" == \"◦\"* ]]; then

# After:
if [[ \"\$line\" == \"+\"* || \"\$line\" == \"⧉\"* || \"\$line\" == \"✕\"* || \"\$line\" == \"↩\"* || \"\$line\" == \"⚙\"* ]]; then
```

- [ ] **Step 3: Update the action dispatch at the bottom of `main_menu()`**

The selection parsing after fzf matches on the old icons. Update:

```bash
# Update all matches from old icons to new icons:
# "› Create" -> "+ Create"
# "◇ Manage" -> "⧉ Manage"
# "× Delete" -> "✕ Delete"
# "◦ Settings" -> "⚙ Settings"
# "‹ Quit" -> "↩ Quit"
```

- [ ] **Step 4: Update the fzf header in `main_menu()`**

Replace the current header with pipe-separated style:

```bash
# Before:
local header="${C_BOLD}$REPO_NAME${C_RESET}  ${C_DIM}^E editor · ^N new · ^P ${pr_term}s · ^G issues · ^D delete${C_RESET}"

# After:
local header="${C_ORANGE}wt${C_RESET} ${C_DIM}│${C_RESET} ${C_DIM}^E${C_RESET} editor ${C_DIM}│${C_RESET} ${C_DIM}^N${C_RESET} new ${C_DIM}│${C_RESET} ${C_DIM}^P${C_RESET} ${pr_term}s ${C_DIM}│${C_RESET} ${C_DIM}^G${C_RESET} issues ${C_DIM}│${C_RESET} ${C_DIM}^D${C_RESET} delete"
```

- [ ] **Step 5: Commit**

```bash
git add wt.sh
git commit -m "update menu icons and fzf header style"
```

---

### Task 10: Replace UI calls with gum wrappers

Go through each module and replace raw `msg`/`echo`/`loader` calls with `ui_*` functions where appropriate.

**Files:**
- Modify: `lib/menus.sh`, `lib/git.sh`, `lib/stash.sh`

This is the biggest migration task. Focus on these replacements:

1. `loader_start "msg" ; command ; loader_stop` → `ui_spin "msg" command`
2. `msg_success "..."` stays (already clean, same pattern)
3. `msg_error "..."` stays (already clean)
4. `msg_warn "..."` stays (already clean)
5. `read -p "Delete? [y/N]" confirm` → `ui_confirm "Delete?"`
6. `read -p "Branch name: " name` → `name=$(ui_input "Branch name" "feature/...")`
7. Section headers like `msg "--- Settings ---"` → `ui_header "Settings"`

- [ ] **Step 1: Replace loader_start/loader_stop patterns in all lib/ files**

Search for all `loader_start` and `loader_stop` calls across `lib/*.sh`. Replace each pair with `ui_spin`. Example:

```bash
# Before:
loader_start "Fetching PRs..."
local pr_list=$(cli_pr_list)
loader_stop

# After:
local pr_list
pr_list=$(ui_spin "Fetching PRs..." cli_pr_list)
```

Note: `ui_spin` captures the command's stdout, so assign it directly.

- [ ] **Step 2: Replace `read -p` confirmations with `ui_confirm`**

Search for `read -p` patterns that ask yes/no questions. Replace with `ui_confirm`:

```bash
# Before:
read -p "Delete worktree? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || return

# After:
ui_confirm "Delete worktree?" || return
```

- [ ] **Step 3: Replace `read -p` text inputs with `ui_input`**

Search for `read -p` patterns that collect text. Replace with `ui_input`:

```bash
# Before:
read -rp "  Branch name: " branch_name

# After:
branch_name=$(ui_input "Branch name:" "feature/...")
```

- [ ] **Step 4: Replace section headers with `ui_header`**

Look for patterns like `msg "--- Title ---"` or boxed headers and replace with `ui_header "Title"`.

- [ ] **Step 5: Replace action summaries with `ui_box`**

After worktree creation, replace the scattered `msg` calls with a single `ui_box`:

```bash
# Before:
msg_success "Worktree created"
msg "  Path: $wt_path"
msg "  Branch: $branch"

# After:
ui_success "Worktree created"
ui_box "Branch    $branch" "Path      $wt_path" "Editor    $editor"
```

- [ ] **Step 6: Commit**

```bash
git add lib/
git commit -m "replace raw UI calls with gum wrappers across all modules"
```

---

### Task 11: Update `--setup` to check gum + jq as required

The `--setup` flag needs to check all 3 required deps.

**Files:**
- Modify: `wt.sh` (in the `--setup` block, currently lines 279-401)

- [ ] **Step 1: Update the dependency check in `--setup`**

Replace the dependency check section:

```bash
# Before:
if command -v fzf &>/dev/null; then
  _msg "  [ok] fzf"
else
  _msg "  [!!] fzf (required) - install with: brew install fzf"
  deps_ok=false
fi
if command -v jq &>/dev/null; then
  _msg "  [ok] jq"
else
  _msg "  [--] jq (optional) - install with: brew install jq"
fi

# After (check all 3 required deps):
for dep in fzf gum jq; do
  if command -v "$dep" &>/dev/null; then
    _msg "  ${_GREEN}●${_RESET} $dep  installed"
  else
    _msg "  ${_RED}●${_RESET} $dep  ${_RED}missing${_RESET} — install with: brew install $dep"
    deps_ok=false
  fi
done
```

Keep the optional deps (gh, glab, claude) with the same pattern but using `○` instead:

```bash
for dep in gh glab claude; do
  if command -v "$dep" &>/dev/null; then
    _msg "  ${_GREEN}●${_RESET} $dep  installed"
  else
    _msg "  ○ $dep  optional"
  fi
done
```

- [ ] **Step 2: Update `main_menu()` to check gum + jq**

In `main_menu()`, add checks alongside the existing `has_fzf` check:

```bash
# Before:
if ! has_fzf; then
  msg "fzf is required"
  msg "Install with: brew install fzf"
  exit 1
fi

# After:
local missing_deps=()
has_fzf || missing_deps+=("fzf")
has_gum || missing_deps+=("gum")
has_jq  || missing_deps+=("jq")
if [[ ${#missing_deps[@]} -gt 0 ]]; then
  msg_error "Missing required dependencies: ${missing_deps[*]}"
  msg "Install with: brew install ${missing_deps[*]}"
  exit 1
fi
```

- [ ] **Step 3: Commit**

```bash
git add wt.sh
git commit -m "require gum + jq in --setup and main_menu dependency check"
```

---

### Task 12: Update `install.sh` to auto-install gum + jq

Extend the installer to auto-install all 3 required deps.

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Replace the single fzf install with a loop for all required deps**

Replace lines 57-78 in `install.sh`:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "install.sh: auto-install gum + jq as required deps"
```

---

### Task 13: Update `default.nix` — Add gum to Nix packaging

**Files:**
- Modify: `default.nix`

- [ ] **Step 1: Add gum to the Nix derivation**

```nix
# Before:
{ lib, stdenvNoCC, makeWrapper, fzf, gh, jq, glab }:

# After:
{ lib, stdenvNoCC, makeWrapper, fzf, gum, gh, jq, glab }:
```

Update `installPhase` to also copy `lib/`:

```nix
  installPhase = ''
    # Main script
    install -Dm755 wt.sh $out/bin/wt-core

    # Library modules
    mkdir -p $out/lib
    cp lib/*.sh $out/lib/

    # Zsh completion
    install -Dm644 completions/wt.zsh $out/share/zsh/site-functions/_wt
  '';
```

Update `wrapProgram` to include gum:

```nix
  postFixup = ''
    wrapProgram $out/bin/wt-core \
      --prefix PATH : ${lib.makeBinPath [ fzf gum gh jq glab ]}
  '';
```

- [ ] **Step 2: Update the version**

Change `version = "1.10.0"` to `version = "2.0.0"` (or whatever the next version will be).

- [ ] **Step 3: Handle `SCRIPT_DIR` for Nix installs**

In the Nix install, `wt-core` is at `$out/bin/wt-core` and `lib/` is at `$out/lib/`. The `SCRIPT_DIR` detection in `wt.sh` needs to resolve the lib path correctly. After the sourcing block in `wt.sh`, add a fallback:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Nix install: lib/ is a sibling of bin/, not inside bin/
if [[ ! -d "$LIB_DIR" ]]; then
  LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
fi
```

- [ ] **Step 4: Commit**

```bash
git add default.nix wt.sh
git commit -m "nix: add gum dep, install lib/ modules, fix SCRIPT_DIR for nix"
```

---

### Task 14: Update BATS test helper

The test helper sources `wt.sh` directly — it needs to handle the new module structure.

**Files:**
- Modify: `tests/test_helper/common.bash`

- [ ] **Step 1: Update `load_wt()` to source modules**

```bash
# Before:
load_wt() {
  _WT_PLATFORM=""
  source "${BATS_TEST_DIRNAME}/../wt.sh"
}

# After:
load_wt() {
  _WT_PLATFORM=""
  local wt_root="${BATS_TEST_DIRNAME}/.."
  # Source modules in order (same as wt.sh does)
  source "$wt_root/lib/core.sh"
  source "$wt_root/lib/ui.sh"
  source "$wt_root/lib/git.sh"
  source "$wt_root/lib/cli.sh"
  source "$wt_root/lib/prompts.sh"
  source "$wt_root/lib/menus.sh"
  source "$wt_root/lib/stash.sh"
}
```

- [ ] **Step 2: Run all existing BATS tests**

Run: `./tests/run.sh`
Expected: all tests pass (6 files, same results as before the refactoring)

If tests fail because they depend on `VERSION` or other vars set in `wt.sh`'s entry point, add them to `load_wt()`:

```bash
load_wt() {
  _WT_PLATFORM=""
  VERSION="test"
  local wt_root="${BATS_TEST_DIRNAME}/.."
  source "$wt_root/lib/core.sh"
  source "$wt_root/lib/ui.sh"
  # ...
}
```

- [ ] **Step 3: Commit**

```bash
git add tests/test_helper/common.bash
git commit -m "update BATS test helper for modular structure"
```

---

### Task 15: Update `--help` text and `VERSION`

Reflect the new dependencies in help and bump version.

**Files:**
- Modify: `wt.sh`

- [ ] **Step 1: Update the help text**

In the `--help` block, update the dependencies line:

```bash
# Before:
Dependencies: fzf (required), gh/glab, jq, claude (optional)

# After:
Dependencies: fzf, gum, jq (required), gh/glab, claude (optional)
```

- [ ] **Step 2: Bump VERSION**

```bash
# Before:
VERSION="1.10.4"

# After:
VERSION="2.0.0"
```

- [ ] **Step 3: Commit**

```bash
git add wt.sh
git commit -m "bump to v2.0.0, update help text for new deps"
```

---

### Task 16: Smoke test end-to-end

Final integration test — verify everything works together.

**Files:** None (testing only)

- [ ] **Step 1: Syntax check all files**

```bash
bash -n wt.sh
for f in lib/*.sh; do bash -n "$f"; done
```
Expected: no output from any file

- [ ] **Step 2: Run BATS tests**

```bash
./tests/run.sh
```
Expected: all tests pass

- [ ] **Step 3: Test `--dev` mode**

```bash
eval "$(./wt.sh --dev)"
wt --version
wt --help
```
Expected: version shows `2.0.0`, help shows new deps

- [ ] **Step 4: Test interactive menu**

```bash
wt
```
Expected: new logo displays, menu shows with new colored icons, new fzf header with pipe separators

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: smoke test fixes for modular refactoring"
```
