#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS="${E2E_RUNS:-3}"

case "$RUNS" in
    ''|*[!0-9]*)
        printf 'E2E_RUNS must be a positive integer\n' >&2
        exit 2
        ;;
esac
[ "$RUNS" -gt 0 ] || {
    printf 'E2E_RUNS must be greater than zero\n' >&2
    exit 2
}

for run in $(seq 1 "$RUNS"); do
    printf 'E2E RUN %s/%s\n' "$run" "$RUNS"
    KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}" \
        TMUX_SESSION_LAUNCHER_TRACE="${TMUX_SESSION_LAUNCHER_TRACE:-0}" \
        TMUX_SESSION_LAUNCHER_DEBUG="${TMUX_SESSION_LAUNCHER_DEBUG:-0}" \
        TEST_TRACE_VERBOSE="${TEST_TRACE_VERBOSE:-false}" \
        bash "$TEST_DIR/test-keyboard-e2e.sh"
done

printf 'PASS: keyboard E2E completed %s consecutive run(s)\n' "$RUNS"
