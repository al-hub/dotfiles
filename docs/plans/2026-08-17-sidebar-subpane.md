# Sidebar Sub-Pane (Satellite Terminal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an on-demand, toggleable sub-pane (satellite interactive terminal) attached directly beneath the session sidebar launcher, sharing the sidebar column and lifecycle.

**Architecture:** Window-local thin presenter model with global state persistence (`@dotfiles_sidebar_subpane_enabled`). When enabled, the sidebar column is vertically split into the top session launcher TUI and the bottom sub-pane running `$SHELL`. The sub-pane is tagged as infrastructure (`dotfiles-sidebar-subpane`), keeping it strictly isolated from work panes and session archives.

**Tech Stack:** Bash, tmux 3.x, Linux PTY/IPC.

## Global Constraints

- Sidebar column width is uniform (default 30 cols) across launcher and sub-pane.
- Sub-pane title is `dotfiles-sidebar-subpane`, tagged with `@dotfiles_sidebar_subpane 1`.
- Work area layout operations (`Ctrl+a |`, `_`, layout save/restore, v3 TSV archive) must strictly ignore the sub-pane.
- Global sidebar toggle off (`Ctrl+a s`) cleans up both launcher and sub-pane across all managed windows.
- Sub-pane toggle (`m`) must preserve keyboard focus inside the session launcher TUI.

---

### Task 1: Pure Sub-Pane Domain & Option Helpers

**Files:**
- Create: `tests/tmux-single-sidebar/test-subpane-unit.sh`
- Modify: `scripts/lib/sidebar_domain.sh`
- Modify: `scripts/lib/sidebar_port_tmux.sh`

**Interfaces:**
- Produces:
  - `sidebar_subpane_title()` -> `dotfiles-sidebar-subpane`
  - `is_sidebar_subpane(title)` -> return 0 if title == `dotfiles-sidebar-subpane`
  - `sidebar_subpane_option_name()` -> `@dotfiles_sidebar_subpane_enabled`
  - `sidebar_subpane_default_height(total_height)` -> returns ~30% of total height (min 8, max 20, default 12)

- [ ] **Step 1: Write the failing unit test**

```bash
# tests/tmux-single-sidebar/test-subpane-unit.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"

[ "$(sidebar_subpane_title)" = "dotfiles-sidebar-subpane" ] || { echo "FAIL title"; exit 1; }
is_sidebar_subpane "dotfiles-sidebar-subpane" || { echo "FAIL is_sidebar_subpane"; exit 1; }
! is_sidebar_subpane "dotfiles-session-sidebar" || { echo "FAIL not main sidebar"; exit 1; }
! is_sidebar_subpane "zsh" || { echo "FAIL not work pane"; exit 1; }

[ "$(sidebar_subpane_default_height 60)" = "18" ] || { echo "FAIL height 60"; exit 1; }
[ "$(sidebar_subpane_default_height 20)" = "8" ] || { echo "FAIL height 20 min"; exit 1; }

echo "PASS: subpane unit tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-subpane-unit.sh`
Expected: FAIL with "sidebar_subpane_title: command not found"

- [ ] **Step 3: Write minimal implementation in `scripts/lib/sidebar_domain.sh`**

```bash
SIDEBAR_SUBPANE_TITLE="dotfiles-sidebar-subpane"
SIDEBAR_SUBPANE_OPTION="@dotfiles_sidebar_subpane_enabled"

sidebar_subpane_title() {
    printf '%s\n' "$SIDEBAR_SUBPANE_TITLE"
}

is_sidebar_subpane() {
    [ "${1:-}" = "$SIDEBAR_SUBPANE_TITLE" ]
}

sidebar_subpane_default_height() {
    local total_h="${1:-40}"
    local calc_h=$(( total_h * 30 / 100 ))
    if [ "$calc_h" -lt 8 ]; then
        calc_h=8
    elif [ "$calc_h" -gt 25 ]; then
        calc_h=25
    fi
    printf '%s\n' "$calc_h"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-subpane-unit.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_domain.sh tests/tmux-single-sidebar/test-subpane-unit.sh
git commit -m "feat(subpane): add pure domain helpers and unit tests for subpane metadata"
```

---

### Task 2: Sub-Pane Provisioning & Lifecycle in Tmux Port Adapter

**Files:**
- Create: `tests/tmux-single-sidebar/test-subpane-contract.sh`
- Modify: `scripts/lib/sidebar_port_tmux.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Produces:
  - `sidebar_window_subpane(window_id)` -> returns subpane pane_id or empty
  - `provision_sidebar_subpane(window_id, launcher_pane, height, command)` -> creates subpane, sets title and option, returns subpane ID
  - `destroy_sidebar_subpane(window_id)` -> kills subpane if present
  - `toggle_sidebar_subpane_global()` -> flips global enabled option and reconciles managed windows

- [ ] **Step 1: Write the failing contract test**

```bash
# tests/tmux-single-sidebar/test-subpane-contract.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCKET="test-subpane-contract-$$"

tmux -L "$SOCKET" new-session -d -s main -n work 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t main '#{window_id}')"

# Test toggle and provisioning via scripts/tmux-session-launcher
export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true

# Provision sidebar
launcher_pane="$(provision_sidebar_window "$win_id" 30)"
[ -n "$launcher_pane" ] || { echo "FAIL: launcher pane not created"; tmux -L "$SOCKET" kill-server; exit 1; }

# Provision subpane below launcher
sub_pane="$(provision_sidebar_subpane "$win_id" "$launcher_pane" 10 "sleep 60")"
[ -n "$sub_pane" ] || { echo "FAIL: subpane not created"; tmux -L "$SOCKET" kill-server; exit 1; }

# Verify subpane properties
sub_title="$(tmux -L "$SOCKET" display-message -p -t "$sub_pane" '#{pane_title}')"
[ "$sub_title" = "dotfiles-sidebar-subpane" ] || { echo "FAIL: subpane title '$sub_title'"; tmux -L "$SOCKET" kill-server; exit 1; }

# Verify destroying subpane
destroy_sidebar_subpane "$win_id"
found_sub="$(sidebar_window_subpane "$win_id")"
[ -z "$found_sub" ] || { echo "FAIL: subpane still exists"; tmux -L "$SOCKET" kill-server; exit 1; }

tmux -L "$SOCKET" kill-server
echo "PASS: subpane contract test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-subpane-contract.sh`
Expected: FAIL

- [ ] **Step 3: Implement subpane provisioning and lifecycle functions**

Implement `sidebar_window_subpane`, `provision_sidebar_subpane`, `destroy_sidebar_subpane`, and `toggle_sidebar_subpane_global` in `scripts/lib/sidebar_port_tmux.sh` and wire them into `scripts/tmux-session-launcher`.

- [ ] **Step 4: Run contract test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-subpane-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_port_tmux.sh scripts/tmux-session-launcher tests/tmux-single-sidebar/test-subpane-contract.sh
git commit -m "feat(subpane): implement subpane lifecycle, provisioning and contract tests"
```

---

### Task 3: Sidebar TUI Integration & Keyboard Navigation (`m` key)

**Files:**
- Create: `tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh`
- Modify: `scripts/tmux-session-launcher`
- Modify: `dist/tmux-session-launcher`

**Interfaces:**
- Consumes:
  - `toggle_sidebar_subpane_global`
  - `sidebar_subpane_title`
- Produces:
  - `m` key dispatch in `run_tui`
  - Subpane status indicator in footer (`m: subpane`)
  - Subpane exclusion in `archive_session` and work-pane split wrappers

- [ ] **Step 1: Write the failing E2E test**

```bash
# tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh
#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=subpane \
    bash "$TEST_DIR/test-keyboard-e2e.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh`
Expected: FAIL

- [ ] **Step 3: Implement TUI keybinding `m`, footer guide, and work-pane safety exclusion**

In `scripts/tmux-session-launcher`:
1. Add `m)` case to `run_tui`: calls `tui_toggle_subpane`.
2. In `render_footer`: append `m: subpane`.
3. In `archive_session` and `find_work_panes`: filter out panes with title `dotfiles-sidebar-subpane`.
4. In `scripts/build-dist.sh`: rebuild `dist/tmux-session-launcher`.

- [ ] **Step 4: Run E2E test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/tmux-session-launcher dist/tmux-session-launcher tests/tmux-single-sidebar/test-keyboard-e2e.sh tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh
git commit -m "feat(subpane): wire 'm' toggle keybinding in TUI with footer indicator and E2E test"
```

---

### Task 4: Full Suite Gate A~D Regression Verification & Handoff

**Files:**
- Modify: `HISTORY.md`
- Modify: `CONVERSATION.md`

- [ ] **Step 1: Run all unit and integration tests**

```bash
bash tests/tmux-single-sidebar/test-subpane-unit.sh
bash tests/tmux-single-sidebar/test-subpane-contract.sh
bash tests/tmux-single-sidebar/test-contract.sh
bash tests/tmux-single-sidebar/test-delete-zero-stale-row.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-direct-layout.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-history-select-all.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh
bash tests/tmux-single-sidebar/test-multi-client-operation-conflict.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-multi-window-topology.sh
```

- [ ] **Step 2: Deploy to local environment and verify live tmux**

```bash
cp -f dist/tmux-session-launcher /home/al-hub/.local/bin/tmux-session-launcher
```

- [ ] **Step 3: Update docs and commit**

```bash
git add HISTORY.md CONVERSATION.md
git commit -m "docs: document sidebar subpane feature and test results"
git push origin feature/single-sidebar
```
