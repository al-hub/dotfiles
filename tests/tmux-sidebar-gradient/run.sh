#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
test_files=(
    test-render.sh
    test-fingerprint.sh
    test-hot-path.sh
    test-state.sh
    test-session-isolation.sh
    test-regressions.sh
    test-lifecycle-e2e.sh
)

for test_file in "${test_files[@]}"; do
    printf '\n== %s ==\n' "$test_file"
    bash "$TEST_DIR/$test_file"
done

printf '\nAll tmux sidebar gradient tests completed.\n'
