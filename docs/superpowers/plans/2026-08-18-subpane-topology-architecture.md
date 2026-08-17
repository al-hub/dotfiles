# Subpane Topology Isolation & WindowTopologyManager Architecture Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 불변 옵션 기반의 `WindowTopologyManager` Deep Module을 구축하여 서브패널 식별 소실, 좀비 패널 잔존, 레이아웃 오염 및 아카이브 찌그러짐 결함을 원천 해결하고, TDD 및 SOLID 원칙에 따라 사이드바/서브패널 토폴로지 라이프사이클을 완전히 격리합니다.

**Architecture:** 
- **SRP (단일 책임)**: Pane 분류, 불변 메타데이터 식별, 레이아웃 스냅샷 계산을 `WindowTopologyManager` (`scripts/lib/sidebar_topology.sh`)로 단일화.
- **DIP (의존 역전)**: 도메인/토폴로지 로직이 원시 tmux 명령어 대신 추상화된 어댑터 포트(`sidebar_port_tmux.sh`)를 통해 동작.
- **Pure Math Snapshot**: 물리적 `break-pane`/`join-pane` 조작을 배제하고 tmux 레이아웃 트리를 안전하게 계산하여 서브패널이 work layout에 혼입되는 문제 완전 제거.

**Tech Stack:** Bash (4.0+), tmux (3.x), POSIX utilities (`awk`, `sed`, `grep`), Linux PTY.

---

## Global Constraints

- 서브패널 식별 시 쉘/프로세스에 의해 가변적인 `pane_title`에 절대 단독 의존하지 않고 불변 pane user option (`@dotfiles_sidebar_subpane 1`)을 사용한다.
- `snapshot_work_layout_transaction` 및 아카이브 스냅샷 시 사이드바와 서브패널은 순수 work layout에서 100% 격리되어야 한다.
- 사이드바 토글 닫기(`Ctrl+a s`) 시 서브패널도 함께 clean하게 제거되어야 한다.
- 모든 기능은 Test-Driven Development (Red -> Green -> Refactor) 사이클을 준수하며 변경마다 커밋을 생성한다.

---

### Task 1: 불변 옵션 기반 Pane 식별자 & 어댑터 강화 (TDD)

**Files:**
- Create: `tests/tmux-single-sidebar/test-topology-unit.sh`
- Modify: `scripts/lib/sidebar_port_tmux.sh`
- Modify: `scripts/lib/sidebar_domain.sh`

---

### Task 2: Deep `WindowTopologyManager` 구축 (TDD)

**Files:**
- Create: `scripts/lib/sidebar_topology.sh`
- Create: `tests/tmux-single-sidebar/test-topology-contract.sh`
- Modify: `scripts/tmux-sidebar-tmux-adapter`

---

### Task 3: 레이아웃 스냅샷 및 아카이브 서브패널 오염 박멸 (TDD)

**Files:**
- Create: `tests/tmux-single-sidebar/test-layout-subpane-isolation.sh`
- Modify: `scripts/lib/sidebar_topology.sh`
- Modify: `scripts/tmux-session-launcher`
- Modify: `dist/tmux-session-launcher`

---

### Task 4: 세션 생성 및 토글 연동 회귀 검증 (E2E)

**Files:**
- Modify: `tests/tmux-single-sidebar/test-keyboard-e2e.sh`
- Modify: `tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh`
- Modify: `scripts/tmux-session-launcher`
