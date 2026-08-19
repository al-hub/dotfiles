#!/usr/bin/env bash
# Hot/Cold Path Session Switch Transaction Service Module
set -euo pipefail

sidebar_switch_execute_hot() {
    local client_tty="$1" target_session="$2" target_window="${3:-}" sidebar_pane="${4:-}" width="${5:-}" sub_pane="${6:-}" sub_height="${7:-12}"
    if [ -z "$target_session" ]; then
        return 1
    fi
    local target_win="$target_window"
    if [ -z "$target_win" ] && [ -n "$sidebar_pane" ]; then
        target_win="$(sidebar_tmux_cmd display-message -p -t "$sidebar_pane" '#{window_id}' 2>/dev/null || true)"
    fi
    if [ -z "$target_win" ] && [ -n "$target_session" ]; then
        target_win="$(sidebar_tmux_cmd display-message -p -t "=$target_session:" '#{window_id}' 2>/dev/null || true)"
    fi

    if [ -n "$target_win" ]; then
        sidebar_port_publish_marker_handover "$target_win" "$target_session"
    fi
    if [ -n "$sidebar_pane" ]; then
        sidebar_port_notify_presenter_wake "$sidebar_pane"
    elif [ -n "$target_win" ]; then
        sidebar_port_notify_presenter_wake "$target_win"
    fi

    local target_spec="=$target_session:"
    if [ -n "$sub_pane" ] && [ -n "$sidebar_pane" ]; then
        local sub_win target_win
        sub_win="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{window_id}' 2>/dev/null || true)"
        target_win="$(sidebar_tmux_cmd display-message -p -t "$sidebar_pane" '#{window_id}' 2>/dev/null || true)"
        if [ -n "$sub_win" ] && [ "$sub_win" != "$target_win" ]; then
            local pos_flag=""
            if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
                if [ "$(sidebar_subpane_get_position)" = "top" ]; then
                    pos_flag="-b"
                fi
            fi
            if [ -n "$client_tty" ]; then
                if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v -l "$sub_height" \; switch-client -c "$client_tty" -t "$target_spec" \; select-pane -t "$sidebar_pane" 2>/dev/null; then
                    sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v \; switch-client -c "$client_tty" -t "$target_spec" \; select-pane -t "$sidebar_pane" 2>/dev/null || return 1
                fi
            else
                if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v -l "$sub_height" \; select-pane -t "$sidebar_pane" 2>/dev/null; then
                    sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v \; select-pane -t "$sidebar_pane" 2>/dev/null || return 1
                fi
            fi
            if [ -n "$sub_height" ] && [ "$sub_height" -ge 4 ] 2>/dev/null; then
                sidebar_tmux_cmd resize-pane -t "$sub_pane" -y "$sub_height" 2>/dev/null || true
            fi
            sidebar_tmux_cmd set-option -p -q -t "$sub_pane" allow-rename off 2>/dev/null || true
            sidebar_tmux_cmd select-pane -t "$sub_pane" -T "${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}" 2>/dev/null || true
            sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
            sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
            return 0
        fi
    fi
    if [ -n "$sidebar_pane" ]; then
        if [ -n "$client_tty" ]; then
            sidebar_tmux_cmd switch-client -c "$client_tty" -t "$target_spec" \; select-pane -t "$sidebar_pane" 2>/dev/null
        else
            sidebar_tmux_cmd select-pane -t "$sidebar_pane" 2>/dev/null || true
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
