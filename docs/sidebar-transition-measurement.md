# Sidebar session transition measurement

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

추가 render phase correlation 4회에서는 render_full 8회, force-refresh 4회,
layout restore 3회, unclassified render 0회가 관측됐다. 전환별 render_full은
모두 phase에 연결됐고 raw PTY output 합계는 87,029 bytes였다.

더 세밀한 cause correlation은 별도 sampler가 5ms 간격으로 trace/debug 파일의
증가를 관찰하고, 각 `render_full start`를 trace의 관찰 전후 phase와 연결한다. 이때
`enter-dispatch`, `force-refresh`, `layout-restore`, `full-render-required`,
`periodic-refresh`, `unclassified`를 전환별 TSV로 저장한다. `cause_pre`와
`cause_observed`가 다르면 trace/debug 파일 flush 순서로 인해 단일 원인으로
확정할 수 없는 `ambiguous` 관측으로 남기고 테스트를 RED로 판정한다. debug 로그의 초 단위 시각만으로
줄을 맞추지 않고 관찰 시점의 trace line boundary와 raw artifact를 함께 남기는
것이 핵심이다.

최초 4회 실행에서는 전환 4/4가 완료됐고 `render_full` 9회가 관측됐다.
미분류는 0회였지만 `ambiguous`가 2회 발생해 테스트는 RED였다. 따라서 현재
자료만으로는 각 render의 정확한 단일 호출 원인을 확정할 수 없으며, 이 결과는
debug 로그의 정밀 timestamp 또는 render 전용 correlation marker가 추가로
필요하다는 근거로 기록한다.

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

모든 테스트는 production launcher/controller를 수정하지 않는다. 측정 실패 시
raw output과 전환별 TSV artifact를 보존해 재분석할 수 있도록 한다.

## 판정 보류 항목

- raw PTY 측정을 20~50회 안정적으로 완료하는지
- bridge와 script transport에서 correlation 결과가 동일한지
- 각 전환에서 PARTIAL frame이 항상 발생하는지
- cursor redraw가 sidebar pane 내부인지 전체 window layout인지
- session switch 중단이 topology 복원 문제인지 PTY 입력 경계 문제인지
- render cause 후보가 trace/debug 파일 관찰 순서에 의해 잘못 분류될 가능성
