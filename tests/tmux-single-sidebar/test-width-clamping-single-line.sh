#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-width-clamping-single-line.sh
#
# 사이드바 폭(Width)에 따른 한 줄 렌더링 무결성 및 줄넘김 방지 검증:
# 1. truncate_text의 CJK / Emoji / 일반 문자열 단일 행 너비 정합성
# 2. switching 메시지 및 queued 메시지가 bottom row 폭(width - 1) 내에 완전히 클램핑되는지 검증
# 3. 좁은 폭(15, 20, 24, 30, 35, 50)에서도 2줄 이상 줄넘김(Auto-wrap / Scroll)이 0건인지 검증
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"

echo "=== [1/3] Testing truncate_text & Cell-Width Awareness ==="
source "$REPO_ROOT/scripts/lib/sidebar_domain.sh"
source "$REPO_ROOT/scripts/lib/sidebar_domain_animation.sh"
source "$LAUNCHER" --source-only 2>/dev/null || true

# Test 1: ASCII string truncation
t1="$(truncate_text "12345678901234567890" 10)"
[ "$t1" = "1234567890" ] || { echo "FAIL: ASCII truncation expected '1234567890', got '$t1'"; exit 1; }

# Test 2: CJK Korean string (2 cells each) in max_width=5 -> 2 chars = 4 cells
t2="$(truncate_text "가나다라마바사" 5)"
[ "$t2" = "가나" ] || { echo "FAIL: Korean truncation expected '가나', got '$t2'"; exit 1; }

# Test 3: Emoji (2 cells) with prefix
t3="$(truncate_text "⚡ switching to my-super-long-session-name..." 15)"
# ⚡ (2 cells) + " switching to" (13 cells) = 15 cells
w3="$(sidebar_domain_animation_measure_cell_width "$t3")"
echo "Truncated emoji message: '$t3' (width=$w3)"
[ "$w3" -le 15 ] || { echo "FAIL: cell width exceeded 15, got $w3"; exit 1; }

echo "=== [2/3] Verifying Single-Line Clamping Across Various Sidebar Widths ==="
WIDTHS=(12 15 20 24 30 35 50)
LONG_SESSIONS=(
    "dotfiles-subpane-hub"
    "very-long-session-name-with-many-words-12345"
    "한글세션이름테스트_오픈코드"
    "project-🚀-super-ai-workflow"
)

for w in "${WIDTHS[@]}"; do
    max_safe=$((w - 1))
    [ "$max_safe" -lt 1 ] && max_safe=1
    
    for sess in "${LONG_SESSIONS[@]}"; do
        switch_msg="⚡ switching to $sess..."
        queued_msg="⚡ queued switch to $sess (#1)..."
        
        trunc_switch="$(truncate_text "$switch_msg" "$max_safe")"
        trunc_queued="$(truncate_text "$queued_msg" "$max_safe")"
        
        w_switch="$(sidebar_domain_animation_measure_cell_width "$trunc_switch")"
        w_queued="$(sidebar_domain_animation_measure_cell_width "$trunc_queued")"
        
        if [ "$w_switch" -gt "$max_safe" ]; then
            echo "FAIL: width=$w, max_safe=$max_safe, switch_msg measured $w_switch ('$trunc_switch')"
            exit 1
        fi
        
        if [ "$w_queued" -gt "$max_safe" ]; then
            echo "FAIL: width=$w, max_safe=$max_safe, queued_msg measured $w_queued ('$trunc_queued')"
            exit 1
        fi
    done
done
echo "All width clamping tests passed for widths: ${WIDTHS[*]}"

echo "=== [3/3] Testing Footer & Header Single-Line Guarantees ==="
for w in "${WIDTHS[@]}"; do
    cached_pane_width="$w"
    cached_pane_height=20
    
    # footer
    help='j/k Enter c/r/d o/a s/P q'
    if [ "$w" -ge 45 ]; then
        help='j/k | Enter | c/r/d | o/a | s: sub | P: pos | q'
    elif [ "$w" -ge 30 ]; then
        help='j/k | Enter | c/r/d | o/a | s/P | q'
    fi
    max_w=$((w - 1))
    [ "$max_w" -lt 1 ] && max_w=1
    trunc_footer="$(truncate_text "$help" "$max_w")"
    w_footer="$(sidebar_domain_animation_measure_cell_width "$trunc_footer")"
    [ "$w_footer" -le "$max_w" ] || { echo "FAIL: footer width $w_footer > $max_w for width $w"; exit 1; }
done

echo "PASS: all sidebar width single-line assertions verified."
