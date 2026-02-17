#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# Find .bats files only in tests/ root and test_helper/, excluding the submodule dirs
bats_files=()
while IFS= read -r -d '' f; do
  bats_files+=("$f")
done < <(find "$DIR" -maxdepth 2 -name "*.bats" ! -path "*/bats/*" ! -path "*/bats-support/*" ! -path "*/bats-assert/*" -print0)
if [[ ${#bats_files[@]} -eq 0 ]]; then
  echo "0 tests, 0 failures"
  exit 0
fi
exec "$DIR/bats/bin/bats" "${bats_files[@]}"
