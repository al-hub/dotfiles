#!/usr/bin/env bash
# Test suite for verifying basic operational fixes (Issues 1-4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-basic-defects-$$"

tmuxc() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    tmuxc kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "=== TDD Test Suite: Basic Operations (Issues 1-4) ==="

# 1. Setup server and client
tmuxc new-session -d -s 0 -n zsh -c "$REPO_ROOT" 'sleep 300'
setsid script -qefc "TERM=xterm-256color tmux -L $SOCKET attach-session -t 0" /tmp/test-basic-client.log >/dev/null 2>&1 &
sleep 1

CLIENT_TTY="$(tmuxc list-clients -F '#{client_tty}' | head -n 1)"
[ -n "$CLIENT_TTY" ] || { echo "FAIL: Client attachment failed"; exit 1; }

# Test 1: Issue 1 - open_sidebar (--open-sidebar) must keep sidebar alive
echo "Testing Issue 1: --open-sidebar creates and preserves sidebar pane..."
tmuxc run-shell "$LAUNCHER --open-sidebar"
sleep 0.5
SIDEBAR_PANE="$(tmuxc list-panes -t 0 -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"
if [ -n "$SIDEBAR_PANE" ]; then
    echo "PASS: Issue 1 - sidebar pane $SIDEBAR_PANE remains alive after --open-sidebar"
else
    echo "FAIL: Issue 1 - sidebar pane vanished after --open-sidebar"
    exit 1
fi

# Test 2: Issue 3 - Deleting numeric session 0 from session test_target targets session 0
echo "Testing Issue 3: Deleting numeric session 0..."
tmuxc new-session -d -s test_target -c "$REPO_ROOT" 'sleep 300'
target_win="$(tmuxc list-windows -t test_target -F '#{window_id}' | head -n 1)"
tmuxc set-option -w -t "$target_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window $target_win"
tmuxc switch-client -c "$CLIENT_TTY" -t test_target
sleep 1
sidebar_pane="$(tmuxc list-panes -t "$target_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"
tmuxc select-pane -t "$sidebar_pane"
sleep 0.2

# Move selection to 0
cur_sel="$(tmuxc capture-pane -p -t "$sidebar_pane" | sed $'s/\033\\[[0-9;]*m//g' | awk '$1==">*"{print $2; exit} $1==">"{print $2; exit}')"
if [ "$cur_sel" = "test_target" ]; then
    tmuxc send-keys -t "$sidebar_pane" Up
    sleep 0.5
fi
tmuxc send-keys -t "$sidebar_pane" d
sleep 0.5
PROMPT_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
if echo "$PROMPT_CAP" | grep -Fq "Delete 0?"; then
    echo "PASS: Issue 3 - prompt correctly targets session 0"
else
    echo "FAIL: Issue 3 - prompt target mismatch. Captured: $PROMPT_CAP"
    exit 1
fi

# Test 3: Issue 4 - Cancel prompt via q / Esc
echo "Testing Issue 4: Canceling prompt via q..."
tmuxc send-keys -t "$sidebar_pane" q
tmuxc send-keys -t "$sidebar_pane" Enter
sleep 0.5
PROMPT_CANCEL_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
if echo "$PROMPT_CANCEL_CAP" | grep -Fq "Delete 0?"; then
    echo "FAIL: Issue 4 - prompt not cancelled by q"
    exit 1
else
    echo "PASS: Issue 4 - prompt cancelled by q"
fi

# Test 4: Issue 2 - Session switch aligns selection cursor to active session
echo "Testing Issue 2: Session switch aligns cursor..."
sleep 0.5
tmuxc select-pane -t "$sidebar_pane"
sleep 0.2
cur_sel="$(tmuxc capture-pane -p -t "$sidebar_pane" | sed $'s/\033\\[[0-9;]*m//g' | awk '$1==">*"{print $2; exit} $1==">"{print $2; exit}')"
if [ "$cur_sel" = "test_target" ]; then
    tmuxc send-keys -t "$sidebar_pane" Up
    sleep 0.5
fi
tmuxc send-keys -t "$sidebar_pane" Enter
sleep 1.0
ACTUAL_CLIENT_SESSION="$(tmuxc list-clients -F '#{session_name}')"
if [ "$ACTUAL_CLIENT_SESSION" = "0" ]; then
    echo "PASS: Issue 2 - client switched to session 0"
else
    echo "FAIL: Issue 2 - client session is $ACTUAL_CLIENT_SESSION, expected 0"
    exit 1
fi

echo "=== ALL BASIC DEFECT TDD TESTS PASSED ==="
