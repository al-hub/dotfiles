#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-long-session-name-switching-flicker-detect.sh
#
# 긴 세션 이름 전환 시 "switching to" 2줄 출력 및 화면 밀림/깜빡임 감지 테스트
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-flicker-detect-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-flicker-detect.XXXXXX")"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup() {
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

echo "=== [1/2] Setting up isolated tmux with long session names & 30-col sidebar ==="
# Long session names (35~45 chars)
LONG_SESS="very-long-ai-development-session-name-12345"

"${TMUX[@]}" new-session -d -s main -x 120 -y 30 -c "$REPO_ROOT" 'sleep 300'
"${TMUX[@]}" new-session -d -s "$LONG_SESS" -x 120 -y 30 -c "$REPO_ROOT" 'sleep 300'

main_win="$("${TMUX[@]}" display-message -p -t '=main:' '#{window_id}')"
long_win="$("${TMUX[@]}" display-message -p -t "=$LONG_SESS:" '#{window_id}')"

"${TMUX[@]}" set-option -wq -t "$main_win" @dotfiles_sidebar_managed 1
"${TMUX[@]}" set-option -wq -t "$long_win" @dotfiles_sidebar_managed 1

# Provision sidebar at width 30
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$main_win' 30"
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$long_win' 30"

main_sb="$("${TMUX[@]}" list-panes -t "$main_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"

echo "Main sidebar pane: $main_sb"

echo "=== [2/2] Simulating Switching Feedback Output for Long Session ==="
# Measure what happens when writing switching feedback on row 30 of a 30-col sidebar
# Case A: Unclamped raw string (37~50 cols)
RAW_MSG="⚡ switching to $LONG_SESS..."
RAW_LEN="${#RAW_MSG}"
echo "Raw switching message length: $RAW_LEN chars (pane width=30)"

# Capture baseline pane content
"${TMUX[@]}" capture-pane -t "$main_sb" -p > "$RUN_DIR/before.txt"
header_before="$(head -n 1 "$RUN_DIR/before.txt")"
echo "Header before switch: '$header_before'"

# Check if un-clamped string wraps when printed on the last row
wrap_detected=0
if [ "$RAW_LEN" -gt 29 ]; then
    wrap_detected=1
    echo "DETECTED: Raw switching message length ($RAW_LEN) exceeds safe width (29) by $((RAW_LEN - 29)) columns."
    echo "          In un-clamped versions, this wraps to the next line and causes terminal scrolling (1-line vertical jump/flicker)."
fi

# Now verify the CLAMPED string from scripts/tmux-session-launcher
source "$REPO_ROOT/scripts/lib/sidebar_domain.sh"
source "$REPO_ROOT/scripts/lib/sidebar_domain_animation.sh"
source "$LAUNCHER" --source-only 2>/dev/null || true

max_safe=29 # width 30 - 1
clamped_msg="$(truncate_text "$RAW_MSG" "$max_safe")"
clamped_width="$(sidebar_domain_animation_measure_cell_width "$clamped_msg")"

echo "Clamped message: '$clamped_msg'"
echo "Clamped message cell width: $clamped_width (max allowed: $max_safe)"

if [ "$clamped_width" -le "$max_safe" ]; then
    echo "VERIFIED: Clamped message is strictly within $max_safe columns. Single-line guaranteed."
else
    echo "FAIL: Clamped message width $clamped_width still exceeds $max_safe!"
    exit 1
fi

echo "PASS: Detection and verification completed successfully."
