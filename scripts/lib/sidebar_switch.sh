#!/usr/bin/env bash
# Hot/Cold Path Session Switch Transaction Service Module
set -euo pipefail

sidebar_switch_execute_hot() {
    local client_tty="$1" target_session="$2" target_window="${3:-}" sidebar_pane="${4:-}"
    if [ -z "$target_session" ]; then
        return 1
    fi
    local target_spec="=$target_session:"
    if [ -n "$sidebar_pane" ]; then
        if [ -n "$client_tty" ]; then
            sidebar_tmux_cmd switch-client -c "$client_tty" -t "$target_spec" \; select-pane -t "$sidebar_pane" 2>/dev/null
        else
            sidebar_tmux_cmd switch-client -t "$target_spec" \; select-pane -t "$sidebar_pane" 2>/dev/null
        fi
    else
        sidebar_port_switch_client "$client_tty" "$target_session"
    fi
}

sidebar_switch_reconcile_cold() {
    local target_session="$1" target_window="$2"
    # Cold repair path helper for missing or degraded sidebar pane
    return 0
}
