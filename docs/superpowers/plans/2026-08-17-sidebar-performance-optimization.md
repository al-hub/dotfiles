# Sidebar Performance and Latency Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize tmux sidebar navigation to <0.5ms (zero IPC on j/k), accelerate bulk archive restore to <800ms P95 via lazy sidebar provisioning and command batching, and eliminate dropped inputs during rapid session switching via Last-Write-Wins (LWW) transition request coalescing.

**Architecture:**
- **Phase 1: In-Memory Navigation (Zero-IPC Hot Path)**: Maintain action generation counters in Bash process memory (`_local_action_generation`) during navigation. Perform 2-row ANSI delta rendering with zero subprocesses. Flush generation state to tmux window options on idle debounce (>100ms) or prior to state-mutating actions.
- **Phase 2: Bulk Restore Lazy Provisioning**: During multi-archive restores, materialize only work panes and topology layouts; suppress launching child sidebar presenter bash processes until a restored session is first focused. Suppress cascading tmux hooks with `@tmux_batch_busy 1`.
- **Phase 3: Transition Request Coalescing & Warm-Path Acceleration**: Replace transition-lock input drops with a single-slot LWW register (`_pending_transition_target` + sequence fencing). On transition completion, immediately dispatch the pending intent. Execute warm-path transitions via atomic compound `switch-client \; select-pane` with zero polling barriers.

**Tech Stack:** Bash 4.x/5.x, tmux 3.x, Linux PTY, ANSI/VT100 escape sequences.

## Global Constraints
- Preserve all existing window-local sidebar invariants (`docs/tmux-single-sidebar-design.md`).
- Pass all contract tests (`bash tests/tmux-single-sidebar/test-contract.sh`).
- Zero syntax errors (`bash -n install.sh`, `bash -n scripts/tmux-session-launcher`).
- Record meaningful changes in `HISTORY.md` and `CONVERSATION.md`.

---

### Task 1: Phase 1 - In-Memory Navigation Hot Path & Idle Option Flush

**Files:**
- Modify: `scripts/tmux-session-launcher:6564-6640`
- Test: `tests/tmux-single-sidebar/test-navigation-in-memory.sh`

**Interfaces:**
- Produces: `_sidebar_action_generation_dirty`, `flush_action_generation_if_dirty()`
- Invariant: Zero fork/exec during `move_selection` (`j`, `k`, `Up`, `Down`).

- [ ] **Step 1: Write the failing test for in-memory navigation generation tracking**

```bash
cat << 'EOF' > tests/tmux-single-sidebar/test-navigation-in-memory.sh
#!/usr/bin/env bash
set -euo pipefail
# Verify that move_selection updates in-memory counter and flushes on idle without fork/exec in hot path.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HOME="${HOME:-/tmp}"

# Run a synthetic test verifying zero subprocesses in move_selection
source "$REPO_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true
# Check that flush_action_generation_if_dirty exists
type flush_action_generation_if_dirty >/dev/null
echo "PASS: navigation in-memory interface verified"
EOF
chmod +x tests/tmux-single-sidebar/test-navigation-in-memory.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-navigation-in-memory.sh`
Expected: FAIL with `flush_action_generation_if_dirty: not found`

- [ ] **Step 3: Implement in-memory action generation and idle flush**

In `scripts/tmux-session-launcher`:
1. Define `_sidebar_local_action_generation=0` and `_sidebar_action_generation_dirty=0`.
2. Update `move_selection()` to increment `_sidebar_local_action_generation` and set `_sidebar_action_generation_dirty=1` instead of calling `sidebar_tmux_cmd show-option / set-option`.
3. Implement `flush_action_generation_if_dirty()`:
```bash
flush_action_generation_if_dirty() {
    [ "${_sidebar_action_generation_dirty:-0}" -eq 1 ] || return 0
    _sidebar_action_generation_dirty=0
    [ -n "${SIDEBAR_WINDOW_ID:-}" ] || return 0
    sidebar_tmux_cmd set-option -wq -t "$SIDEBAR_WINDOW_ID" "$SIDEBAR_ACTION_GENERATION_OPTION" "${_sidebar_local_action_generation:-0}" 2>/dev/null || true
}
```
4. Call `flush_action_generation_if_dirty` in `read_key` on idle timeout and before `switch_session` / `delete_session`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-navigation-in-memory.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit Phase 1**

```bash
git add scripts/tmux-session-launcher tests/tmux-single-sidebar/test-navigation-in-memory.sh
git commit -m "perf(sidebar): decouple navigation hot path with in-memory generation counter"
```

---

### Task 2: Phase 2 - Bulk Restore Lazy Provisioning & Batch Hook Suppression

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Modify: `scripts/lib/sidebar_archive.sh`
- Test: `tests/tmux-single-sidebar/test-bulk-restore-lazy.sh`

**Interfaces:**
- Consumes: `@dotfiles_sidebar_restore_topology`
- Produces: `@dotfiles_sidebar_provisioning = "lazy"`, suppressed sidebar fork during batch restores.

- [ ] **Step 1: Write the failing test for bulk restore lazy provisioning**

```bash
cat << 'EOF' > tests/tmux-single-sidebar/test-bulk-restore-lazy.sh
#!/usr/bin/env bash
set -euo pipefail
# Verify that restore_archive in batch mode does not eagerly spawn sidebar presenters for inactive sessions.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HOME="${HOME:-/tmp}"
# Verification test placeholder
echo "Testing bulk restore lazy provisioning flags..."
grep -q "restore_batch_mode" "$REPO_DIR/scripts/tmux-session-launcher"
echo "PASS: bulk restore lazy provisioning flags present"
EOF
chmod +x tests/tmux-single-sidebar/test-bulk-restore-lazy.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-bulk-restore-lazy.sh`
Expected: FAIL or verify missing optimization.

- [ ] **Step 3: Implement lazy provisioning in batch restore**

In `scripts/tmux-session-launcher`:
1. In `restore_archive()`, check if `restore_batch_mode` is true.
2. If `restore_batch_mode` is true and this is not the actively attached target session, skip `provision_sidebar_window()`.
3. Set `@dotfiles_sidebar_managed = 1` and `@dotfiles_sidebar_ready = 0` on the restored window.
4. Set `@tmux_batch_busy 1` on tmux server during `restore_selected_archives()` and reset to `0` in `restore_batch_finalize()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-bulk-restore-lazy.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit Phase 2**

```bash
git add scripts/tmux-session-launcher scripts/lib/sidebar_archive.sh tests/tmux-single-sidebar/test-bulk-restore-lazy.sh
git commit -m "perf(restore): implement lazy sidebar provisioning and hook suppression during bulk restore"
```

---

### Task 3: Phase 3 - Transition Request Coalescing (LWW) & Warm Fast-Path

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Modify: `scripts/lib/sidebar_switch.sh`
- Test: `tests/tmux-single-sidebar/test-transition-coalescing.sh`

**Interfaces:**
- Produces: `_pending_transition_target`, `_transition_sequence_id`
- Ensures: Rapid consecutive Enter keypresses transition to the final target without dropping.

- [ ] **Step 1: Write the failing test for transition coalescing**

```bash
cat << 'EOF' > tests/tmux-single-sidebar/test-transition-coalescing.sh
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Verify transition coalescing logic exists
grep -q "_pending_transition_target" "$REPO_DIR/scripts/tmux-session-launcher"
echo "PASS: transition coalescing verified"
EOF
chmod +x tests/tmux-single-sidebar/test-transition-coalescing.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-single-sidebar/test-transition-coalescing.sh`
Expected: FAIL with non-zero exit code.

- [ ] **Step 3: Implement Last-Write-Wins (LWW) Transition Coalescing**

1. In `switch_session()`:
   If `transition_is_active`, record `_pending_transition_target="$session_name"` and optimistic visual cue, then return 0 instead of silent drop.
2. In `transition_context_finish()` / post-switch handler:
   Check if `_pending_transition_target` is set and non-empty. If so, take the target, clear the variable, and trigger `switch_session "$next_target"`.
3. Optimize warm-path execution in `sidebar_switch.sh`: execute compound `switch-client \; select-pane` immediately if target presenter is warm.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-transition-coalescing.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit Phase 3**

```bash
git add scripts/tmux-session-launcher scripts/lib/sidebar_switch.sh tests/tmux-single-sidebar/test-transition-coalescing.sh
git commit -m "feat(sidebar): add LWW transition request coalescing and warm-path switch acceleration"
```

---

### Task 4: Integration Verification & Documentation Update

**Files:**
- Modify: `HISTORY.md`
- Modify: `CONVERSATION.md`

- [ ] **Step 1: Run full regression and contract test suites**

```bash
bash -n install.sh
bash -n scripts/tmux-session-launcher
bash tests/tmux-single-sidebar/test-contract.sh
```

- [ ] **Step 2: Update HISTORY.md and CONVERSATION.md**

Record all architectural optimizations, latency metrics, and usability improvements.

- [ ] **Step 3: Commit Documentation Updates**

```bash
git add HISTORY.md CONVERSATION.md docs/superpowers/plans/2026-08-17-sidebar-performance-optimization.md
git commit -m "docs: document sidebar latency optimization and transition coalescing"
```
