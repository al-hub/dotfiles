#!/usr/bin/env bash
# test-restore-history-no-pollution.sh
# Validates that restoring an archive never re-injects past archive commands into HISTFILE,
# preserving global command history order and preventing time-travel pollution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_SOCKET="test-hist-pollute-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-hist-pollute.XXXXXX")"
MOCK_HISTFILE="$RUN_DIR/tmux.zsh_history"
HISTORY_DIR="$RUN_DIR/history"
LAUNCHER="$SCRIPT_DIR/scripts/tmux-session-launcher"
TMUX=(tmux -L "$TEST_SOCKET" -f "$SCRIPT_DIR/dotfiles/tmux.conf")

mkdir -p "$HISTORY_DIR"

cleanup() {
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

# 1. Setup initial modern history
printf 'modern_cmd_1\nmodern_cmd_2\nmodern_cmd_3\n' > "$MOCK_HISTFILE"

echo "=== [1/3] Creating and archiving session ==="
# Anchor session keeps server alive
"${TMUX[@]}" new-session -d -s "anchor" -x 120 -y 40 -c "$SCRIPT_DIR" 'sleep 300'
"${TMUX[@]}" set-option -gq '@dotfiles_sidebar_owner_client' "/dev/null"

"${TMUX[@]}" new-session -d -s "legacy-app" -x 120 -y 40 -c "$SCRIPT_DIR" 'sleep 60'
win_id="$("${TMUX[@]}" display-message -p -t '=legacy-app:' '#{window_id}')"
"${TMUX[@]}" set-option -wq -t "$win_id" @dotfiles_sidebar_managed 1
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$win_id' 30"

# Archive session
"${TMUX[@]}" run-shell "TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' $LAUNCHER --archive-session 'legacy-app' false"

ARCHIVE_FILE="$(find "$HISTORY_DIR" -type f -name '*legacy-app*.tsv' | head -n 1)"
[ -n "$ARCHIVE_FILE" ] && [ -f "$ARCHIVE_FILE" ] || { echo "FAIL: archive not created"; exit 1; }

# Deliberately append legacy history lines into the archive file to simulate older archives
cat <<ARCH_EOF >> "$ARCHIVE_FILE"
history	legacy_polluting_command_alpha
history	legacy_polluting_command_beta
history	legacy_polluting_command_gamma
ARCH_EOF

# Kill the session
"${TMUX[@]}" kill-session -t "=legacy-app:"

echo "=== [2/3] Restoring legacy archive ==="
orig_content="$(cat "$MOCK_HISTFILE")"

# Restore archive in batch mode
"${TMUX[@]}" run-shell "HISTFILE='$MOCK_HISTFILE' TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' $LAUNCHER --restore-archive '$ARCHIVE_FILE' 'op-test-$$' true"

sleep 0.5

echo "=== [3/3] Checking HISTFILE for zero pollution ==="
after_content="$(cat "$MOCK_HISTFILE")"
echo "HISTFILE after restore:"
echo "$after_content"

if echo "$after_content" | grep -q "legacy_polluting_command"; then
    echo "FAIL: Legacy polluting command was injected into HISTFILE!"
    exit 1
fi

if [ "$after_content" != "$orig_content" ]; then
    echo "FAIL: HISTFILE content changed unexpectedly!"
    exit 1
fi

echo "=========================================================================="
echo "PASS: Restoring archive did NOT pollute HISTFILE with past commands!"
echo "=========================================================================="
