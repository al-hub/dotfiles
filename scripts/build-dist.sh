#!/usr/bin/env bash
# Bundles all scripts/lib/sidebar_*.sh modules and scripts/tmux-session-launcher into dist/tmux-session-launcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
OUTPUT_BIN="$DIST_DIR/tmux-session-launcher"

mkdir -p "$DIST_DIR"

cat <<'EOF' > "$OUTPUT_BIN"
#!/usr/bin/env bash
# Auto-generated bundled production binary for tmux-session-launcher
# Zero Sourcing I/O Overhead
set -euo pipefail
EOF

# Append lib modules in dependency order
LIBS=(
    "sidebar_domain.sh"
    "sidebar_domain_animation.sh"
    "sidebar_domain_activity.sh"
    "sidebar_port_tmux.sh"
    "sidebar_subpane_hub.sh"
    "sidebar_topology.sh"
    "sidebar_switch.sh"
    "sidebar_presenter.sh"
    "sidebar_coordinator.sh"
    "sidebar_archive.sh"
)

for lib_name in "${LIBS[@]}"; do
    lib="$REPO_ROOT/scripts/lib/$lib_name"
    [ -r "$lib" ] || continue
    echo "# --- BEGIN $lib_name ---" >> "$OUTPUT_BIN"
    grep -v '^#!/usr/bin/env bash' "$lib" | grep -v '^set -euo pipefail' >> "$OUTPUT_BIN"
    echo "# --- END $lib_name ---" >> "$OUTPUT_BIN"
done

# Append main launcher body (excluding individual lib sourcing lines)
grep -v 'LAUNCHER_DIR/lib/sidebar_' "$REPO_ROOT/scripts/tmux-session-launcher" | grep -v '^#!/usr/bin/env bash' | grep -v '^set -euo pipefail' >> "$OUTPUT_BIN" || true

chmod +x "$OUTPUT_BIN"
cp "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$DIST_DIR/" 2>/dev/null || true
cp "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" ~/.local/bin/ 2>/dev/null || true
echo "Production bundle created successfully: $OUTPUT_BIN"
