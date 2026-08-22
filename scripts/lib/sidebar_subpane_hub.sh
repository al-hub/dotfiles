#!/usr/bin/env bash
# SubpaneHubManager: Global Singleton Subpane Session & Mirror Management
set -euo pipefail

SUBPANE_HUB_SESSION="dotfiles-subpane-hub"
SUBPANE_LEASE_OPTION="@dotfiles_subpane_lease_window"

subpane_hub_get_lease_holder() {
    sidebar_tmux_cmd show-option -gqv "$SUBPANE_LEASE_OPTION" 2>/dev/null || true
}

subpane_hub_acquire_lease() {
    local target_win="${1:-}"
    [ -n "$target_win" ] || return 1
    sidebar_tmux_cmd set-option -gq "$SUBPANE_LEASE_OPTION" "$target_win" 2>/dev/null || true
}

subpane_hub_release_lease() {
    local target_win="${1:-}"
    local current_holder
    current_holder="$(subpane_hub_get_lease_holder)"
    if [ -z "$target_win" ] || [ "$current_holder" = "$target_win" ]; then
        sidebar_tmux_cmd set-option -gu "$SUBPANE_LEASE_OPTION" 2>/dev/null || true
    fi
}

subpane_hub_session_name() {
    printf '%s\n' "$SUBPANE_HUB_SESSION"
}

subpane_hub_default_command() {
    local zdot="${HOME}/.cache/dotfiles"
    if [ -x "/bin/zsh" ]; then
        printf 'exec env ZDOTDIR="%s" /bin/zsh\n' "$zdot"
    else
        printf 'exec env ZDOTDIR="%s" %s\n' "$zdot" "${SHELL:-/bin/bash}"
    fi
}

subpane_hub_is_alive() {
    if sidebar_tmux_cmd has-session -t "=$(subpane_hub_session_name):" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

subpane_hub_ensure_session() {
    if subpane_hub_is_alive; then
        return 0
    fi
    local existing_pane
    existing_pane="$( (sidebar_tmux_cmd list-panes -a -F '#{pane_id}|#{@dotfiles_subpane_hub_pane}' 2>/dev/null || true) | awk -F '|' '$2 == "1" { print $1; exit }')"
    if [ -n "$existing_pane" ]; then
        return 0
    fi
    local zdot="${HOME}/.cache/dotfiles"
    mkdir -p "$zdot" 2>/dev/null || true
    if [ ! -f "$zdot/.zshrc" ]; then
        cat <<'EOF' > "$zdot/.zshrc" 2>/dev/null || true
PROMPT='$ '
RPROMPT=''
autoload -Uz compinit 2>/dev/null || true
compinit -u 2>/dev/null || true
EOF
    fi
    local cmd hub_sess
    hub_sess="$(subpane_hub_session_name)"
    cmd="$(subpane_hub_default_command)"
    sidebar_tmux_cmd new-session -d -s "$hub_sess" -n "hub" -x 30 -y 12 "$cmd" 2>/dev/null || true
    sidebar_tmux_cmd set-option -t "=$hub_sess:" remain-on-exit off 2>/dev/null || true
    sidebar_tmux_cmd set-option -s -t "$hub_sess" @dotfiles_sidebar_managed 0 2>/dev/null || true
    sidebar_tmux_cmd set-hook -t "$hub_sess" -u window-linked 2>/dev/null || true
    sidebar_tmux_cmd set-hook -t "$hub_sess" -u window-unlinked 2>/dev/null || true
    sidebar_tmux_cmd set-hook -t "$hub_sess" -u session-created 2>/dev/null || true
    sidebar_tmux_cmd set-hook -t "$hub_sess" -u client-session-changed 2>/dev/null || true
    local init_pane
    init_pane="$(sidebar_tmux_cmd list-panes -t "=$hub_sess:" -F '#{pane_id}' 2>/dev/null | head -n 1 || true)"
    if [ -n "$init_pane" ]; then
        sidebar_tmux_cmd set-option -p -q -t "$init_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
        sidebar_tmux_cmd set-option -p -q -t "$init_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
        sidebar_tmux_cmd set-option -p -q -t "$init_pane" allow-rename off 2>/dev/null || true
        sidebar_tmux_cmd select-pane -t "$init_pane" -T "${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}" 2>/dev/null || true
    fi
    sleep 0.3
}

subpane_hub_get_pane() {
    local pane_id
    # 1. Search if any pane has @dotfiles_subpane_hub_pane 1 across server
    pane_id="$( (sidebar_tmux_cmd list-panes -a -F '#{pane_id}|#{@dotfiles_subpane_hub_pane}' 2>/dev/null || true) | awk -F '|' '$2 == "1" { print $1; exit }')"
    if [ -n "$pane_id" ]; then
        printf '%s\n' "$pane_id"
        return 0
    fi
    # 2. Search in hub session
    if subpane_hub_is_alive; then
        pane_id="$( (sidebar_tmux_cmd list-panes -t "=$(subpane_hub_session_name):" -F '#{pane_id}' 2>/dev/null || true) | head -n 1)"
        if [ -n "$pane_id" ]; then
            sidebar_tmux_cmd set-option -p -q -t "$pane_id" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
            sidebar_tmux_cmd set-option -p -q -t "$pane_id" @dotfiles_sidebar_subpane 1 2>/dev/null || true
            printf '%s\n' "$pane_id"
            return 0
        fi
    fi
    return 1
}

subpane_hub_relocate_pane_atomic() {
    local sub_pane="${1:-}" target_launcher="${2:-}" height="${3:-}"
    [ -n "$sub_pane" ] && [ -n "$target_launcher" ] || return 1
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"

    if [ -z "$height" ] || ! [ "$height" -ge 4 ] 2>/dev/null; then
        local saved_h
        if declare -f sidebar_subpane_get_height >/dev/null 2>&1; then
            saved_h="$(sidebar_subpane_get_height || true)"
        else
            local opt="${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
            saved_h="$(sidebar_tmux_cmd show-option -gqv "$opt" 2>/dev/null || true)"
        fi
        if [ -n "$saved_h" ] && [ "$saved_h" -ge 4 ] 2>/dev/null; then
            height="$saved_h"
        else
            height=12
        fi
    fi
    local target_win
    target_win="$(sidebar_tmux_cmd display-message -p -t "$target_launcher" '#{window_id}' 2>/dev/null || true)"
    [ -n "$target_win" ] && subpane_hub_acquire_lease "$target_win"

    if [ -z "$height" ]; then
        local saved_h
        if declare -f sidebar_subpane_get_height >/dev/null 2>&1; then
            saved_h="$(sidebar_subpane_get_height 2>/dev/null || true)"
        fi
        if [ -n "$saved_h" ] && [ "$saved_h" -ge 4 ] 2>/dev/null; then
            height="$saved_h"
        else
            height=12
        fi
    fi

    local sub_pos="bottom" pos_flag=""
    if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
        sub_pos="$(sidebar_subpane_get_position 2>/dev/null || echo bottom)"
    fi
    if declare -f sidebar_subpane_calc_pos_flag >/dev/null 2>&1; then
        pos_flag="$(sidebar_subpane_calc_pos_flag "$sub_pos")"
    elif [ "$sub_pos" = "top" ]; then
        pos_flag="-b"
    fi

    local join_l="$height"
    if declare -f sidebar_subpane_calc_join_length >/dev/null 2>&1; then
        join_l="$(sidebar_subpane_calc_join_length "$sub_pos" "$height")"
    elif [ "$pos_flag" = "-b" ]; then
        join_l="$((height + 1))"
    fi

    if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$target_launcher" -v -l "$join_l" 2>/dev/null; then
        sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$target_launcher" -v 2>/dev/null || return 1
    fi

    if [ -n "$height" ] && [ "$height" -ge 4 ] 2>/dev/null; then
        sidebar_tmux_cmd resize-pane -t "$sub_pane" -y "$join_l" 2>/dev/null || true
    fi

    # Keep role tags immutable
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    return 0
}

subpane_hub_acquire_pane() {
    local target_launcher="$1" height="${2:-}" sub_title="${3:-dotfiles-sidebar-subpane}"
    [ -n "$target_launcher" ] || return 1

    if [ -z "$height" ]; then
        local saved_h
        if declare -f sidebar_subpane_get_height >/dev/null 2>&1; then
            saved_h="$(sidebar_subpane_get_height 2>/dev/null || true)"
        fi
        if [ -n "$saved_h" ] && [ "$saved_h" -ge 4 ] 2>/dev/null; then
            height="$saved_h"
        else
            height=12
        fi
    fi

    subpane_hub_ensure_session

    local hub_pane
    hub_pane="$(subpane_hub_get_pane || true)"
    if [ -z "$hub_pane" ]; then
        subpane_hub_ensure_session
        hub_pane="$(subpane_hub_get_pane || true)"
    fi
    [ -n "$hub_pane" ] || return 1

    local target_win hub_win
    target_win="$(sidebar_tmux_cmd display-message -p -t "$target_launcher" '#{window_id}' 2>/dev/null || true)"
    hub_win="$(sidebar_tmux_cmd display-message -p -t "$hub_pane" '#{window_id}' 2>/dev/null || true)"

    # If already in the target window, nothing to join
    if [ -n "$target_win" ] && [ "$target_win" = "$hub_win" ]; then
        subpane_hub_acquire_lease "$target_win"
        printf '%s\n' "$hub_pane"
        return 0
    fi

    local sub_pos="bottom" pos_flag=""
    if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
        sub_pos="$(sidebar_subpane_get_position 2>/dev/null || echo bottom)"
    fi
    if declare -f sidebar_subpane_calc_pos_flag >/dev/null 2>&1; then
        pos_flag="$(sidebar_subpane_calc_pos_flag "$sub_pos")"
    elif [ "$sub_pos" = "top" ]; then
        pos_flag="-b"
    fi

    local join_l="$height"
    if declare -f sidebar_subpane_calc_join_length >/dev/null 2>&1; then
        join_l="$(sidebar_subpane_calc_join_length "$sub_pos" "$height")"
    elif [ "$pos_flag" = "-b" ]; then
        join_l="$((height + 1))"
    fi

    local resize_l="$height"
    if declare -f sidebar_subpane_calc_resize_length >/dev/null 2>&1; then
        resize_l="$(sidebar_subpane_calc_resize_length "$sub_pos" "$height")"
    fi

    # Join pane from hub or background into target launcher column
    if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$hub_pane" -t "$target_launcher" -v -l "$join_l" 2>/dev/null; then
        sidebar_tmux_cmd join-pane -d $pos_flag -s "$hub_pane" -t "$target_launcher" -v 2>/dev/null || return 1
    fi

    if [ -n "$height" ] && [ "$height" -ge 4 ] 2>/dev/null; then
        sidebar_tmux_cmd resize-pane -t "$hub_pane" -y "$resize_l" 2>/dev/null || true
    fi

    sidebar_tmux_cmd set-option -p -q -t "$hub_pane" allow-rename off 2>/dev/null || true
    sidebar_tmux_cmd select-pane -t "$hub_pane" -T "$sub_title" 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$hub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$hub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    sidebar_tmux_cmd select-pane -t "$target_launcher" 2>/dev/null || true
    local client_tty
    while IFS= read -r client_tty; do
        [ -n "$client_tty" ] || continue
        sidebar_tmux_cmd select-pane -t "$target_launcher" -c "$client_tty" 2>/dev/null || true
    done < <(sidebar_tmux_cmd list-clients -F '#{client_tty}' 2>/dev/null || true)

    [ -n "$target_win" ] && subpane_hub_acquire_lease "$target_win"
    printf '%s\n' "$hub_pane"
}

subpane_hub_release_pane() {
    local sub_pane="${1:-}"
    [ -n "$sub_pane" ] || return 0
    local curr_win
    curr_win="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{window_id}' 2>/dev/null || true)"
    [ -n "$curr_win" ] && subpane_hub_release_lease "$curr_win"
    local curr_sess hub_sess
    curr_sess="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{session_name}' 2>/dev/null || true)"
    hub_sess="$(subpane_hub_session_name)"
    if [ "$curr_sess" != "$hub_sess" ]; then
        local sub_h
        sub_h="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{pane_height}' 2>/dev/null || true)"
        if [ -n "$sub_h" ] && [ "$sub_h" -ge 4 ] 2>/dev/null; then
            local opt="${SIDEBAR_SUBPANE_HEIGHT_OPTION:-@dotfiles_sidebar_subpane_height}"
            sidebar_tmux_cmd set-option -gq "$opt" "$sub_h" 2>/dev/null || true
        fi
    fi
    # Keep role tags immutable
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    if [ "$curr_sess" != "$hub_sess" ]; then
        if ! subpane_hub_is_alive; then
            sidebar_tmux_cmd new-session -d -s "$hub_sess" -n "hub" -x 30 -y 12 'sleep 3600' 2>/dev/null || true
            sidebar_tmux_cmd set-option -t "=$hub_sess:" remain-on-exit off 2>/dev/null || true
            sidebar_tmux_cmd set-option -s -t "$hub_sess" @dotfiles_sidebar_managed 0 2>/dev/null || true
            sidebar_tmux_cmd set-hook -t "$hub_sess" -u window-linked 2>/dev/null || true
            sidebar_tmux_cmd set-hook -t "$hub_sess" -u window-unlinked 2>/dev/null || true
            sidebar_tmux_cmd set-hook -t "$hub_sess" -u session-created 2>/dev/null || true
            sidebar_tmux_cmd set-hook -t "$hub_sess" -u client-session-changed 2>/dev/null || true
            local placeholder
            placeholder="$(sidebar_tmux_cmd list-panes -t "=$hub_sess:" -F '#{pane_id}' 2>/dev/null | head -n 1 || true)"
            sidebar_tmux_cmd join-pane -d -s "$sub_pane" -t "=$hub_sess:" 2>/dev/null || true
            if [ -n "$placeholder" ] && [ "$placeholder" != "$sub_pane" ]; then
                sidebar_tmux_cmd kill-pane -t "$placeholder" 2>/dev/null || true
            fi
        else
            sidebar_tmux_cmd join-pane -d -s "$sub_pane" -t "=$hub_sess:" 2>/dev/null || true
        fi
    fi
}

subpane_hub_destroy() {
    local hub_pane
    hub_pane="$(subpane_hub_get_pane || true)"
    if [ -n "$hub_pane" ]; then
        sidebar_tmux_cmd kill-pane -t "$hub_pane" 2>/dev/null || true
    fi
    if subpane_hub_is_alive; then
        sidebar_tmux_cmd kill-session -t "=$(subpane_hub_session_name):" 2>/dev/null || true
    fi
}
