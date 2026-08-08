#!/usr/bin/env bash
# Typed Tmux Port & Adapter Isolation Module
set -euo pipefail

sidebar_port_get_current_session() {
    sidebar_tmux_cmd display-message -p '#S' 2>/dev/null || echo ""
}

sidebar_port_get_current_path() {
    sidebar_tmux_cmd display-message -p '#{pane_current_path}' 2>/dev/null || echo ""
}

sidebar_port_switch_client() {
    local client_tty="$1" target_session="$2"
    if [ -n "$client_tty" ]; then
        sidebar_tmux_cmd switch-client -c "$client_tty" -t "=$target_session:"
    else
        sidebar_tmux_cmd switch-client -t "=$target_session:"
    fi
}

sidebar_port_list_sessions() {
    sidebar_tmux_cmd list-sessions -F '#S:#{session_created}:#{session_attached}' 2>/dev/null || true
}
