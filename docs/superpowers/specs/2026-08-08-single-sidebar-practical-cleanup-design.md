# Single Sidebar Practical Cleanup Spec (Clean Sweep - Option A)

> **Date:** 2026-08-08  
> **Target:** `al-hub/dotfiles` (`feature/single-sidebar`)  
> **Goal:** Eliminate pure dead functions (15 functions), unify duplicate 30-line blocks in session deletion and timing helpers, while preserving 100% contract test safety and zero latency regressions.

---

## 1. Overview & Scope

### Current Technical Debt
`scripts/tmux-session-launcher` contains historical dead code from previous single-pane movement iterations and duplicate blocks introduced during TUI error handling hardening.

### Target Improvements
1. **Remove Pure Dead Functions (15 functions)**:
   - `prepare_window_for_archive`
   - `wait_for_sidebar_refresh`
   - `wait_for_sidebar_selection_sync`
   - `session_ai_pane_for_session`
   - `session_animation_seed_for`
   - `session_status`
   - `row_screen_line`
   - `row_mark`
   - `history_title_from_file`
   - `row_name_width`
   - `render_session_name_cell`
   - `archivable_window_count`
   - `clear_restored_work_panes`
   - `wait_for_sidebar_transition`
   - `wait_for_batch_sidebar_content`

2. **Deduplicate Boilerplate Blocks**:
   - Consolidate duplicated 30-line session delete handler in `tui_delete_session()` into helper `execute_tui_session_delete()`.
   - Remove duplicate post-restore cache reset in `tui_restore_archives()`.
   - Merge `debug_now_us()` into `metrics_now_us()`.

---

## 2. Safety & Regression Hard-Gates

1. All contract and unit test suites MUST pass:
   `bash tests/tmux-single-sidebar/test-contract.sh` and `tests/tmux-single-sidebar/test-*-unit.sh`.
2. Zero behavior or API changes to CLI subcommands or TUI keybindings.
