#!/usr/bin/env bash
set -euo pipefail

# Test: Batch Restore Layout Integrity
# Ensures that batch restore (restore_batch_mode=true) preserves work-pane layout widths
# and restores exact geometries when sidebars are lazily provisioned on demand.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-batch-restore-layout-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-batch-restore-layout.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
mkdir -p "$HISTORY_DIR" "$RUN_DIR/home"

cleanup() {
  "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

tmuxc() { HOME="$RUN_DIR/home" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" "${TMUX[@]}" "$@"; }
fail() {
  KEEP_RUN_DIR=true
  printf 'FAIL: %s\nartifacts=%s\n' "$*" "$RUN_DIR" >&2
  tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|width=#{pane_width}|height=#{pane_height}|left=#{pane_left}|top=#{pane_top}' > "$RUN_DIR/panes.txt" 2>/dev/null || true
  exit 1
}

# 1. Setup isolated server with dummy session to keep server alive
tmuxc new-session -d -s dummy -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'

# 2. Session 1 (sess1, 120x50): Provision sidebar (width 35). Split work pane vertically (-h) into 2 panes.
#    Resize first work pane to width 25 (second pane becomes width 58).
tmuxc new-session -d -s sess1 -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
sess1_win="$(tmuxc list-windows -t '=sess1:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$sess1_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$sess1_win' 35"

sess1_work_pane1="$(tmuxc list-panes -t "$sess1_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $1; exit }')"
[ -n "$sess1_work_pane1" ] || fail "sess1 work pane 1 not found"
sess1_work_pane2="$(tmuxc split-window -h -P -F '#{pane_id}' -t "$sess1_work_pane1" -c "$REPO_ROOT" 'sleep 300')"
tmuxc resize-pane -t "$sess1_work_pane1" -x 25

# 3. Session 2 (sess2, 120x50): Identically, provision sidebar (width 35). Split work pane vertically into 2 panes (widths 25 and 58).
tmuxc new-session -d -s sess2 -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
sess2_win="$(tmuxc list-windows -t '=sess2:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$sess2_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$sess2_win' 35"

sess2_work_pane1="$(tmuxc list-panes -t "$sess2_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $1; exit }')"
[ -n "$sess2_work_pane1" ] || fail "sess2 work pane 1 not found"
sess2_work_pane2="$(tmuxc split-window -h -P -F '#{pane_id}' -t "$sess2_work_pane1" -c "$REPO_ROOT" 'sleep 300')"
tmuxc resize-pane -t "$sess2_work_pane1" -x 25

# Verify initial dimensions before archive
sess1_p1_w="$(tmuxc display-message -p -t "$sess1_work_pane1" '#{pane_width}')"
sess1_p2_w="$(tmuxc display-message -p -t "$sess1_work_pane2" '#{pane_width}')"
[ "$sess1_p1_w" -eq 25 ] || fail "sess1 pre-archive pane1 width expected 25, got $sess1_p1_w"
[ "$sess1_p2_w" -eq 58 ] || fail "sess1 pre-archive pane2 width expected 58, got $sess1_p2_w"

# 4. Archive both sess1 and sess2 to $HISTORY_DIR
tmuxc run-shell "$LAUNCHER --archive-session sess1 false" || fail "failed to archive sess1"
tmuxc run-shell "$LAUNCHER --archive-session sess2 false" || fail "failed to archive sess2"

[ -f "$HISTORY_DIR/sess1.tsv" ] || fail "sess1.tsv missing in $HISTORY_DIR"
[ -f "$HISTORY_DIR/sess2.tsv" ] || fail "sess2.tsv missing in $HISTORY_DIR"

# 5. Kill sess1 and sess2
tmuxc kill-session -t '=sess1:' || fail "failed to kill sess1"
tmuxc kill-session -t '=sess2:' || fail "failed to kill sess2"

# 6. Perform batch restore on both sess1 and sess2 (restore_batch_mode=true)
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/sess1.tsv' op-1 true" || fail "failed to batch restore sess1"
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/sess2.tsv' op-2 true" || fail "failed to batch restore sess2"

tmuxc has-session -t '=sess1:' >/dev/null 2>&1 || fail "sess1 not restored"
tmuxc has-session -t '=sess2:' >/dev/null 2>&1 || fail "sess2 not restored"

# 7. Provision sidebars on demand on sess1 and sess2
tmuxc set-option -g @dotfiles_sidebar_restore_topology 0 2>/dev/null || true
tmuxc set-option -g @tmux_batch_busy 0 2>/dev/null || true
tmuxc set-option -g @dotfiles_sidebar_enabled 1 2>/dev/null || true

sess1_restored_win="$(tmuxc list-windows -t '=sess1:' -F '#{window_id}' | head -n 1)"
sess2_restored_win="$(tmuxc list-windows -t '=sess2:' -F '#{window_id}' | head -n 1)"

tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$sess1_restored_win' 35" || fail "failed to ensure sidebar window sess1"
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$sess2_restored_win' 35" || fail "failed to ensure sidebar window sess2"

# 8. CRITICAL ASSERTION: In both sess1 and sess2, the work pane widths must be EXACTLY 25 and 58
sess1_work_widths="$(tmuxc list-panes -t "$sess1_restored_win" -F '#{pane_left}|#{pane_title}|#{pane_width}' | sort -n -k1,1 | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $3 }' | tr '\n' ' ' | xargs)"
sess2_work_widths="$(tmuxc list-panes -t "$sess2_restored_win" -F '#{pane_left}|#{pane_title}|#{pane_width}' | sort -n -k1,1 | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $3 }' | tr '\n' ' ' | xargs)"

echo "sess1 restored work pane widths: $sess1_work_widths"
echo "sess2 restored work pane widths: $sess2_work_widths"

[ "$sess1_work_widths" = "25 58" ] || fail "sess1 work pane widths expected '25 58', got '$sess1_work_widths'"
[ "$sess2_work_widths" = "25 58" ] || fail "sess2 work pane widths expected '25 58', got '$sess2_work_widths'"

echo "PASS: batch restore layout integrity verified"
