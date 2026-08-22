#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-atomic-lease-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 1. Create two test sessions with work panes
tmux -L "$SOCKET" new-session -d -s sess_a -n main 'sleep 60'
tmux -L "$SOCKET" new-session -d -s sess_b -n main 'sleep 60'

win_a="$(tmux -L "$SOCKET" display-message -p -t sess_a '#{window_id}')"
win_b="$(tmux -L "$SOCKET" display-message -p -t sess_b '#{window_id}')"
export TMUX="$SOCKET"

# Source libraries and launcher
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"
source "$SCRIPT_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true

cleanup() {
    TMUX="" tmux -L "$SOCKET" kill-server 2>/dev/null || true
    TMUX="" tmux -S "/tmp/tmux-$(id -u 2>/dev/null || echo 1000)/$SOCKET" kill-server 2>/dev/null || true
}
trap cleanup EXIT

# 2. Enable subpane globally
tmux -L "$SOCKET" set-option -gq "${SIDEBAR_SUBPANE_OPTION:-@dotfiles_sidebar_subpane_enabled}" 1

# 3. Provision sidebar and subpane on window A
topology_ensure_window "$win_a" 30 1
sidebar_a="$(sidebar_window_pane "$win_a")"
sub_pane="$(sidebar_window_subpane "$win_a")"

[ -n "$sidebar_a" ] || { echo "FAIL: sidebar_a not created"; exit 1; }
[ -n "$sub_pane" ] || { echo "FAIL: subpane on win_a not created"; exit 1; }

# Verify immutable role tagging
tag_sub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_sidebar_subpane || true)"
tag_hub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_subpane_hub_pane || true)"

if [ "$tag_sub" != "1" ] || [ "$tag_hub" != "1" ]; then
    echo "FAIL: subpane roles not set correctly (sub=$tag_sub, hub=$tag_hub)"
    exit 1
fi

# 4. Provision sidebar on window B (without subpane initially)
topology_ensure_window "$win_b" 30 0
sidebar_b="$(sidebar_window_pane "$win_b")"
[ -n "$sidebar_b" ] || { echo "FAIL: sidebar_b not created"; exit 1; }
sub_b_initial="$(sidebar_window_subpane "$win_b" || true)"
[ -z "$sub_b_initial" ] || { echo "FAIL: win_b unexpectedly has subpane before lease"; exit 1; }

# 5. Atomic relocation directly into target launcher
subpane_hub_relocate_pane_atomic "$sub_pane" "$sidebar_b" 12

# Verify subpane is now on win_b and absent from win_a
sub_a_after="$(sidebar_window_subpane "$win_a" || true)"
sub_b_after="$(sidebar_window_subpane "$win_b" || true)"

if [ -n "$sub_a_after" ]; then
    echo "FAIL: subpane still present on win_a after relocation ($sub_a_after)"
    exit 1
fi
if [ "$sub_b_after" != "$sub_pane" ]; then
    echo "FAIL: subpane not present on win_b (expected $sub_pane, got $sub_b_after)"
    exit 1
fi

# Verify immutable roles remain intact
tag_sub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_sidebar_subpane || true)"
tag_hub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_subpane_hub_pane || true)"
if [ "$tag_sub" != "1" ] || [ "$tag_hub" != "1" ]; then
    echo "FAIL: role tags corrupted after atomic relocation (sub=$tag_sub, hub=$tag_hub)"
    exit 1
fi

# 6. Test session switch with atomic subpane lease pipeline
sidebar_switch_execute_hot "" "sess_a" "$win_a" "$sidebar_a" "30" "$sub_pane" "12"

sub_a_switched="$(sidebar_window_subpane "$win_a" || true)"
sub_b_switched="$(sidebar_window_subpane "$win_b" || true)"

if [ "$sub_a_switched" != "$sub_pane" ]; then
    echo "FAIL: subpane not returned to win_a during session switch (expected $sub_pane, got $sub_a_switched)"
    exit 1
fi
if [ -n "$sub_b_switched" ]; then
    echo "FAIL: subpane still present on win_b after hot switch ($sub_b_switched)"
    exit 1
fi

# Role tags must still be intact
tag_sub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_sidebar_subpane || true)"
tag_hub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_subpane_hub_pane || true)"
if [ "$tag_sub" != "1" ] || [ "$tag_hub" != "1" ]; then
    echo "FAIL: role tags corrupted after switch lease (sub=$tag_sub, hub=$tag_hub)"
    exit 1
fi

# 7. Test releasing subpane to hub (toggle OFF)
subpane_hub_release_pane "$sub_pane"

# Subpane should be in hub session, absent from win_a and win_b
sub_a_rel="$(sidebar_window_subpane "$win_a" || true)"
sub_b_rel="$(sidebar_window_subpane "$win_b" || true)"
if [ -n "$sub_a_rel" ] || [ -n "$sub_b_rel" ]; then
    echo "FAIL: subpane still in active windows after release (win_a=$sub_a_rel, win_b=$sub_b_rel)"
    exit 1
fi

# Role tags must remain intact even in hub session
tag_sub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_sidebar_subpane || true)"
tag_hub="$(tmux -L "$SOCKET" show-option -pqv -t "$sub_pane" @dotfiles_subpane_hub_pane || true)"
if [ "$tag_sub" != "1" ] || [ "$tag_hub" != "1" ]; then
    echo "FAIL: role tags corrupted after release to hub (sub=$tag_sub, hub=$tag_hub)"
    exit 1
fi

# 8. Test re-acquiring subpane on win_a
acquired_pane="$(subpane_hub_acquire_pane "$sidebar_a" 12)"
if [ "$acquired_pane" != "$sub_pane" ]; then
    echo "FAIL: re-acquired pane ID mismatch (expected $sub_pane, got $acquired_pane)"
    exit 1
fi
sub_a_reacq="$(sidebar_window_subpane "$win_a" || true)"
if [ "$sub_a_reacq" != "$sub_pane" ]; then
    echo "FAIL: subpane not attached to win_a after acquire"
    exit 1
fi

# 9. Verify work pane count and layout integrity on win_a
work_panes_a="$(tmux -L "$SOCKET" list-panes -t "$win_a" -F '#{pane_id}|#{pane_title}|#{@dotfiles_sidebar_subpane}' | awk -F '|' -v title="$SIDEBAR_TITLE" -v subtitle="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}" '$2 != title && $2 != subtitle && $3 != "1" { print $1 }')"
work_count_a="$(echo "$work_panes_a" | grep -v '^$' | wc -l)"
if [ "$work_count_a" -ne 1 ]; then
    echo "FAIL: work pane count corrupted on win_a (count=$work_count_a)"
    exit 1
fi

echo "PASS: atomic subpane lease and immutable role tagging verified"
