#!/usr/bin/env bash
# Exact reproduction test matching the user workflow:
# 1. Start tmux session (like user's session 0)
# 2. Enter history mode (o) and restore multiple real archived sessions
# 3. Toggle subpane (m)
# 4. Switch between restored sessions using Enter (switch-client)
# 5. Capture trace events, pane layout anomalies, error logs, and subpane hub interactions
set -euo pipefail

SOCKET="test-user-exact-$$"
TMP_DIR="$(mktemp -d /tmp/test-user-exact.XXXXXX)"
export TMUX_SESSION_HISTORY_DIR="$TMP_DIR/history"
mkdir -p "$TMUX_SESSION_HISTORY_DIR"

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== 1. Copying 3 real TSV archives ==="
cp ~/.cache/dotfiles/tmux-session-history/20260815-234203-595506-mmm-1w.tsv "$TMUX_SESSION_HISTORY_DIR/"
cp ~/.cache/dotfiles/tmux-session-history/20260815-234219-599516-lll-1w.tsv "$TMUX_SESSION_HISTORY_DIR/"
cp ~/.cache/dotfiles/tmux-session-history/20260815-234229-602396-kkk-1w.tsv "$TMUX_SESSION_HISTORY_DIR/"

echo "=== 2. Launching attached tmux terminal with pty-bridge ==="
tmux -L "$SOCKET" -f /home/al-hub/workspace/dotfiles/dotfiles/tmux.conf new-session -d -s 0 -n main -x 120 -y 35 'sleep 300'
setsid script -qefc "TERM=xterm-256color tmux -L '$SOCKET' attach-session -t 0" "$TMP_DIR/client.log" >/dev/null 2>&1 &
sleep 0.5
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --open-sidebar
sleep 0.5

echo "--- Sessions before restore ---"
tmux -L "$SOCKET" list-sessions

echo "=== 3. Restoring 3 archives via launcher CLI restore ==="
for f in "$TMUX_SESSION_HISTORY_DIR"/*.tsv; do
    echo "Restoring $f..."
    DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --restore-archive "$f" 2>&1 || echo "Restore failed: $?"
done
sleep 0.5

echo "--- Sessions after restore ---"
tmux -L "$SOCKET" list-sessions
echo "--- Panes across all sessions after restore ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "=== 4. Toggling subpane (m) in session 0 ==="
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --toggle-subpane
sleep 0.5

echo "--- Panes across all sessions after subpane ON ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "=== 5. Switching between sessions using switch-client and verifying subpane lease ==="
# Test switching to mmm
echo "Switching to mmm..."
client_tty="$(tmux -L "$SOCKET" list-clients -F '#{client_tty}' | head -n 1)"
tmux -L "$SOCKET" switch-client -c "$client_tty" -t "=mmm:"
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --sync-active-window "$client_tty"
sleep 0.5

echo "--- Panes across all sessions after switch to mmm ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "Switching to lll..."
tmux -L "$SOCKET" switch-client -c "$client_tty" -t "=lll:"
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --sync-active-window "$client_tty"
sleep 0.5

echo "Switching to kkk..."
tmux -L "$SOCKET" switch-client -c "$client_tty" -t "=kkk:"
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --sync-active-window "$client_tty"
sleep 0.5

echo "=== 6. Final State Inspection ==="
echo "--- Sessions ---"
tmux -L "$SOCKET" list-sessions
echo "--- Panes ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}|cmd=#{pane_current_command}'
