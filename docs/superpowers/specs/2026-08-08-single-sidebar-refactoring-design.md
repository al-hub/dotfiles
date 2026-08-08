# Single Sidebar Refactoring & Modularization Spec (M1-M7)

> **Date:** 2026-08-08  
> **Target:** `al-hub/dotfiles` (`feature/single-sidebar`)  
> **Goal:** Decompose monolithic `scripts/tmux-session-launcher` (7,300+ lines) into clean, testable, decoupled Bash modules implementing SOLID principles, TDD contracts, LOC optimization, and strict hard-gate performance targets (<=1000ms transition, <=100ms key response).

---

## 1. Overview & Architecture

### Current Problem
`scripts/tmux-session-launcher` contains over 7,300 lines of Bash code intermingling domain logic, UI rendering, ANSI formatting, state management, file IPC, and raw `tmux` shell invocations.

### Architectural Target
We split the system into distinct, focused modules following the single-sidebar design specification (`docs/tmux-single-sidebar-design.md`):

1. **Domain (`scripts/lib/sidebar_domain.sh`)**: Pure data structures, state reducers, row formatting, diff calculations, archive parse/validation. Zero external commands or side effects.
2. **Ports & Adapters (`scripts/lib/sidebar_port_tmux.sh`)**: Abstracted, typed `tmux` operations and allowlisted IPC calls. Zero direct un-isolated shell calls in domain or UI layers.
3. **Switch & State Application Services (`scripts/lib/sidebar_switch.sh`)**: Hot-path `validate → publish → switch → confirm` transaction and cold-path reconciliation.
4. **Presenter & UI Rendering (`scripts/lib/sidebar_presenter.sh`)**: Thin presenter facade per managed window, terminal ANSI rendering, input handling.
5. **Archive & Lifecycle (`scripts/lib/sidebar_archive.sh`)**: Session archive v1/v2/v3 codecs, transaction-safe file saving/restoring, history imports.
6. **Main Composition Root (`scripts/tmux-session-launcher`)**: Glues modules together, sets up trap/signals, and enters event loop.

---

## 2. Milestones Breakdown (M1 — M7)

### Milestone M1: Pure Seam (Domain Extraction)
- Extract pure functions (render diff calculation, row index mapping, string sanitization, archive line validation, state reducer) into `scripts/lib/sidebar_domain.sh`.
- Ensure `sidebar_domain.sh` can be sourced and unit-tested with pure Bash functions without tmux or terminal dependencies.

### Milestone M2: Port Boundary (Tmux Adapter Isolation)
- Extract all `tmux` queries and mutations into `scripts/lib/sidebar_port_tmux.sh`.
- Enforce strict allowlists for hot-path mutations (`switch-client`). Eliminate raw `tmux` calls across domain and UI code.

### Milestone M3: Hot/Cold Path Split (Switch Path Refactoring)
- Refactor the 200+ line switch function in `scripts/lib/sidebar_switch.sh`.
- Hot path: `validate` -> `publish marker` -> `switch-client` -> `confirm`. (0 `move-pane`, 0 `split-window`, 0 `select-layout`).
- Cold path: Provisioning, layout reconciliation, repair.

### Milestone M4: Presenter & UI Extraction
- Extract ANSI screen rendering, scroll calculation, and key-mapping into `scripts/lib/sidebar_presenter.sh`.
- Ensure presenter acts as a thin window-local view layer.

### Milestone M5: Coordinator & Bus Interface
- Setup singleton coordinator protocol and event dispatch boundaries.
- Ensure bounded crash recovery and idempotent event handling.

### Milestone M6: Archive Service Extraction
- Extract v1/v2/v3 archive serialization, deserialization, atomic file transactions, and validation to `scripts/lib/sidebar_archive.sh`.

### Milestone M7: Cutover, Validation & Cleanup
- Replace inline monolith functions in `scripts/tmux-session-launcher` with clean module calls.
- Verify zero regression against contract tests and PTY test suites.
- Clean up unused helper procedures.

---

## 3. Global Constraints & Quality Hard-Gates

1. **Performance Hard-Gate**: Every key-to-stable-frame switch MUST be `<= 1000ms`. Key response MUST be `<= 100ms`.
2. **Test Safety**: All unit/contract tests MUST pass (`bash tests/tmux-single-sidebar/test-contract.sh`).
3. **No Breakage**: Maintain full backwards compatibility for existing TUI keybindings (`Ctrl+a s`, `|`, `_`, `%`, `"`, `n`, etc.) and archive versions (v1, v2, v3).
4. **Clean Code**: SOLID principles, modular file structure, small focused functions (<50 lines per function where feasible).
