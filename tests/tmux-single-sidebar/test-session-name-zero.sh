#!/usr/bin/env bash
set -euo pipefail

# Regression for the live failure reproduced with a numeric session named `0`.
# The adapter must not use ambiguous name-based list-panes targets.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-session-zero-$$"
SOCKET_PATH="/tmp/tmux-$(id -u)/$SOCKET"
RUN_DIR="${TMPDIR:-/tmp}/dotfiles-single-sidebar-session-zero-$$"
HOME_DIR="$RUN_DIR/home"
TMUX_CONFIG="$REPO_ROOT/dotfiles/tmux.conf"
CLIENT_LOG="$RUN_DIR/client.log"
CLIENT_PID=""

cleanup()
{
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    if [ -n "$CLIENT_PID" ]; then
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$HOME_DIR/.local/bin"
ln -s "$LAUNCHER" "$HOME_DIR/.local/bin/tmux-session-launcher"
ln -s "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$HOME_DIR/.local/bin/tmux-sidebar-tmux-adapter"

tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$TMUX_CONFIG" "$@"; }

tmuxc new-session -d -s 0 -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s aaaaaaaaaaaaaaaaaaa -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s bbbbbbbbbbbbbbbbbb -c "$REPO_ROOT" 'sleep 300'
tmuxc split-window -d -t '=aaaaaaaaaaaaaaaaaaa:' -h -b -l 35 "$LAUNCHER --sidebar"

for attempt in $(seq 1 50); do
    sidebar_count="$(tmuxc list-panes -a -F '#{pane_title}' 2>/dev/null |
        awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')"
    [ "$sidebar_count" -eq 1 ] && break
    sleep 0.05
done

sidebar_count="$(tmuxc list-panes -a -F '#{pane_title}' 2>/dev/null |
    awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')"
[ "$sidebar_count" -eq 1 ]

# The ambiguity is client-context dependent. Reproduce the live shape by
# attaching the client to the session that owns the sidebar before discovery.
TERM=xterm script -qefc "HOME='$HOME_DIR' tmux -L '$SOCKET' -f '$TMUX_CONFIG' attach-session -t aaaaaaaaaaaaaaaaaaa" "$CLIENT_LOG" >/dev/null 2>&1 &
CLIENT_PID=$!
for attempt in $(seq 1 50); do
    [ "$(tmuxc list-clients -F '#{session_name}' 2>/dev/null | grep -Fx 'aaaaaaaaaaaaaaaaaaa' | wc -l | tr -d ' ')" -eq 1 ] && break
    sleep 0.05
done

# Use the same socket shape inherited by a real pane process so the checked-in
# adapter takes its explicit -S socket path.
export TMUX="$SOCKET_PATH,0,1"
source "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter"

discovered="$(sidebar_tmux_global_sidebar_pane)"
discovered_lines="$(printf '%s\n' "$discovered" | sed '/^$/d' | wc -l | tr -d ' ')"
printf 'discovered pane IDs (%s lines):\n%s\n' "$discovered_lines" "$discovered"
if [ "$discovered_lines" -ne 1 ]; then
    printf 'RED: numeric session name 0 duplicates global sidebar discovery\n' >&2
    printf 'discovered pane IDs:\n%s\n' "$discovered" >&2
    exit 1
fi

sidebar_pane="$(printf '%s\n' "$discovered" | head -n 1)"
sidebar_window="$(tmuxc display-message -p -t "$sidebar_pane" '#{window_id}' 2>/dev/null || true)"
for attempt in $(seq 1 100); do
    if tmuxc capture-pane -p -t "$sidebar_pane" 2>/dev/null |
        grep -Fxq 'sessions'; then
        break
    fi
    sleep 0.05
done
for move in $(seq 1 7); do
    tmuxc send-keys -t "$sidebar_pane" Down
    for attempt in $(seq 1 100); do
        if tmuxc capture-pane -p -t "$sidebar_pane" 2>/dev/null |
            grep -E --quiet '>[[:space:]]*bbbbbbbbbbbbbbbbbb'; then
            break 2
        fi
        sleep 0.05
    done
done
selection_capture="$(tmuxc capture-pane -p -t "$sidebar_pane" 2>/dev/null || true)"
printf '%s\n' "$selection_capture" |
    grep -E --quiet '>[[:space:]]*bbbbbbbbbbbbbbbbbb' || {
        printf 'selection capture after Down:+%s\n' "$selection_capture" >&2
        exit 1
    }
tmuxc send-keys -t "$sidebar_pane" Enter
for attempt in $(seq 1 100); do
    client_session="$(tmuxc list-clients -F '#{session_name}' 2>/dev/null | head -n 1 || true)"
    owner_session="$(tmuxc display-message -p -t "$sidebar_pane" '#{session_name}' 2>/dev/null || true)"
    [ "$client_session" = bbbbbbbbbbbbbbbbbb ] &&
        [ "$owner_session" = aaaaaaaaaaaaaaaaaaa ] && break
    sleep 0.05
done

[ "$client_session" = bbbbbbbbbbbbbbbbbb ]
[ "$owner_session" = aaaaaaaaaaaaaaaaaaa ]
[ "$(sidebar_tmux_sidebar_pane_count)" = 2 ]
printf 'PASS: numeric session name preserves unique sidebar discovery\n'
printf 'PASS: attached-client Down+Enter switches to bbbbbbbbbbbbbbbbbb while each window-local sidebar remains unique\n'
