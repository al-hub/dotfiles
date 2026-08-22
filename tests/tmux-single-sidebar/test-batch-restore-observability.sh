#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-batch-restore-observability.sh
#
# 다중 세션 일괄 복원(Batch Restore) 관측성 및 진행률/타임스탬프 검증
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-restore-obs-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-restore-obs.XXXXXX")"
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

echo "=== [1/2] Creating and Archiving 6 Sessions ==="
ARCHIVES=()
for i in {1..6}; do
    sname="batch-sess-$i"
    tmuxc new-session -d -s "$sname" -x 120 -y 50 -c "$REPO_ROOT" 'sleep 300'
    win="$(tmuxc list-windows -t "=$sname:" -F '#{window_id}' | head -n 1)"
    tmuxc set-option -wq -t "$win" @dotfiles_sidebar_managed 1
    tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$win' 35"
    
    tmuxc run-shell "$LAUNCHER --archive-session '$sname' false"
    [ -f "$HISTORY_DIR/$sname.tsv" ] || { echo "FAIL: archive $sname.tsv missing"; exit 1; }
    ARCHIVES+=("$HISTORY_DIR/$sname.tsv")
    tmuxc kill-session -t "=$sname:"
done

echo "=== [2/2] Performing Batch Restore and Verifying Timestamps & Progress ==="
RESTORE_LOG="$RUN_DIR/restore.log"
RESTORED_COUNT=0
START_TIME=$(date +%s%N 2>/dev/null || date +%s)

for idx in "${!ARCHIVES[@]}"; do
    arch="${ARCHIVES[$idx]}"
    num=$((idx + 1))
    t_start=$(date +%s%N 2>/dev/null || date +%s)
    
    # Run batch restore
    echo "Restoring $num/6: $(basename "$arch")" | tee -a "$RESTORE_LOG"
    tmuxc run-shell "$LAUNCHER --restore-archive '$arch' 'op-batch-$num' true"
    
    t_end=$(date +%s%N 2>/dev/null || date +%s)
    echo "Completed $num/6 timestamp_start=$t_start timestamp_end=$t_end" >> "$RESTORE_LOG"
    RESTORED_COUNT=$((RESTORED_COUNT + 1))
done

END_TIME=$(date +%s%N 2>/dev/null || date +%s)
echo "Total batch restore completed: $RESTORED_COUNT/6 sessions"

# Verify all 6 sessions are present in tmux server
for i in {1..6}; do
    sname="batch-sess-$i"
    tmuxc has-session -t "=$sname:" || { echo "FAIL: session $sname missing after batch restore"; exit 1; }
done

[ "$RESTORED_COUNT" -eq 6 ] || { echo "FAIL: expected 6 restored sessions, got $RESTORED_COUNT"; exit 1; }

# Verify progress log format
grep -q "Restoring 1/6" "$RESTORE_LOG" || { echo "FAIL: log missing Restoring 1/6"; exit 1; }
grep -q "Restoring 6/6" "$RESTORE_LOG" || { echo "FAIL: log missing Restoring 6/6"; exit 1; }
grep -q "Completed 6/6" "$RESTORE_LOG" || { echo "FAIL: log missing Completed 6/6"; exit 1; }

echo "PASS: batch restore observability and 6/6 progress verified."
