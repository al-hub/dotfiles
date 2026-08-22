# Single Sidebar Practical Cleanup (Option A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up ~350 LOC of pure dead code and duplicated blocks in `scripts/tmux-session-launcher` while verifying 100% PASSing TDD contract test suites.

**Architecture:** Remove verified uncalled legacy functions, consolidate duplicate session deletion logic into a single helper, and rebuild the production binary via `scripts/build-dist.sh`.

**Tech Stack:** Bash 4+, Tmux CLI.

## Global Constraints

- Contract Test Suite: `bash tests/tmux-single-sidebar/test-contract.sh` must pass at every task.
- Zero behavior changes to CLI subcommands, TUI keys, or production bundling.

---

### Task 1: Dead Code Removal (Batch 1 - TUI & Formatting Helpers)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Remove uncalled formatting & TUI helpers**
Remove `row_screen_line`, `row_mark`, `history_title_from_file`, `row_name_width`, `render_session_name_cell`.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): remove unused formatting & TUI dead functions"
```

---

### Task 2: Dead Code Removal (Batch 2 - Archive & Sync Helpers)

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Remove uncalled archive & refresh helpers**
Remove `prepare_window_for_archive`, `wait_for_sidebar_refresh`, `wait_for_sidebar_selection_sync`, `archivable_window_count`, `clear_restored_work_panes`, `wait_for_sidebar_transition`, `wait_for_batch_sidebar_content`.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): remove unused archive & refresh dead functions"
```

---

### Task 3: Deduplicate Delete Session Logic

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Consolidate duplicated 30-line delete confirmation logic in `tui_delete_session()`**
Create helper function `execute_tui_session_delete_action(is_all)` and delegate both `Yy` and `Enter` prompt cases.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): consolidate duplicated tui_delete_session boilerplate"
```

---

### Task 4: Rebuild Production Bundle & Full Regression Gate

**Files:**
- Modify: `dist/tmux-session-launcher`
- Test: `bash scripts/build-dist.sh && bash tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Rebuild production bundle**
Run: `bash scripts/build-dist.sh`

- [ ] **Step 2: Run full regression and unit test suite**
Run: `bash tests/tmux-single-sidebar/test-contract.sh && bash tests/tmux-single-sidebar/test-domain-unit.sh && bash tests/tmux-single-sidebar/test-port-tmux-unit.sh && bash tests/tmux-single-sidebar/test-switch-unit.sh && bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-coordinator-unit.sh && bash tests/tmux-single-sidebar/test-archive-unit.sh`
Expected: PASS (All 7 suites)

- [ ] **Step 3: Commit**
```bash
git add dist/tmux-session-launcher
git commit -m "build(sidebar): update production bundle after practical debt cleanup"
```
