#!/usr/bin/env bash
# TDD Test for find_global_sidebar_pane restoration & archive execution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$SCRIPT_DIR/scripts/tmux-session-launcher"
SOCKET="dotfiles-find-pane-test-$$"
TMUX=(tmux -L "$SOCKET" -f "$SCRIPT_DIR/dotfiles/tmux.conf")

cleanup() {
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s test-archive-sess 'sleep 300'
"${TMUX[@]}" split-window -d -t '=test-archive-sess:' -h -b -l 35 "$LAUNCHER --sidebar"
sleep 1

# Execute delete_session_after_archive via launcher CLI
if ! "${TMUX[@]}" run-shell "$LAUNCHER --delete-session-after-archive test-archive-sess true" >/tmp/archive-test-$$.log 2>&1; then
    cat /tmp/archive-test-$$.log
    echo "FAIL: --delete-session-after-archive command crashed or failed"
    exit 1
fi
rm -f /tmp/archive-test-$$.log

echo "PASS: find_global_sidebar_pane regression test"
