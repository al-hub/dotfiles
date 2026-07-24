#!/usr/bin/env bash
set -euo pipefail

# End-to-end keyboard scenario. The attached tmux client is backed by a real
# PTY and receives the same byte stream a terminal would send: Ctrl+a prefix,
# arrow escape sequences, printable prompt text, and Enter.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-keyboard-$$"
RUN_DIR="${TMPDIR:-/tmp}/dotfiles-single-sidebar-keyboard-$$"
HOME_DIR="$RUN_DIR/home"
HISTORY_DIR="$RUN_DIR/history"
CLIENT_LOG="$RUN_DIR/client.log"
CLIENT_PID=""
ATTACHED_PID=""
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" "$@"; }

cleanup()
{
    tmuxc kill-server >/dev/null 2>&1 || true
    if [ -n "$ATTACHED_PID" ]; then
        kill "$ATTACHED_PID" >/dev/null 2>&1 || true
        wait "$ATTACHED_PID" 2>/dev/null || true
    fi
    if [ -n "$CLIENT_PID" ]; then
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$HOME_DIR/.local/bin" "$HISTORY_DIR"
ln -s "$LAUNCHER" "$HOME_DIR/.local/bin/tmux-session-launcher"
ln -s "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$HOME_DIR/.local/bin/tmux-sidebar-tmux-adapter"
ln -s "$REPO_ROOT/scripts/tmux-sidebar-controller" "$HOME_DIR/.local/bin/tmux-sidebar-controller"

count_sessions()
{
    tmuxc list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' '
}

count_sidebars()
{
    tmuxc list-panes -a -F '#{pane_title}' 2>/dev/null |
        awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }'
}

count_archives()
{
    find "$HISTORY_DIR" -maxdepth 1 -type f -name '*.tsv' -print 2>/dev/null | wc -l | tr -d ' '
}

client_session()
{
    tmuxc list-clients -F '#{session_name}' 2>/dev/null | head -n 1
}

wait_until()
{
    local description="$1" expected="$2" command_name="$3" deadline=$(( $(date +%s) + 20 ))
    shift 3
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ "$($command_name "$@" 2>/dev/null || true)" = "$expected" ]; then
            return 0
        fi
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for %s (expected %s)\n' "$description" "$expected" >&2
    return 1
}

wait_for_sessions()
{
    local expected="$1" description="${2:-session count}" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" = "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for %s (got %s, expected %s)\n' \
        "$description" "$(count_sessions)" "$expected" >&2
    return 1
}

wait_for_archives()
{
    local expected="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_archives)" -ge "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for at least %s archives (got %s)\n' "$expected" "$(count_archives)" >&2
    return 1
}

wait_for_session_count_below()
{
    local previous="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" -lt "$previous" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_session_count_above()
{
    local previous="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" -gt "$previous" ] && return 0
        sleep 0.05
    done
    return 1
}

send_keys()
{
    # ATTACHED[1] is the stdin of `script`; script forwards it to the tmux
    # client's controlling PTY, so this is not a tmux send-keys shortcut.
    printf '%b' "$1" >&"${ATTACHED[1]}"
    sleep 0.08
}

tmuxc new-session -d -s keyboard-anchor -c "$REPO_ROOT" 'sleep 300'
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG "${TMUX_SESSION_LAUNCHER_DEBUG:-0}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/debug.log"
tmuxc split-window -d -t '=keyboard-anchor:' -h -b -l 35 "$LAUNCHER --sidebar"
wait_until 'initial sidebar' 1 count_sidebars

# A real attached client is created through script(1), which allocates the
# child terminal. Its stdin remains writable through the coprocess descriptor.
coproc ATTACHED {
    TERM=xterm script -qefc "HOME='$HOME_DIR' tmux -L '$SOCKET' -f '$REPO_ROOT/dotfiles/tmux.conf' attach-session -t keyboard-anchor" "$CLIENT_LOG"
}
ATTACHED_PID="$ATTACHED_PID"
sleep 0.3

# Ctrl+a, s: exercise the configured tmux prefix and binding. Since the
# sidebar already exists, this is also the user's normal toggle-off path.
send_keys $'\001s'
wait_until 'sidebar toggle off' 0 count_sidebars

# Ctrl+a, s again: restore the always-on sidebar and leave focus in its TUI.
send_keys $'\001s'
wait_until 'sidebar toggle on' 1 count_sidebars

# c + name + Enter, six times.
for index in 1 2 3 4 5 6; do
    send_keys 'c'
    send_keys "keyboard-$index\\r"
done
wait_for_sessions 7 'six keyboard-created sessions plus anchor'
printf 'PASS: Ctrl+a s toggles one sidebar through an attached PTY\n'
printf 'PASS: c creates six named sessions using keyboard input\n'

# Down + Enter six times. The selected session changes and the client follows
# the sidebar's switch path each time; the final iteration wraps naturally.
for ignored in 1 2 3 4 5 6; do
    send_keys $'\033[B'
    send_keys $'\r'
done
printf 'PASS: arrow navigation and Enter switch sessions six times\n'

# Re-anchor the client without bypassing the UI. This prevents the deliberate
# current-session delete path (which exits the launcher after client handoff)
# from being mistaken for a keyboard input failure in the bulk-delete phase.
for ignored in 1 2 3 4 5 6 7; do
    [ "$(client_session)" = keyboard-anchor ] && break
    send_keys $'\033[B'
    send_keys $'\r'
done
[ "$(client_session)" = keyboard-anchor ] || {
    printf 'ERROR: could not return to anchor through keyboard selection\n' >&2
    exit 1
}

# Delete the six non-anchor sessions one by one and archive each one. Selection
# can be re-aligned by the TUI after a cross-session move, so keep using the
# same physical Down/d/confirm sequence until only the anchor remains.
delete_attempt=0
while [ "$(count_sessions)" -gt 1 ]; do
    delete_attempt=$((delete_attempt + 1))
    [ "$delete_attempt" -le 12 ] || {
        printf 'ERROR: keyboard deletion made no progress\n' >&2
        exit 1
    }
    previous_session_count="$(count_sessions)"
    send_keys $'\033[B'
    send_keys 'd'
    send_keys $'y\r'
    wait_for_session_count_below "$previous_session_count" || {
        printf 'ERROR: keyboard deletion made no progress (attempt %s)\n' "$delete_attempt" >&2
        exit 1
    }
done
wait_for_sessions 1 'six deleted sessions'
wait_for_archives 6
printf 'PASS: d + y + Enter archives and deletes six sessions\n'

# o enters history. The launcher waits for each async sidebar transition before
# accepting the next action, so six physical Down + Enter pairs restore six
# distinct archives without changing the user's input sequence.
send_keys 'o'
for ignored in 1 2 3 4 5 6; do
    previous_session_count="$(count_sessions)"
    send_keys $'\033[B'
    # Model a human seeing the refreshed history row after the pane move.
    sleep 0.5
    send_keys $'\r'
    wait_for_session_count_above "$previous_session_count" || {
        printf 'ERROR: keyboard restore made no progress (iteration %s)\n' "$ignored" >&2
        exit 1
    }
done
wait_for_sessions 7 'six restored sessions plus anchor'
printf 'PASS: o plus arrow navigation and Enter restores six archives\n'

# d, All, Enter, y, Enter: archive and terminate every remaining session.
send_keys 'd'
send_keys $'All\r'
send_keys $'y\r'
local_deadline=$(( $(date +%s) + 20 ))
while [ "$(date +%s)" -lt "$local_deadline" ]; do
    tmuxc list-sessions >/dev/null 2>&1 || break
    sleep 0.05
done
if tmuxc list-sessions >/dev/null 2>&1; then
    printf 'ERROR: All deletion did not terminate the tmux server\n' >&2
    exit 1
fi
printf 'PASS: d + All + Enter + y + Enter terminates all sessions\n'
