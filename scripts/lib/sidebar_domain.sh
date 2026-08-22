#!/usr/bin/env bash
# Pure domain helpers for tmux-session-launcher with zero external side-effects or CLI dependencies
set -euo pipefail

sidebar_domain_sanitize_name() {
    local raw="${1:-}"
    local clean="${raw//[:. ]/_}"
    printf '%s\n' "$clean"
}

sidebar_domain_validate_archive_line() {
    local line="${1:-}"
    [[ "$line" =~ ^[0-9]+\|[^|]+\|[^|]+\|[0-9]+\|[0-9]+\|[^|]+\|[0-9]+\|[0-9]+\|[0-9]+\|[^|]*\|[0-9]+$ ]]
}

sidebar_domain_epoch_now() {
    if [ -n "${EPOCHSECONDS:-}" ]; then
        printf '%s\n' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

sidebar_domain_format_duration() {
    local elapsed="${1:-0}"
    case "$elapsed" in
        ''|*[!0-9]*) elapsed=0 ;;
    esac
    local days=$((elapsed / 86400))
    local remain=$((elapsed % 86400))
    local hours=$((remain / 3600))
    remain=$((remain % 3600))
    local minutes=$((remain / 60))
    local seconds=$((remain % 60))
    printf '%d:%02d:%02d:%02d\n' "$days" "$hours" "$minutes" "$seconds"
}

sidebar_domain_session_age_value() {
    local -n _age_out_ref="$1"
    local created_value="${2:-}"
    local now_value
    now_value="$(sidebar_domain_epoch_now)"
    case "$created_value" in
        ''|*[!0-9]*) created_value="$now_value" ;;
    esac
    local duration_elapsed=$((now_value - created_value))
    [ "$duration_elapsed" -lt 0 ] && duration_elapsed=0
    _age_out_ref="$(sidebar_domain_format_duration "$duration_elapsed")"
}

sidebar_domain_layout_body() {
    local layout="${1:-}"
    case "$layout" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F],*) printf '%s\n' "${layout#*,}" ;;
        *) printf '%s\n' "$layout" ;;
    esac
}
SIDEBAR_SUBPANE_OPTION="@dotfiles_sidebar_subpane_enabled"
SIDEBAR_SUBPANE_HEIGHT_OPTION="@dotfiles_sidebar_subpane_height"
SIDEBAR_SUBPANE_POSITION_OPTION="@dotfiles_sidebar_subpane_position"
SIDEBAR_SUBPANE_ENABLED_STATE_FILE="${TMUX_SESSION_SIDEBAR_SUBPANE_ENABLED_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-enabled}"
SIDEBAR_SUBPANE_HEIGHT_STATE_FILE="${TMUX_SESSION_SIDEBAR_SUBPANE_HEIGHT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-height}"
SIDEBAR_SUBPANE_POSITION_STATE_FILE="${TMUX_SESSION_SIDEBAR_SUBPANE_POSITION_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tmux-sidebar-subpane-position}"

sidebar_subpane_title() {
    printf '%s\n' "${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"
}

sidebar_subpane_height_option() {
    printf '%s\n' "${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
}

sidebar_subpane_position_option() {
    printf '%s\n' "${SIDEBAR_SUBPANE_POSITION_OPTION:-@dotfiles_sidebar_subpane_position}"
}

is_sidebar_subpane() {
    local title="${1:-}"
    [ "$title" = "${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}" ]
}

sidebar_subpane_default_height() {
    local total="${1:-0}"
    case "$total" in
        ''|*[!0-9]*) total=0 ;;
    esac
    local h=$((total * 30 / 100))
    if [ "$h" -lt 8 ]; then
        h=8
    elif [ "$h" -gt 25 ]; then
        h=25
    fi
    printf '%d\n' "$h"
}

is_infrastructure_session() {
    local session="${1:-}"
    case "$session" in
        dotfiles-subpane-hub) return 0 ;;
        *) return 1 ;;
    esac
}

sidebar_subpane_calc_pos_flag() {
    local pos="${1:-bottom}"
    case "$pos" in
        top|TOP) printf '%s\n' "-b" ;;
        *) printf '%s\n' "" ;;
    esac
}

sidebar_subpane_calc_join_length() {
    local pos="${1:-bottom}" height="${2:-12}"
    case "$height" in ''|*[!0-9]*) height=12 ;; esac
    case "$pos" in
        top|TOP) printf '%s\n' "$((height + 1))" ;;
        *) printf '%s\n' "$height" ;;
    esac
}

sidebar_subpane_calc_resize_length() {
    local pos="${1:-bottom}" height="${2:-12}"
    case "$height" in ''|*[!0-9]*) height=12 ;; esac
    case "$pos" in
        top|TOP)
            local ver_raw ver
            if declare -f sidebar_tmux_cmd >/dev/null 2>&1; then
                ver_raw="$(sidebar_tmux_cmd -V 2>/dev/null || true)"
            fi
            if [ -z "$ver_raw" ]; then
                ver_raw="$(tmux -V 2>/dev/null || true)"
            fi
            ver="$(printf '%s\n' "$ver_raw" | sed -n 's/^tmux [^0-9]*\([0-9]\+\.[0-9]\+\).*/\1/p')"
            if [ -n "$ver" ] && awk -v v="$ver" 'BEGIN { exit !(v < 3.3) }'; then
                printf '%s\n' "$((height + 1))"
            else
                printf '%s\n' "$height"
            fi
            ;;
        *) printf '%s\n' "$height" ;;
    esac
}
