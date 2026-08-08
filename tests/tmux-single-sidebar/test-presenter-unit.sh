#!/usr/bin/env bash
# Unit test for presenter module in scripts/lib/sidebar_presenter.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_presenter.sh"

key_action="$(sidebar_presenter_map_key "q")"
[ "$key_action" = "QUIT" ] || { echo "FAIL: map_key expected 'QUIT', got '$key_action'"; exit 1; }

echo "PASS: presenter unit tests"
