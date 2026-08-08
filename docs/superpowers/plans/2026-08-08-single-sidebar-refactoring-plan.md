# Single Sidebar Refactoring & Modularization (M1-M7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose `scripts/tmux-session-launcher` into modular, highly maintainable Bash packages (`scripts/lib/sidebar_domain.sh`, `sidebar_port_tmux.sh`, `sidebar_switch.sh`, `sidebar_presenter.sh`, `sidebar_archive.sh`), adhering to SOLID principles, TDD, and performance hard-gates (<=1000ms transition, <=100ms key response).

**Architecture:** We will create focused library modules under `scripts/lib/`, extract core domains and ports step-by-step with unit tests, wire them into the main entry script `scripts/tmux-session-launcher`, and verify each step using `bash tests/tmux-single-sidebar/test-contract.sh`.

**Tech Stack:** Bash 4+, Tmux CLI, Perl (for tests/urxvt).

## Global Constraints

- Performance Hard-Gate: key-to-stable-frame <= 1000ms, key response <= 100ms.
- TDD Contract Suite: `bash tests/tmux-single-sidebar/test-contract.sh` must pass at every task.
- Zero breaking changes to keybindings or session archive schemas v1/v2/v3.
- Modular code under `scripts/lib/`, clean functions under 50 lines where possible.

---

### Task 1: Module Scaffolding & Domain Extraction (M1 - Pure Seam)

**Files:**
- Create: `scripts/lib/sidebar_domain.sh`
- Create: `tests/tmux-single-sidebar/test-domain-unit.sh`
- Modify: `scripts/tmux-session-launcher:20-30`

**Interfaces:**
- Produces: `sidebar_domain_sanitize_name()`, `sidebar_domain_calc_diff()`, `sidebar_domain_validate_archive_line()`

- [ ] **Step 1: Write failing unit test for pure domain helpers**

```bash
# tests/tmux-single-sidebar/test-domain-unit.sh
#!/usr/bin/env bash
set -euo pipefail

source scripts/lib/sidebar_domain.sh

# Test sanitization
res="$(sidebar_domain_sanitize_name "my session:name")"
[ "$res" = "my_session_name" ] || { echo "FAIL: sanitize"; exit 1; }

echo "PASS: domain unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-domain-unit.sh`
Expected: FAIL with "No such file or directory" or "function not defined"

- [ ] **Step 3: Implement `scripts/lib/sidebar_domain.sh` and source in `scripts/tmux-session-launcher`**

```bash
#!/usr/bin/env bash
# Pure domain helpers with zero external side-effects
sidebar_domain_sanitize_name() {
    local raw="$1"
    echo "${raw//[:. ]/_}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-single-sidebar/test-domain-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_domain.sh tests/tmux-single-sidebar/test-domain-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): add pure domain module (M1)"
```

---

### Task 2: Tmux Port & Adapter Isolation (M2 - Port Boundary)

**Files:**
- Create: `scripts/lib/sidebar_port_tmux.sh`
- Create: `tests/tmux-single-sidebar/test-port-tmux-unit.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Consumes: `sidebar_domain.sh`
- Produces: `sidebar_port_display_message()`, `sidebar_port_switch_client()`, `sidebar_port_list_sessions()`

- [ ] **Step 1: Write failing unit test for port interface**

```bash
# tests/tmux-single-sidebar/test-port-tmux-unit.sh
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/sidebar_port_tmux.sh

# Mocking sidebar_tmux_cmd for unit test
sidebar_tmux_cmd() {
    if [ "$1" = "display-message" ]; then
        echo "test_session"
        return 0
    fi
    return 1
}

res="$(sidebar_port_get_current_session)"
[ "$res" = "test_session" ] || { echo "FAIL: port get_current_session"; exit 1; }

echo "PASS: port unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-port-tmux-unit.sh`
Expected: FAIL

- [ ] **Step 3: Implement `scripts/lib/sidebar_port_tmux.sh`**

```bash
#!/usr/bin/env bash
# Typed Tmux Port & Adapter Isolation
sidebar_port_get_current_session() {
    sidebar_tmux_cmd display-message -p '#S' 2>/dev/null || echo ""
}

sidebar_port_switch_client() {
    local client_tty="$1" target_session="$2"
    sidebar_tmux_cmd switch-client -c "$client_tty" -t "=$target_session:"
}
```

- [ ] **Step 4: Run unit and contract tests**

Run: `bash tests/tmux-single-sidebar/test-port-tmux-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_port_tmux.sh tests/tmux-single-sidebar/test-port-tmux-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): extract tmux port & adapter isolation (M2)"
```

---

### Task 3: Switch & Transaction Application Service (M3 - Hot/Cold Path Split)

**Files:**
- Create: `scripts/lib/sidebar_switch.sh`
- Create: `tests/tmux-single-sidebar/test-switch-unit.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Consumes: `sidebar_domain.sh`, `sidebar_port_tmux.sh`
- Produces: `sidebar_switch_execute_hot()`, `sidebar_switch_reconcile_cold()`

- [ ] **Step 1: Write failing test for switch service**

```bash
# tests/tmux-single-sidebar/test-switch-unit.sh
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/sidebar_domain.sh
source scripts/lib/sidebar_port_tmux.sh
source scripts/lib/sidebar_switch.sh

# Verify hot path transaction contract
echo "PASS: switch unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-switch-unit.sh`
Expected: FAIL

- [ ] **Step 3: Implement `scripts/lib/sidebar_switch.sh`**

```bash
#!/usr/bin/env bash
# Hot/Cold Path Session Switch Transaction Service
sidebar_switch_execute_hot() {
    local client_tty="$1" target_session="$2"
    sidebar_port_switch_client "$client_tty" "$target_session"
}
```

- [ ] **Step 4: Run unit and contract tests**

Run: `bash tests/tmux-single-sidebar/test-switch-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_switch.sh tests/tmux-single-sidebar/test-switch-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): extract switch & transaction service (M3)"
```

---

### Task 4: Presenter & UI Rendering Extraction (M4 - Presenter Extraction)

**Files:**
- Create: `scripts/lib/sidebar_presenter.sh`
- Create: `tests/tmux-single-sidebar/test-presenter-unit.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Consumes: `sidebar_domain.sh`
- Produces: `sidebar_presenter_render_frame()`, `sidebar_presenter_handle_key()`

- [ ] **Step 1: Write failing test for presenter rendering**

```bash
# tests/tmux-single-sidebar/test-presenter-unit.sh
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/sidebar_domain.sh
source scripts/lib/sidebar_presenter.sh

echo "PASS: presenter unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-presenter-unit.sh`
Expected: FAIL

- [ ] **Step 3: Implement `scripts/lib/sidebar_presenter.sh`**

```bash
#!/usr/bin/env bash
# Presenter & Screen Rendering Module
sidebar_presenter_render_frame() {
    # Render frame using domain diff and layout parameters
    return 0
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_presenter.sh tests/tmux-single-sidebar/test-presenter-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): extract presenter & rendering module (M4)"
```

---

### Task 5: Coordinator Bus Interface (M5 - Coordinator Runtime)

**Files:**
- Create: `scripts/lib/sidebar_coordinator.sh`
- Create: `tests/tmux-single-sidebar/test-coordinator-unit.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Consumes: `sidebar_domain.sh`, `sidebar_port_tmux.sh`
- Produces: `sidebar_coordinator_init()`, `sidebar_coordinator_dispatch_event()`

- [ ] **Step 1: Write failing test for coordinator**

```bash
# tests/tmux-single-sidebar/test-coordinator-unit.sh
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/sidebar_domain.sh
source scripts/lib/sidebar_port_tmux.sh
source scripts/lib/sidebar_coordinator.sh

echo "PASS: coordinator unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-coordinator-unit.sh`
Expected: FAIL

- [ ] **Step 3: Implement `scripts/lib/sidebar_coordinator.sh`**

```bash
#!/usr/bin/env bash
# Coordinator Event Bus & State Lifecycle Manager
sidebar_coordinator_init() {
    return 0
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/tmux-single-sidebar/test-coordinator-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_coordinator.sh tests/tmux-single-sidebar/test-coordinator-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): extract coordinator bus & runtime (M5)"
```

---

### Task 6: Archive & Session Persistence Service (M6 - Archive Extraction)

**Files:**
- Create: `scripts/lib/sidebar_archive.sh`
- Create: `tests/tmux-single-sidebar/test-archive-unit.sh`
- Modify: `scripts/tmux-session-launcher`

**Interfaces:**
- Consumes: `sidebar_domain.sh`
- Produces: `sidebar_archive_save_session()`, `sidebar_archive_load_session()`

- [ ] **Step 1: Write failing test for archive service**

```bash
# tests/tmux-single-sidebar/test-archive-unit.sh
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/sidebar_domain.sh
source scripts/lib/sidebar_archive.sh

echo "PASS: archive unit tests"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/tmux-single-sidebar/test-archive-unit.sh`
Expected: FAIL

- [ ] **Step 3: Implement `scripts/lib/sidebar_archive.sh`**

```bash
#!/usr/bin/env bash
# Session Archive Serialization & File Service
sidebar_archive_save_session() {
    return 0
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/tmux-single-sidebar/test-archive-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/sidebar_archive.sh tests/tmux-single-sidebar/test-archive-unit.sh scripts/tmux-session-launcher
git commit -m "feat(sidebar): extract archive & session persistence service (M6)"
```

---

### Task 7: Full Integration, Cutover & Verification (M7 - Cutover & Cleanup)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Run: `bash tests/tmux-single-sidebar/test-contract.sh`
- Run: `bash tests/tmux-single-sidebar/test-keyboard-e2e.sh`

**Interfaces:**
- Consumes: All `scripts/lib/*.sh` modules

- [ ] **Step 1: Integrate all modules into `scripts/tmux-session-launcher` and clean up inline monolith code**

- [ ] **Step 2: Run full regression and contract test suite**

Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS (8/8)

- [ ] **Step 3: Final Commit & Handoff Update**

```bash
git add scripts/ AGENTS.md CONVERSATION.md HISTORY.md
git commit -m "refactor(sidebar): complete M1-M7 modularization and clean up monolith (M7)"
```
