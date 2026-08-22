#!/usr/bin/env bash
set -euo pipefail

# Full live test against the user's existing tmux server. The test creates
# only managed keyboard-* sessions and never kills the shared server.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${TMUX_USER_FULL_RUN_DIR:-}" ]; then
    RUN_DIR="$TMUX_USER_FULL_RUN_DIR"
else
    RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-user-full-XXXXXX")"
fi

TMUX_LIVE_FULL_USER_SERVER=1 \
TMUX_LIVE_FULL_SOCKET=default \
TMUX_LIVE_FULL_RUN_DIR="$RUN_DIR" \
TMUX_LIVE_FULL_TRANSPORT="${TMUX_USER_FULL_TRANSPORT:-script}" \
TMUX_LIVE_FULL_SEED_LIVE_TOPOLOGY=0 \
TMUX_LIVE_FULL_ANCHOR_SESSION=keyboard-anchor \
    bash "$TEST_DIR/test-live-full-monitored.sh"
