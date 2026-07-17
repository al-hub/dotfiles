#!/usr/bin/env bash
# Compatibility entry point. Baselines must not mutate a user's live tmux server.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

cat >&2 <<'EOF'
profile-active-sidebar.sh now runs the controlled attached-client profile.
The old implementation modified and eventually killed the user's live tmux server,
so its results were neither safe nor reproducible.
EOF

exec "$SCRIPT_DIR/profile-isolated-sidebar.sh" "$@"
