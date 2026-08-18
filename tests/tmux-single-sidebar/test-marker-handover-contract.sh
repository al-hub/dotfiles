#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCKET="test-marker-handover-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-marker-handover.XXXXXX")"
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    if [ "$KEEP_RUN_DIR" != "true" ]; then
        rm -rf -- "$RUN_DIR"
    fi
}
trap cleanup EXIT INT TERM

# Start test tmux server with two sessions
tmux -L "$SOCKET" -f "$SCRIPT_DIR/dotfiles/tmux.conf" new-session -d -s sess-a -n work-a 'sleep 100'
tmux -L "$SOCKET" -f "$SCRIPT_DIR/dotfiles/tmux.conf" new-session -d -s sess-b -n work-b 'sleep 100'

win_a="$(tmux -L "$SOCKET" display-message -p -t sess-a '#{window_id}')"
win_b="$(tmux -L "$SOCKET" display-message -p -t sess-b '#{window_id}')"

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

echo "=== Test 1: sidebar_port_publish_marker_handover sets options on target window ==="
sidebar_port_publish_marker_handover "$win_b" "sess-b"

target_marker="$(tmux -L "$SOCKET" show-option -wqv -t "$win_b" @dotfiles_sidebar_target_marker)"
selection_sync="$(tmux -L "$SOCKET" show-option -wqv -t "$win_b" @dotfiles_sidebar_selection_sync)"

if [ "$target_marker" != "sess-b" ]; then
    echo "FAIL: expected @dotfiles_sidebar_target_marker to be 'sess-b', got '$target_marker'"
    exit 1
fi

if [ "$selection_sync" != "sess-b" ]; then
    echo "FAIL: expected @dotfiles_sidebar_selection_sync to be 'sess-b', got '$selection_sync'"
    exit 1
fi
echo "PASS: sidebar_port_publish_marker_handover sets target marker and selection sync options"

echo "=== Test 2: sidebar_port_notify_presenter_wake sends SIGWINCH to presenter process ==="
SIG_FILE="$RUN_DIR/sigwinch_received"
TEST_PRESENTER_CMD="bash -c 'trap \"echo winch >> \\\"$SIG_FILE\\\"\" WINCH; touch \"$RUN_DIR/ready\"; while true; do sleep 0.1; done'"

# Provision sidebar running the test presenter command
sb_pane="$(provision_sidebar_window "$win_b" 30 "$TEST_PRESENTER_CMD")"
[ -n "$sb_pane" ] || { echo "FAIL: failed to provision sidebar in win_b"; exit 1; }

# Wait for test presenter to become ready
deadline=$(( $(date +%s) + 5 ))
while [ ! -f "$RUN_DIR/ready" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "FAIL: presenter did not start ready in time"
        exit 1
    fi
    sleep 0.05
done

# Send wake notification
sidebar_port_notify_presenter_wake "$sb_pane"

# Wait for signal to be caught
deadline=$(( $(date +%s) + 5 ))
received=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ -f "$SIG_FILE" ] && grep -q "winch" "$SIG_FILE" 2>/dev/null; then
        received=true
        break
    fi
    sleep 0.05
done

if [ "$received" != "true" ]; then
    echo "FAIL: presenter did not receive SIGWINCH signal"
    exit 1
fi
echo "PASS: sidebar_port_notify_presenter_wake successfully signaled presenter"

echo "=== Test 3: sidebar_switch_execute_hot publishes marker and wakes presenter ==="
SIG_FILE_HOT="$RUN_DIR/sigwinch_hot"
rm -f "$RUN_DIR/ready_hot"
TEST_HOT_CMD="bash -c 'trap \"echo hot_winch >> \\\"$SIG_FILE_HOT\\\"\" WINCH; touch \"$RUN_DIR/ready_hot\"; while true; do sleep 0.1; done'"

# Clean up existing sidebar and provision fresh one in win_a
destroy_sidebar_window "$win_a"
sb_pane_a="$(provision_sidebar_window "$win_a" 30 "$TEST_HOT_CMD")"
[ -n "$sb_pane_a" ] || { echo "FAIL: failed to provision sidebar in win_a"; exit 1; }

deadline=$(( $(date +%s) + 5 ))
while [ ! -f "$RUN_DIR/ready_hot" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "FAIL: presenter in win_a did not start ready in time"
        exit 1
    fi
    sleep 0.05
done

# Clear options on win_a
tmux -L "$SOCKET" set-option -wu -t "$win_a" @dotfiles_sidebar_target_marker 2>/dev/null || true
tmux -L "$SOCKET" set-option -wu -t "$win_a" @dotfiles_sidebar_selection_sync 2>/dev/null || true

# Execute hot switch to sess-a
sidebar_switch_execute_hot "" "sess-a" "$win_a" "$sb_pane_a" 30

# Verify marker handover published
hot_target_marker="$(tmux -L "$SOCKET" show-option -wqv -t "$win_a" @dotfiles_sidebar_target_marker)"
hot_selection_sync="$(tmux -L "$SOCKET" show-option -wqv -t "$win_a" @dotfiles_sidebar_selection_sync)"

if [ "$hot_target_marker" != "sess-a" ]; then
    echo "FAIL: hot switch did not set @dotfiles_sidebar_target_marker (got '$hot_target_marker')"
    exit 1
fi

if [ "$hot_selection_sync" != "sess-a" ]; then
    echo "FAIL: hot switch did not set @dotfiles_sidebar_selection_sync (got '$hot_selection_sync')"
    exit 1
fi

# Verify presenter woke up
deadline=$(( $(date +%s) + 5 ))
hot_received=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ -f "$SIG_FILE_HOT" ] && grep -q "hot_winch" "$SIG_FILE_HOT" 2>/dev/null; then
        hot_received=true
        break
    fi
    sleep 0.05
done

if [ "$hot_received" != "true" ]; then
    echo "FAIL: presenter in win_a did not receive SIGWINCH during hot switch"
    exit 1
fi
echo "PASS: sidebar_switch_execute_hot published marker handover and triggered presenter wake"

echo "ALL MARKER HANDOVER CONTRACT TESTS PASSED!"
