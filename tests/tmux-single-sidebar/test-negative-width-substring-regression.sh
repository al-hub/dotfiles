#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-negative-width-substring-regression.sh
#
# Phase 1 & 2 Feedback Loop / Reproduction for:
# "tmux-session-launcher: line 6253: width: substring expression < 0"
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"

echo "=== [1/2] Sourcing launcher in isolated subshell ==="
source "$REPO_ROOT/scripts/lib/sidebar_domain.sh"
source "$REPO_ROOT/scripts/lib/sidebar_domain_animation.sh"
source "$LAUNCHER" --source-only 2>/dev/null || true

echo "=== [2/2] Driving negative & boundary width inputs into format_session_name & format_row ==="

# Test Case 1: Short session name (len 1) with negative width (-3) -> EXACT USER ERROR
echo "Testing format_session_name with name='0' and width=-3..."
format_session_name "0" -3 false 0 || {
    echo "FAIL: format_session_name crashed with exit code $?"
    exit 1
}

# Test Case 2: Zero width to format_session_name
echo "Testing format_session_name with zero width (0)..."
format_session_name "0" 0 false 0 || {
    echo "FAIL: format_session_name crashed on width 0"
    exit 1
}

# Test Case 3: format_row with cached_pane_width=1, 2, 3 on short session name "0"
session_names=("0")
session_created=("$(sidebar_domain_epoch_now)")
session_animate=("false")
session_animation_seed=(0)
scroll_offset=0

for test_w in -5 -1 0 1 2 3 5 10 15; do
    echo "Testing format_row with cached_pane_width=$test_w on session '0'..."
    cached_pane_width="$test_w"
    format_row 0 || {
        echo "FAIL: format_row crashed on cached_pane_width=$test_w"
        exit 1
    }
done

echo "PASS: all boundary and negative width inputs handled safely without crash."
