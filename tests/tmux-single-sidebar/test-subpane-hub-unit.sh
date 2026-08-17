#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

[ "$(subpane_hub_session_name)" = "dotfiles-subpane-hub" ] || { echo "FAIL: session name"; exit 1; }
[[ "$(subpane_hub_default_command)" == *"ZDOTDIR"* ]] || { echo "FAIL: default command missing ZDOTDIR"; exit 1; }

echo "PASS: subpane hub unit tests"
