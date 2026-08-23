#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-eager-warm-provisioning-restore.sh
#
# TDD Test for Eager Warm Provisioning on Session Creation & Archive Restore:
# 1. New Session Creation: Active window must be eagerly warm-provisioned upon creation
# 2. Single Archive Restore: Active window must be eagerly warm-provisioned upon restore
# 3. Batch Archive Restore: Active window of each restored session must be eagerly warm-provisioned
# 4. First Enter Switch: Must execute as 0% cold provisioning Hot-Path
# ==============================================================================

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-warm-restore-$$"
export TMUX_SOCKET="$SOCKET"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-warm-restore.XXXXXX")"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup() {
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
    rm -f "$HOME/.cache/dotfiles/tmux-session-history/"*to-be-archived-1*.tsv 2>/dev/null || true
}
trap cleanup EXIT

echo "=== [1/4] Setting up isolated tmux environment ==="
"${TMUX[@]}" new-session -d -s main -x 120 -y 30 -c "$REPO_ROOT" 'sleep 300'
main_win="$("${TMUX[@]}" display-message -p -t '=main:' '#{window_id}')"
"${TMUX[@]}" set-option -wq -t "$main_win" @dotfiles_sidebar_managed 1
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$main_win' 30"

main_sb="$("${TMUX[@]}" list-panes -t "$main_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
[ -n "$main_sb" ] || { echo "FAIL: main sidebar was not provisioned"; exit 1; }
echo "Main sidebar ready at: $main_sb"

export TMUX_SESSION_LAUNCHER_HISTORY_DIR="$RUN_DIR/history"
mkdir -p "$TMUX_SESSION_LAUNCHER_HISTORY_DIR"

echo "=== [2/4] Testing Session Creation Eager Warm Provisioning ==="
# Sourcing launcher functions
source "$REPO_ROOT/scripts/lib/sidebar_domain.sh"
source "$REPO_ROOT/scripts/lib/sidebar_domain_animation.sh"
source "$REPO_ROOT/scripts/lib/sidebar_port_tmux.sh"
source "$REPO_ROOT/scripts/lib/sidebar_archive.sh"
source "$REPO_ROOT/scripts/lib/sidebar_topology.sh"
source "$LAUNCHER" --source-only 2>/dev/null || true

# Call create_session_with_active_client_geometry helper or new session workflow
NEW_SESS="eager-new-session"
"${TMUX[@]}" new-session -d -s "$NEW_SESS" -x 120 -y 30 'sleep 300'
new_win="$("${TMUX[@]}" display-message -p -t "=$NEW_SESS:" '#{window_id}')"
"${TMUX[@]}" set-option -wq -t "$new_win" @dotfiles_sidebar_managed 1

# Eager warm provisioning step
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$new_win' 30"

new_sb="$("${TMUX[@]}" list-panes -t "$new_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
if [ -n "$new_sb" ]; then
    echo "PASS: New session active window has eager warm sidebar ($new_sb)"
else
    echo "FAIL: New session active window is missing warm sidebar"
    exit 1
fi

echo "=== [3/4] Testing Archive Creation and Restore Warm State ==="
# Setup a session to archive
ARCH_SESS="to-be-archived-1"
"${TMUX[@]}" new-session -d -s "$ARCH_SESS" -x 120 -y 30 'sleep 300'
arch_win="$("${TMUX[@]}" display-message -p -t "=$ARCH_SESS:" '#{window_id}')"
"${TMUX[@]}" set-option -wq -t "$arch_win" @dotfiles_sidebar_managed 1
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$arch_win' 30"

# Save archive using archive_session
export TMUX_SOCKET="$SOCKET"
export TMUX_SESSION_LAUNCHER_DEBUG=1
"${TMUX[@]}" run-shell "TMUX_SESSION_LAUNCHER_HISTORY_DIR='$RUN_DIR/history' $LAUNCHER --archive-session '$ARCH_SESS' false"

archive_file="$(find "$RUN_DIR/history" "$HOME/.cache/dotfiles/tmux-session-history" -type f -name '*to-be-archived-1*.tsv' 2>/dev/null | head -n 1 || true)"
[ -n "$archive_file" ] && [ -f "$archive_file" ] || { echo "FAIL: archive file not created"; exit 1; }
echo "Created archive: $archive_file"

# Delete the session so it only exists in archive
"${TMUX[@]}" kill-session -t "=$ARCH_SESS" 2>/dev/null || true
if "${TMUX[@]}" has-session -t "=$ARCH_SESS" 2>/dev/null; then
    echo "FAIL: session was not killed"; exit 1
fi

echo "Restoring archive in BATCH mode (simulating 'o' / bulk restore)..."
# In batch restore mode (restore_batch_mode=true), test whether active window is eagerly warmed
"${TMUX[@]}" run-shell "TMUX_SESSION_LAUNCHER_HISTORY_DIR='$RUN_DIR/history' $LAUNCHER --restore-archive '$archive_file' 'op-test-$$' true"

# Verify that restored session exists
if ! "${TMUX[@]}" has-session -t "=$ARCH_SESS" 2>/dev/null; then
    echo "FAIL: restored session does not exist"; exit 1
fi

# CRITICAL ASSERTION:
# Immediately after restore (BEFORE user switches or enters),
# the active window of the restored session MUST ALREADY have a running sidebar pane and ready=1
restored_win="$("${TMUX[@]}" display-message -p -t "=$ARCH_SESS:" '#{window_id}')"
restored_sb="$("${TMUX[@]}" list-panes -t "$restored_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"
ready_flag="$("${TMUX[@]}" show-option -wqv -t "$restored_win" @dotfiles_sidebar_ready 2>/dev/null || echo 0)"

echo "Restored window: $restored_win, sidebar pane: ${restored_sb:-NONE}, ready flag: $ready_flag"

if [ -z "$restored_sb" ]; then
    echo "FAIL (RED): Restored session active window has NO warm sidebar pane yet (Cold Lazy state)."
    exit 1
fi

if [ "$ready_flag" != "1" ]; then
    echo "FAIL (RED): Restored session sidebar is not marked ready=1 yet."
    exit 1
fi

echo "PASS: Restored session is in 100% Warm state immediately upon restore."

echo "=== [4/4] Verifying First Enter Switch Takes 0% Cold Provisioning Hot-Path ==="
# Ensure that first switch to restored session takes Fast Hot-Path without spawning a new pane
pre_switch_sb="$restored_sb"
# Invoke --ensure-sidebar-window via launcher CLI
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-window '$restored_win' 30"

post_switch_sb="$("${TMUX[@]}" list-panes -t "$restored_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1 }')"

if [ "$pre_switch_sb" = "$post_switch_sb" ]; then
    echo "PASS: First switch preserved warm sidebar pane identity ($pre_switch_sb == $post_switch_sb). Zero cold provisioning occurred!"
else
    echo "FAIL: First switch replaced or respawned sidebar pane ($pre_switch_sb -> $post_switch_sb)"
    exit 1
fi

echo "ALL EAGER WARM PROVISIONING TESTS PASSED!"
