#!/usr/bin/env bash
# test-help-viewer.sh
# Validates tmux-help-viewer standalone execution, tmux.conf bindings, and launcher integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELP_SCRIPT="$SCRIPT_DIR/scripts/tmux-help-viewer"
TMUX_CONF="$SCRIPT_DIR/dotfiles/tmux.conf"
INSTALL_TOML="$SCRIPT_DIR/install.toml"
LAUNCHER="$SCRIPT_DIR/scripts/tmux-session-launcher"
TEST_SOCKET="test-help-$$"

cleanup() {
    tmux -L "$TEST_SOCKET" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== [1/4] Verifying tmux-help-viewer script execution ==="
[ -x "$HELP_SCRIPT" ] || { echo "FAIL: tmux-help-viewer is not executable"; exit 1; }
output="$(printf '\n' | "$HELP_SCRIPT" || true)"
if ! echo "$output" | grep -q "주요 단축키 가이드"; then
    echo "FAIL: Help viewer output missing title header!"
    exit 1
fi
if ! echo "$output" | grep -q "Ctrl+a s"; then
    echo "FAIL: Help viewer output missing Ctrl+a s sidebar toggle!"
    exit 1
fi
if ! echo "$output" | grep -q "Ctrl+a T"; then
    echo "FAIL: Help viewer output missing Ctrl+a T theme picker!"
    exit 1
fi
if ! echo "$output" | grep -q "Ctrl+a /"; then
    echo "FAIL: Help viewer output missing Ctrl+a / command palette!"
    exit 1
fi
echo "PASS: tmux-help-viewer renders all keybinding categories cleanly."

echo "=== [2/4] Verifying tmux.conf keybindings ==="
if ! grep -F -q 'h display-popup -E -w 70% -h 65% "$HOME/.local/bin/tmux-help-viewer"' "$TMUX_CONF"; then
    echo "FAIL: tmux.conf missing 'h' keybinding for tmux-help-viewer!"
    exit 1
fi
if ! grep -F -q '? display-popup -E -w 70% -h 65% "$HOME/.local/bin/tmux-help-viewer"' "$TMUX_CONF"; then
    echo "FAIL: tmux.conf missing '?' keybinding for tmux-help-viewer!"
    exit 1
fi
echo "PASS: tmux.conf contains 'Ctrl+a h' and 'Ctrl+a ?' bindings."

echo "=== [3/4] Verifying install.toml configuration ==="
if ! grep -q "name = \"tmux-help-viewer\"" "$INSTALL_TOML"; then
    echo "FAIL: install.toml missing tmux-help-viewer entry!"
    exit 1
fi
if ! grep -q "\"tmux-help-viewer\"" "$INSTALL_TOML"; then
    echo "FAIL: install.toml tmux dependencies missing tmux-help-viewer!"
    exit 1
fi
echo "PASS: install.toml properly configures tmux-help-viewer."

echo "=== [4/4] Verifying sidebar launcher TUI help key dispatch ==="
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$LAUNCHER" --source-only 2>/dev/null || true

# Test read_key mapping with piped stdin
printf 'h' | {
    read_key 0.1
    if [ "$key_result" != "help" ]; then
        echo "FAIL: 'h' key did not map to help! got: $key_result"
        exit 1
    fi
}

printf '?' | {
    read_key 0.1
    if [ "$key_result" != "help" ]; then
        echo "FAIL: '?' key did not map to help! got: $key_result"
        exit 1
    fi
}
echo "PASS: Sidebar TUI correctly maps 'h' and '?' to 'help'."

echo "=========================================================================="
echo "ALL TESTS PASS: tmux-help-viewer and keybinding integration 100% verified!"
echo "=========================================================================="
