#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh - Dotfiles Orchestrator Validation Suite
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "======================================================"
echo "   Running Dotfiles Orchestrator Verification"
echo "======================================================"

# 1. Shell Script Syntax Checks
echo -n "▶ Verifying setup.sh syntax ... "
bash -n setup.sh
echo "[PASS]"

echo -n "▶ Verifying get_dotfiles.sh syntax ... "
sh -n get_dotfiles.sh
echo "[PASS]"

echo -n "▶ Verifying install_dotfiles.sh syntax ... "
sh -n install_dotfiles.sh
echo "[PASS]"

# 2. Perl extension checks
echo -n "▶ Verifying urxvt resize-font extension ... "
perl -c dotfiles/urxvt/ext/resize-font >/dev/null 2>&1
echo "[PASS]"

# 3. Setup diagnostics check
echo -n "▶ Verifying ./setup.sh doctor ... "
./setup.sh doctor >/dev/null
echo "[PASS]"

echo -n "▶ Verifying ./setup.sh status ... "
./setup.sh status >/dev/null
echo "[PASS]"

# 4. Tmux configuration load check
echo -n "▶ Verifying dotfiles/tmux.conf in isolated session ... "
TEST_SOCK="test-dotfiles-$$"
tmux -L "$TEST_SOCK" -f dotfiles/tmux.conf new-session -d -s verify 'sleep 2'
tmux -L "$TEST_SOCK" kill-server >/dev/null 2>&1 || true
echo "[PASS]"

echo "======================================================"
echo "   All dotfiles orchestrator checks PASSED!"
echo "======================================================"
