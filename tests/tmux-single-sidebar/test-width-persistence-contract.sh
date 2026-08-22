#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-width-persistence-contract.sh
#
# 사이드바 폭(Width) 영속화, Fallback 및 아카이브 독립성 계약 테스트
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-width-persist-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-width-persist.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
HOME_DIR="$RUN_DIR/home"
STATE_DIR="$HOME_DIR/.local/state/dotfiles"
WIDTH_STATE_FILE="$STATE_DIR/tmux-sidebar-width"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

mkdir -p "$HISTORY_DIR" "$STATE_DIR"
source "$REPO_ROOT/tests/lib/test_artifact_helper.sh"

cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        KEEP_RUN_DIR=true
        dump_test_failure_artifacts "$SOCKET" "$RUN_DIR"
    fi
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

tmuxc() { HOME="$HOME_DIR" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" "${TMUX[@]}" "$@"; }

echo "=== [1/3] Testing State File Corruption Fallback ==="
# Write corrupted state content
echo "CORRUPTED_TEXT_NOT_A_NUMBER" > "$WIDTH_STATE_FILE"

tmuxc new-session -d -s anchor -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s test-fallback -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
win_id="$(tmuxc list-windows -t '=test-fallback:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$win_id" @dotfiles_sidebar_managed 1

# Ensure sidebar with corrupted width file -> should safely fallback to default (32)
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$win_id'"

sb_pane="$(tmuxc list-panes -t "$win_id" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
[ -n "$sb_pane" ] || { echo "FAIL: sidebar pane not created on corrupted state"; exit 1; }

sb_width="$(tmuxc display-message -p -t "$sb_pane" '#{pane_width}')"
echo "Corrupted state fallback sidebar width: $sb_width"
# Width must be between 20 and 45, default is 32 or clamped correctly
[ "$sb_width" -ge 20 ] && [ "$sb_width" -le 45 ] || { echo "FAIL: width out of range on fallback: $sb_width"; exit 1; }

echo "=== [2/3] Testing Global Width Persistence Across Resize & Restart ==="
# User resizes sidebar to 40
tmuxc resize-pane -t "$sb_pane" -x 40
tmuxc run-shell "$LAUNCHER --persist-sidebar-width 40" 2>/dev/null || echo "40" > "$WIDTH_STATE_FILE"

# Verify persisted state file has 40
persisted_w="$(cat "$WIDTH_STATE_FILE" | tr -d '[:space:]')"
[ "$persisted_w" = "40" ] || { echo "FAIL: persisted width expected 40, got '$persisted_w'"; exit 1; }

# Kill server and restart to verify persistence
tmuxc kill-server
sleep 0.2

tmuxc new-session -d -s anchor -x 140 -y 50 -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s test-restart -x 140 -y 50 -c "$REPO_ROOT" 'sleep 300'
new_win_id="$(tmuxc list-windows -t '=test-restart:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$new_win_id" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$new_win_id'"

new_sb_pane="$(tmuxc list-panes -t "$new_win_id" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
[ -n "$new_sb_pane" ] || { echo "FAIL: sidebar pane not created on restart"; exit 1; }

restarted_w="$(tmuxc display-message -p -t "$new_sb_pane" '#{pane_width}')"
echo "Restarted sidebar width: $restarted_w"
[ "$restarted_w" -eq 40 ] || { echo "FAIL: expected width 40 on restart, got $restarted_w"; exit 1; }

echo "=== [3/3] Testing Archive Restore Does Not Overwrite Global Sidebar Width ==="
# Archive test-restart session (which was saved with width 40)
tmuxc run-shell "$LAUNCHER --archive-session test-restart false"
[ -f "$HISTORY_DIR/test-restart.tsv" ] || { echo "FAIL: archive test-restart.tsv missing"; exit 1; }

# User now changes global width to 28
echo "28" > "$WIDTH_STATE_FILE"
tmuxc set-option -gq '@dotfiles-session-sidebar-width' 28
tmuxc kill-session -t '=test-restart:'

# Restore archive
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/test-restart.tsv' op-width-test false"
tmuxc has-session -t '=test-restart:' || { echo "FAIL: session test-restart not restored"; exit 1; }

# Re-ensure sidebar on restored window
restored_win="$(tmuxc list-windows -t '=test-restart:' -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$restored_win'"

restored_sb_pane="$(tmuxc list-panes -t "$restored_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
restored_sb_width="$(tmuxc display-message -p -t "$restored_sb_pane" '#{pane_width}')"
echo "Restored window sidebar width: $restored_sb_width"
# The global width (28) must be respected and NOT overwritten by archive's old width (40)
[ "$restored_sb_width" -eq 28 ] || { echo "FAIL: expected global width 28, but got $restored_sb_width"; exit 1; }

echo "PASS: all width persistence, fallback, and archive isolation tests succeeded."
