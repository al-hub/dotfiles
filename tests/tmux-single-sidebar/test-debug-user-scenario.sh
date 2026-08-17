#!/usr/bin/env bash
# Reproduction script for user scenario:
# 1. Restore multiple archived sessions via history mode (o -> space -> Enter)
# 2. Toggle subpane (m)
# 3. Switch between restored sessions using Enter
# 4. Inspect errors, pane duplicates, focus loss, and subpane hub anomalies
set -euo pipefail

SOCKET="test-user-scenario-$$"
TMP_DIR="$(mktemp -d /tmp/test-user-scenario.XXXXXX)"
export TMUX_SESSION_HISTORY_DIR="$TMP_DIR/history"
mkdir -p "$TMUX_SESSION_HISTORY_DIR"

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== 1. Preparing test archives in $TMUX_SESSION_HISTORY_DIR ==="
cat <<'EOF' > "$TMUX_SESSION_HISTORY_DIR/20260818-000001-100-alpha-1w.tsv"
session	alpha
archive_version	3
window	0	main	120x35	0,0,120,35
pane	0	0	%10	work-alpha	0,0,120,35	1	0	/home/al-hub
EOF

cat <<'EOF' > "$TMUX_SESSION_HISTORY_DIR/20260818-000002-200-beta-1w.tsv"
session	beta
archive_version	3
window	0	main	120x35	0,0,120,35
pane	0	0	%20	work-beta	0,0,120,35	1	0	/home/al-hub
EOF

cat <<'EOF' > "$TMUX_SESSION_HISTORY_DIR/20260818-000003-300-gamma-1w.tsv"
session	gamma
archive_version	3
window	0	main	120x35	0,0,120,35
pane	0	0	%30	work-gamma	0,0,120,35	1	0	/home/al-hub
EOF

echo "=== 2. Creating initial tmux session & starting sidebar ==="
tmux -L "$SOCKET" -f /home/al-hub/workspace/dotfiles/dotfiles/tmux.conf new-session -d -s initial -n main -x 120 -y 35 'sleep 300'
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --open-sidebar
sleep 0.5

echo "--- Sessions before restore ---"
tmux -L "$SOCKET" list-sessions

echo "=== 3. Restoring sessions via history restore logic ==="
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --restore-archive "$TMUX_SESSION_HISTORY_DIR/20260818-000001-100-alpha-1w.tsv" 2>&1 || echo "restore alpha result: $?"
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --restore-archive "$TMUX_SESSION_HISTORY_DIR/20260818-000002-200-beta-1w.tsv" 2>&1 || echo "restore beta result: $?"
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --restore-archive "$TMUX_SESSION_HISTORY_DIR/20260818-000003-300-gamma-1w.tsv" 2>&1 || echo "restore gamma result: $?"
sleep 0.5

echo "--- Sessions after restore ---"
tmux -L "$SOCKET" list-sessions
echo "--- Panes across all sessions after restore ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "=== 4. Toggling subpane (m) in session initial ==="
DOTFILES_DIR="/home/al-hub/workspace/dotfiles" TMUX="$SOCKET" /home/al-hub/workspace/dotfiles/dist/tmux-session-launcher --toggle-subpane
sleep 0.5

echo "--- Panes across all sessions after subpane ON ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "=== 5. Switching from session initial to restored session alpha ==="
tmux -L "$SOCKET" switch-client -t "=alpha:" 2>&1 || echo "switch error: $?"
sleep 0.5

echo "--- Panes across all sessions after switch to alpha ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'

echo "=== 6. Switching to session beta and then gamma ==="
tmux -L "$SOCKET" switch-client -t "=beta:" 2>&1 || echo "switch to beta error: $?"
sleep 0.5
tmux -L "$SOCKET" switch-client -t "=gamma:" 2>&1 || echo "switch to gamma error: $?"
sleep 0.5

echo "--- Final Panes across all sessions ---"
tmux -L "$SOCKET" list-panes -a -F 'session=#{session_name}|win=#{window_id}|pane=#{pane_id}|subpane=#{@dotfiles_sidebar_subpane}|title=#{pane_title}'
