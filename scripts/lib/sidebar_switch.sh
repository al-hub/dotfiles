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
    local lease_opt="${SUBPANE_LEASE_OPTION:-@dotfiles_subpane_lease_window}"
    if [ -n "$sub_pane" ] && [ -n "$sidebar_pane" ]; then
        local sub_win
        sub_win="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{window_id}' 2>/dev/null || true)"
        if [ -n "$sub_win" ] && [ "$sub_win" != "$target_win" ]; then
            local sub_pos="bottom" pos_flag=""
            if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
                sub_pos="$(sidebar_subpane_get_position 2>/dev/null || echo bottom)"
            fi
            if declare -f sidebar_subpane_calc_pos_flag >/dev/null 2>&1; then
                pos_flag="$(sidebar_subpane_calc_pos_flag "$sub_pos")"
            elif [ "$sub_pos" = "top" ]; then
                pos_flag="-b"
            fi

            local win_h target_h
            win_h="$(sidebar_tmux_cmd display-message -p -t "$target_win" '#{window_height}' 2>/dev/null || echo 40)"
            target_h="${sub_height:-12}"
            [ "$target_h" -ge 4 ] 2>/dev/null || target_h=12
            if [ "$((win_h - target_h))" -lt 6 ]; then
                target_h="$((win_h - 6))"
                [ "$target_h" -ge 4 ] || target_h=4
            fi

            local join_l="$target_h"
            if declare -f sidebar_subpane_calc_join_length >/dev/null 2>&1; then
                join_l="$(sidebar_subpane_calc_join_length "$sub_pos" "$target_h")"
            elif [ "$pos_flag" = "-b" ]; then
                join_l="$((target_h + 1))"
            fi

            if declare -f set_sidebar_layout_hook_guard >/dev/null 2>&1; then
                set_sidebar_layout_hook_guard 500
            else
                sidebar_tmux_cmd set-option -gq "${SIDEBAR_LAYOUT_HOOK_GUARD_OPTION:-@dotfiles_sidebar_layout_hook_guard}" "$(( $(date +%s%N) + 500000000 ))" 2>/dev/null || true
            fi

            local resize_l="$target_h"
            if declare -f sidebar_subpane_calc_resize_length >/dev/null 2>&1; then
                resize_l="$(sidebar_subpane_calc_resize_length "$sub_pos" "$target_h")"
            fi

            if [ -n "$client_tty" ]; then
                if ! sidebar_tmux_cmd switch-client -c "$client_tty" -t "$target_spec" \; set-option -gq "$lease_opt" "$target_win" \; join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v -l "$join_l" \; resize-pane -t "$sub_pane" -y "$resize_l" \; select-pane -t "$sidebar_pane" 2>/dev/null; then
                    sidebar_tmux_cmd switch-client -c "$client_tty" -t "$target_spec" \; set-option -gq "$lease_opt" "$target_win" \; join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v \; resize-pane -t "$sub_pane" -y "$resize_l" \; select-pane -t "$sidebar_pane" 2>/dev/null || return 1
                fi
            else
                if ! sidebar_tmux_cmd set-option -gq "$lease_opt" "$target_win" \; join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v -l "$join_l" \; resize-pane -t "$sub_pane" -y "$resize_l" \; select-pane -t "$sidebar_pane" 2>/dev/null; then
                    sidebar_tmux_cmd set-option -gq "$lease_opt" "$target_win" \; join-pane -d $pos_flag -s "$sub_pane" -t "$sidebar_pane" -v \; resize-pane -t "$sub_pane" -y "$resize_l" \; select-pane -t "$sidebar_pane" 2>/dev/null || return 1
                fi
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
