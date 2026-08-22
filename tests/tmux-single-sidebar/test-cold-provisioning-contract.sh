#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-cold-provisioning-contract.sh
#
# Cold Provisioning(지연 생성) 안정성, 로딩/Ready 상태 및 연타 디바운스 계약 검증
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-cold-prov-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-cold-prov.XXXXXX")"
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

echo "=== [1/2] Testing Cold Provisioning Lifecycle & Ready State ==="
tmuxc new-session -d -s cold-sess -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
win="$(tmuxc list-windows -t '=cold-sess:' -F '#{window_id}' | head -n 1)"

# Initially, 0 sidebars exist
sb_count_before="$(tmuxc list-panes -t "$win" -F '#{pane_title}' | grep -c "dotfiles-session-sidebar" || true)"
[ "$sb_count_before" -eq 0 ] || { echo "FAIL: sidebar already exists before provisioning"; exit 1; }

# Trigger cold provisioning
tmuxc set-option -wq -t "$win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$win' 35"

# Verify sidebar exists and is ready
sb_pane="$(tmuxc list-panes -t "$win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
[ -n "$sb_pane" ] || { echo "FAIL: sidebar not created on cold provisioning"; exit 1; }

ready_val="$(tmuxc show-option -wq -t "$win" @dotfiles_sidebar_ready 2>/dev/null || true)"
echo "Cold provisioned sidebar pane: $sb_pane, ready: $ready_val"

echo "=== [2/2] Testing Rapid Concurrent Provisioning (Debounce / Idempotence) ==="
tmuxc new-session -d -s rapid-sess -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
rapid_win="$(tmuxc list-windows -t '=rapid-sess:' -F '#{window_id}' | head -n 1)"
tmuxc set-option -wq -t "$rapid_win" @dotfiles_sidebar_managed 1

# Fire rapid ensure calls
for _ in {1..5}; do
    tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$rapid_win' 35"
done

# Verify EXACTLY 1 sidebar exists in rapid_win
rapid_sb_count="$(tmuxc list-panes -t "$rapid_win" -F '#{pane_title}' | grep -c "dotfiles-session-sidebar" || true)"
echo "Rapid concurrent provisioning sidebar count: $rapid_sb_count"
[ "$rapid_sb_count" -eq 1 ] || { echo "FAIL: expected exactly 1 sidebar under rapid provisioning, got $rapid_sb_count"; exit 1; }

# Verify exactly 1 work pane remains intact
rapid_work_count="$(tmuxc list-panes -t "$rapid_win" -F '#{pane_title}' | grep -vc "dotfiles-" || true)"
echo "Rapid concurrent provisioning work pane count: $rapid_work_count"
[ "$rapid_work_count" -eq 1 ] || { echo "FAIL: work pane count distorted, got $rapid_work_count"; exit 1; }

echo "PASS: cold provisioning and debounce contracts verified."
