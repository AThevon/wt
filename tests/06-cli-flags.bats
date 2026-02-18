#!/usr/bin/env bats

load 'test_helper/common'

WT_SCRIPT="${BATS_TEST_DIRNAME}/../wt.sh"

setup() {
  # Create a mock fzf that prints "cursor" for any call
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/usr/bin/env bash\necho "cursor"\n' > "${BATS_TEST_TMPDIR}/bin/fzf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/fzf"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  # Isolate config file
  export WT_CONFIG_FILE
  WT_CONFIG_FILE="$(mktemp)"
}

teardown() {
  rm -f "$WT_CONFIG_FILE"
  rm -rf "${BATS_TEST_TMPDIR}/bin"
}

@test "--version prints 'wt X.Y.Z' and exits 0" {
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
  rm -f "$WT_CONFIG_FILE"
  run bash "$WT_SCRIPT" --wizard
  assert_success
  [[ -f "$WT_CONFIG_FILE" ]]
}
