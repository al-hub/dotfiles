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

sidebar_port_publish_marker_handover() {
    local window_id="${1:-}" target_session="${2:-}"
    [ -n "$window_id" ] || return 1
    [ -n "$target_session" ] || return 1
    local marker_opt="${SIDEBAR_TARGET_MARKER_OPTION:-@dotfiles_sidebar_target_marker}"
    local sync_opt="${SIDEBAR_SELECTION_SYNC_OPTION:-@dotfiles_sidebar_selection_sync}"
    sidebar_tmux_cmd set-option -wq -t "$window_id" "$marker_opt" "$target_session" 2>/dev/null || true
    sidebar_tmux_cmd set-option -wq -t "$window_id" "$sync_opt" "$target_session" 2>/dev/null || true
}

sidebar_port_notify_presenter_wake() {
    local target="${1:-}"
    [ -n "$target" ] || return 0
    local pane_pid=""
    pane_pid="$(sidebar_tmux_cmd display-message -p -t "$target" '#{pane_pid}' 2>/dev/null || true)"
    if [ -z "$pane_pid" ] && declare -f sidebar_window_pane >/dev/null 2>&1; then
        local sb_pane
        sb_pane="$(sidebar_window_pane "$target" 2>/dev/null || true)"
        if [ -n "$sb_pane" ]; then
            pane_pid="$(sidebar_tmux_cmd display-message -p -t "$sb_pane" '#{pane_pid}' 2>/dev/null || true)"
        fi
    fi
    if [ -n "$pane_pid" ] && [ "$pane_pid" -gt 0 ] 2>/dev/null && kill -0 "$pane_pid" 2>/dev/null; then
        kill -WINCH "$pane_pid" 2>/dev/null || kill -SIGWINCH "$pane_pid" 2>/dev/null || true
    fi
    return 0
}

sidebar_tmux_list_user_sessions() {
    local tab="$(printf '\t')"
    local default_fmt="#{session_name}${tab}#{session_created}${tab}#{session_activity}"
    local format="${1:-$default_fmt}"
    sidebar_tmux_cmd list-sessions -F "$format" 2>/dev/null |
        awk -F "$tab" '$1 != "dotfiles-subpane-hub" { print $0 }'
}

sidebar_window_pane() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local title="${SIDEBAR_TITLE:-dotfiles-session-sidebar}"
    sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{@dotfiles_sidebar_pane}|#{pane_title}' 2>/dev/null |
        awk -F '|' -v title="$title" '$2 == "1" || $3 == title { print $1; exit }'
}

sidebar_window_subpane() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"
    sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{@dotfiles_sidebar_subpane}|#{pane_title}' 2>/dev/null |
        awk -F '|' -v title="$sub_title" '$2 == "1" || $3 == title { print $1; exit }'
}

sidebar_port_is_subpane() {
    local pane_id="${1:-}"
    [ -n "$pane_id" ] || return 1
    local opt
    opt="$(sidebar_tmux_cmd show-option -pqv -t "$pane_id" @dotfiles_sidebar_subpane 2>/dev/null || echo 0)"
    [ "$opt" = "1" ]
}

persist_sidebar_subpane_height() {
    local height="$1" state_dir tmp_file
    case "$height" in ''|*[!0-9]*) return 1 ;; esac
    local state_file="${SIDEBAR_SUBPANE_HEIGHT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-height}"
    state_dir="$(dirname "$state_file")"
    mkdir -p "$state_dir" 2>/dev/null || return 1
    tmp_file="$(mktemp "$state_dir/.tmux-sidebar-subpane-height.XXXXXX" 2>/dev/null || true)"
    [ -n "$tmp_file" ] || return 1
    if ! printf '%s\n' "$height" > "$tmp_file"; then
        rm -f -- "$tmp_file"
        return 1
    fi
    if ! mv -f -- "$tmp_file" "$state_file"; then
        rm -f -- "$tmp_file"
        return 1
    fi
}

read_persisted_sidebar_subpane_height() {
    local state_file="${SIDEBAR_SUBPANE_HEIGHT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-height}"
    local height
    [ -r "$state_file" ] || return 1
    IFS= read -r height < "$state_file" || true
    case "$height" in
        ''|*[!0-9]*) return 1 ;;
        *)
            if [ "$height" -ge 4 ] 2>/dev/null; then
                printf '%s\n' "$height"
                return 0
            fi
            return 1
            ;;
    esac
}

sidebar_subpane_get_height() {
    local opt="${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
    local height
    height="$(sidebar_tmux_cmd show-option -gqv "$opt" 2>/dev/null || true)"
    if [ -n "$height" ] && [ "$height" -ge 4 ] 2>/dev/null; then
        printf '%s\n' "$height"
        return 0
    fi
    height="$(read_persisted_sidebar_subpane_height || true)"
    if [ -n "$height" ] && [ "$height" -ge 4 ] 2>/dev/null; then
        sidebar_tmux_cmd set-option -gq "$opt" "$height" 2>/dev/null || true
        printf '%s\n' "$height"
        return 0
    fi
    return 1
}

persist_sidebar_subpane_position() {
    local pos="$1" state_dir tmp_file
    case "$pos" in top|bottom) ;; *) return 1 ;; esac
    local state_file="${SIDEBAR_SUBPANE_POSITION_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-position}"
    state_dir="$(dirname "$state_file")"
    mkdir -p "$state_dir" 2>/dev/null || return 1
    tmp_file="$(mktemp "$state_dir/.tmux-sidebar-subpane-position.XXXXXX" 2>/dev/null || true)"
    [ -n "$tmp_file" ] || return 1
    if ! printf '%s\n' "$pos" > "$tmp_file"; then
        rm -f -- "$tmp_file"
        return 1
    fi
    if ! mv -f -- "$tmp_file" "$state_file"; then
        rm -f -- "$tmp_file"
        return 1
    fi
}

read_persisted_sidebar_subpane_position() {
    local state_file="${SIDEBAR_SUBPANE_POSITION_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-position}"
    local pos
    [ -r "$state_file" ] || return 1
    IFS= read -r pos < "$state_file" || true
    case "$pos" in
        top|bottom) printf '%s\n' "$pos"; return 0 ;;
        *) return 1 ;;
    esac
}

remember_sidebar_subpane_height_for_window() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local win_sess
    win_sess="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{session_name}' 2>/dev/null || true)"
    if declare -f is_infrastructure_session >/dev/null 2>&1 && is_infrastructure_session "$win_sess"; then
        return 0
    fi
    local sub_pane
    sub_pane="$(sidebar_window_subpane "$window_id" || true)"
    [ -n "$sub_pane" ] || return 0
    local height
    height="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{pane_height}' 2>/dev/null || true)"
    case "$height" in
        ''|*[!0-9]*) return 0 ;;
        *)
            if [ "$height" -ge 4 ] 2>/dev/null; then
                local opt="${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
                sidebar_tmux_cmd set-option -gq "$opt" "$height" 2>/dev/null || true
                persist_sidebar_subpane_height "$height" 2>/dev/null || true
            fi
            ;;
    esac
}

sidebar_subpane_get_position() {
    local opt="${SIDEBAR_SUBPANE_POSITION_OPTION:-@dotfiles_sidebar_subpane_position}"
    local pos
    pos="$(sidebar_tmux_cmd show-option -gqv "$opt" 2>/dev/null || true)"
    if [ -z "$pos" ]; then
        pos="$(read_persisted_sidebar_subpane_position 2>/dev/null || true)"
        if [ -n "$pos" ]; then
            sidebar_tmux_cmd set-option -gq "$opt" "$pos" 2>/dev/null || true
        fi
    fi
    case "$pos" in
        top|TOP) printf 'top\n' ;;
        *) printf 'bottom\n' ;;
    esac
}

sidebar_subpane_set_position() {
    local pos="${1:-bottom}"
    local opt="${SIDEBAR_SUBPANE_POSITION_OPTION:-@dotfiles_sidebar_subpane_position}"
    case "$pos" in
        top|TOP) pos="top" ;;
        *) pos="bottom" ;;
    esac
    sidebar_tmux_cmd set-option -gq "$opt" "$pos" 2>/dev/null || true
    persist_sidebar_subpane_position "$pos" 2>/dev/null || true
}

sidebar_subpane_swap_position() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || window_id="$(sidebar_tmux_cmd display-message -p '#{window_id}' 2>/dev/null || true)"
    [ -n "$window_id" ] || return 1

    local cur_pos
    cur_pos="$(sidebar_subpane_get_position)"
    local new_pos="top"
    if [ "$cur_pos" = "top" ]; then
        new_pos="bottom"
    fi
    sidebar_subpane_set_position "$new_pos"

    local launcher_pane sub_pane
    launcher_pane="$(sidebar_window_pane "$window_id" 2>/dev/null || true)"
    sub_pane="$(sidebar_window_subpane "$window_id" 2>/dev/null || true)"
    if [ -n "$launcher_pane" ] && [ -n "$sub_pane" ]; then
        local opt="${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
        local target_h
        target_h="$(sidebar_tmux_cmd show-option -gqv "$opt" 2>/dev/null || true)"
        [ -n "$target_h" ] && [ "$target_h" -ge 4 ] 2>/dev/null || target_h=12

        sidebar_tmux_cmd swap-pane -d -s "$launcher_pane" -t "$sub_pane" 2>/dev/null || true
        sidebar_tmux_cmd resize-pane -t "$sub_pane" -y "$target_h" 2>/dev/null || true
        sidebar_tmux_cmd select-pane -t "$launcher_pane" 2>/dev/null || true
    fi
}

sync_sidebar_subpane_position_for_window() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || window_id="$(sidebar_tmux_cmd display-message -p '#{window_id}' 2>/dev/null || true)"
    [ -n "$window_id" ] || return 0

    local launcher_pane sub_pane
    launcher_pane="$(sidebar_window_pane "$window_id" 2>/dev/null || true)"
    sub_pane="$(sidebar_window_subpane "$window_id" 2>/dev/null || true)"
    [ -n "$launcher_pane" ] && [ -n "$sub_pane" ] || return 0

    local l_top s_top
    l_top="$(sidebar_tmux_cmd display-message -p -t "$launcher_pane" '#{pane_top}' 2>/dev/null || true)"
    s_top="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{pane_top}' 2>/dev/null || true)"
    case "$l_top" in
        ''|*[!0-9]*) return 0 ;;
    esac
    case "$s_top" in
        ''|*[!0-9]*) return 0 ;;
    esac

    if [ "$s_top" -lt "$l_top" ]; then
        sidebar_subpane_set_position "top"
    elif [ "$s_top" -gt "$l_top" ]; then
        sidebar_subpane_set_position "bottom"
    fi
}

provision_sidebar_subpane() {
    local window_id="${1:-}" launcher_pane="${2:-}" height="${3:-}" cmd="${4:-}"
    [ -n "$launcher_pane" ] || return 1
    if [ -z "$height" ]; then
        local saved_h
        saved_h="$(sidebar_subpane_get_height || true)"
        if [ -n "$saved_h" ] && [ "$saved_h" -ge 4 ] 2>/dev/null; then
            height="$saved_h"
        else
            local total_h
            total_h="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{window_height}' 2>/dev/null || echo 40)"
            height="$(sidebar_subpane_default_height "$total_h")"
        fi
    fi

    if declare -f subpane_hub_acquire_pane >/dev/null 2>&1; then
        subpane_hub_acquire_pane "$launcher_pane" "$height"
        return $?
    fi

    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"
    local sub_pane
    local pos_flag=""
    if [ "$(sidebar_subpane_get_position)" = "top" ]; then
        pos_flag="-b"
    fi
    sub_pane="$(sidebar_tmux_cmd split-window -P -F '#{pane_id}' -v $pos_flag -t "$launcher_pane" -l "$height" "${cmd:-/bin/bash}" 2>/dev/null || true)"
    [ -n "$sub_pane" ] || return 1

    if [ -n "$height" ] && [ "$height" -ge 4 ] 2>/dev/null; then
        sidebar_tmux_cmd resize-pane -t "$sub_pane" -y "$height" 2>/dev/null || true
    fi

    sidebar_tmux_cmd select-pane -t "$sub_pane" -T "$sub_title" 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    sidebar_tmux_cmd select-pane -t "$launcher_pane" 2>/dev/null || true

    printf '%s\n' "$sub_pane"
}

destroy_sidebar_subpane() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local win_sess
    win_sess="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{session_name}' 2>/dev/null || true)"
    if declare -f is_infrastructure_session >/dev/null 2>&1 && is_infrastructure_session "$win_sess"; then
        return 0
    fi
    remember_sidebar_subpane_height_for_window "$window_id"
    local sub_pane
    while IFS= read -r sub_pane; do
        [ -n "$sub_pane" ] || continue
        if declare -f subpane_hub_release_pane >/dev/null 2>&1; then
            subpane_hub_release_pane "$sub_pane"
        else
            sidebar_tmux_cmd kill-pane -t "$sub_pane" 2>/dev/null || true
        fi
    done < <(sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{@dotfiles_sidebar_subpane}' 2>/dev/null | awk -F '|' '$2 == "1" { print $1 }')
}

ensure_sidebar_subpane_window() {
    local window_id="${1:-}" launcher_pane="${2:-}"
    [ -n "$window_id" ] || return 0
    local win_sess
    win_sess="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{session_name}' 2>/dev/null || true)"
    if is_infrastructure_session "$win_sess"; then
        return 0
    fi
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

    if [ "$next" = "1" ]; then
        local active_win=""
        local client_tty
        client_tty="$(sidebar_tmux_cmd show-option -gqv "@dotfiles_sidebar_owner_client" 2>/dev/null || true)"
        [ -n "$client_tty" ] || client_tty="$(sidebar_tmux_cmd list-clients -F '#{client_tty}' 2>/dev/null | head -n 1 || true)"
        if [ -n "$client_tty" ]; then
            active_win="$(sidebar_tmux_cmd display-message -p -c "$client_tty" '#{window_id}' 2>/dev/null || true)"
        fi
        if [ -z "$active_win" ] || (declare -f is_infrastructure_session >/dev/null 2>&1 && is_infrastructure_session "$(sidebar_tmux_cmd display-message -p -t "$active_win" '#{session_name}' 2>/dev/null || true)"); then
            active_win="$(sidebar_tmux_cmd list-windows -a -F '#{window_id}|#{session_name}' 2>/dev/null | awk -F '|' '!/dotfiles-subpane-hub/ { print $1; exit }')"
        fi
        if [ -n "$active_win" ]; then
            ensure_sidebar_subpane_window "$active_win" ""
        fi
    else
        local sub_pane
        if declare -f subpane_hub_get_pane >/dev/null 2>&1; then
            sub_pane="$(subpane_hub_get_pane 2>/dev/null || true)"
            if [ -n "$sub_pane" ] && declare -f subpane_hub_release_pane >/dev/null 2>&1; then
                subpane_hub_release_pane "$sub_pane"
            fi
        fi
        local win_id sess_name
        while IFS='|' read -r win_id sess_name; do
            [ -n "$win_id" ] || continue
            if declare -f is_infrastructure_session >/dev/null 2>&1 && is_infrastructure_session "$sess_name"; then
                continue
            fi
            destroy_sidebar_subpane "$win_id"
        done < <(sidebar_tmux_cmd list-windows -a -F '#{window_id}|#{session_name}' 2>/dev/null || true)
    fi
}

provision_sidebar_window() {
    local window_id="${1:-}" width="${2:-30}" cmd="${3:-}"
    [ -n "$window_id" ] || return 1
    local win_sess
    win_sess="$(sidebar_tmux_cmd display-message -p -t "$window_id" '#{session_name}' 2>/dev/null || true)"
    if is_infrastructure_session "$win_sess"; then
        return 0
    fi
    local existing
    existing="$(sidebar_window_pane "$window_id" || true)"
    [ -z "$existing" ] || return 0
    local work_pane
    work_pane="$(sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{@dotfiles_sidebar_subpane}' 2>/dev/null |
        awk -F '|' '$2 != "dotfiles-session-sidebar" && $2 != "dotfiles-sidebar-subpane" && $3 != "1" { print $1; exit }')"
    [ -n "$work_pane" ] || return 1
    if [ -z "$cmd" ]; then
        local launcher_bin="${DOTFILES_DIR:-/home/al-hub/workspace/dotfiles}/scripts/tmux-session-launcher"
        cmd="$launcher_bin --sidebar"
    fi
    local pane_id
    pane_id="$(sidebar_tmux_cmd split-window -P -F '#{pane_id}' -d -t "$work_pane" -h -f -b -l "$width" "$cmd" 2>/dev/null || true)"
    [ -n "$pane_id" ] || return 1
    sidebar_tmux_cmd select-pane -t "$pane_id" -T "dotfiles-session-sidebar" 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$pane_id" remain-on-exit on 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$pane_id" @dotfiles_sidebar_pane 1 2>/dev/null || true
    printf '%s\n' "$pane_id"
}

destroy_sidebar_window() {
    local window_id="${1:-}"
    [ -n "$window_id" ] || return 0
    local sb_pane
    sb_pane="$(sidebar_tmux_cmd list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{@dotfiles_sidebar_pane}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" || $3 == "1" { print $1; exit }')"
    if [ -n "$sb_pane" ]; then
        sidebar_tmux_cmd kill-pane -t "$sb_pane" 2>/dev/null || true
    fi
}

