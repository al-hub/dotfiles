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

subpane_hub_attach_command() {
    printf 'tmux attach-session -t =%s:\n' "$SUBPANE_HUB_SESSION"
}

subpane_hub_is_alive() {
    sidebar_tmux_cmd has-session -t "=$(subpane_hub_session_name):" >/dev/null 2>&1
}

subpane_hub_ensure_session() {
    if ! subpane_hub_is_alive; then
        local cmd
        cmd="$(subpane_hub_default_command)"
        sidebar_tmux_cmd new-session -d -s "$(subpane_hub_session_name)" -x 30 -y 12 "$cmd" 2>/dev/null || true
        sidebar_tmux_cmd set-option -t "=$(subpane_hub_session_name):" remain-on-exit off 2>/dev/null || true
    fi
}

subpane_hub_destroy() {
    if subpane_hub_is_alive; then
        sidebar_tmux_cmd kill-session -t "=$(subpane_hub_session_name):" 2>/dev/null || true
    fi
}
