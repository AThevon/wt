# wt — Tests Design

**Date:** 2026-02-18
**Branch:** feature/13-ajouter-une-section-settings

---

## Overview

Add a BATS test suite covering the non-interactive logic of `wt.sh` (config functions, editor/platform/worktree-dir/claude-mode helpers, CLI flags), and integrate BATS into the existing GitHub Actions CI.

---

## Scope

**In scope:** Pure logic + CLI flags (no fzf/TTY).

**Out of scope:** Interactive fzf menus, wizards, `main_menu` — require a real TTY and cannot be reliably automated.

---

## Test Framework

**BATS** (Bash Automated Testing System) via git submodules:
- `tests/bats/` — bats-core (test runner)
- `tests/test_helper/bats-support/` — output helpers
- `tests/test_helper/bats-assert/` — `assert_output`, `assert_success`, etc.

---

## Sourcing Strategy

`wt.sh` is a single executable file. BATS needs to `source` it to access its functions without triggering the entry point.

**Change to `wt.sh`:** wrap the entry point block in a `BASH_SOURCE` guard:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # load_config, wizard trigger, main_menu, etc.
fi
```

When sourced (BATS): `BASH_SOURCE[0] != $0` → entry point skipped, functions available.
When executed (`./wt.sh`): `BASH_SOURCE[0] == $0` → entry point runs normally.

**Test isolation** — `tests/test_helper/common.bash`:
```bash
load_wt() {
  source "${BATS_TEST_DIRNAME}/../wt.sh"
}

setup_config() {
  export WT_CONFIG_FILE="$(mktemp)"
}

teardown_config() {
  rm -f "$WT_CONFIG_FILE"
}
```

---

## File Structure

```
tests/
  bats/                        # submodule: bats/bats-core
  test_helper/
    bats-support/              # submodule: bats-libs/bats-support
    bats-assert/               # submodule: bats-libs/bats-assert
    common.bash                # shared helpers
  01-config.bats               # load_config, save_config_value, get_config_value
  02-editor.bats               # get_editor + WT_EDITOR override
  03-platform.bats             # detect_platform + WT_PLATFORM override
  04-worktree-dir.bats         # get_worktree_base_dir
  05-claude-mode.bats          # select_claude_mode bypass via WT_CLAUDE_MODE
  06-cli-flags.bats            # --version, --help, --wizard
  run.sh                       # convenience runner: ./tests/run.sh
```

---

## Test Cases

### `01-config.bats`
- `load_config` loads values from config file into env
- `save_config_value` writes a new key to config file
- `save_config_value` updates an existing key
- `save_config_value` handles values with special chars (`|`, `&`, spaces)
- `get_config_value` returns correct value for existing key
- `get_config_value` returns empty string for missing key

### `02-editor.bats`
- Returns `WT_EDITOR` value when set in config
- Falls back to auto-detection when `WT_EDITOR` is unset

### `03-platform.bats`
- Returns `github` when `WT_PLATFORM=github`
- Returns `gitlab` when `WT_PLATFORM=gitlab`
- Auto-detects from remote URL when `WT_PLATFORM=auto`

### `04-worktree-dir.bats`
- Returns `WT_WORKTREE_DIR` when set (with `~/` expansion)
- Falls back to `dirname $MAIN_REPO` when `WT_WORKTREE_DIR` unset

### `05-claude-mode.bats`
- Returns `forced` immediately when `WT_CLAUDE_MODE=forced` (no fzf)
- Returns `ask` immediately when `WT_CLAUDE_MODE=ask`
- Returns `plan` immediately when `WT_CLAUDE_MODE=plan`
- Calls fzf when `WT_CLAUDE_MODE` is empty (mock fzf to verify)

### `06-cli-flags.bats`
- `--version` prints `wt X.Y.Z` on stderr and exits 0
- `--help` prints usage info and exits 0
- `--wizard` with mocked fzf exits 0 and creates config file

---

## CI Integration

Add a `bats` job to `.github/workflows/ci.yml`, running in parallel with `shellcheck`:

```yaml
bats:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        submodules: recursive
    - name: Run BATS tests
      run: ./tests/run.sh
```

Both `shellcheck` and `bats` must pass for a PR to be mergeable.

---

## Files Changed

- `wt.sh` — add `BASH_SOURCE` guard around entry point
- `.github/workflows/ci.yml` — add `bats` job
- `tests/` — new directory with all test files and submodules
- `.gitmodules` — 3 new submodule entries
