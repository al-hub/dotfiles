#!/usr/bin/env bash
# Presenter & Screen Rendering Module
set -euo pipefail

sidebar_presenter_map_key() {
    local key="$1"
    case "$key" in
        q|Q) echo "QUIT" ;;
        s|S) echo "TOGGLE" ;;
        j|J) echo "DOWN" ;;
        k|K) echo "UP" ;;
        *) echo "UNKNOWN" ;;
    esac
}

sidebar_presenter_render_header() {
    local title="$1" width="$2"
    printf "\033[1;36m%-*s\033[0m\n" "$width" "$title"
}
