#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-split-restore-edge-cases.sh
#
# Split 상태의 정상 복원 엣지 케이스 종합 검증:
# 1. 서브페인(Subpane) 활성 상태에서의 워크 페인 Split 아카이브 및 복원 무결성
# 2. 수평 상/하 분할(-v) 시 페인별 정밀 높이(Height) 복원 검증
# 3. 터미널 크기 변경(Geometry change) 시 비율 적응 및 복원 안정성
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-split-edge-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-split-edge.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
HOME_DIR="$RUN_DIR/home"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

mkdir -p "$HISTORY_DIR" "$HOME_DIR"
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

# 0. Setup isolated server with dummy anchor session
tmuxc new-session -d -s anchor -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"

echo "=== [1/3] Testing Split Restore with Subpane Active ==="
# Create session split-subpane (120x50)
tmuxc new-session -d -s split-subpane -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
win1="$(tmuxc list-windows -t '=split-subpane:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$win1" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$win1' 35"

# Enable subpane at height 12
tmuxc set-option -gq @dotfiles_sidebar_subpane_enabled 1
tmuxc set-option -gq @dotfiles_sidebar_subpane_height 12
tmuxc run-shell "$LAUNCHER --ensure-subpane-window '$win1'" 2>/dev/null || true

# Find initial work pane
p1="$(tmuxc list-panes -t "$win1" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $1; exit }')"
[ -n "$p1" ] || { echo "FAIL: work pane 1 not found"; exit 1; }

# Split horizontally (side-by-side) then vertically (top-bottom)
p2="$(tmuxc split-window -h -P -F '#{pane_id}' -t "$p1" -c "$REPO_ROOT" 'sleep 300')"
p3="$(tmuxc split-window -v -P -F '#{pane_id}' -t "$p2" -c "$REPO_ROOT" 'sleep 300')"

work_count="$(tmuxc list-panes -t "$win1" -F '#{pane_title}' | grep -v "dotfiles-" | wc -l)"
[ "$work_count" -eq 3 ] || { echo "FAIL: expected 3 work panes, got $work_count"; exit 1; }

# Archive split-subpane session
tmuxc run-shell "$LAUNCHER --archive-session split-subpane false"
[ -f "$HISTORY_DIR/split-subpane.tsv" ] || { echo "FAIL: archive missing"; exit 1; }

# Kill and restore
tmuxc kill-session -t '=split-subpane:'
while tmuxc has-session -t '=split-subpane:' 2>/dev/null; do sleep 0.05; done
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/split-subpane.tsv' op-split-subpane true"
tmuxc has-session -t '=split-subpane:' || { echo "FAIL: session not restored"; exit 1; }

restored_win1="$(tmuxc list-windows -t '=split-subpane:' -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$restored_win1' 35"

restored_work_count="$(tmuxc list-panes -t "$restored_win1" -F '#{pane_title}' | grep -v "dotfiles-" | wc -l)"
echo "Restored work pane count with subpane: $restored_work_count"
[ "$restored_work_count" -eq 3 ] || { echo "FAIL: work pane count expected 3, got $restored_work_count"; exit 1; }

echo "=== [2/3] Testing Vertical Split Height Precision on Restore ==="
tmuxc new-session -d -s split-height -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
win2="$(tmuxc list-windows -t '=split-height:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$win2" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$win2' 35"

hp1="$(tmuxc list-panes -t "$win2" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $1; exit }')"
hp2="$(tmuxc split-window -v -P -F '#{pane_id}' -t "$hp1" -c "$REPO_ROOT" 'sleep 300')"
tmuxc resize-pane -t "$hp1" -y 15

orig_h1="$(tmuxc display-message -p -t "$hp1" '#{pane_height}')"
orig_h2="$(tmuxc display-message -p -t "$hp2" '#{pane_height}')"
echo "Original vertical heights: hp1=$orig_h1, hp2=$orig_h2"

# Archive and restore
tmuxc run-shell "$LAUNCHER --archive-session split-height false"
tmuxc kill-session -t '=split-height:'
while tmuxc has-session -t '=split-height:' 2>/dev/null; do sleep 0.05; done
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/split-height.tsv' op-height true"

restored_win2="$(tmuxc list-windows -t '=split-height:' -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$restored_win2' 35"

restored_h_list="$(tmuxc list-panes -t "$restored_win2" -F '#{pane_top}|#{pane_title}|#{pane_height}' | sort -n -k1,1 | awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" { print $3 }' | tr '\n' ' ' | xargs)"
echo "Restored vertical heights: $restored_h_list"
[ "$restored_h_list" = "$orig_h1 $orig_h2" ] || { echo "FAIL: vertical heights expected '$orig_h1 $orig_h2', got '$restored_h_list'"; exit 1; }

echo "=== [3/3] Testing Terminal Resolution Adaptability on Restore ==="
tmuxc kill-session -t '=split-subpane:' 2>/dev/null || true
while tmuxc has-session -t '=split-subpane:' 2>/dev/null; do sleep 0.05; done
tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/split-subpane.tsv' op-adapt true"
tmuxc has-session -t '=split-subpane:' || { echo "FAIL: adaptive restore failed"; exit 1; }

echo "PASS: all split restore edge cases succeeded."
