# Global Singleton Subpane & Prompt Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사이드바 서브패널(Subpane)을 전역 싱글톤 백그라운드 세션(`.dotfiles-subpane-hub`) 기반의 Attach/Mirror 모델로 전환하여, 세션을 전환해도 실행 중이던 작업 프로세스가 100% 영속 유지되도록 하고, 일반 작업창과 완전히 동일한 `$ ` 프롬프트를 적용합니다.

**Architecture:** 
- **SRP (단일 책임 원칙)**: 전역 싱글톤 쉘 세션의 라이프사이클 및 환경 주입을 `SubpaneHubManager` (`scripts/lib/sidebar_subpane_hub.sh`)로 단일화.
- **Attach/Mirroring**: 실제 쉘 프로세스는 단 1개만 상주하고, 각 윈도우의 서브패널은 `tmux attach-session -t =.dotfiles-subpane-hub:` 래퍼를 실행하여 실시간 동기화.
- **Zero Sourcing & Clean Prompt**: tmux 전용 `ZDOTDIR="$HOME/.cache/dotfiles"`를 주입하여 호스트 프롬프트(`WIN-...%`) 대신 `$ ` 프롬프트와 git 자동완성 통일.

**Tech Stack:** Bash (4.0+), tmux (3.x), POSIX utilities, Linux PTY.

---

## Global Constraints

- 서브패널 전용 백그라운드 세션 이름은 `.dotfiles-subpane-hub`로 고정한다.
- 쉘 실행 커맨드는 `exec env ZDOTDIR="$HOME/.cache/dotfiles" /bin/zsh` (또는 기본 쉘 폴백)을 사용하여 `$ ` 프롬프트를 보장한다.
- 서브패널 토글 off(`m`) 시 프론트의 attach 래퍼 pane만 kill되고 백그라운드 Hub 세션은 유지되어야 한다.
- 모든 기능은 Test-Driven Development (Red -> Green -> Refactor) 사이클을 준수하며 단계마다 커밋을 생성한다.

---

### Task 1: `SubpaneHubManager` 도메인 헬퍼 & 단위 테스트 (TDD)

**Files:**
- Create: `tests/tmux-single-sidebar/test-subpane-hub-unit.sh`
- Create: `scripts/lib/sidebar_subpane_hub.sh`

---

### Task 2: Subpane Hub 세션 멱등 생성 및 프롬프트 계약 검증 (TDD)

**Files:**
- Create: `tests/tmux-single-sidebar/test-subpane-hub-contract.sh`
- Modify: `scripts/lib/sidebar_subpane_hub.sh`
- Modify: `scripts/lib/sidebar_port_tmux.sh`

---

### Task 3: `WindowTopologyManager` & `sidebar_port_tmux.sh` Hub 연동 (TDD)

**Files:**
- Modify: `scripts/lib/sidebar_port_tmux.sh`
- Modify: `scripts/lib/sidebar_topology.sh`
- Modify: `scripts/build-dist.sh`
- Modify: `scripts/tmux-session-launcher`

---

### Task 4: 멀티 세션 작업 내역 영속성 & 프롬프트 E2E 검증 (E2E)

**Files:**
- Modify: `tests/tmux-single-sidebar/test-keyboard-e2e.sh`
