# Single Sidebar Architecture Integrity & Trap Guard Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove legacy single-pane fallback code, fix signal trap restoration leaks in prompts, unify 3-tier client lookups, and verify 100% PASSing TDD test suites.

**Architecture:** Remove obsolete `find_global_sidebar_pane`/`ensure_global_sidebar_window` functions, wrap prompt trap cleanup in try/finally semantics, rebuild `dist/tmux-session-launcher`.

**Tech Stack:** Bash 4+, Tmux CLI.

## Global Constraints

- Contract Test Suite: `bash tests/tmux-single-sidebar/test-contract.sh` must pass at every task.
- Zero behavior changes to CLI subcommands, TUI keys, or production bundling.

---

### Task 1: Remove Obsolete Global Pane Movement Fallback Code

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Remove `find_global_sidebar_pane` and `ensure_global_sidebar_window` definitions**
Delete `find_global_sidebar_pane` and `ensure_global_sidebar_window`. Update `--ensure-sidebar-window` CLI route in `main()` to call `provision_sidebar_window`.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "refactor(sidebar): remove legacy global single-pane movement fallbacks"
```

---

### Task 2: Harden `prompt_text()` Signal Trap Restoration

**Files:**
- Modify: `scripts/tmux-session-launcher`
- Test: `tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Ensure trap restoration in `prompt_text()` is always executed**
Add reliable cleanup call for `trap handle_refresh_signal USR2` and `trap handle_geometry_signal WINCH` upon all return points in `prompt_text()`.

- [ ] **Step 2: Run contract test**
Run: `bash tests/tmux-single-sidebar/test-contract.sh`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher
git commit -m "fix(sidebar): prevent signal trap leak on early prompt cancellation"
```

---

### Task 3: Unify Active Client Lookups & Rebuild Production Bundle

**Files:**
- Modify: `scripts/tmux-session-launcher`, `dist/tmux-session-launcher`
- Test: `bash scripts/build-dist.sh && bash tests/tmux-single-sidebar/test-contract.sh`

- [ ] **Step 1: Unify 3-tier client lookups in `active_client_window` and `active_client_session`**
Consolidate repeated `list-clients` filtering into `resolve_active_client_property()`.

- [ ] **Step 2: Rebuild production bundle and run full test suite**
Run: `bash scripts/build-dist.sh && bash tests/tmux-single-sidebar/test-contract.sh && bash tests/tmux-single-sidebar/test-domain-unit.sh && bash tests/tmux-single-sidebar/test-port-tmux-unit.sh && bash tests/tmux-single-sidebar/test-switch-unit.sh && bash tests/tmux-single-sidebar/test-presenter-unit.sh && bash tests/tmux-single-sidebar/test-coordinator-unit.sh && bash tests/tmux-single-sidebar/test-archive-unit.sh`
Expected: PASS (All 7 suites)

- [ ] **Step 3: Commit**
```bash
git add scripts/tmux-session-launcher dist/tmux-session-launcher
git commit -m "build(sidebar): update production bundle after architecture integrity cleanup"
```
