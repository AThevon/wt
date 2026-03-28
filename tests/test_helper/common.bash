# Usage in .bats files: load 'test_helper/common'
load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

# Source individual modules with all functions available, entry point skipped.
# NOTE: Must be called from a git repository context (the project root).
load_wt() {
  # Reset cached platform to avoid state leakage between tests
  _WT_PLATFORM=""
  VERSION="test"
  local wt_root="${BATS_TEST_DIRNAME}/.."
  # shellcheck disable=SC1091
  source "$wt_root/lib/core.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/ui.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/git.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/cli.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/prompts.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/menus.sh"
  # shellcheck disable=SC1091
  source "$wt_root/lib/stash.sh"
}

# Set WT_CONFIG_FILE to a fresh temp file for test isolation
setup_config() {
  export WT_CONFIG_FILE
  WT_CONFIG_FILE="$(mktemp)"
}

# Clean up temp config file
teardown_config() {
  rm -f "${WT_CONFIG_FILE:-}"
}

# Create a minimal fake git repo with a given remote URL, print its path
make_fake_repo() {
  local remote_url="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  git init "$tmpdir" -q
  git -C "$tmpdir" remote add origin "$remote_url"
  echo "$tmpdir"
}
