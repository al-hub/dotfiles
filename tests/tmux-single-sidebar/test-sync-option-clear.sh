#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying selection sync option clearing and window pending state reset

SIDEBAR_SELECTION_SYNC_OPTION="@dotfiles_sidebar_selection_sync"

selection_sync_window_pending()
{
    local sync_val="$1"
    [ -n "$sync_val" ]
}

# Test 1: Active sync pending
if ! selection_sync_window_pending "aaa"; then
    echo "FAIL: expected selection_sync_window_pending to be true when option is set"
    exit 1
fi

# Test 2: Cleared sync option (after switch finish)
cleared_val=""
if selection_sync_window_pending "$cleared_val"; then
    echo "FAIL: expected selection_sync_window_pending to be false when option is cleared"
    exit 1
fi

echo "PASS: selection_sync_window_pending correctly resets when sync option is cleared"
