# BATS Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a BATS test suite covering non-interactive logic (config, editor, platform, worktree-dir, claude-mode, CLI flags) and integrate it into the existing GitHub Actions CI.

**Architecture:** Single-file bash script (`wt.sh`) sourced by BATS via a `BASH_SOURCE` guard that prevents the entry point from running when sourced. Tests use git submodules for bats-core + bats-support + bats-assert. Each test file isolates state via `setup()`/`teardown()` with a temp `WT_CONFIG_FILE`.

**Tech Stack:** BATS (bats-core 1.x), bats-support, bats-assert, GitHub Actions

---

### Task 1: Add BASH_SOURCE guard to wt.sh

**Goal:** Allow `source wt.sh` from tests without triggering the entry point.

**Context:** The entry point starts at line ~3584 (`# Point d'entrée`) and ends at line 3685. Without a guard, sourcing runs `main_menu` which calls `fzf` and hangs in a non-TTY environment.

**Files:**
- Modify: `wt.sh` (entry point section, lines ~3584–3685)

**Step 1: Wrap the entry point in a BASH_SOURCE guard**

Find the `# Point d'entrée` comment (around line 3584) and wrap everything after it:

```bash
# Point d'entrée
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

load_config

if [[ "$1" == "--wizard" ]]; then
  rm -f "$WT_CONFIG_FILE"
  run_preferences_wizard
  exit 0
fi

# ... (all existing entry point code unchanged) ...

result=$(main_menu)

if [[ -n "$result" ]]; then
  echo "$result"
fi

fi  # end BASH_SOURCE guard
```

The exact change: add `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then` immediately after the `# =============================================================================` line under `# Point d'entrée`, and add `fi` as the very last line of the file.

**Step 2: Verify the guard works**

```bash
# Source the file — should produce no output, no error, no hang
bash -c 'source ./wt.sh; echo "sourced OK"'
```

Expected output: `sourced OK` (no hang, no fzf errors)

**Step 3: Verify the script still runs normally when executed**

```bash
./wt.sh --version
```

Expected: `wt 1.7.1` (or current version) — proves entry point still works.

**Step 4: Commit**

```bash
git add wt.sh
git commit -m "refactor: add BASH_SOURCE guard to entry point for test sourcing"
```

---

### Task 2: Setup BATS submodules and runner

**Goal:** Install BATS toolchain as git submodules and create a convenience runner.

**Files:**
- Create: `tests/run.sh`
- Create: `tests/test_helper/common.bash`
- Modify: `.gitmodules` (auto-updated by git submodule add)

**Step 1: Add the three BATS submodules**

```bash
git submodule add https://github.com/bats-core/bats-core.git tests/bats
git submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```

**Step 2: Verify submodules are initialized**

```bash
ls tests/bats/bin/bats
ls tests/test_helper/bats-support/load.bash
ls tests/test_helper/bats-assert/load.bash
```

Expected: all three files exist.

**Step 3: Create `tests/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/bats/bin/bats" --recursive "$DIR"
```

```bash
chmod +x tests/run.sh
```

**Step 4: Create `tests/test_helper/common.bash`**

```bash
# Load bats helpers
load 'bats-support/load'
load 'bats-assert/load'

# Source wt.sh with all functions available, entry point skipped
load_wt() {
  # Unset cached platform to avoid state leakage between tests
  _WT_PLATFORM=""
  source "${BATS_TEST_DIRNAME}/../wt.sh"
}

# Set WT_CONFIG_FILE to a fresh temp file
setup_config() {
  export WT_CONFIG_FILE
  WT_CONFIG_FILE="$(mktemp)"
}

# Clean up temp config file
teardown_config() {
  rm -f "${WT_CONFIG_FILE:-}"
}

# Create a fake git repo with a given remote URL, return its path
make_fake_repo() {
  local remote_url="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  git init "$tmpdir" -q
  git -C "$tmpdir" remote add origin "$remote_url"
  echo "$tmpdir"
}
```

**Step 5: Verify runner works (with no test files yet)**

```bash
./tests/run.sh
```

Expected: exits 0 with "0 tests, 0 failures" or similar (no crash).

**Step 6: Commit**

```bash
git add tests/ .gitmodules
git commit -m "test: add BATS submodules and test runner"
```

---

### Task 3: Config function tests (`01-config.bats`)

**Goal:** Test `load_config`, `save_config_value`, `get_config_value`.

**Files:**
- Create: `tests/01-config.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
}

teardown() {
  teardown_config
}

# --- load_config ---

@test "load_config: loads key=value from config file into env" {
  echo "WT_FEATURE_PREFIX=ticket/" > "$WT_CONFIG_FILE"
  load_config
  assert_equal "$WT_FEATURE_PREFIX" "ticket/"
}

@test "load_config: does nothing when config file does not exist" {
  rm -f "$WT_CONFIG_FILE"
  run load_config
  assert_success
}

# --- save_config_value ---

@test "save_config_value: writes a new key to config file" {
  save_config_value "WT_LIST_LIMIT" "50"
  run grep "^WT_LIST_LIMIT=50" "$WT_CONFIG_FILE"
  assert_success
}

@test "save_config_value: updates an existing key without duplicating it" {
  echo "WT_LIST_LIMIT=20" > "$WT_CONFIG_FILE"
  save_config_value "WT_LIST_LIMIT" "99"
  local count
  count=$(grep -c "^WT_LIST_LIMIT=" "$WT_CONFIG_FILE")
  assert_equal "$count" "1"
  run grep "^WT_LIST_LIMIT=99" "$WT_CONFIG_FILE"
  assert_success
}

@test "save_config_value: handles value with pipe character" {
  save_config_value "WT_FEATURE_PREFIX" "feat|fix/"
  run grep "^WT_FEATURE_PREFIX=feat|fix/" "$WT_CONFIG_FILE"
  assert_success
}

@test "save_config_value: handles value with ampersand" {
  save_config_value "WT_FEATURE_PREFIX" "feat&fix/"
  run grep "^WT_FEATURE_PREFIX=feat&fix/" "$WT_CONFIG_FILE"
  assert_success
}

# --- get_config_value ---

@test "get_config_value: returns value for existing key" {
  echo "WT_LIST_LIMIT=42" > "$WT_CONFIG_FILE"
  run get_config_value "WT_LIST_LIMIT" "20"
  assert_output "42"
}

@test "get_config_value: returns default when key is absent" {
  run get_config_value "WT_MISSING_KEY" "fallback"
  assert_output "fallback"
}
```

**Step 2: Run and verify all tests pass**

```bash
./tests/run.sh
```

Expected: `7 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/01-config.bats
git commit -m "test: add config function tests (load_config, save_config_value, get_config_value)"
```

---

### Task 4: Editor tests (`02-editor.bats`)

**Goal:** Test `get_editor` respects `WT_EDITOR` config override.

**Files:**
- Create: `tests/02-editor.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  # Unset WT_EDITOR so auto-detect is used by default
  unset WT_EDITOR
}

teardown() {
  teardown_config
  unset WT_EDITOR
}

@test "get_editor: returns WT_EDITOR when set" {
  export WT_EDITOR="nvim"
  run get_editor
  assert_output "nvim"
}

@test "get_editor: falls back to auto-detection when WT_EDITOR is unset" {
  # Auto-detect returns something (cursor, code, vim, or $EDITOR) — just not empty
  run get_editor
  assert_success
  [[ -n "$output" ]]
}
```

**Step 2: Run and verify**

```bash
./tests/run.sh
```

Expected: `2 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/02-editor.bats
git commit -m "test: add get_editor tests"
```

---

### Task 5: Platform detection tests (`03-platform.bats`)

**Goal:** Test `detect_platform` respects `WT_PLATFORM` override and auto-detects from git remote.

**Context:** `detect_platform` has an internal cache `_WT_PLATFORM`. The `load_wt` helper in `common.bash` already resets it. The function also uses `MAIN_REPO` for git remote auto-detection.

**Files:**
- Create: `tests/03-platform.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_PLATFORM
}

teardown() {
  teardown_config
  unset WT_PLATFORM
  # Clean up any temp repos created in tests
  [[ -n "${_fake_repo:-}" ]] && rm -rf "$_fake_repo"
}

@test "detect_platform: returns github when WT_PLATFORM=github" {
  export WT_PLATFORM="github"
  run detect_platform
  assert_output "github"
}

@test "detect_platform: returns gitlab when WT_PLATFORM=gitlab" {
  export WT_PLATFORM="gitlab"
  run detect_platform
  assert_output "gitlab"
}

@test "detect_platform: auto-detects github from remote URL" {
  _fake_repo=$(make_fake_repo "https://github.com/user/repo.git")
  export MAIN_REPO="$_fake_repo"
  run detect_platform
  assert_output "github"
}

@test "detect_platform: auto-detects gitlab from remote URL" {
  _fake_repo=$(make_fake_repo "https://gitlab.com/user/repo.git")
  export MAIN_REPO="$_fake_repo"
  run detect_platform
  assert_output "gitlab"
}
```

**Step 2: Run and verify**

```bash
./tests/run.sh
```

Expected: `4 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/03-platform.bats
git commit -m "test: add detect_platform tests"
```

---

### Task 6: Worktree base dir tests (`04-worktree-dir.bats`)

**Goal:** Test `get_worktree_base_dir` returns correct path with and without `WT_WORKTREE_DIR`.

**Files:**
- Create: `tests/04-worktree-dir.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_WORKTREE_DIR
  export MAIN_REPO="/tmp/projects/myrepo"
}

teardown() {
  teardown_config
  unset WT_WORKTREE_DIR
}

@test "get_worktree_base_dir: returns WT_WORKTREE_DIR when set" {
  export WT_WORKTREE_DIR="/custom/worktrees"
  run get_worktree_base_dir
  assert_output "/custom/worktrees"
}

@test "get_worktree_base_dir: expands tilde in WT_WORKTREE_DIR" {
  export WT_WORKTREE_DIR="~/worktrees"
  run get_worktree_base_dir
  assert_output "${HOME}/worktrees"
}

@test "get_worktree_base_dir: falls back to dirname of MAIN_REPO when WT_WORKTREE_DIR unset" {
  run get_worktree_base_dir
  assert_output "/tmp/projects"
}
```

**Step 2: Run and verify**

```bash
./tests/run.sh
```

Expected: `3 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/04-worktree-dir.bats
git commit -m "test: add get_worktree_base_dir tests"
```

---

### Task 7: Claude mode bypass tests (`05-claude-mode.bats`)

**Goal:** Test that `select_claude_mode` bypasses the fzf picker when `WT_CLAUDE_MODE` is set to a valid value.

**Context:** `select_claude_mode` takes two args (`context_type`, `context_num`). When `WT_CLAUDE_MODE` is `forced|ask|plan`, it echoes the value and returns immediately without calling fzf.

**Files:**
- Create: `tests/05-claude-mode.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  load_wt
  setup_config
  unset WT_CLAUDE_MODE
}

teardown() {
  teardown_config
  unset WT_CLAUDE_MODE
}

@test "select_claude_mode: returns 'forced' immediately when WT_CLAUDE_MODE=forced" {
  export WT_CLAUDE_MODE="forced"
  run select_claude_mode "pr-review" "42"
  assert_success
  assert_output "forced"
}

@test "select_claude_mode: returns 'ask' immediately when WT_CLAUDE_MODE=ask" {
  export WT_CLAUDE_MODE="ask"
  run select_claude_mode "issue-work" "7"
  assert_success
  assert_output "ask"
}

@test "select_claude_mode: returns 'plan' immediately when WT_CLAUDE_MODE=plan" {
  export WT_CLAUDE_MODE="plan"
  run select_claude_mode "pr-work" "1"
  assert_success
  assert_output "plan"
}
```

**Step 2: Run and verify**

```bash
./tests/run.sh
```

Expected: `3 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/05-claude-mode.bats
git commit -m "test: add select_claude_mode bypass tests"
```

---

### Task 8: CLI flag tests (`06-cli-flags.bats`)

**Goal:** Test `--version`, `--help`, and `--wizard` flags via subprocess execution (not sourcing).

**Context:** These tests execute `wt.sh` as a subprocess. `--version` and `--help` exit before any fzf call. `--wizard` calls `run_preferences_wizard` which uses fzf — mock fzf by injecting a fake executable into PATH.

**Files:**
- Create: `tests/06-cli-flags.bats`

**Step 1: Create the test file**

```bash
#!/usr/bin/env bats

load 'test_helper/common'

WT_SCRIPT="${BATS_TEST_DIRNAME}/../wt.sh"

setup() {
  # Create a mock fzf that echoes "cursor" (first option) for any call
  export BATS_TEST_TMPDIR
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/fzf" << 'MOCKEOF'
#!/usr/bin/env bash
echo "cursor"
MOCKEOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # Isolate config file
  export WT_CONFIG_FILE
  WT_CONFIG_FILE="$(mktemp)"
}

teardown() {
  rm -f "$WT_CONFIG_FILE"
  rm -rf "$BATS_TEST_TMPDIR/bin"
}

@test "--version prints 'wt X.Y.Z' on stderr and exits 0" {
  run bash "$WT_SCRIPT" --version
  assert_success
  assert_output --partial "wt "
}

@test "--help prints usage information and exits 0" {
  run bash "$WT_SCRIPT" --help
  assert_success
  assert_output --partial "wt"
}

@test "--wizard exits 0 and creates the config file" {
  run bash "$WT_SCRIPT" --wizard
  assert_success
  [[ -f "$WT_CONFIG_FILE" ]]
}
```

**Step 2: Run and verify**

```bash
./tests/run.sh
```

Expected: `3 tests, 0 failures`

**Step 3: Commit**

```bash
git add tests/06-cli-flags.bats
git commit -m "test: add CLI flag tests (--version, --help, --wizard)"
```

---

### Task 9: Add BATS job to CI

**Goal:** Run BATS tests on every push/PR alongside the existing ShellCheck job.

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Read the current ci.yml**

Current content:
```yaml
name: CI

on:
  push:
    branches: [ main, feature/* ]
  pull_request:
    branches: [ main ]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: '.'
          severity: error
          ignore_paths: 'completions'
```

**Step 2: Add the `bats` job**

Add after the `shellcheck` job:

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

The full updated file:

```yaml
name: CI

on:
  push:
    branches: [ main, feature/* ]
  pull_request:
    branches: [ main ]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: '.'
          severity: error
          ignore_paths: 'completions'

  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Run BATS tests
        run: ./tests/run.sh
```

**Step 3: Run tests locally one final time to confirm everything passes**

```bash
./tests/run.sh
```

Expected: all tests pass (22 total: 7 + 2 + 4 + 3 + 3 + 3).

**Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add BATS test job to GitHub Actions"
```

---

## Summary

| Task | What it does |
|---|---|
| 1 | `BASH_SOURCE` guard in `wt.sh` — enables safe sourcing |
| 2 | BATS submodules + `run.sh` + `common.bash` |
| 3 | `01-config.bats` — 7 tests for config functions |
| 4 | `02-editor.bats` — 2 tests for `get_editor` |
| 5 | `03-platform.bats` — 4 tests for `detect_platform` |
| 6 | `04-worktree-dir.bats` — 3 tests for `get_worktree_base_dir` |
| 7 | `05-claude-mode.bats` — 3 tests for `select_claude_mode` |
| 8 | `06-cli-flags.bats` — 3 tests for CLI flags |
| 9 | `ci.yml` — `bats` job added alongside `shellcheck` |

**Total: 22 tests across 6 files.**
