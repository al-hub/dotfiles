# Sidebar session transition measurement

## 2026-07-27 - measurement gate correction

The multi-pane visual-layer scenario no longer treats “one geometry value for the
whole run” as a success condition. Different target sessions are allowed to have
different sidebar geometry. Each target now records its expected geometry after
its layout metadata is established, and every sampled row compares the observed
geometry with the expectation for the sampled session.

The scenario also records a raw PTY artifact and per-transition summary containing
output offsets, byte count, full-screen-clear count, and cursor-home count. A
pane-buffer `blank` or `partial` row is diagnostic only; it becomes a RED result
only when sidebar identity or target-specific geometry is incorrect. Raw output
must be correlated before claiming a user-visible redraw discontinuity.

The canonical P1 test requests 10 transitions by default; `VISUAL_TRANSITIONS`
can override it. Each transition compares target geometry and pane signature with
its fixture manifest. The normal profile is 3 repeated runs of 10 transitions;
the 6-transition profile is a smoke run.

The latest single 10-transition profile recorded:

```text
172 samples: blank=0 partial=0 complete=172
sidebar identities=1 geometry mismatches=0 stable geometry mismatches=0
pane mismatches=33 stable pane mismatches=0 phase missing=0
latency p50=4089 ms p95=4269 ms
phase Ttotal p50=3821213 us p95=4019317 us
```

The 33 pane mismatches occurred only in transition samples; stable rows matched
the target manifest. They remain WARN evidence for intermediate redraw/layout
activity, not final topology failure.

## 2026-07-27 structural transition implementation

The transition path now has three structural safeguards:

- readiness polling is observation-only; it no longer repeats `switch-client` or
  `select-pane` while waiting;
- pane movement uses detached `move-pane`, avoiding an intermediate focus change;
- transition state remains `COMMIT`/`committed` until the single render completes,
  so the observable phase order is `COMMIT → RENDER_ONCE → READY`.

During a running/committed transition, layout/focus/active-window hooks defer
instead of reapplying layout. Deferred metadata is flushed once after success.

The first 10-transition post-change profile recorded 185 samples, blank/partial
0, stable geometry mismatch 0, stable pane mismatch 0, phase missing 0, and
Ttotal p50/p95 of 3.233/3.719 seconds. Transition pane mismatch remained 32
WARN samples, so the structural change improved the observer latency but did not
yet prove that all user-visible intermediate redraw has been eliminated.

The test remains measurement-only and does not modify production behavior. The
P0 correctness gates remain the split-cycle, multi-window, arbitrary-topology,
and failure/rollback scenarios.

## 2026-07-28 incremental sidebar render implementation

Normal session switching now uses `render_transition_delta()` after the tmux
topology transition. It redraws only the source/target session rows and records
`RENDER_DELTA`; `render_full()` remains the recovery path for an invisible row,
geometry change, topology change, or explicit full refresh.

The existing render-phase/cause/correlation tests treat delta and full render as
one logical transition render, while the strict sidebar-fixed test rejects any
normal full render. A three-transition attached-PTY smoke run recorded:

```text
sidebar_id_changes=0 sidebar_geometry_changes=0 sidebar_hash_changes=0
blank_frames=0 partial_frames=0 work_signature_mismatches=0
full_render_calls=0 latency_p50=3768ms latency_p95=3785ms
sidebar_move_p95=1218368us client_switch_p95=163966us total_metrics_p95=2370751us
```

The redraw contract is improved and the full sidebar repaint is removed, but
the latency target is not yet met. The latest 10-transition profile recorded:

```text
full_render_calls=0 latency_p50=3427ms latency_p95=3531ms
sidebar_move_p95=1149961us client_switch_p95=178963us total_metrics_p95=2212421us
```

The remaining delay is concentrated in the
tmux sidebar move/layout and readiness settlement path, not in the sidebar
renderer.

The target-layout fault injection is now placed at the real target layout
restore/capture boundary. `move`, `client-switch`, `restore-layout`, and
`transition` failure profiles all preserve sidebar identity/geometry and owner
client state.

## 실행 계층과 판정 기준

### P0 correctness Gate

다음 테스트는 구조 정합성의 필수 회귀다.

- horizontal/vertical split-cycle
- multi-window topology
- arbitrary topology archive/restore
- metadata/failure-injection rollback
- single-sidebar contract

각 전환은 sidebar identity 중복 0, target expected geometry 일치, pane 수와
logical metadata 보존, active focus 보존, 그리고 정상 `READY` 또는 명확한
`ROLLBACK/FAILED`를 만족해야 한다.

### P1 canonical redraw diagnostic

`test-keyboard-e2e-switch-visual-layer-measurement.sh`가 사용자 체감 redraw의
기준 테스트다. 실제 Enter 전환마다
`visual-transition-samples.tsv`, `visual-transition-raw.tsv`,
`visual-transition-phases.tsv`를 생성한다. samples에는 target expected
  geometry와 semantic pane signature 비교 결과가 포함된다. transition row와
  stable row를 분리해 중간 redraw와 최종 복원 실패를 구분한다.

phase artifact는 다음을 기록한다.

```text
T1 = Enter → PREPARE
T2 = PREPARE → RESTORE_FOCUS
T3 = RESTORE_FOCUS → RENDER_ONCE
T4 = RENDER_ONCE → READY
Ttotal = Enter → READY
```

각 값은 p50/p95로 출력하며 raw byte 수와 함께 보관한다. 현재 observer latency는
tmux/PTY settlement를 포함하므로 절대 성능 목표가 아니라 동일 fixture baseline
대비 20% 이상 증가하는 회귀 판정에 사용한다.

blank/partial `capture-pane` sample은 단독 RED가 아니다. raw PTY 구간과
operation phase에 연결되고 target geometry 불일치 또는 READY 이후 미복구가
함께 확인될 때만 RED이며, 그 외에는 WARN이다.

### 2026-07-30 operation correlation 보강

visual-layer 측정은 이제 trace와 metrics를 같은 run ID로 활성화하고, 각 전환을
`transition.begin`의 operation ID로 연결한다. `visual-transition-phases.tsv`에는
다음 항목이 추가된다.

- `render.request_count`, `render_full_count`, `render_delta_count`
- `transition.finish` 결과와 transition 중 오류 marker 수
- monotonic microsecond 기준 Enter 시각, phase 시각, raw PTY byte 범위

native 전환에서 실제로 필요한 최소 invariant는
`VALIDATE_TARGET`, `SWITCH_CLIENT`, `VERIFY_CLIENT`, `RENDER_DELTA 또는 RENDER_ONCE`,
`READY`, 성공 `transition.finish` 각각의 operation 귀속이다. archive-era
`SNAPSHOT`/`MOVE_SIDEBAR`/`RESTORE_LAYOUT` phase가 없다는 이유로 해당 전환을
오류로 분류하지 않는다. 반대로 operation ID·READY·finish 결과가 없거나 한
전환에 render 경로가 0개 또는 2개 이상이면 `missing_or_ambiguous`로 RED한다.

이 구분으로 다음을 분리할 수 있다.

| 관측 결과 | 해석 |
| --- | --- |
| delta 1회, full 0회 | sidebar 유지형 정상 render 후보 |
| full 1회, delta 0회 | geometry/visibility fallback 후보 |
| full+delta 2회 이상 | 중복 render/refresh 후보 |
| operation 없음 또는 finish/READY 없음 | 관측 경계 또는 실제 전환 실패; PASS 금지 |
| raw PTY 오류와 trace 오류 marker 동시 존재 | 사용자 오류 메시지와 production 원인 연결 |

`metrics.log`는 launcher의 render/switch duration을 별도로 보존한다. private
attached-PTY 실행은 raw byte offset과 함께 이 파일을 남기며, user-server 실행은
raw PTY를 소유하지 않으므로 오류 부재를 판정하지 않고 `INCONCLUSIVE`로 기록한다.

## 2026-07-30 structural production change

`feature/single-sidebar`의 production path를 global single-sidebar model로
전환했다. session 생성은 새 session window마다 sidebar를 provision하거나
모든 managed window를 기다리지 않고, 현재 sidebar process의 model refresh만
수행한다. session 전환은 target-local sidebar를 찾지 않고 기존 pane을
`move-pane`으로 이동한 뒤 client를 전환한다.

private attached-PTY 결과:

```text
session create row: average 701ms, maximum 766ms
raw PTY switch: 3/3 completed, full clear=0, delta render path observed
multi-pane correlation: operation finish=success, render_delta=1, render_full=0
```

single-work-pane transition은 약 0.8~1.1초로 감소했지만 500ms 목표에는 아직
미달이다. 남은 시간은 tmux pane move/client hook settlement 경계에 집중되어
있으며 후속 최적화 대상으로 남긴다.

사용자 tmux live 검증은 기존 설치 hook과 현재 branch runner가 동시에 provision하는
환경 race 때문에 duplicate sidebar를 재현했다. 이는 current checkout 기능 결과와
분리해 `LIVE-HARNESS-INCONCLUSIVE`로 분류하며, runner는 hook 설치/cleanup 경계를
명시적으로 정리해야 한다.

### 보조 진단

- `test-keyboard-e2e-switch-render-phase.sh`: phase와 one-render invariant 보조
- `test-keyboard-e2e-switch-render-cause.sh`: render 원인 미분류 회귀 확인
- `test-keyboard-e2e-switch-pty-render-measurement.sh`: 장시간 raw PTY baseline
- `test-keyboard-e2e-switch-correlation.sh`: 기존 phase correlation 보조/legacy
- `test-keyboard-e2e-switch-flicker-measurement.sh`: 기존 pane-buffer flicker 보조/legacy

### Sidebar fixed/work-only contract

`test-keyboard-e2e-sidebar-fixed-work-switch.sh`는 sidebar 영역과 work 영역을
분리해 strict 고정 계약을 측정한다. 실제 attached PTY에서 서로 다른 2/3/4-pane
topology를 가진 세 session을 `A → B → C → A`로 전환하며, 전환 sample마다
sidebar pane ID/PID/geometry, canonical sidebar structural hash, blank/partial
frame, target work signature, raw PTY bytes와 `render.full.begin` 수를 기록한다.

선택 marker와 session age/status는 정상적으로 변하므로 session row identity만
남기도록 canonicalize한다. 반면 sidebar identity/geometry/hash/frame과 full
render 호출은 엄격히 판정하고, work signature는 stable target sample에서만
expected topology와 비교한다.

현재 기본 10-transition 실행 결과는 다음과 같다.

```text
sidebar_id_changes=0 sidebar_geometry_changes=0 sidebar_hash_changes=0
blank_frames=0 partial_frames=0 work_signature_mismatches=0
full_render_calls=10 latency_p50=3731ms latency_p95=5109ms
```

따라서 pane identity/geometry와 최종 work topology는 안정적이지만, 매 전환
sidebar를 포함한 `render.full`이 발생해 strict sidebar 고정 계약은 RED다.
이 테스트는 production 동작을 수정하지 않고 위반 지점을 정량적으로 고정한다.

metrics가 활성화된 실행은 `sidebar-fixed-metrics.log`와
`sidebar-fixed-timing.tsv`에 operation ID별 `sidebar_move_us`,
`client_switch_us`, `final_force_refresh_us`, `total_us`를 보존한다. 최근 smoke
실행에서 `sidebar_move_us` p95는 약 1.16초, `client_switch_us` p95는 약
0.14초, transition metrics `total_us` p95는 약 2.17초였다. 전체 latency와
launcher switch metrics의 차이는 readiness/render/PTY settlement 구간으로
분리해 후속 분석할 수 있다.

`test-keyboard-e2e-sidebar-fixed-work-failure.sh`는 `move`, `client-switch`,
`transition` fault injection에서 sidebar identity/geometry, client session,
rollback/FAILED phase를 PASS로 확인한다. `restore-layout` fault injection은
target client로 전환된 뒤 rollback이 기록되지 않는 RED side-effect를 재현한다.
이 결과는 failure path의 layout restore 순서가 아직 안전하지 않다는 기준선이다.

## 목적

사용자가 sidebar에서 방향키로 session을 선택하고 Enter를 누를 때 전체 화면,
sidebar layer, pane identity, geometry의 변화를 production 코드 변경 없이 측정한다.

## 현재 관측 결과

pane-buffer 측정은 실행마다 결과가 달랐다. 한 실행에서는 불완전 frame 1회가
관측됐고, 재실행에서는 0회였다. 따라서 이 방식만으로 사용자가 느끼는 지속적인
redraw를 판정할 수 없다.

raw PTY 측정에서는 완료된 전환 구간에서 다음 특성이 관측됐다.

- 전환당 약 22~25KB의 terminal output
- 전환당 약 25~32회의 cursor-home sequence
- ESC[2J 전체 화면 clear는 0회
- 일부 반복 실행은 모든 전환을 완료하지 못하고 session switch 검증이 중단됨

추가 correlation 측정에서는 10회 전환 모두 다음 phase를 통과했다.

- input 전송 후 switch.begin 연결
- sidebar move begin/end: 10/10
- client switch begin/end: 10/10
- force refresh begin/end: 10/10
- switch end: 10/10
- switch abort: 0회

10회 raw PTY 측정에서는 다음 결과가 나왔다.

- 전체 clear count: 0
- cursor-home count: 265회
- cursor 1,1 home count: 276회
- 전환 완료: 10/10

render/debug correlation 10회에서는 다음 결과가 나왔다.

- render_full begin/end: 20/20
- input.read.result: 20회
- switch.abort: 0회
- sidebar hook sync: 0회
- sidebar layout restore begin: 9회

정상 완료된 단순 session 전환에서 전환당 render_full이 평균 2회 발생한 것이
확인됐다. 따라서 현재 사용자가 느끼는 redraw는 PTY 입력 실패보다 session
전환 과정의 중복 render/refresh 경로와 더 강하게 연관된다. hook sync는 발생하지
않았으므로 단순 session 전환에서는 active-window hook 중복 실행을 우선 원인에서
제외한다.

추가 render phase correlation 4회에서는 render_full 4회, force-refresh 4회,
layout restore 3회, unclassified render 0회가 관측됐다. 전환별 render_full은
전환당 1회로 감소했고 raw PTY output 합계는 92,568 bytes였다.

더 세밀한 cause correlation은 별도 sampler가 5ms 간격으로 trace/debug 파일의
증가를 관찰하고, 각 `render_full start`를 trace의 관찰 전후 phase와 연결한다. 이때
`enter-dispatch`, `force-refresh`, `layout-restore`, `full-render-required`,
`periodic-refresh`, `unclassified`를 전환별 TSV로 저장한다. `cause_pre`와
`cause_observed`가 다르면 trace/debug 파일 flush 순서로 인해 단일 원인으로
확정할 수 없는 `ambiguous` 관측으로 남기고 테스트를 RED로 판정한다. debug 로그의 초 단위 시각만으로
줄을 맞추지 않고 관찰 시점의 trace line boundary와 raw artifact를 함께 남기는
것이 핵심이다.

render reason marker 적용 후 4회 실행에서는 전환 4/4, `render_full` 4회,
`enter-dispatch` 4회, ambiguous 0회, unclassified 0회가 관측됐다. 따라서
각 전환의 render가 `enter-session-switch` 요청으로 단일 연결되며, 이전의
trace/debug flush 순서에 의한 원인 판정 ambiguity가 제거됐다.

추가 보조 검증에서는 rapid operation 3회 반복, flicker sample 176회,
raw PTY 20회가 PASS했다. raw PTY 20회에서도 전체 clear는 0회였고
cursor-home 544회가 관측됐다. 반면 mouse selection은 target session 전환에
실패했고, visual-layer topology 테스트는 session 전환 timeout 뒤 server 종료로
RED가 됐다.

따라서 정상 완료되는 단순 topology 전환에서는 PTY 경계 단절보다 대량 cursor
redraw가 일관된 관측값이다. 다만 multi-pane topology에서의 server 종료와
20회 이상 장시간 반복 안정성은 별도 미해결 항목이다.

현재 증거상 전체 화면 clear 후 복원보다는 session 전환 때 sidebar와 work 영역에
대량의 cursor 기반 redraw가 순차적으로 발생하는 가능성이 높다. 다만 PTY 전환이
중간에 중단되는 별도 안정성 문제가 있어 두 문제를 분리해 후속 분석해야 한다.

## 측정 시나리오

1. 전용 tmux socket과 임시 HOME으로 attached PTY를 시작한다.
2. sidebar에서 pty-a, pty-b session을 생성한다.
3. pty-a를 선택한다.
4. 방향키와 Enter를 실제 PTY 입력으로 전송해 두 session을 반복 전환한다.
5. 각 전환마다 Enter 직전과 sidebar readiness 이후의 PTY output offset을 기록한다.
6. offset 사이의 raw terminal output을 전환별 artifact로 분리한다.

## 측정 항목

- raw output bytes
- ESC[2J 전체 화면 clear count
- cursor-home count
- sidebar pane ID와 geometry
- BLANK, PARTIAL, COMPLETE frame 분류
- Enter부터 target session/sidebar ready까지의 시간

## 테스트 파일

- tests/tmux-single-sidebar/test-keyboard-e2e-switch-flicker-measurement.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-correlation.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-phase.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-render-cause.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-pty-render-measurement.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-visual-layer-measurement.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-sidebar-fixed-work-switch.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-sidebar-fixed-work-failure.sh

측정 전용 테스트는 production launcher/controller 동작을 monkey-patch하지 않는다.
측정 실패 시 raw output과 전환별 TSV artifact를 보존해 재분석할 수 있도록 한다.

## 판정 보류 항목

- raw PTY 측정을 20~50회 안정적으로 완료하는지
- bridge와 script transport에서 correlation 결과가 동일한지
- 각 전환에서 PARTIAL frame이 항상 발생하는지
- cursor redraw가 sidebar pane 내부인지 전체 window layout인지
- session switch 중단이 topology 복원 문제인지 PTY 입력 경계 문제인지
- render cause 후보가 trace/debug 파일 관찰 순서에 의해 잘못 분류될 가능성
- render reason marker가 누락된 비-session-switch 경로의 원인 분류
- `test-contract.sh`의 `--open-sidebar` toggle 관측 경계는 보강 후 PASS

## 2026-07-27 transition coordinator baseline

session 전환은 production launcher에서 operation ID와 명시적 phase를 갖는
transaction으로 관측한다. 현재 phase 계약은
`PREPARE → SNAPSHOT → MOVE_SIDEBAR → SWITCH_CLIENT → RESTORE_LAYOUT →
RESTORE_FOCUS → COMMIT → RENDER_ONCE → READY`이며, 실패 시
`ROLLBACK → FAILED`를 기록한다. snapshot에는 source/target layout, sidebar
pane identity/geometry, owner client 상태가 함께 남는다.

`test-keyboard-e2e-switch-render-phase.sh`는 실제 attached PTY Enter 입력마다
phase가 하나의 operation ID로 연결되고, render_full이 정확히 한 번 발생하는지
검증한다. 전환 latency와 phase별 T1~Ttotal은 canonical visual-layer 테스트의
TSV에서 p50/p95(ms/us)로 기록한다. blank/partial frame은 raw correlation과
최종 geometry/READY 상태를 함께 확인한 뒤 RED 또는 WARN으로 분류한다.
이는 render 호출 수가 정상이어도 사용자에게 보이는 layer 복원이 불연속적일 수
있음을 분리해서 판정하기 위한 기준이다.

## 2026-07-27 observation-boundary reinforcement

- interactive 공통 helper에 trace wait, sidebar stable wait, timeout artifact
  보존을 추가했다.
- mouse 테스트는 실제 SGR byte가 `input.log`까지 도달하는지와
  `mouse.select.target` dispatch를 분리해 관측한다. 현재 byte 전달은 확인되지만
  tmux mouse binding/launcher dispatch는 발생하지 않아 RED다.
- visual-layer 테스트는 topology fixture를 전용 tmux 명령으로 고정하고,
  session 선택·Enter 전환과 raw PTY 관측만 사용자 입력 경계로 유지한다.
  target별 expected geometry를 비교하므로 서로 다른 정상 geometry를 오류로
  판정하지 않는다. 최신 6회 실행은 102개 sampled row에서 blank/partial 0,
  sidebar identity 1, geometry mismatch 0으로 완료됐다.
- multi-client conflict 테스트는 worker 시작 trace와 외부 client 출현을
  동기화하고, owner 정책으로 target session을 유지하지 못하면 timeout 대신
  `INCONCLUSIVE`로 분류한다.
- sidebar toggle contract는 고정 sleep 대신 sidebar count readiness를 기다리며
  remove/recreate 검증이 PASS했다.
# 2026-07-30 production phase optimization result

## 최신 측정

현재 branch의 production 전환은 다음 경계를 기록한다.

- `validate`: 약 25~44ms
- `move-pane`: 약 0.24~0.29초
- `switch-client`: 약 0.10~0.21초
- `refresh-queue`: 약 0.07~0.16초
- 전체 `transition.finish`: 약 0.63~0.86초
- 성공 전환 `render_full`: 0회
- 성공 전환 `render_delta`: 1회
- sidebar pane identity 변경: 0회

최신 user live 6회는 Enter 이후 736~911ms였고 target 변경 6/6, duplicate
sidebar 0, identity 변경 0, known error 0이었다. session 생성 3회는
667~997ms였다.

반복 tmux 조회와 transition 중 hook 재진입은 보강으로 줄였지만 500ms
acceptance는 아직 통과하지 못했다. 다음 production 개선은 `move-pane`와
switch-client/refresh 경계를 별도 최적화 대상으로 다뤄야 한다.

## 테스트 harness 보정

user live runner는 sidebar 폭에서 잘리는 session 이름을 사용하지 않으며,
selection 이동 완료 후 Enter 직전부터 switch latency를 측정한다. 따라서
row navigation 시간과 production session switch 시간을 혼합하지 않는다.

## Control-mode 경계

FIFO-backed persistent control-mode adapter의 전용 socket query 테스트는
통과했지만, 실제 pane 이동 후 tmux control client가 `%sessions-changed`와
`%exit`를 발생시켜 후속 session/client context를 오염시켰다. 현재
`TMUX_SESSION_SIDEBAR_CONTROL_MODE` 기본값은 `false`이며 CLI adapter가
기본 production 경로다. control-mode를 승격하려면 사용자 session과 분리된
dedicated internal control session/client 및 event isolation을 추가해야 한다.
