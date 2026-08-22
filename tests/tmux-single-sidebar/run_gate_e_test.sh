#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"

tmux -L default kill-server 2>/dev/null || true
sleep 0.5

tmux -L default new-session -d -s main -n main-win
script -qefc "TERM=xterm tmux -L default attach-session -t main" /tmp/user-client-pty.log >/dev/null 2>&1 &
sleep 1

export TMUX_USER_LIVE_LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
bash "$TEST_DIR/test-user-tmux-required-monitored.sh"
