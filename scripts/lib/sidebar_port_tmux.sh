#!/usr/bin/env bash
# Typed Tmux Port & Adapter Isolation Module
set -euo pipefail

if ! declare -f sidebar_tmux_cmd >/dev/null 2>&1; then
    sidebar_tmux_cmd() {
        local tmux_socket="${TMUX:-}"
        tmux_socket="${tmux_socket%%,*}"
        if [ -n "$tmux_socket" ] && [ -S "$tmux_socket" ]; then
            command tmux -S "$tmux_socket" "$@"
        elif [ -n "$tmux_socket" ] && [ -S "/tmp/tmux-$(id -u 2>/dev/null || echo 1000)/$tmux_socket" ]; then
            command tmux -S "/tmp/tmux-$(id -u 2>/dev/null || echo 1000)/$tmux_socket" "$@"
        elif [ -n "$tmux_socket" ] && [[ "$tmux_socket" != *"/"* ]]; then
            command tmux -L "$tmux_socket" "$@"
        else
            command tmux "$@"
        fi
    }
fi

sidebar_port_get_current_session() {
    sidebar_tmux_cmd display-message -p '#S' 2>/dev/null || echo ""
}

sidebar_port_get_current_path() {
    sidebar_tmux_cmd display-message -p '#{pane_current_path}' 2>/dev/null || echo ""
}

sidebar_port_switch_client() {
    local client_tty="${1:-}" target_session="${2:-}"
    [ -n "$target_session" ] || return 1
    if [ -n "$client_tty" ]; then
        sidebar_tmux_cmd switch-client -c "$client_tty" -t "=$target_session:"
    else
        sidebar_tmux_cmd switch-client -t "=$target_session:"
    fi
}

sidebar_port_session_exists() {
    local target="${1:-}"
    [ -n "$target" ] || return 1
    sidebar_tmux_cmd has-session -t "=$target:" >/dev/null 2>&1
}

sidebar_port_mark_session_managed() {
    local session="${1:-}"
    [ -n "$session" ] || return 1
    local opt="${SIDEBAR_MANAGED_OPTION:-@dotfiles_sidebar_managed}"
    sidebar_tmux_cmd set-option -t "=$session:" "$opt" 1 2>/dev/null || true
}

sidebar_port_session_is_managed() {
    local session="${1:-}"
    [ -n "$session" ] || return 1
    local opt="${SIDEBAR_MANAGED_OPTION:-@dotfiles_sidebar_managed}"
    [ "$(sidebar_tmux_cmd show-option -qv -t "=$session:" "$opt" 2>/dev/null || true)" = "1" ]
}

sidebar_window_subpane() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"
    sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' -v title="$sub_title" '$2 == title { print $1; exit }'
}

provision_sidebar_subpane() {
    local window_id="${1:-}" launcher_pane="${2:-}" height="${3:-}" cmd="${4:-}"
    [ -n "$launcher_pane" ] || return 1
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"
    if [ -z "$height" ]; then
        local total_h
        total_h="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{window_height}' 2>/dev/null || echo 40)"
        height="$(sidebar_subpane_default_height "$total_h")"
    fi
    if [ -z "$cmd" ]; then
        cmd="${SHELL:-/bin/bash}"
    fi

    local sub_pane
    sub_pane="$(sidebar_tmux_cmd split-window -P -F '#{pane_id}' -v -t "$launcher_pane" -l "$height" "$cmd" 2>/dev/null || true)"
    [ -n "$sub_pane" ] || return 1

    sidebar_tmux_cmd select-pane -t "$sub_pane" -T "$sub_title" 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    sidebar_tmux_cmd select-pane -t "$launcher_pane" 2>/dev/null || true

    printf '%s\n' "$sub_pane"
}

destroy_sidebar_subpane() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local sub_pane
    sub_pane="$(sidebar_window_subpane "$window_id" || true)"
    if [ -n "$sub_pane" ]; then
        sidebar_tmux_cmd kill-pane -t "$sub_pane" 2>/dev/null || true
    fi
}

ensure_sidebar_subpane_window() {
    local window_id="${1:-}" launcher_pane="${2:-}"
    [ -n "$window_id" ] || return 0
    [ -n "$launcher_pane" ] || launcher_pane="$(sidebar_window_pane "$window_id" || true)"
    [ -n "$launcher_pane" ] || return 0

    local enabled sub_pane
    enabled="$(sidebar_tmux_cmd show-option -gqv "${SIDEBAR_SUBPANE_OPTION:-@dotfiles_sidebar_subpane_enabled}" 2>/dev/null || echo 0)"
    sub_pane="$(sidebar_window_subpane "$window_id" || true)"

    if [ "$enabled" = "1" ]; then
        if [ -z "$sub_pane" ]; then
            provision_sidebar_subpane "$window_id" "$launcher_pane" "" "" >/dev/null 2>&1 || true
        fi
    else
        if [ -n "$sub_pane" ]; then
            destroy_sidebar_subpane "$window_id"
        fi
    fi
}

toggle_sidebar_subpane_global() {
    local opt="${SIDEBAR_SUBPANE_OPTION:-@dotfiles_sidebar_subpane_enabled}"
    local current
    current="$(sidebar_tmux_cmd show-option -gqv "$opt" 2>/dev/null || echo 0)"
    local next=1
    [ "$current" = "1" ] && next=0
    sidebar_tmux_cmd set-option -gq "$opt" "$next" 2>/dev/null || true

    local win_id
    while IFS= read -r win_id; do
        [ -n "$win_id" ] || continue
        ensure_sidebar_subpane_window "$win_id" ""
    done < <(sidebar_tmux_cmd list-windows -a -F '#{window_id}' 2>/dev/null || true)
}
