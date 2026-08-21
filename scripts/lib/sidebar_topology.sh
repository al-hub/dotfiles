#!/usr/bin/env bash
# WindowTopologyManager: Single Source of Truth for Window Layout and Pane Classification
set -euo pipefail

topology_inspect() {
    local window_id="$1"
    local -n _out_sb="$2"
    local -n _out_sub="$3"
    local -n _out_work="$4"
    local -n _out_act_work="$5"

    _out_sb=""
    _out_sub=""
    _out_work=""
    _out_act_work=""

    local pid ptitle pactive popt_sub
    while IFS='|' read -r pid ptitle pactive popt_sub; do
        [ -n "$pid" ] || continue
        if [ "$ptitle" = "dotfiles-session-sidebar" ]; then
            _out_sb="$pid"
        elif [ "$popt_sub" = "1" ] || [ "$ptitle" = "dotfiles-sidebar-subpane" ]; then
            _out_sub="$pid"
        else
            _out_work="${_out_work:+$_out_work }$pid"
            if [ "$pactive" = "1" ]; then
                _out_act_work="$pid"
            fi
        fi
    done < <(sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_active}|#{@dotfiles_sidebar_subpane}' 2>/dev/null || true)
}

topology_ensure_window() {
    local window_id="$1" width="${2:-30}" subpane_enabled="${3:-0}"
    local sb sub work act_w
    topology_inspect "$window_id" sb sub work act_w

    if [ -z "$sb" ]; then
        provision_sidebar_window "$window_id" "$width" "" "$subpane_enabled" >/dev/null 2>&1 || true
        topology_inspect "$window_id" sb sub work act_w
    fi

    if [ "$subpane_enabled" = "1" ]; then
        if [ -n "$sb" ] && [ -z "$sub" ]; then
            provision_sidebar_subpane "$window_id" "$sb" "" "" >/dev/null 2>&1 || true
        fi
    else
        if [ -n "$sub" ]; then
            destroy_sidebar_subpane "$window_id"
        fi
    fi
}

topology_destroy_sidebar_cluster() {
    local window_id="$1"
    local sb sub work act_w
    topology_inspect "$window_id" sb sub work act_w
    if [ -n "$sub" ]; then
        destroy_sidebar_subpane "$window_id"
    fi
    if [ -n "$sb" ]; then
        destroy_sidebar_window "$window_id"
    fi
}
