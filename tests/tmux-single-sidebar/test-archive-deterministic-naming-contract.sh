#!/usr/bin/env bash
set -euo pipefail

# Contract test for Unique Session-Key Archive with Deterministic Naming & Last-Write-Wins (Option A).
# Asserts:
# 1. Archive filename for session "$NAME" is exactly "$NAME.tsv" (no timestamp, no PID, no window suffix).
# 2. Repeated archiving of the same session overwrites the deterministic archive file (Last-Write-Wins, single file).
# 3. Numeric session "0" produces "0.tsv".
# 4. Restoring from deterministic archive correctly restores the multi-pane layout.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-archive-naming-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-archive-naming.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
mkdir -p "$HISTORY_DIR" "$RUN_DIR/home"

cleanup() {
  "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

tmuxc() { HOME="$RUN_DIR/home" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" "${TMUX[@]}" "$@"; }
fail() {
  KEEP_RUN_DIR=true
  printf 'FAIL: %s\nartifacts=%s\n' "$*" "$RUN_DIR" >&2
  tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}' > "$RUN_DIR/panes.txt" 2>/dev/null || true
  exit 1
}

# 1. Start isolated tmux session 'my-app' with 1 window (1 pane)
tmuxc new-session -d -s my-app -c "$REPO_ROOT" 'sleep 300'
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-option -t '=my-app:' @dotfiles_sidebar_managed 1

# 2. Archive 'my-app'
tmuxc run-shell "$LAUNCHER --archive-session my-app" || fail "failed to archive session my-app"

# CRITICAL ASSERTION: The created archive file in $HISTORY_DIR must be EXACTLY my-app.tsv
[ -f "$HISTORY_DIR/my-app.tsv" ] || fail "expected $HISTORY_DIR/my-app.tsv to exist, but it was not found. Found: $(ls -la "$HISTORY_DIR")"

# Verify only ONE file matching *my-app* exists in $HISTORY_DIR
my_app_files_count="$(find "$HISTORY_DIR" -maxdepth 1 -type f -name '*my-app*' ! -name '*.history-imported' | wc -l | tr -d ' ')"
[ "$my_app_files_count" -eq 1 ] || fail "expected exactly 1 archive file matching *my-app*, found $my_app_files_count"

# Check pane count in my-app.tsv is 1
pane_count_1="$(grep -c '^pane	' "$HISTORY_DIR/my-app.tsv" || true)"
[ "$pane_count_1" -eq 1 ] || fail "expected 1 pane in my-app.tsv, got: $pane_count_1"

# 3. Modify session 'my-app' by splitting window into 2 panes
tmuxc split-window -t '=my-app:' -c "$REPO_ROOT" 'sleep 300'
active_panes_count="$(tmuxc list-panes -t '=my-app:' | wc -l | tr -d ' ')"
[ "$active_panes_count" -eq 2 ] || fail "expected 2 active panes in my-app session before second archive, got $active_panes_count"

# Re-archive 'my-app' (Last-Write-Wins)
tmuxc run-shell "$LAUNCHER --archive-session my-app" || fail "failed to re-archive session my-app"

# CRITICAL ASSERTION: Still EXACTLY ONE file my-app.tsv exists (no second timestamped file created)
my_app_files_count_2="$(find "$HISTORY_DIR" -maxdepth 1 -type f -name '*my-app*' ! -name '*.history-imported' | wc -l | tr -d ' ')"
[ "$my_app_files_count_2" -eq 1 ] || fail "expected still exactly 1 archive file matching *my-app*, found $my_app_files_count_2"

# Window pane count in my-app.tsv is now 2
pane_count_2="$(grep -c '^pane	' "$HISTORY_DIR/my-app.tsv" || true)"
[ "$pane_count_2" -eq 2 ] || fail "expected 2 panes in overwritten my-app.tsv, got: $pane_count_2"

# 4. Test numeric session 0
tmuxc new-session -d -s 0 -c "$REPO_ROOT" 'sleep 300'
tmuxc set-option -t '=0:' @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --archive-session 0" || fail "failed to archive numeric session 0"

[ -f "$HISTORY_DIR/0.tsv" ] || fail "expected $HISTORY_DIR/0.tsv to exist for numeric session 0. Found: $(ls -la "$HISTORY_DIR")"

# 5. Test restore: Kill session my-app, restore from my-app.tsv, verify 2 panes are restored
tmuxc kill-session -t '=my-app:' || fail "failed to kill my-app session before restore"
[ "$(tmuxc has-session -t '=my-app:' >/dev/null 2>&1; echo $?)" -ne 0 ] || fail "session my-app should not exist after kill"

tmuxc run-shell "$LAUNCHER --restore-archive '$HISTORY_DIR/my-app.tsv' restore-op-1 false" || fail "failed to restore my-app from $HISTORY_DIR/my-app.tsv"

tmuxc has-session -t '=my-app:' >/dev/null 2>&1 || fail "restored session my-app does not exist"
restored_panes_count="$(tmuxc list-panes -t '=my-app:' -F '#{pane_title}' | grep -v 'dotfiles-session-sidebar' | wc -l | tr -d ' ')"
[ "$restored_panes_count" -eq 2 ] || fail "expected 2 restored work panes in my-app, got $restored_panes_count"

echo "PASS: deterministic archive naming and last-write-wins verified successfully"
