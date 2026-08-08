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

# Append lib modules
for lib in "$REPO_ROOT"/scripts/lib/sidebar_*.sh; do
    [ -r "$lib" ] || continue
    echo "# --- BEGIN ${lib##*/} ---" >> "$OUTPUT_BIN"
    grep -v '^#!/usr/bin/env bash' "$lib" | grep -v '^set -euo pipefail' >> "$OUTPUT_BIN"
    echo "# --- END ${lib##*/} ---" >> "$OUTPUT_BIN"
done

# Append main launcher body (excluding individual lib sourcing)
grep -v '^source ' "$REPO_ROOT/scripts/tmux-session-launcher" | grep -v 'sidebar_.*_path' >> "$OUTPUT_BIN" || true

chmod +x "$OUTPUT_BIN"
echo "Production bundle created successfully: $OUTPUT_BIN"
