#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)"
exec env TMUX_SESSION_SWITCH_TOPOLOGY=horizontal \
    bash "$TEST_DIR/test-session-switch-live-correlation.sh" "$@"
