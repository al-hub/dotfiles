#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCKET="test-presenter-handover-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-presenter-handover.XXXXXX")"
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

echo "=== Test 1: Provision sidebar in sess-a and verify initial markers ==="
tmux -L "$SOCKET" split-window -d -t "=sess-a:0" -h -b -l 35 "$SCRIPT_DIR/scripts/tmux-session-launcher --sidebar"

# Wait for sidebar pane to become ready
deadline=$(( $(date +%s) + 5 ))
sidebar_pane=""
while [ "$(date +%s)" -lt "$deadline" ]; do
    sidebar_pane="$(sidebar_window_pane "$win_a" || true)"
    if [ -n "$sidebar_pane" ]; then
        ready="$(tmux -L "$SOCKET" show-option -wqv -t "$win_a" @dotfiles_sidebar_ready 2>/dev/null || true)"
        if [ "$ready" = "1" ]; then
            break
        fi
    fi
    sleep 0.05
done

[ -n "$sidebar_pane" ] || { echo "FAIL: sidebar pane not provisioned in time"; exit 1; }

# Verify initial capture has sess-a marked with >*
deadline=$(( $(date +%s) + 5 ))
initial_marked=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    cap="$(tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true)"
    if echo "$cap" | grep -q '>\* sess-a' || echo "$cap" | grep -q '>\*.*sess-a'; then
        initial_marked=true
        break
    fi
    sleep 0.05
done

if [ "$initial_marked" != "true" ]; then
    echo "FAIL: initial capture did not show sess-a as >*"
    echo "Capture was:"
    tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true
    exit 1
fi
echo "PASS: initial sidebar in sess-a shows sess-a marked as >*"

echo "=== Test 2: Publish marker handover to sess-b and notify presenter wake ==="
sidebar_port_publish_marker_handover "$win_a" "sess-b"
sidebar_port_notify_presenter_wake "$sidebar_pane"

# Wait for sidebar to update its markers to sess-b
deadline=$(( $(date +%s) + 5 ))
handover_success=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    cap="$(tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true)"
    if (echo "$cap" | grep -q '>\* sess-b' || echo "$cap" | grep -q '>\*.*sess-b') && ! (echo "$cap" | grep -q '>\* sess-a'); then
        handover_success=true
        break
    fi
    sleep 0.05
done

if [ "$handover_success" != "true" ]; then
    echo "FAIL: presenter did not update markers to sess-b after handover wake"
    echo "Capture was:"
    tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true
    exit 1
fi

target_marker_leftover="$(tmux -L "$SOCKET" show-option -wqv -t "$win_a" @dotfiles_sidebar_target_marker 2>/dev/null || true)"
if [ -n "$target_marker_leftover" ]; then
    echo "FAIL: @dotfiles_sidebar_target_marker was not consumed/cleared, found '$target_marker_leftover'"
    exit 1
fi
echo "PASS: presenter immediately updated markers to sess-b and consumed target marker"

echo "=== Test 3: Marker handover back to sess-a ==="
sidebar_port_publish_marker_handover "$win_a" "sess-a"
sidebar_port_notify_presenter_wake "$sidebar_pane"

deadline=$(( $(date +%s) + 5 ))
handover_back_success=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    cap="$(tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true)"
    if (echo "$cap" | grep -q '>\* sess-a' || echo "$cap" | grep -q '>\*.*sess-a') && ! (echo "$cap" | grep -q '>\* sess-b'); then
        handover_back_success=true
        break
    fi
    sleep 0.05
done

if [ "$handover_back_success" != "true" ]; then
    echo "FAIL: presenter did not update markers back to sess-a"
    echo "Capture was:"
    tmux -L "$SOCKET" capture-pane -p -t "$sidebar_pane" 2>/dev/null || true
    exit 1
fi
echo "PASS: presenter updated markers back to sess-a"

echo "ALL PRESENTER HANDOVER E2E TESTS PASSED"
