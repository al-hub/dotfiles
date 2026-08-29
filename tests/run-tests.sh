#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh - dotfiles orchestrator validation
# Verifies the installer itself. Component behaviour (tmux, dock) is tested by
# the component owner (tmux-session-dock: `setup.sh test`).
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

pass() { echo "[PASS]"; }
fail() { echo "[FAIL] $*"; exit 1; }

echo "======================================================"
echo "   dotfiles orchestrator verification"
echo "======================================================"

# 1. Shell syntax
echo -n "▶ bash -n setup.sh ... ";            bash -n setup.sh && pass
echo -n "▶ sh -n get_dotfiles.sh ... ";       sh -n get_dotfiles.sh && pass
echo -n "▶ sh -n install_dotfiles.sh ... ";   sh -n install_dotfiles.sh && pass

# 2. Perl extension
echo -n "▶ perl -c urxvt resize-font ... "
perl -c dotfiles/urxvt/ext/resize-font >/dev/null 2>&1 && pass

# 3. install.toml contract
echo -n "▶ install.toml parses ... "
ITEMS="$(./setup.sh dump-config)"
[ -n "$ITEMS" ] || fail "no items parsed"
pass

echo -n "▶ every file module has source+target ... "
while IFS='|' read -r name enabled hidden mtype source target repo dir min_version post_install commands packages depends description; do
    [ "$mtype" = "file" ] || continue
    [ -n "$source" ] && [ -n "$target" ] || fail "$name missing source/target"
    [ -f "$source" ] || fail "$name source not in repo: $source"
done <<< "$ITEMS"
pass

echo -n "▶ every upstream module has repo+dir+min_version ... "
while IFS='|' read -r name enabled hidden mtype source target repo dir min_version post_install commands packages depends description; do
    [ "$mtype" = "upstream" ] || continue
    [ -n "$repo" ] && [ -n "$dir" ] && [ -n "$min_version" ] || fail "$name missing repo/dir/min_version"
done <<< "$ITEMS"
pass

echo -n "▶ dependencies resolve ... "
names="$(printf '%s\n' "$ITEMS" | cut -d'|' -f1)"
while IFS='|' read -r name enabled hidden mtype source target repo dir min_version post_install commands packages depends description; do
    for dep in $depends; do
        printf '%s\n' "$names" | grep -qx "$dep" || fail "$name depends on undefined '$dep'"
    done
done <<< "$ITEMS"
pass

echo -n "▶ no tmux configuration owned by dotfiles ... "
! printf '%s\n' "$ITEMS" | cut -d'|' -f6 | grep -q 'tmux.conf' || fail "install.toml still targets ~/.tmux.conf"
[ ! -e dotfiles/tmux.conf ] || fail "dotfiles/tmux.conf still exists"
pass

# 4. Read-only CLI commands
echo -n "▶ ./setup.sh status ... "; ./setup.sh status >/dev/null && pass
echo -n "▶ ./setup.sh doctor ... "; ./setup.sh doctor >/dev/null && pass
echo -n "▶ ./setup.sh --help ... "; ./setup.sh --help >/dev/null && pass

echo "======================================================"
echo "   All orchestrator checks PASSED"
echo "======================================================"
