#!/usr/bin/env bash
set -euo pipefail

# Verify that restore_archive in batch mode does not eagerly spawn sidebar presenters for inactive sessions,
# marks windows with @dotfiles_sidebar_provisioning = "lazy", and suppresses cascading hooks with @tmux_batch_busy.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-bulk-restore-lazy-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bulk-restore-lazy.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
mkdir -p "$HISTORY_DIR"

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

# 1. Structural check for lazy provisioning in scripts
grep -q '@dotfiles_sidebar_provisioning' "$LAUNCHER" || fail "missing @dotfiles_sidebar_provisioning definition"
grep -q 'restore_batch_mode' "$LAUNCHER" || fail "missing restore_batch_mode handling"
grep -q '@tmux_batch_busy' "$LAUNCHER" || fail "missing @tmux_batch_busy suppression flag"

# 2. Functional test of restore_archive with batch mode
mkdir -p "$RUN_DIR/home"
tmuxc new-session -d -s main -c "$REPO_ROOT" 'sleep 300'
main_win="$(tmuxc display-message -p '#{window_id}')"
tmuxc set-option -t "=main:" @dotfiles_sidebar_managed 1

# Create an archive to restore
archive_file="$HISTORY_DIR/test-archive-1.tsv"
cat << 'EOF' > "$archive_file"
version	3
session	lazy-sess
window	1	main	1	-	120,40
pane	1	%100	0	0	120	40	1	/tmp	bash	active_pane
endwindow
EOF

# Call launcher to restore archive in batch mode (restore_batch_mode=true)
tmuxc run-shell "$LAUNCHER --restore-archive '$archive_file' batch-op-1 true" || fail "restore_archive failed in batch mode"

# Verify session exists
tmuxc has-session -t '=lazy-sess:' >/dev/null 2>&1 || fail "restored session lazy-sess does not exist"

# Verify window options
lazy_win="$(tmuxc list-windows -t '=lazy-sess:' -F '#{window_id}' | head -n 1)"
managed_opt="$(tmuxc show-option -wqv -t "$lazy_win" @dotfiles_sidebar_managed 2>/dev/null || true)"
ready_opt="$(tmuxc show-option -wqv -t "$lazy_win" @dotfiles_sidebar_ready 2>/dev/null || true)"
prov_opt="$(tmuxc show-option -wqv -t "$lazy_win" @dotfiles_sidebar_provisioning 2>/dev/null || true)"

[ "$managed_opt" = "1" ] || fail "expected @dotfiles_sidebar_managed=1 on restored window, got: $managed_opt"
[ "$ready_opt" = "0" ] || fail "expected @dotfiles_sidebar_ready=0 on lazily restored window, got: $ready_opt"
[ "$prov_opt" = "lazy" ] || fail "expected @dotfiles_sidebar_provisioning=lazy on lazily restored window, got: $prov_opt"

# Verify no sidebar pane was eagerly created in lazy-sess
sidebar_count="$(tmuxc list-panes -t "$lazy_win" -F '#{pane_title}' | awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }')"
[ "$sidebar_count" -eq 0 ] || fail "expected 0 sidebar panes in lazily restored window, got: $sidebar_count"

# 3. Verify on-demand provisioning when session is activated
tmuxc set-option -g @dotfiles_sidebar_restore_topology 0
tmuxc set-option -g @tmux_batch_busy 0
tmuxc set-option -g @dotfiles_sidebar_enabled 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$lazy_win'" || fail "on-demand sidebar provisioning failed"

for attempt in $(seq 1 100); do
  ready_opt="$(tmuxc show-option -wqv -t "$lazy_win" @dotfiles_sidebar_ready 2>/dev/null || true)"
  [ "$ready_opt" = "1" ] && break
  sleep 0.05
done
[ "$ready_opt" = "1" ] || fail "expected @dotfiles_sidebar_ready=1 after on-demand provisioning"

sidebar_count="$(tmuxc list-panes -t "$lazy_win" -F '#{pane_title}' | awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }')"
[ "$sidebar_count" -eq 1 ] || fail "expected 1 sidebar pane after on-demand provisioning, got: $sidebar_count"

echo "PASS: bulk restore lazy provisioning flags and behavior verified"

