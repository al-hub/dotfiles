#!/usr/bin/env bash
# SubpaneHubManager: Global Singleton Subpane Session & Mirror Management
set -euo pipefail

SUBPANE_HUB_SESSION="dotfiles-subpane-hub"

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
    local sub_pane="${1:-}" target_launcher="${2:-}" height="${3:-12}"
    [ -n "$sub_pane" ] && [ -n "$target_launcher" ] || return 1
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"

    local target_win sub_win
    target_win="$(sidebar_tmux_cmd display-message -p -t "$target_launcher" '#{window_id}' 2>/dev/null || true)"
    sub_win="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{window_id}' 2>/dev/null || true)"

    if [ -n "$target_win" ] && [ "$target_win" = "$sub_win" ]; then
        return 0
    fi

    local pos_flag=""
    if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
        if [ "$(sidebar_subpane_get_position)" = "top" ]; then
            pos_flag="-b"
        fi
    fi

    if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$target_launcher" -v -l "$height" 2>/dev/null; then
        sidebar_tmux_cmd join-pane -d $pos_flag -s "$sub_pane" -t "$target_launcher" -v 2>/dev/null || return 1
    fi

    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" allow-rename off 2>/dev/null || true
    sidebar_tmux_cmd select-pane -t "$sub_pane" -T "$sub_title" 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    return 0
}

subpane_hub_acquire_pane() {
    local target_launcher="${1:-}" height="${2:-12}"
    [ -n "$target_launcher" ] || return 1
    local sub_title="${SIDEBAR_SUBPANE_TITLE:-dotfiles-sidebar-subpane}"

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

    if [ -n "$target_win" ] && [ "$target_win" = "$hub_win" ]; then
        sidebar_tmux_cmd set-option -p -q -t "$hub_pane" allow-rename off 2>/dev/null || true
        sidebar_tmux_cmd select-pane -t "$hub_pane" -T "$sub_title" 2>/dev/null || true
        sidebar_tmux_cmd set-option -p -q -t "$hub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
        sidebar_tmux_cmd set-option -p -q -t "$hub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
        printf '%s\n' "$hub_pane"
        return 0
    fi

    local pos_flag=""
    if declare -f sidebar_subpane_get_position >/dev/null 2>&1; then
        if [ "$(sidebar_subpane_get_position)" = "top" ]; then
            pos_flag="-b"
        fi
    fi

    # Join pane from hub or background into target launcher column
    if ! sidebar_tmux_cmd join-pane -d $pos_flag -s "$hub_pane" -t "$target_launcher" -v -l "$height" 2>/dev/null; then
        sidebar_tmux_cmd join-pane -d $pos_flag -s "$hub_pane" -t "$target_launcher" -v 2>/dev/null || return 1
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

    printf '%s\n' "$hub_pane"
}

subpane_hub_release_pane() {
    local sub_pane="${1:-}"
    [ -n "$sub_pane" ] || return 0
    # Keep role tags immutable
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_subpane_hub_pane 1 2>/dev/null || true
    sidebar_tmux_cmd set-option -p -q -t "$sub_pane" @dotfiles_sidebar_subpane 1 2>/dev/null || true
    local curr_sess hub_sess
    curr_sess="$(sidebar_tmux_cmd display-message -p -t "$sub_pane" '#{session_name}' 2>/dev/null || true)"
    hub_sess="$(subpane_hub_session_name)"
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
