# Single Sidebar Architecture Integrity & Trap Guard Spec (Phase 2 Clean Up)

> **Date:** 2026-08-08  
> **Target:** `al-hub/dotfiles` (`feature/single-sidebar`)  
> **Goal:** Remove obsolete global single-pane movement fallback functions (`find_global_sidebar_pane`, `ensure_global_sidebar_window`), fix trap restoration leaks in `prompt_text()`, and unify redundant 3-tier client/window queries.

---

## 1. Overview & Scope

### Current Architectural Discrepancies
1. **Legacy Physical Pane Movement Code**:
   - `find_global_sidebar_pane()` (L1105–1108) and `ensure_global_sidebar_window()` (L1879–1892) are relics from the pre-M0 single physical pane movement model.
   - Current architecture strictly uses **Window-Local Sidebars** (1 presenter pane per managed window).
2. **Signal Trap Restoration Leak**:
   - `prompt_text()` ignores `SIGUSR2` and `SIGWINCH` signals via `trap ''` while reading input. If `prompt_text()` returns early, traps are not restored, causing the TUI to freeze on window resizes or force refreshes.
3. **Redundant 3-Tier Client Queries**:
   - `active_client_window()` and `active_client_session()` duplicate identical 3-level fallback client lookup logic.

---

## 2. Target Improvements

1. **Remove Obsolete Fallback Functions**:
   - Delete `find_global_sidebar_pane()` and `ensure_global_sidebar_window()`.
   - Update `--ensure-sidebar-window` CLI route to delegate cleanly to `provision_sidebar_window()`.
2. **Harden `prompt_text()` Trap Handling**:
   - Wrap trap restoration in a local cleanup guard or explicit exit path to prevent signal handler leaks.
3. **Unify Active Client Lookup**:
   - Consolidate 3-tier client queries into `resolve_active_client_property()`.

---

## 3. Safety & Regression Hard-Gates

1. All 7 contract and unit test suites MUST pass:
   `bash tests/tmux-single-sidebar/test-contract.sh` and unit tests.
2. Zero performance overhead regressions (key response <= 100ms, transition <= 1000ms).
