# v0.6.7 reproduction profile 개발 계획

## 목적

`tests/profile-isolated-sidebar-reproduction.sh`를 추가하여 `docs/reproduction.md`의 attached-client 재현 절차를 자동화한다. 기존 `tests/profile-isolated-sidebar-auto.sh`는 수정하지 않고 보관하며, 두 profile이 공통 metric을 출력하도록 하여 실행 결과를 정량 비교한다.

## 비교 원칙

- 전용 tmux socket과 attached URxvt를 사용한다.
- geometry는 양쪽 모두 `100x30`으로 고정한다.
- 공통 metric 이름, 단위, 측정 시작·종료 지점을 auto profile과 동일하게 유지한다.
- 기본 실행 횟수는 3회로 한다.
- 수치 비교는 평균보다 중앙값을 우선하고, 각 실행의 raw output과 outlier를 함께 기록한다.
- `capture-pane -e` 및 ESC 분석은 latency 측정과 분리하여 측정 오염을 방지한다.

## docs/reproduction.md 준수 항목

1. 실제 attached client의 tty를 `list-clients`로 조회한다.
2. 모든 외부 client 전환에 `switch-client -c "$client_tty"`를 사용한다.
3. pane title `dotfiles-session-sidebar`로 sidebar pane을 식별한다.
4. 선택 이동과 session 전환은 `send-keys`의 `j`, `k`, `Enter`로 수행한다.
5. 안정된 source session 전환 후 7초를 기다린다.
6. Enter session 전환 후 2초를 기다린다.
7. 전환 후 target session의 sidebar를 다시 검색한다.
8. target sidebar를 `capture-pane -e -p`로 캡처한다.
9. ANSI escape 개수와 plain-text cursor 상태를 별도 기록한다.
10. `>* target-session` cursor와 active session 정렬을 검증한다.

## 공통 정량 시나리오

auto profile과 비교하기 위해 다음 metric을 같은 형식으로 출력한다.

- idle CPU/RSS
- active CPU/RSS
- key-to-render latency
- Enter session switch latency
- archive latency/bytes
- restore latency/integrity
- `nav-01`→`nav-10` 하향 navigation 단계별 latency
- `nav-10`→`nav-01` 상향 navigation 단계별 latency
- 5-key burst latency
- periodic refresh 경계 입력 latency
- resize 결과
- lifecycle/layout 결과

## reproduction 전용 검증 결과

공통 metric과 별도로 다음을 출력한다.

- `REPRO_CLIENT_TTY`
- source/target session 및 sidebar pane
- `REPRO_ESC_COUNT`
- `REPRO_CURSOR_TARGET`
- `REPRO_CURSOR_COUNT`
- `REPRO_SWITCH_STABLE_MS`
- `REPRO_TARGET_STABLE_MS`

## 구현 단계

1. auto profile의 공통 측정 구조를 standalone reproduction profile에 구성한다.
2. attached URxvt와 client tty 검증을 추가한다.
3. `docs/reproduction.md`의 source→target 전환 절차를 별도 phase로 구현한다.
4. 공통 성능·lifecycle·navigation phase를 실행한다.
5. 정적 검사와 기능 profile을 실행한다.
6. 오류가 발생하면 원인별로 수정하고 동일 검증을 반복한다.
7. 3회 결과를 `tests/profile-reports/v0.6.7-reproduction.md`에 기록한다.
8. auto와 reproduction의 중앙값·편차·invariant를 비교한다.

## 실패 조건

- attached client를 찾지 못함
- client tty가 예상과 다름
- source 또는 target sidebar를 찾지 못함
- `switch-client -c` 후 client session이 예상과 다름
- target sidebar에 `>* target-session`이 없음
- cursor count가 1이 아님
- lifecycle 후 sidebar pane이 남음
- layout이 원상 복구되지 않음
- archive/restore integrity가 100%가 아님

## 최종 보고서

보고서에는 다음 표를 포함한다.

| Metric | auto median | reproduction median | delta | 판정 |
|---|---:|---:|---:|---|
| idle CPU |  |  |  |  |
| active CPU |  |  |  |  |
| key latency |  |  |  |  |
| session switch |  |  |  |  |
| archive |  |  |  |  |
| restore |  |  |  |  |
| navigation |  |  |  |  |
| ESC/cursor invariant |  |  |  |  |

결과 해석에서는 auto와 reproduction의 측정 목적 차이, 안정화 대기 비용, attached client 및 ANSI capture의 영향을 분리하여 기록한다.

## 리뷰 및 버전 관리

- 기존 auto/navigation test는 수정하지 않는다.
- 계획서, 신규 profile, 결과 report, HISTORY/CONVERSATION만 변경한다.
- 사용자 리뷰가 완료되기 전에는 commit, tag, push를 실행하지 않는다.

## 현재 진행 결과

- standalone reproduction profile 구현 완료
- `switch-client -c`, source/background client 재확인, 실제 source/target 안정화 시간, target sidebar 재검색 구현 완료
- `capture-pane -e`와 ESC/cursor 검증 구현 완료
- sidebar pane title을 `TMUX_PANE`에 명시적으로 적용하도록 launcher를 보완해 duplicate sidebar false positive를 제거했습니다.
- launcher Enter 전환도 attached client를 찾으면 `switch-client -c`를 사용하도록 보완했습니다.
- source/target sidebar count와 capture 시점 client session을 검증합니다.
- before-enter, immediate-after-enter, settled cursor frame과 source/target pane ID·PID를 기록합니다.
- TERM/SHELL/locale/DISPLAY/tmux config metadata를 기록하고 `PROFILE_KEEP_RUN_DIR=true`로 raw capture artifact를 보존할 수 있습니다.
- auto와 reproduction 각각 3회 실행 완료
- 두 profile의 공통 metric 및 invariant 비교 report 작성 완료
- 최종 reproduction 3회와 기존 auto 3회는 모두 PASS입니다.
- immediate-after-enter에서는 target cursor가 아직 0/1이고 settled frame에서 1/1로 회복되는 transient frame을 3/3 확인했습니다.
- 현재 상태는 사용자 리뷰 대기이며 commit/tag/push를 실행하지 않음

## 보완 구현 및 최종 측정

- reproduction profile의 tmux 호출에 저장소 `dotfiles/tmux.conf`와 전용 임시 HOME을 명시했습니다.
- 초기 sidebar 생성은 직접 `split-window`가 아니라 `tmux-session-launcher --open-sidebar` 토글 명령을 사용합니다. 이는 `Ctrl+a s` binding이 호출하는 동일 launcher 경로이며, tmux API로 attached client의 prefix parser에 키를 주입할 수 없는 환경 제약을 기록합니다.
- archive 측정은 `-pending.tsv`가 아닌 최종 `-[window]w.tsv`가 생성되고 크기가 안정될 때 종료하도록 수정했습니다.
- 최종 3회 reproduction 실행은 모두 PASS했습니다. 중앙값은 idle CPU 15.96%, active CPU 15.11%, key 54ms, session switch 301ms, archive 345ms, restore 491ms입니다.
- 최종 3회에서 cursor count 1, source/target sidebar count 1, client session alignment, lifecycle/layout, archive/restore integrity가 모두 PASS했습니다.
- navigation 중앙값은 하향 nav-02~10이 54/60/68/68/60/60/57/61/60ms, 상향 nav-09~01이 58/67/63/91/63/56/66/56/62ms입니다. 하향 nav-04, nav-03 및 상향 nav-08에서 1.2초대 outlier가 각각 1회 관찰됐습니다.

## 리뷰 전 남은 편차

- 물리적인 URxvt `Ctrl+a s` 입력 자체를 주입하지 못하고, 동일 launcher toggle 명령으로 sidebar를 엽니다.
- mouse/focus/실제 terminal resize event는 생성하지 않습니다.
- ANSI ESC count는 기록만 하며 0을 실패로 판정하지 않습니다.
- capture polling 기반 key latency와 navigation outlier의 원인은 별도 pipe observer/trace 분석이 필요합니다.
- 사용자가 검토하기 전에는 commit, tag, push를 하지 않습니다.
