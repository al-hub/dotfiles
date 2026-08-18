# tmux sidebar 테스트 운영표

이 문서는 `tests/tmux-single-sidebar`에 이미 있는 테스트를 기능별 실행 단계로
정리한 것이다. 변경 범위에 맞는 빠른 gate부터 순서대로 실행한다.

## 실행 단계

### Gate A: 빠른 계약 및 실패 경계

사용자 tmux를 변경하지 않는 기본 gate다. launcher, controller, metadata,
ownership, rollback을 변경하면 반드시 실행한다.

```sh
bash -n scripts/tmux-session-launcher
bash -n scripts/tmux-sidebar-controller
bash tests/tmux-single-sidebar/test-contract.sh
bash tests/tmux-single-sidebar/test-window-local-contract.sh
bash tests/tmux-single-sidebar/test-active-window.sh
bash tests/tmux-single-sidebar/test-hook-target-regression.sh
bash tests/tmux-single-sidebar/test-managed-sessions.sh
bash tests/tmux-single-sidebar/test-session-name-zero.sh
bash tests/tmux-single-sidebar/test-raw-layout-snapshot.sh
bash tests/tmux-single-sidebar/test-layout-metadata-failure.sh
bash tests/tmux-single-sidebar/test-failure-injection.sh
```

현재 `test-contract.sh`는 전역 sidebar 폭 저장, 새 session 폭 재사용, stale
metadata 복구, provisioning 중 중복 toggle 억제를 함께 검증한다. 전역 폭과
session별 work layout을 서로 덮어쓰지 않는지 확인하는 assertion도 이 계약
테스트에 유지한다.

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
```

필수 invariant는 다음과 같다.

- session 생성·이동·Enter 선택이 반복해서 성공한다.
- work pane 수, title, path, geometry와 active pane이 보존된다.
- archive 선택 수와 restore 완료 수가 일치한다. 다중 복원은 6/6이어야 한다.
- restore 중 빠른 입력은 중복 operation을 만들지 않는다.
- session `0`과 stale sidebar row가 정상 처리된다.
- known error, `session switch failed`, `longjmp causes uninitialized stack frame`
  이 없어야 한다.

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

외부 session은 보존하고 managed session만 변경해야 하며, conflict나 injected
failure에서는 원본 session과 sidebar ownership이 보존되어야 한다.

### Gate D: 전환 관측 및 성능

기능 gate가 통과한 뒤 phase별 latency와 redraw 원인을 측정한다. 이 테스트는
기능 성공과 성능 목표 미달을 별도로 보고한다.

```sh
bash tests/tmux-single-sidebar/test-session-switch-live-correlation.sh
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-horizontal.sh
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-vertical.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-correlation.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-phase.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-cause.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-pty-render-measurement.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-visual-layer-measurement.sh
bash tests/tmux-single-sidebar/test-keyboard-e2e-switch-flicker-measurement.sh
bash tests/compare-profiles.sh
```

`test-keyboard-e2e-session-create-latency.sh`는 provisioning 또는 session
생성 지연을 변경했을 때 별도로 실행한다. 공식 release hard gate는 유효한 전환
sample 전체 1000ms 이하, 외부 키 반응 100ms 이하이다. p95 500ms는 기능 실패와
분리한 최적화 목표/P2 경고로 기록한다.

### Gate E: 사용자-visible tmux 최종 검증

설치 직후, release 후보, 실제 사용자 tmux 동작 변경 후에만 실행한다.

```sh
bash tests/tmux-single-sidebar/test-user-tmux-required-monitored.sh
bash tests/tmux-single-sidebar/test-user-tmux-full-monitored.sh
bash tests/tmux-single-sidebar/test-user-visible-full-monitored.sh
bash tests/tmux-single-sidebar/test-live-full-monitored.sh
```

사용자 tmux 대상 테스트는 managed 이름을 사용하고 기존 user session을 삭제하거나
server를 종료하지 않아야 한다. 실패 시 PTY 화면, pane 목록, layout, launcher
trace를 보존한다.

## 변경 범위별 최소 실행 세트

| 변경 범위 | 최소 테스트 |
|---|---|
| sidebar toggle, provisioning, 폭 저장 | Gate A + `test-keyboard-e2e-repeat.sh` |
| session 전환, Enter, selection sync | Gate A + Gate B + correlation 1종 |
| split, resize, layout metadata | Gate A + direct/split/arbitrary topology |
| archive/restore, 다중 선택 | Gate A + history-select-all + arbitrary/multi-window |
| delete, stale row, numeric session | Gate A + zero/stale-row + rapid operations |
| owner, client, conflict, linked window | Gate A + Gate C |
| latency, render, trace | 해당 correlation/measurement + `compare-profiles.sh` |
| 설치 또는 실제 사용자 환경 | 전체 isolated gate 후 Gate E |

## 현재 보강이 필요한 assertion

기존 테스트를 유지하면서 다음 항목만 보강한다.

1. 폭 저장

   - tmux 재시작 후 전역 sidebar 폭 복원
   - state 파일 손상 시 기본 폭 fallback
   - session별 archive geometry가 전역 sidebar 폭을 덮어쓰지 않음
   - 실제 mouse resize 입력 후 마지막 폭 유지

2. 다중 restore

   - 각 archive의 시작·완료 timestamp
   - 전체 restore 완료 timestamp
   - 선택 수/복원 수/실패 session 이름
   - `Restoring n/6`와 최종 `6/6` 결과

3. cold provisioning

   - 첫 toggle 직후 loading 상태 표시
   - content ready 시점과 timeout 기록
   - provisioning 중 중복 toggle로 pane이 추가·제거되지 않음

4. 실패 artifact

   - 첫 실패 시점의 pane ID, PID, title, geometry, layout
   - 현재 client/session/window
   - operation ID와 phase trace
   - PTY raw input/output delta

## pane 소멸의 후순위 처리

pane 소멸의 근본 원인 분석은 이 문서의 기능 gate 승격 조건에서 제외한다.
다만 기존 Gate D/E observer에서는 다음 invariant를 계속 기록한다.

- expected sidebar pane 수와 실제 pane 수
- metadata pane ID의 실제 존재 여부
- `ready=1`인데 pane/content가 없는 상태
- sidebar 소멸 전후 work pane 수와 layout 변화
- provisioning 중복 실행 여부

이 invariant가 실패하면 해당 테스트는 기능 회귀로 중단하고 첫 snapshot과 trace를
보존한다. 소멸 방지 자체를 위해 production 구조를 확대 수정하는 것은 별도
원인 분석 작업으로 분리한다.

## 승격 기준

현재 branch를 master 반영 후보로 판단하려면 다음 순서를 만족해야 한다.

1. Gate A 전부 통과
2. Gate B 전체 시나리오 3회 연속 통과
3. archive/restore 6/6 및 topology invariant 통과
4. Gate C conflict/ownership 통과
5. Gate E에서 known error 0건
6. Gate D 결과를 기능 결과와 별도로 기록

성능 목표 미달은 별도 P2로 추적할 수 있지만, pane/work layout 손실, archive
불일치, ownership 위반, known error는 승격을 막는 기능 실패로 처리한다.
