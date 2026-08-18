# 유지보수 가능한 Single Sidebar 설계

## 상태와 문서 권한

- 상태: **Proposed**. 현재 동작을 한 번에 교체하는 구현 지시가 아니라, 이후
  리팩터링의 목표 구조와 TDD 승격 계약이다.
- 기준일: 2026-08-08, `feature/single-sidebar`의 window-local 구현 기준.
- 이 문서는 single-sidebar의 현재 아키텍처 결정 원본이다. 과거 global
  `move-pane` 설계와 충돌하는 설명은 역사적 기록일 뿐 현재 계약이 아니다.
- 현재 production이 이미 만족하는 항목과 목표 항목을 구분한다. 목표 구조를
  문서화했다는 사실만으로 구현 완료를 선언하지 않는다.

## 결론

사용자의 가설은 다음과 같이 해석할 때 맞다.

> session 전환 때 sidebar pane을 옮기거나 다시 만들지 않고, target window에
> 이미 준비된 고정 view로 `switch-client`만 수행하면 전환은 더 빠르고
> topology 손상 위험도 작다.

다만 tmux에서 pane은 하나의 physical window에 속하므로, **pane/PTY process
하나를 여러 window에 동시에 표시할 수는 없다**. 하나의 pane을 고집하면
`move-pane`/`join-pane`과 layout 복구를 다시 도입해야 하며, 지금 제거하려는
지연과 race가 되돌아온다. `link-window`는 전체 window를 공유하고 popup은 docked
pane이 아니므로 대안이 아니다.

따라서 이 설계에서 single은 다음 두 조건을 뜻한다.

1. tmux server당 session model, operation ownership, archive 정책을 소유하는
   **논리 backend/coordinator는 하나**다.
2. 각 unique managed `window_id`에는 입력과 출력만 담당하는 **얇고 고정된
   presenter pane이 하나** 있다. linked window는 physical `window_id` 기준으로
   하나만 둔다.

정확히 OS process 하나만 실행하는 것은 목표가 아니다. 각 PTY에는 출력과 입력을
중계할 process가 필요하다. 목표는 여러 presenter가 7천 줄짜리 업무 로직을 각각
소유하지 않게 하는 것이다.

## 현재 구현 진단

### 확인된 규모와 결합

| 항목 | 현재 값 | 의미 |
| --- | ---: | --- |
| `tmux-session-launcher` | 7,311 LOC, 261 함수 | composition root가 아니라 대부분의 책임을 직접 소유 |
| 관련 production shell 합계 | 7,789 LOC | launcher/controller/adapter에 전환·TUI·archive가 혼재 |
| `collect_sessions()` | 약 610줄 | catalog, cache, AI probe, render invalidation 결합 |
| `run_tui()` | 약 424줄 | input, signal, timer, maintenance, operation dispatch 결합 |
| `restore_archive()` | 약 346줄 | codec, topology, transaction, UI progress 결합 |
| `switch_session()` | 약 246줄 | ready hot path와 repair cold path 결합 |
| single-sidebar tests | 54개, 약 7,225 LOC | E2E 비중이 높고 작은 domain seam 검증이 부족 |

launcher에는 direct `tmux` 호출이 adapter 호출보다 훨씬 넓게 분포한다. 범용
`sidebar_tmux_cmd` escape hatch도 application layer에 노출되어 있어 현재 adapter는
실질적인 dependency-inversion 경계가 아니다.

`tmux-sidebar-controller`의 `sidebar_controller_move_to_session()`은 현재 저장소에서
호출자가 없지만 global pane 이동, layout snapshot, rollback을 168줄에 보존한다.
이는 window-local production 모델과 충돌하는 legacy 제거 후보이다. 기본값이 꺼진
FIFO control-mode 경로도 production CLI adapter와 분리되지 않아 인지 비용을 높인다.

### 성능 가설에 대한 증거

현재 production은 target window에 local sidebar를 준비하고 native
`switch-client`를 사용하는 방향으로 이미 이동했다. 최신 인수 기록은 다음과 같다.

| profile | 전환 결과 | 판정 |
| --- | --- | --- |
| isolated attached PTY | 약 623~838ms | 공식 1000ms 기준 내 |
| user live 6회 | 약 343~593ms | 6/6 marker·pane identity 유지 |
| Gate E window-local | 약 703~880ms | 1000ms 기준 내 |

과거 global `move-pane` 단계에서 측정한 수 초 단위 수치는 현재 native switch와 같은
baseline으로 합치지 않는다. 이후 측정에는 commit, transport, topology, sample 수를
반드시 같이 기록한다.

속도와 안정성의 직접 원인은 “프로그램 수가 적다”가 아니라 정상 전환에서
topology mutation, provisioning, full render, 반복 polling이 없다는 점이다. 현재
`switch_session()`에는 absent-pane repair, width/focus 보정, content ACK 등 cold
recovery 책임이 함께 있어 이 경계를 코드로 더 분명히 해야 한다.

## 목표 topology

```text
tmux server
│
├─ Sidebar coordinator (logical singleton)
│  ├─ pure state/reducer
│  ├─ application use cases
│  ├─ operation owner/lock
│  └─ presenter registry
│
├─ managed window @1 ─ fixed presenter pane ─┐
├─ managed window @2 ─ fixed presenter pane ─┼─ PresenterBus
└─ linked window @3 ─ one physical presenter ┘
                    │
                    ├─ TmuxQueryPort / TmuxMutationPort
                    ├─ ArchiveStorePort / LayoutPolicyPort
                    └─ Clock / Trace
```

presenter는 key/resize event를 전달하고 full snapshot 또는 delta frame을 적용한다.
session mutation, archive, ownership 판정, arbitrary tmux command는 수행하지 않는다.

coordinator를 persistent runtime으로 구현하는 transport와 언어는 별도 ADR/spike에서
결정한다. 먼저 protocol과 port를 fake로 검증한다. 새 runtime은 mandatory 외부
dependency를 추가하지 않고, 현 CLI 대비 복잡도·latency·recovery gate를 모두
통과한 뒤에만 기본값으로 승격한다.

## 책임과 인터페이스

| component | 단일 책임 | 의존할 수 있는 대상 |
| --- | --- | --- |
| composition root | CLI 해석과 구현 wiring | 모든 public port |
| `sidebar-core` | state + command → state + effects | 값 객체만 |
| session catalog | stable session/window identity snapshot | `TmuxQueryPort` |
| switch service | 전환 protocol과 precondition | query/mutation/presenter/trace port |
| lifecycle supervisor | cold provision, respawn, reconcile | tmux ports, presenter registry |
| ownership service | owner client, lock, operation idempotency | clock/state port |
| layout service | work-only geometry 정책 | query/mutation/layout store port |
| archive service | v1/v2/v3 codec와 transaction | archive/layout/tmux ports |
| presenter | input, resize, frame output, reconnect | `PresenterBus`, renderer |
| renderer | snapshot/delta를 ANSI frame으로 변환 | pure view model |
| CLI tmux adapter | stable ID query와 explicit mutation | tmux binary |
| trace/metrics adapter | operation/phase/call journal | clock, file sink |

application service에는 범용 `tmux_cmd`를 노출하지 않는다. query와 mutation을
분리하고 mutation은 `switch_client`, `provision_window`, `select_work_pane`,
`apply_archived_layout`처럼 의도가 드러나는 작은 interface로 제한한다.

### 상태 소유권

| scope | 상태 |
| --- | --- |
| server-wide | enabled, canonical width, session catalog generation, archive operation, coordinator runtime ID |
| owner-client | owner tty, selected session, view mode, input generation, active operation |
| window-local | pane ID, presenter ID/PID, readiness, geometry, rendered generation |
| tmux authoritative | session/window/pane/client identity, actual topology, attachment |

tmux identity는 cache보다 우선한다. destructive mutation과 `switch-client` 직전에는
stable ID와 client tty를 다시 검증한다. non-owner presenter는 관찰과 render만 할
수 있고 owner client를 전환하거나 sidebar를 탈취하지 않는다.

## 상태 머신

```text
Sidebar: Disabled ──on──> Enabled(owner, width) ──off──> Disabled

Presenter: Absent → Provisioning → Ready(id, generation)
                         └───────→ Failed
            Ready → Disconnected → Provisioning

Transition: Idle → Validating → Publishing → Switching → Confirming → Idle
                    └──────────── cold repair/retry ────────────────┘
                    └──────────────── failure → Failed → Idle
```

정상 Ready→Ready 전환에는 `Provisioning`이나 topology repair를 포함하지 않는다.
target presenter가 준비되지 않았다면 해당 요청을 cold recovery operation으로
분류하고, 준비가 완료된 후 전환을 새로 시도한다. 실패한 준비를 정상 전환의
긴 tail로 숨기지 않는다.

## session 전환 protocol

### Ready hot path

1. owner client tty, source/target session ID, target window ID를 조회한다.
2. in-memory registry에서 target presenter의 ready generation을 확인한다.
3. target에 선택 delta를 게시하고 동일 generation ACK를 확인한다.
4. explicit client를 stable session target으로 `switch-client` 한 번 전환한다.
5. client session과 target presenter generation을 확인하고 operation을 종료한다.

hot path tmux mutation allowlist는 `switch-client -c <tty> -t =<id>:` 1회다.
marker transport가 임시로 tmux option을 사용하면 option write를 별도 effect로
계측하되 topology mutation으로 취급하지 않는다.

정상 hot path에서 다음은 **0회**여야 한다.

- `move-pane`, `join-pane`, `split-window`, `kill-pane`, `respawn-pane`
- `select-layout`, layout snapshot/restore, `resize-pane`
- presenter/coordinator spawn 또는 exec
- `render_full`, full snapshot 재전송
- sleep 기반 readiness polling과 absent-pane repair

### Cold path

sidebar on, new window/session, restore 완료, presenter crash, raw layout mutation은
lifecycle supervisor가 처리한다. cold path는 bounded provision/reconcile을 허용하고
완료 후 `Ready(generation)`을 publish한다. archive는 sidebar infrastructure를
저장하지 않고 work topology만 저장하며, restore topology가 끝난 뒤 presenter를
provision한다.

### 실패 원칙

- target ready/ACK 실패: source client와 topology를 보존하고 switch하지 않는다.
- `switch-client` 실패: source 상태를 보존하고 operation을 `Failed` 후 `Idle`로
  유한 시간 안에 정리한다.
- coordinator crash: stale runtime identity를 검증한 뒤 singleton으로 재기동하고
  마지막 committed snapshot에서 복구한다.
- presenter disconnect: 재연결 시 full snapshot 정확히 1회, 이후 delta만 받는다.
- archive/restore conflict: 외부 session을 삭제하지 않고 matching partial managed
  state만 rollback한다.

## geometry 계약

정상 크기의 terminal에서 presenter는 좌측 `top=0`, full-height, canonical cell
width를 유지한다. session 전환 중 pane ID/PID/geometry는 변하지 않는다.

`window_width < sidebar_width + min_work_width`에서는 절대 폭 고정이 불가능하므로
폭을 clamp하고 `degraded_geometry`를 기록한다. terminal resize, 사용자의 raw
`select-layout`, direct split/resize 후에는 hook이 bounded reconciliation을 수행할
수 있지만 native switch hot path에서는 layout을 수정하지 않는다.

따라서 “항상 고정”은 모든 외부 tmux mutation 순간이 아니라 다음 steady-state
invariant를 뜻한다.

- unique managed window당 presenter pane 0/1개, enabled+ready이면 정확히 1개
- 정상 전환 전후 left/top/width와 work topology 불변
- 외부 geometry 변경 후 bounded cold reconciliation 또는 명확한 degraded 상태

## SOLID 적용

- **SRP**: catalog, switch, provision, layout, archive, input, render, metrics를 각각
  하나의 변경 이유로 분리한다.
- **OCP**: use case는 port에만 의존하여 CLI tmux adapter, 향후 격리된 control-mode
  adapter, archive store를 교체할 수 있다.
- **LSP**: fake와 real adapter는 같은 stable-ID semantics와 typed result/error를
  반환한다. 빈 stdout을 성공으로 해석하지 않는다.
- **ISP**: query/mutation/layout/archive/presenter bus를 작은 interface로 나누고
  application에 arbitrary tmux 명령을 주지 않는다.
- **DIP**: domain과 use case는 shell global, tmux option, ANSI escape를 모르며
  composition root가 구체 adapter를 주입한다.

파일 분리는 SOLID 달성의 결과이지 목적이 아니다. global state를 그대로 여러
파일에 source하는 것만으로 책임 분리를 완료했다고 보지 않는다.

## TDD 전략

### 원칙

1. 현 동작을 characterization test로 고정한다.
2. 구현 전 가장 작은 실패 계약을 RED로 만든다.
3. port/facade로 기존 코드를 감싸 최소 GREEN을 만든다.
4. 동일 contract 아래에서 책임을 이동하는 REFACTOR를 수행한다.
5. 기능 invariant가 실패한 sample은 latency 통계에서 제외하고 suite 자체를
   실패시킨다.
6. RED를 expected-failure로 숨기지 않는다. 구현 직전 feature milestone gate에
   추가하고 실패 assertion/artifact를 보존한다.

### 테스트 피라미드

| level | 비중 목표 | 예시 |
| --- | ---: | --- |
| L0 pure/domain | 60~70% | reducer, identity, layout policy, render diff, archive codec |
| L1 port/component | 20~25% | recording tmux adapter, IPC protocol, singleton, switch use case |
| L2 isolated tmux | 10~15% | provisioning, lifecycle, failure, real multi-client |
| L3 attached PTY/release | 핵심 journey | keyboard switch/topology/toggle/live correlation |

신규 contract의 권장 entrypoint는 다음과 같다.

- `test-sidebar-domain-state-unit.sh`
- `test-sidebar-render-diff-unit.sh`
- `test-sidebar-operation-unit.sh`
- `test-sidebar-tmux-port-contract.sh`
- `test-sidebar-coordinator-singleton-contract.sh`
- `test-sidebar-presenter-contract.sh`
- `test-sidebar-switch-usecase-contract.sh`
- `test-sidebar-runtime-recovery-contract.sh`
- `test-persistent-sidebar-layout-contract.sh`
- `test-persistent-sidebar-multi-client.sh`
- `test-keyboard-e2e-persistent-switch.sh`

recording adapter는 trace 문자열이 아니라 실제 요청 journal을 검증한다. Ready
switch 기대 목록은 target query/readiness와 `switch-client` 1회이며, forbidden
mutation이 하나라도 있으면 RED다.

### 알려진 test gap

- 기존 `test-window-local-contract.sh`는 attached client 없이 pane identity를
  비교하므로 실제 native switch contract를 단독 증명하지 못한다.
- 기존 multi-client contract는 linked-window 구조를 검증하지만 실제 PTY client
  두 개의 동시 입력/tty 격리를 증명하지 못한다.
- pane PID만으로 logical coordinator singleton을 증명할 수 없다. runtime ID,
  coordinator PID와 process start time을 함께 기록해야 한다.
- 일부 E2E는 p95 문구와 달리 적은 sample의 max를 출력하거나 threshold 초과를
  WARN으로 둔다. release hard gate와 diagnostic warning을 분리해야 한다.

## 점진적 migration

### M0 — Baseline/fitness

- RED: module sourceability, hot-path command journal, 문서 threshold 일치 검사.
- GREEN: 현 HEAD의 Gate A~E와 commit/transport/topology별 baseline을 고정한다.
- REFACTOR: 없음. production 변경을 섞지 않는다.

종료 조건: 현재 8개 Gate E journey와 archive v1/v2/v3 fixture가 재현 가능하다.

### M1 — Pure seam

- RED: reducer, stable identity, row mark, render diff, archive parse/validate unit.
- GREEN: 기존 함수 앞에 facade를 두고 순수 leaf부터 이동한다.
- REFACTOR: `main` guard/library mode와 explicit context를 도입한다.

종료 조건: domain test는 tmux/PTY 없이 실행되고 frame golden diff가 0이다.

### M2 — Port boundary

- RED: fake/real tmux port contract와 mutation allowlist.
- GREEN: direct tmux query/mutation을 typed port 뒤로 옮긴다.
- REFACTOR: control-mode 실험 adapter를 production CLI adapter와 격리한다.

종료 조건: application/service에서 raw `tmux` 호출과 범용 escape hatch가 0이다.

### M3 — Hot/cold split

- RED: Ready switch `switch-client=1`, topology mutation/provision/sleep=0.
- GREEN: provision/repair를 lifecycle operation으로 이동한다.
- REFACTOR: 246줄 switch transaction을 validate/publish/switch/confirm으로 분리한다.

종료 조건: A→B→C 100회에서 hot allowlist 위반 0, pane/geometry mismatch 0이다.

### M4 — Presenter extraction

- RED: unique window당 presenter 1개, reconnect snapshot 1회, 이후 delta.
- GREEN: 기존 window-local pane을 thin presenter facade로 바꾼다.
- REFACTOR: input/prompt/renderer/event loop와 signal intent 처리를 분리한다.

종료 조건: presenter에는 business/archive/tmux mutation 함수가 없다.

### M5 — Coordinator runtime spike/promotion

- RED: 동시에 20회 start해도 runtime 1개, stale endpoint recovery, protocol
  generation/idempotency/backpressure contract.
- GREEN: feature flag 뒤에 최소 coordinator + PresenterBus를 구현한다.
- REFACTOR: transport를 port 내부로 숨기고 mandatory dependency를 제거한다.

종료 조건: old/new behavior golden diff 0, runtime identity 변화 0, latency와 CPU가
현 baseline보다 나빠지지 않고 crash recovery가 bounded하다. 미달이면 feature flag를
기본 off로 유지하고 M1~M4의 모듈화 이득만 채택한다.

### M6 — Archive/lifecycle extraction

- RED: v1/v2/v3 round-trip, arbitrary topology, 6/6 restore, conflict/failure.
- GREEN: codec/store/transaction을 application service로 이동한다.
- REFACTOR: sidebar infrastructure와 work archive schema 결합을 제거한다.

종료 조건: external session 삭제 0, partial rollback과 history import idempotency PASS.

### M7 — Cutover/legacy removal

- old/new path를 동일 acceptance로 각 3회 연속 비교한다.
- coordinator flag를 기본 on으로 바꾼 뒤 한 release 동안 rollback flag를 유지한다.
- 호출자 0과 replacement contract를 확인한 후 legacy move controller와 기본-off
  control experiment를 제거한다.
- stale architecture/test 문서를 현재 계약으로 갱신한다.

한 단계에서 파일 대량 이동과 동작 변경을 동시에 수행하지 않는다.

## 정량 acceptance criteria

### 구조/기능

- coordinator count=1, runtime ID/PID/start time 변화 0: 동시 start 20회, session
  생성 20회, switch 100회 동안 유지.
- enabled 상태에서 unique managed window당 presenter 정확히 1개; duplicate/gap 0.
- linked window는 physical presenter 1개.
- normal switch의 presenter pane ID/PID/geometry와 work pane count/title/path/
  geometry/focus mismatch 0.
- 정상 switch: `switch-client=1`, spawn/provision/move/join/layout/resize/full render=0.
- selected marker, client session, target view generation 일치 100%; blank/partial 0,
  known error 0.
- create/rename/delete/toggle/split semantics, numeric session `0`, stale row 계약 유지.
- archive restore selected/restored 6/6, v1/v2/v3 read compatibility 유지.

### 성능

- release hard gate: 유효 attached-PTY sample의 key→stable complete frame이 모두
  **1000ms 이하**.
- 외부(non-sidebar) key→observable echo/action은 **100ms 이하**.
- topology별 최소 30회와 p50/p95/max/sample count를 기록하고 release 후보는
  suite별 3회 연속 통과한다.
- 500ms p95는 최적화 목표/경고로 유지하며 현재 release hard gate로 오기하지 않는다.

### failure/multi-client

- coordinator kill 후 1000ms 이내 singleton recovery, duplicate 0, 마지막 committed
  snapshot 복구.
- stale endpoint, malformed/partial/oversized frame, backpressure, missing presenter,
  switch failure가 source client/session/layout을 보존하고 1000ms 안에
  `Idle|Failed`로 수렴한다.
- 실제 PTY client 2개가 각각 50회 교차 전환할 때 cross-client switch 0,
  non-owner claim 0, owner identity 변화 0.
- busy archive/delete/restore 입력은 reject/drain되고 외부 session은 보존된다.

## Architecture fitness rules

CI가 다음 구조 회귀를 빠른 gate에서 막는다.

- domain/UI module의 raw `tmux` 호출 0
- application의 arbitrary command adapter 접근 0
- legacy `move-pane` controller 호출 0
- Ready switch recording journal의 forbidden mutation 0
- production module import 시 `main` 실행 0
- 설계·테스트의 공식 hard threshold는 1000ms/100ms로 일치
- 새 module의 public function과 상태 owner는 한 곳에서만 정의

LOC 자체를 품질 gate로 사용하지는 않지만, 함수가 50줄을 넘거나 두 port 이상을
직접 조정하면 책임 분리 review를 요구한다.

## 보존 invariant와 비목표

반드시 보존한다.

- `Ctrl+a s`, `|`, `_`, `%`, `"`, `n` 및 기존 TUI key semantics
- work pane만 split하는 정책과 direct layout metadata
- explicit owner client, non-owner 관찰 정책, operation idempotency
- managed-only bulk delete와 외부 session 보존
- archive v3 logical slot/title/geometry/focus와 v1/v2 호환
- atomic archive rename, duplicate history import 방지, failure rollback
- signal handler는 intent만 publish하고 tmux IPC/render를 직접 수행하지 않음

이번 설계의 비목표는 다음과 같다.

- 하나의 physical pane을 session 사이에서 이동시키기
- popup/전체 shared window로 docked sidebar UX를 대체하기
- 첫 단계에서 언어 재작성 또는 새 mandatory dependency 추가하기
- 검증 없이 control-mode를 production 기본값으로 승격하기
- 리팩터링과 archive schema 변경을 한 번에 수행하기

## 완료 정의

이 설계는 다음 조건을 모두 충족할 때 구현 완료다.

1. logical coordinator singleton과 window-local thin presenter가 runtime identity로
   증명된다.
2. application/domain/UI 책임이 typed port로 분리되고 hot/cold path가 코드와
   recording test에서 분리된다.
3. topology·archive·multi-client·failure·PTY acceptance가 각각 3회 연속 통과한다.
4. 전환 1000ms, 외부 키 100ms hard gate와 no-full-render/no-topology-mutation
   contract를 만족한다.
5. feature flag rollback을 검증한 뒤 legacy move path와 모순 문서를 제거한다.
