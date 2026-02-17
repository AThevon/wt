# Usage in .bats files: load 'test_helper/common'
load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

# Source wt.sh with all functions available, entry point skipped.
# NOTE: Must be called from a git repository context (the project root).
load_wt() {
  # Reset cached platform to avoid state leakage between tests
  _WT_PLATFORM=""
  # shellcheck disable=SC1091
  source "${BATS_TEST_DIRNAME}/../wt.sh"
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
