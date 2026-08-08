# Single Sidebar M7 Phased Cutover & Production Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute full M7 Cutover of `scripts/tmux-session-launcher` into modular `scripts/lib/sidebar_*.sh` modules, shrink launcher LOC from 7,322 down to ~400 LOC, introduce a production bundler step to prevent sourcing latency, and fix TUI bugs (`Ctrl+a s` prefix & `o` history view).

**Architecture:** 
1. **Phased Cutover**: Cut over functions in 5 distinct layers (Domain -> Archive -> Port -> Presenter -> Switch/Coordinator) while passing contract tests at each phase.
2. **Production Bundling**: Create `scripts/build-dist.sh` to bundle `scripts/lib/sidebar_*.sh` into `dist/tmux-session-launcher` for zero I/O overhead.
3. **Bug Fixes**: Fix prefix key capture for `Ctrl+a s` and history view toggle (`o` key) in TUI.

**Tech Stack:** Bash 4+, Tmux CLI.

## Global Constraints

- Performance Hard-Gate: key-to-stable-frame <= 1000ms, key response <= 100ms.
- Contract Test Suite: `bash tests/tmux-single-sidebar/test-contract.sh` and unit tests must pass at every task.
- Zero Subshell Rule: Avoid `$(...)` in TUI hot-paths.

---

### Task 1: Fix Bug 1 (`Ctrl+a s` Prefix Binding & TUI key handler)

**Files:**
- Modify: `dotfiles/tmux.conf` or `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Verify keybinding definitions**
Ensure `bind-key -T prefix s` correctly triggers `--toggle-sidebar` and clears terminal buffer cleanly.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher dotfiles/tmux.conf
git commit -m "fix(sidebar): fix Ctrl+a s prefix binding trigger"
```

---

### Task 2: Fix Bug 2 (History View Mode `o` Key Toggle)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Modify: `scripts/lib/sidebar_presenter.sh`
- Test: `tests/tmux-single-sidebar/test-presenter-unit.sh`

- [ ] **Step 1: Fix `read_key` and `toggle_history_mode` linkage for `o` key**
Ensure `o` maps to `history` action and correctly triggers `view_mode="history"`.

- [ ] **Step 2: Run unit and contract tests**
Run: `bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/lib/sidebar_presenter.sh scripts/tmux-session-launcher
git commit -m "fix(sidebar): fix history view mode toggle on 'o' key"
```

---

### Task 3: Phased Cutover Phase 7a & 7b (Domain & Archive Inlines Removal)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-domain-unit.sh`
- Test: `tests/tmux-single-sidebar/test-archive-unit.sh`

- [ ] **Step 1: Remove inline domain & archive functions from launcher and delegate to `scripts/lib/sidebar_domain.sh` & `sidebar_archive.sh`**
Remove redundant duplicate function implementations for `epoch_now`, `layout_pane_count`, `format_duration`, `truncate_text`, `archive_session`, `archive_all_sessions`.

- [ ] **Step 2: Run unit and contract tests**
Run: `bash tests/tmux-single-sidebar/test-domain-unit.sh && bash tests/tmux-single-sidebar/test-archive-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): Cutover Phase 7a & 7b (Domain & Archive inlines removal)"
```

---

### Task 4: Phased Cutover Phase 7c & 7d (Port & Presenter Inlines Removal)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-port-tmux-unit.sh`
- Test: `tests/tmux-single-sidebar/test-presenter-unit.sh`

- [ ] **Step 1: Remove inline tmux port and presenter functions from launcher and delegate to `scripts/lib/sidebar_port_tmux.sh` & `sidebar_presenter.sh`**
Remove redundant duplicate function implementations for `sidebar_runtime_set/get`, `mark_session_managed`, `sidebar_window_pane`, `render_header`, `render_footer`, `format_row`.

- [ ] **Step 2: Run unit and contract tests**
Run: `bash tests/tmux-single-sidebar/test-port-tmux-unit.sh && bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): Cutover Phase 7c & 7d (Port & Presenter inlines removal)"
```

---

### Task 5: Phased Cutover Phase 7e (Switch, Coordinator & Composition Root Shrink)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-switch-unit.sh`
- Test: `tests/tmux-single-sidebar/test-coordinator-unit.sh`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Remove remaining switch/coordinator inlines and shrink `scripts/tmux-session-launcher` into a ~400 LOC Composition Root**

- [ ] **Step 2: Run full unit and contract test suite**
Run: `bash tests/tmux-single-sidebar/test-contract.sh && bash tests/tmux-single-sidebar/test-domain-unit.sh && bash tests/tmux-single-sidebar/test-port-tmux-unit.sh && bash tests/tmux-single-sidebar/test-switch-unit.sh && bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-coordinator-unit.sh && bash tests/tmux-single-sidebar/test-archive-unit.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): Cutover Phase 7e (Complete Composition Root shrink)"
```

---

### Task 6: Production Bundler Script & Build Target Setup

**Files:**
- Create: `scripts/build-dist.sh`
- Modify: `install.sh`
- Test: `bash scripts/build-dist.sh && bash tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Create zero-dependency bundler script `scripts/build-dist.sh`**
Inlines all `scripts/lib/sidebar_*.sh` modules into `dist/tmux-session-launcher` for zero-sourcing production execution.

- [ ] **Step 2: Test production bundle execution**
Run: `bash scripts/build-dist.sh && LAUNCHER="./dist/tmux-session-launcher" bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/build-dist.sh install.sh
git commit -m "feat(sidebar): add production bundler script and build integration"
```
