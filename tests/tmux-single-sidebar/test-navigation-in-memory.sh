#!/usr/bin/env bash
set -euo pipefail
# Verify that move_selection updates in-memory counter and flushes on idle without fork/exec in hot path.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HOME="${HOME:-/tmp}"

# Run a synthetic test verifying zero subprocesses in move_selection
source "$REPO_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true

# 1. Check that flush_action_generation_if_dirty exists
type flush_action_generation_if_dirty >/dev/null

# 2. Test in-memory state tracking
_sidebar_local_action_generation=0
_sidebar_action_generation_dirty=0
SIDEBAR_WINDOW_ID="@1"

# Mock session list and helper functions for move_selection test
session_names=("sess1" "sess2" "sess3")
selected_index=0
current_session="sess1"
view_mode="sessions"
cached_pane_height=20
cached_pane_width=40

# Track if sidebar_tmux_cmd is invoked during move_selection
tmux_cmd_calls=0
sidebar_tmux_cmd() {
    tmux_cmd_calls=$((tmux_cmd_calls + 1))
    return 0
}
render_selection_pair() { :; }
render_visible_rows() { :; }
row_is_visible() { return 0; }
ensure_selection_visible() { :; }

# Call move_selection
move_selection next

if [ "$tmux_cmd_calls" -ne 0 ]; then
    echo "FAIL: move_selection called tmux_cmd $tmux_cmd_calls times (expected 0)" >&2
    exit 1
fi

if [ "${_sidebar_local_action_generation:-0}" -ne 1 ]; then
    echo "FAIL: _sidebar_local_action_generation not incremented (got ${_sidebar_local_action_generation:-0})" >&2
    exit 1
fi

if [ "${_sidebar_action_generation_dirty:-0}" -ne 1 ]; then
    echo "FAIL: _sidebar_action_generation_dirty not set to 1" >&2
    exit 1
fi

# Now call flush_action_generation_if_dirty
flush_action_generation_if_dirty

if [ "$tmux_cmd_calls" -ne 1 ]; then
    echo "FAIL: flush_action_generation_if_dirty did not invoke tmux_cmd (calls=$tmux_cmd_calls)" >&2
    exit 1
fi

if [ "${_sidebar_action_generation_dirty:-0}" -ne 0 ]; then
    echo "FAIL: _sidebar_action_generation_dirty not reset to 0 after flush" >&2
    exit 1
fi

# Second flush should be no-op
flush_action_generation_if_dirty
if [ "$tmux_cmd_calls" -ne 1 ]; then
    echo "FAIL: second flush was not a no-op (calls=$tmux_cmd_calls)" >&2
    exit 1
fi

echo "PASS: navigation in-memory interface and zero-fork verified"
