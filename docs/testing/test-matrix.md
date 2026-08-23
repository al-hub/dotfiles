# tmux sidebar 테스트 운영표

이 문서는 `tests/` 디렉터리 내의 모든 테스트 스위트, 프로파일러, 과거 결함 회귀 및 공통 인프라 하네스(총 134개 스크립트)를 기능별 실행 단계로 정리한 것이다.

## 테스트 러너 및 건전성 진단 도구

통합 테스트 러너와 건전성 진단 스크립트를 통해 Gate별 일괄 실행 및 스위트 무결성을 점검할 수 있다.

```sh
# 테스트 스위트 건전성(Health) 정적 분석 및 Orphan/레거시 감사
bash tests/analyze-test-health.sh

# Gate A 빠른 계약 및 단위 테스트 일괄 실행 (20종)
bash tests/run-tests.sh --gate a

# Gate B PTY E2E 기능 회귀 테스트 일괄 실행 (15종)
bash tests/run-tests.sh --gate b

# Gate C 멀티 클라이언트 및 소유권 테스트 (5종)
bash tests/run-tests.sh --gate c

# 서브페인(Subpane) 종합 스위트 (21종)
bash tests/run-tests.sh --subpane

# 스트레스 및 고속 연속 전환/락 회수 스위트 (5종)
bash tests/run-tests.sh --stress

# 복원 엣지케이스, 손상 복구 및 관측성 스위트 (6종)
bash tests/run-tests.sh --edge

# 사이드바 그래디언트 및 웨이브폼 스위트 (7종)
bash tests/run-tests.sh --gradient

# 전체 종합 실행
bash tests/run-tests.sh --all
```

---

## 실행 단계별 테스트 분류

### Gate A: 빠른 계약 및 단위 경계

사용자 tmux를 변경하지 않는 기본 gate다. launcher, controller, metadata,
ownership, rollback, 폭 영속화, cold provisioning을 변경하면 반드시 실행한다.

```sh
bash -n scripts/tmux-session-launcher
bash -n scripts/tmux-sidebar-tmux-adapter

# 순수 도메인/유닛 테스트
bash tests/tmux-single-sidebar/test-domain-unit.sh
bash tests/tmux-single-sidebar/test-presenter-unit.sh
bash tests/tmux-single-sidebar/test-coordinator-unit.sh
bash tests/tmux-single-sidebar/test-archive-unit.sh
bash tests/tmux-single-sidebar/test-topology-unit.sh
bash tests/tmux-single-sidebar/test-port-tmux-unit.sh
bash tests/tmux-single-sidebar/test-infra-registry-unit.sh
bash tests/tmux-single-sidebar/test-activity-observer-unit.sh
bash tests/tmux-single-sidebar/test-restore-terminal-unit.sh
bash tests/tmux-single-sidebar/test-selection-alignment-unit.sh
bash tests/tmux-single-sidebar/test-switch-unit.sh

# 코어 사이드바 계약 테스트
bash tests/tmux-single-sidebar/test-contract.sh
bash tests/tmux-single-sidebar/test-window-local-contract.sh
bash tests/tmux-single-sidebar/test-active-window.sh
bash tests/tmux-single-sidebar/test-hook-target-regression.sh
bash tests/tmux-single-sidebar/test-managed-sessions.sh
bash tests/tmux-single-sidebar/test-session-name-zero.sh
bash tests/tmux-single-sidebar/test-raw-layout-snapshot.sh
bash tests/tmux-single-sidebar/test-layout-metadata-failure.sh
bash tests/tmux-single-sidebar/test-failure-injection.sh
bash tests/tmux-single-sidebar/test-topology-contract.sh
bash tests/tmux-single-sidebar/test-marker-handover-contract.sh
bash tests/tmux-single-sidebar/test-marker-sync.sh
bash tests/tmux-single-sidebar/test-middle-footer.sh
bash tests/tmux-single-sidebar/test-navigation-in-memory.sh
bash tests/tmux-single-sidebar/test-sync-option-clear.sh
bash tests/tmux-single-sidebar/test-transition-coalescing.sh
bash tests/tmux-single-sidebar/test-window-ready-options.sh
bash tests/tmux-single-sidebar/test-client-source-resolution.sh
bash tests/tmux-single-sidebar/test-fast-self-switch.sh
bash tests/tmux-single-sidebar/test-bulk-restore-lazy.sh
bash tests/tmux-single-sidebar/test-archive-deterministic-naming-contract.sh

# 서브페인 기본 계약 및 레이아웃 격리
bash tests/tmux-single-sidebar/test-subpane-unit.sh
bash tests/tmux-single-sidebar/test-subpane-contract.sh
bash tests/tmux-single-sidebar/test-layout-subpane-isolation.sh

# [신규 보강] 폭 영속화/Fallback, 단일 행 클램핑(줄넘김 방지), Cold Provisioning, 다중 복원 관측성
bash tests/tmux-single-sidebar/test-width-persistence-contract.sh
bash tests/tmux-single-sidebar/test-width-clamping-single-line.sh
bash tests/tmux-single-sidebar/test-cold-provisioning-contract.sh
bash tests/tmux-single-sidebar/test-batch-restore-observability.sh
```

### Gate B: isolated attached-PTY 기능 회귀

실제 terminal byte를 attached PTY에 주입하지만 별도 tmux socket을 사용한다.
sidebar 입력, session 전환, topology와 archive/restore를 변경하면 실행한다.

```sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-repeat.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-direct-layout.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-split-cycle.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-split-cycle-vertical.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-arbitrary-topology.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-multi-window-topology.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-pane-reorder.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-history-select-all.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-rename-roundtrip.sh
bash tests/tmux-single-sidebar/test-delete-zero-stale-row.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-window-local-switch.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-window-local-toggle.sh
bash tests/tmux-single-sidebar/test-batch-restore-layout-integrity.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-mouse-selection.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-sidebar-fixed-work-switch.sh
bash tests/tmux-single-sidebar/test-presenter-handover-e2e.sh
bash tests/tmux-single-sidebar/test-multi-session-animation-e2e.sh

# [신규 보강] Split 복원 엣지케이스 (서브페인 공존, 수평 높이 정량, 해상도 변경 적응)
bash tests/tmux-single-sidebar/test-split-restore-edge-cases.sh
```

### Gate C: multi-client와 lifecycle 경계

client ownership, linked window, archive/delete/restore conflict를 변경했을 때
실행한다.

```sh
bash tests/tmux-single-sidebar/test-multi-client-ownership.sh
bash tests/tmux-single-sidebar/test-multi-client-operation-conflict.sh
bash tests/tmux-single-sidebar/test-window-local-multi-client.sh
bash tests/tmux-single-sidebar/test-window-local-lifecycle-contract.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-window-local-lifecycle.sh
```

### 서브페인(Subpane) 특화 스위트

사이드바 내부 서브페인의 임대(Lease), 위치 전환(`Ctrl+a P`), 높이 유지, 마우스 리사이즈를 검증한다.

```sh
# 단위 및 허브 로직
bash tests/tmux-single-sidebar/test-subpane-unit.sh
bash tests/tmux-single-sidebar/test-subpane-hub-unit.sh

# 생성/소멸/임대 및 레이아웃 격리
bash tests/tmux-single-sidebar/test-subpane-contract.sh
bash tests/tmux-single-sidebar/test-subpane-hub-contract.sh
bash tests/tmux-single-sidebar/test-atomic-subpane-lease.sh
bash tests/tmux-single-sidebar/test-layout-subpane-isolation.sh
bash tests/tmux-single-sidebar/test-subpane-work-isolation.sh

# 위치 전환 (Top/Bottom) 및 세션 전환 보존
bash tests/tmux-single-sidebar/test-subpane-position-contract.sh
bash tests/tmux-single-sidebar/test-subpane-switch-position-contract.sh
bash tests/tmux-single-sidebar/test-subpane-ctrl-alt-swap.sh
bash tests/tmux-single-sidebar/test-subpane-swap-switch-immediate.sh
bash tests/tmux-single-sidebar/test-subpane-top-switch-decay.sh
bash tests/tmux-single-sidebar/test-subpane-intent-decay-repro.sh

# 높이 유지 및 마우스/수동 리사이즈
bash tests/tmux-single-sidebar/test-subpane-height-persistence.sh
bash tests/tmux-single-sidebar/test-subpane-mouse-resize-detect.sh
bash tests/tmux-single-sidebar/test-subpane-mouse-resize-fidelity.sh
bash tests/tmux-single-sidebar/test-subpane-swap-manual-resize-detect.sh
bash tests/tmux-single-sidebar/test-subpane-swap-manual-resize-fidelity.sh

# PTY E2E 및 스트레스
bash tests/tmux-single-sidebar/test-keyboard-e2e-subpane.sh
bash tests/tmux-single-sidebar/test-subpane-default-bottom-off-height-persist.sh
bash tests/tmux-single-sidebar/test-subpane-p-key-rapid-loop.sh
bash tests/tmux-single-sidebar/test-subpane-multi-session-stress.sh
```

### 스트레스 및 엣지케이스 특화 스위트

고속 전환, 락 회수, 소켓 분쟁 및 과거 버그 재현 스위트다.

```sh
# 스트레스 스위트
bash tests/tmux-single-sidebar/test-rapid-15-switches-lock-reclaim.sh
bash tests/tmux-single-sidebar/test-consecutive-session-switches.sh
bash tests/tmux-single-sidebar/test-rapid-input-drain.sh
bash tests/tmux-single-sidebar/test-subpane-multi-session-stress.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh

# 엣지케이스 스위트
bash tests/tmux-single-sidebar/test-width-persistence-contract.sh
bash tests/tmux-single-sidebar/test-width-clamping-single-line.sh
bash tests/tmux-single-sidebar/test-long-session-name-switching-flicker-detect.sh
bash tests/tmux-single-sidebar/test-negative-width-substring-regression.sh
bash tests/tmux-single-sidebar/test-eager-warm-provisioning-restore.sh
bash tests/tmux-single-sidebar/test-cold-provisioning-contract.sh
bash tests/tmux-single-sidebar/test-batch-restore-observability.sh
bash tests/tmux-single-sidebar/test-split-restore-edge-cases.sh
bash tests/tmux-single-sidebar/test-first-enter-warm-session-flicker-detect.sh
bash tests/tmux-single-sidebar/test-mouse-width-resize-switch.sh
bash tests/tmux-single-sidebar/test-incremental-session-discovery-stale-footer-detect.sh
bash tests/tmux-single-sidebar/test-sidebar-ghost-row-stale-footer-detect.sh
bash tests/tmux-single-sidebar/test-missing-session-switch-graceful.sh
bash tests/tmux-single-sidebar/test-find-global-pane-regression.sh
```

### 사이드바 애니메이션 및 웨이브폼 스위트

Look-Up Table(LUT) 24프레임 파형 엔진, ANSI 그라데이션, 백그라운드 AI 활동 상태 전이를 검증한다.

```sh
bash tests/tmux-sidebar-gradient/test-render.sh
bash tests/tmux-sidebar-gradient/test-fingerprint.sh
bash tests/tmux-sidebar-gradient/test-state.sh
bash tests/tmux-sidebar-gradient/test-session-isolation.sh
bash tests/tmux-sidebar-gradient/test-lifecycle-e2e.sh
bash tests/tmux-sidebar-gradient/test-regressions.sh
bash tests/tmux-sidebar-gradient/test-hot-path.sh
bash tests/tmux-sidebar-gradient/test-launcher-lifecycle.sh
bash tests/tmux-single-sidebar/test-animation-lut-unit.sh
```

### Gate D: 전환 관측 및 성능 프로파일링

기능 gate가 통과한 뒤 phase별 latency와 redraw 원인을 측정한다.

```sh
# 전환 관측 및 지연시간 측정
bash tests/tmux-single-sidebar/test-session-switch-live-correlation.sh
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-horizontal.sh
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-vertical.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-correlation.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-phase.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-cause.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-pty-render-measurement.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-visual-layer-measurement.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-flicker-measurement.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-session-create-latency.sh
bash tests/compare-profiles.sh

# 정밀 프로파일링 및 정착 측정 스위트
bash tests/profile-active-sidebar.sh
bash tests/profile-isolated-sidebar.sh
bash tests/profile-isolated-sidebar-auto.sh
bash tests/profile-isolated-sidebar-reproduction.sh
bash tests/profile-observer-settlement.sh
bash tests/profile-separated-run.sh
bash tests/profile-sidebar-navigation.sh
bash tests/profile-tmux-settlement.sh
```

### 과거 회귀 및 결함 재현 스위트 (Historical Regression & Defect Reproductions)

과거 릴리스 및 개발 과정에서 발생했던 특수 결함 패턴을 방지하는 회귀 검증 스위트다.

```sh
bash tests/tmux-single-sidebar/test-debug-user-exact.sh
bash tests/tmux-single-sidebar/test-debug-user-scenario.sh
bash tests/tmux-single-sidebar/test-basic-defects.sh
bash tests/tmux-single-sidebar/test-new-defects.sh
bash tests/tmux-single-sidebar/test-option-a-geometry.sh
bash tests/tmux-single-sidebar/test-tui-delete-action-regression.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-sidebar-fixed-work-failure.sh
```

### 테스트 인프라 및 공통 하네스

독립 실행 스크립트가 아닌 공통 런타임/모듈 하네스다.

- `tests/lib/test_artifact_helper.sh`: 테스트 실패 시 진단 덤프(pane, layout, capture) 보존 헬퍼.
- `tests/tmux-sidebar-gradient/lib.sh`: 그래디언트 테스트용 assertion 및 snapshot stub 공통 라이브러리.
- `tests/tmux-sidebar-gradient/fake-ai.sh`: 백그라운드 AI 출력 시뮬레이터.
- `tests/tmux-sidebar-gradient/run.sh`: 그래디언트 러너 래퍼.
- `tests/tmux-single-sidebar/test-interactive-common.sh`: 격리 socket 및 PTY interactor 공통 설정.
- `tests/tmux-single-sidebar/run_gate_e_test.sh` / `tests/tmux-single-sidebar/run_gate_e_scenarios.sh`: Gate E 라이브 러너 하네스.
- `tests/tmux-single-sidebar/test-keyboard-e2e.sh`: PTY 브릿지 E2E 코어 드라이버.

### Gate E: 사용자-visible tmux 최종 검증

설치 직후, release 후보, 실제 사용자 tmux 동작 변경 후에만 실행한다.

```sh
bash tests/tmux-single-sidebar/test-user-tmux-required-monitored.sh
bash tests/tmux-single-sidebar/test-user-tmux-full-monitored.sh
bash tests/tmux-single-sidebar/test-user-visible-full-monitored.sh
bash tests/tmux-single-sidebar/test-live-full-monitored.sh
```

## 변경 범위별 최소 실행 세트

| 변경 범위 | 최소 테스트 |
|---|---|
| sidebar toggle, provisioning, 폭 저장 | Gate A + `test-width-persistence-contract.sh` |
| session 전환, Enter, selection sync | Gate A + Gate B + correlation 1종 |
| split, resize, layout metadata | Gate A + direct/split + `test-split-restore-edge-cases.sh` |
| archive/restore, 다중 선택 | Gate A + `test-batch-restore-observability.sh` + arbitrary/multi-window |
| delete, stale row, numeric session | Gate A + zero/stale-row + rapid operations |
| owner, client, conflict, linked window | Gate A + Gate C |
| 서브페인(Subpane) 생성, 위치, 리사이즈 | `bash tests/run-tests.sh --subpane` |
| 고속 전환 스트레스 및 부하 | `bash tests/run-tests.sh --stress` |
| 복원 엣지케이스 및 손상 복구 | `bash tests/run-tests.sh --edge` |
| 애니메이션, 웨이브폼, TUI 렌더링 | `bash tests/run-tests.sh --gradient` |
| latency, render, trace | 해당 correlation/measurement + `compare-profiles.sh` |
| 설치 또는 실제 사용자 환경 | 전체 isolated gate 후 Gate E |

## 승격 기준

현재 branch를 master 반영 후보로 판단하려면 다음 순서를 만족해야 한다.

1. Gate A 전부 통과 (보강 3종 포함 20/20 PASS)
2. Gate B 전체 시나리오 통과 (Split 엣지 포함 15/15 PASS)
3. archive/restore 6/6 및 topology invariant 통과
4. Gate C conflict/ownership 통과
5. Gate E에서 known error 0건
6. Gate D 결과를 기능 결과와 별도로 기록
