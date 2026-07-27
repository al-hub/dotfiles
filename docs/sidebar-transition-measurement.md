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

The test remains measurement-only and does not modify production behavior. The
P0 correctness gates remain the split-cycle, multi-window, arbitrary-topology,
and failure/rollback scenarios.

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

### 보조 진단

- `test-keyboard-e2e-switch-render-phase.sh`: phase와 one-render invariant 보조
- `test-keyboard-e2e-switch-render-cause.sh`: render 원인 미분류 회귀 확인
- `test-keyboard-e2e-switch-pty-render-measurement.sh`: 장시간 raw PTY baseline
- `test-keyboard-e2e-switch-correlation.sh`: 기존 phase correlation 보조/legacy
- `test-keyboard-e2e-switch-flicker-measurement.sh`: 기존 pane-buffer flicker 보조/legacy

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
