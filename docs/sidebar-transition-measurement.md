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
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-pty-render-measurement.sh
- tests/tmux-single-sidebar/test-keyboard-e2e-switch-visual-layer-measurement.sh

모든 테스트는 production launcher/controller를 수정하지 않는다. 측정 실패 시
raw output과 전환별 TSV artifact를 보존해 재분석할 수 있도록 한다.

## 판정 보류 항목

- raw PTY 측정을 20~50회 안정적으로 완료하는지
- 각 전환에서 PARTIAL frame이 항상 발생하는지
- cursor redraw가 sidebar pane 내부인지 전체 window layout인지
- session switch 중단이 topology 복원 문제인지 PTY 입력 경계 문제인지
