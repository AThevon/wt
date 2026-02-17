# wt — Settings Section Design

**Date:** 2026-02-17
**Issue:** #13
**Branch:** feature/13-ajouter-une-section-settings

---

## Overview

Add a settings section to `wt` that allows users to configure their preferred IDE, versioning platform, and other preferences. Includes a unified first-time setup wizard and an interactive Settings menu accessible from the main menu.

---

## Goals

- Store user preferences persistently in `~/.config/wt/config`
- Provide a stylish, guided wizard on first launch (replaces the need to know about `--setup`)
- Allow editing preferences at any time via `⚙ Settings` in the main menu
- Integrate settings into existing behaviors (editor, platform detection, Claude mode)

---

## Config File

**Path:** `~/.config/wt/config`
**Format:** `KEY=VALUE` (one per line, `#` for comments)

```bash
# wt — user configuration
# Edit manually or via: wt > ⚙ Settings

WT_EDITOR=cursor
WT_PLATFORM=auto
WT_WORKTREE_DIR=
WT_AUTO_CD=true
WT_FEATURE_PREFIX=feature/
WT_AUTO_FETCH=true
WT_CLAUDE_MODE=
WT_LIST_LIMIT=20
```

### Config keys (Level 1 — shown in Settings menu)

| Key | Default | Values | Description |
|---|---|---|---|
| `WT_EDITOR` | auto-detected | cursor / code / vim / nvim / custom | Preferred editor (Ctrl+E) |
| `WT_PLATFORM` | auto | auto / github / gitlab | Git platform override |
| `WT_WORKTREE_DIR` | *(current behavior)* | path | Custom worktree root directory |
| `WT_AUTO_CD` | true | true / false | Auto-navigate to selected worktree |
| `WT_FEATURE_PREFIX` | feature/ | any string | Prefix for branches created from issues |
| `WT_AUTO_FETCH` | true | true / false | Fetch before listing PRs/issues |
| `WT_CLAUDE_MODE` | *(empty)* | *(empty)* / forced / ask / plan | Default Claude launch mode |
| `WT_LIST_LIMIT` | 20 | number | Max items in PR/issue lists |

### Config keys (Level 2 — config file only, advanced)

| Key | Default | Description |
|---|---|---|
| `WT_REVIEW_PREFIX` | reviewing- | Prefix for PR review worktrees |
| `WT_TEMP_PREFIX` | temp/ | Prefix for temp branches |
| `WT_SLUG_MAX_LENGTH` | 30 | Max chars in issue-generated branch names |
| `WT_AUTO_PRUNE` | true | Auto-prune stale worktree entries |

---

## Unified First-Time Wizard

### Trigger Logic

```
wt launched
    │
    ├─ wt-core not in PATH? ──→ Phase 1: Install
    │                                    │
    │                                    ▼
    └─ ~/.config/wt/config missing? ──→ Phase 2: Preferences
                │
                ▼
            main_menu()
```

Both phases can run in sequence on a truly fresh install.

### Phase 1 — Install (when wt-core not in PATH)

Replaces the need to know about `wt --setup`. The wizard:
1. Detects what needs to be installed (symlink, zshrc init line)
2. Shows a stylish confirmation screen
3. Performs the installation on "Yes"
4. Shows success and proceeds to Phase 2

Screen design:
```
╔══════════════════════════════════════════════════════╗
║                                                      ║
║   [wt ASCII logo]                                    ║
║                                                      ║
║            ─  Welcome to wt  ─                       ║
╚══════════════════════════════════════════════════════╝

  wt needs a quick one-time setup.
  This will:

    ✓ Create symlink  → /usr/local/bin/wt-core
    ✓ Add init line   → ~/.zshrc

  ──────────────────────────────────────
   Install now?

   ● Yes, set it up
   ○ No, skip for now
```

### Phase 2 — Preferences Wizard

Two fzf steps with rich preview panels.

**Step 1/2 — Preferred editor:**
```
  Step 1/2 — Preferred editor          ^S skip

  ● cursor  (detected)    │ cursor
  ○ code    (detected)    │
  ○ vim                   │ ✓ Found on your system
  ○ nvim                  │
  ○ custom...             │ Used when pressing Ctrl+E
                          │ in the worktree menu.
```

**Step 2/2 — Platform:**
```
  Step 2/2 — Git platform              ^S skip

  ● auto  (detect from remote)  │ auto (recommended)
  ○ github                      │
  ○ gitlab                      │ Reads your git remote URL
                                 │ to detect GitHub vs GitLab.
  Current repo: → github         │ Override to force a platform.
```

**Setup complete screen:**
```
  ╔══════════════════════════════════════╗
  ║  ✓  wt is ready                     ║
  ╠══════════════════════════════════════╣
  ║                                      ║
  ║  IDE         cursor                  ║
  ║  Platform    auto                    ║
  ║                                      ║
  ║  Config saved to ~/.config/wt/config ║
  ║                                      ║
  ║  Tip: wt > ⚙ Settings to change     ║
  ║                                      ║
  ╚══════════════════════════════════════╝

  Launching wt...
```

### Testing the wizard

```bash
# Delete config to trigger preferences wizard
rm ~/.config/wt/config && wt

# Force wizard re-run (new flag)
wt --wizard

# Phase 1 only (uninstall + reinstall)
# Remove symlink first, then: ./wt.sh
```

---

## Settings Menu

### Access

A `⚙ Settings` entry is added to the main menu (between `⬡ Manage stashes` and `◀ Quit`).

### Menu design

```
⚙ Settings                    ^R reset · Enter edit

  IDE              cursor
  Platform         auto  (detected: github)
  Worktree dir     ~/worktrees/
  Auto-CD          ✓ enabled
  Feature prefix   feature/
  Auto-fetch       ✓ enabled
  Claude mode      prompt each time
  PR/Issue limit   20
  ────────────────────────────────────
  ↺ Reset to defaults
```

Each item opens a sub-fzf to edit the value, with a preview panel explaining the setting.

**Reset to defaults:** Confirmation prompt → overwrites `~/.config/wt/config` with defaults.

---

## Integration with Existing Behaviors

### `get_editor()` — reads `WT_EDITOR`

Current: auto-detects cursor > code > $EDITOR > vim
New: if `WT_EDITOR` set in config, use that directly; otherwise keep auto-detection

### `detect_platform()` — reads `WT_PLATFORM`

Already supports `WT_PLATFORM` env var. Config file will be sourced at startup, so this works automatically.

### `select_claude_mode()` — reads `WT_CLAUDE_MODE`

Current: always shows fzf picker
New:
- `WT_CLAUDE_MODE` empty (default) → show picker (current behavior unchanged)
- `WT_CLAUDE_MODE=forced` → skip picker, use forced
- `WT_CLAUDE_MODE=ask` → skip picker, use ask
- `WT_CLAUDE_MODE=plan` → skip picker, use plan

### `WT_AUTO_CD`

The shell wrapper function already handles the cd. New logic: if `WT_AUTO_CD=false`, don't cd after selecting a worktree.

### `WT_WORKTREE_DIR`

Used in `menu_create_worktree()` as the base path when creating new worktrees.

### `WT_AUTO_FETCH`

Passed to existing fetch calls (currently unconditional).

### `WT_FEATURE_PREFIX`

Used in `menu_from_issue()` when generating branch names from issue titles.

---

## `wt --wizard` flag

New CLI flag that forces the wizard to run, regardless of whether config exists. Useful for:
- Re-running setup after a fresh install on a new machine
- Testing during development
- Resetting preferences interactively

---

## Files Changed

- `wt.sh` — all changes (single-file project)
  - `load_config()` — new function, sources `~/.config/wt/config`
  - `save_config_value KEY VALUE` — new function, writes to config file
  - `run_wizard()` — new function, unified wizard (install + preferences)
  - `menu_settings()` — new function, interactive settings menu
  - `main_menu()` — add `⚙ Settings` entry
  - `get_editor()` — check `WT_EDITOR` config first
  - `select_claude_mode()` — check `WT_CLAUDE_MODE` config to bypass picker
  - Top of script — call `load_config()` and check for wizard trigger
  - `--wizard` flag handling

---

## Out of Scope (future issues)

- Per-repo config (`.wt/config` in repo root)
- Config import/export
- Themes/colors customization
- `WT_SHELL_RC_FILE` override
