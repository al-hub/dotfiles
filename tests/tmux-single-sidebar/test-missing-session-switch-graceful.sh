#!/usr/bin/env bash
# TDD Test for graceful handling when switching to missing/deleted session
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Verify switch_session logic in scripts/tmux-session-launcher
grep_count=$(grep -c "session switch failed: session.*does not exist" "$SCRIPT_DIR/scripts/tmux-session-launcher" || true)

if [ "$grep_count" -lt 1 ]; then
    echo "FAIL: graceful error handling missing in switch_session"
    exit 1
fi

echo "PASS: missing session switch graceful test"


