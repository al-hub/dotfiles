# v0.6.10 archive/restore 목표 달성 계획

## 현재 기준

v0.6.9 reproduction 기준:

| Metric | 현재 sample | 목표 |
|---|---:|---:|
| idle/active CPU | 16%대 | ≤8% |
| key latency | 46~50ms | ≤45ms |
| session switch | 483~627ms | ≤180ms |
| archive | 322~345ms | ≤250ms |
| restore | 418~510ms | ≤300ms |
| periodic navigation | 68~77ms | ≤150ms p95, max <500ms |

## 1차 목표

이번 반복은 archive/restore 경로를 우선합니다.

- archive ≤250ms
- restore ≤300ms
- archive/restore/layout/cursor/lifecycle invariant 100%
- key/navigation 성능 악화 없음

CPU와 session switch는 별도 반복으로 계속 추적합니다.

## 세부 계측

### Archive

```text
run-shell dispatch
→ archive script start
→ pane/window snapshot
→ archive file write 완료
→ atomic final rename
→ session kill 완료
```

### Restore

```text
restore key dispatch
→ archive parse/history append
→ session/window/pane 생성
→ layout 적용
→ sidebar split 및 launcher startup
→ client/session/cursor/integrity settlement
```

측정부 polling 시간과 제품 내부 실행 시간을 별도 기록합니다.

## 구현 후보

1. archive file observer의 불필요한 고정 sleep 제거
2. archive snapshot에서 중복 `list-panes`/`show-option` 호출 제거
3. restore history append를 복원 후 maintenance로 분리
4. restore pane/layout 생성 명령 수 최소화
5. restore 후 sidebar direct-open 경로 유지
6. session switch와 full refresh를 분리

각 후보는 하나씩 적용하고 기능 invariant를 즉시 검사합니다.

## 검증 순서

```sh
bash -n scripts/tmux-session-launcher
bash -n tests/profile-isolated-sidebar-reproduction.sh
bash tests/tmux-sidebar-gradient/run.sh
bash tests/profile-isolated-sidebar-reproduction.sh
git diff --check
```

3회 smoke에서 목표를 만족하면 10회, 최종 승격 판단은 30회로 확대합니다. 미달이면 가장 오래 걸린 구간만 다음 계획으로 넘깁니다.

## 승격 원칙

- 목표와 invariant를 모두 만족하기 전에는 v0.6.10 승격/tag/commit/push를 하지 않습니다.
- 측정부 polling을 줄인 경우 제품 내부 시간과 외부 관측 시간을 함께 기록합니다.
- 기능 회귀가 발생하면 성능 수치보다 회귀 원인 해결을 우선합니다.

## 1차 실행 결과

- `append_archive_history`를 조건부 mkdir과 `sed` 기반 append로 변경했습니다.
- 전체 sidebar regression/lifecycle suite는 PASS했습니다.
- archive phase: dispatch 218ms, file ready 336ms, total 345ms.
- restore phase: history append 94ms, dispatch 159ms, session settlement 385ms, total 437ms.
- idle/active CPU 16.66/16.73%, key 59ms, switch 294ms, periodic navigation 66ms입니다.
- restore는 개선됐지만 300ms, archive는 250ms 목표에 미달했습니다.
- 다음 수정 범위는 archive/delete 사전 tmux 호출 통합과 restore session 전환·pane 생성 병합입니다.
- delete wrapper의 session/client/fallback snapshot 통합은 lifecycle-e2e에서 AI exit state 회귀를 발생시켜 원복했습니다.
- 해당 통합은 성능 후보에서 제외하고, archive 본체와 restore settlement를 독립적으로 최적화합니다.

추가 검증:
- target pane을 명시한 상태에서 `sidebar 생성 → client 전환` 순서를 재시험했습니다.
- restore session settlement 495ms, total 562ms로 악화되어 해당 순서는 채택하지 않고 원복했습니다.
- lifecycle-e2e와 launcher lifecycle은 PASS했으며, direct-open/history append 변경만 유지합니다.

## 2차 실행 결과 및 다음 반복

- animation/poll 주기를 500ms로 늘리는 통제 실험은 idle CPU 15.46%, active CPU 15.96%로 목표를 달성하지 못했습니다.
- 해당 실험에서는 reproduction 후반이 안정적으로 완료되지 않아 제품 변경으로 채택하지 않고 기본 주기로 원복했습니다.
- archive pane snapshot을 window마다 반복 파싱하지 않고 session당 한 번 집계하는 내부 최적화를 적용했습니다.
- regression suite 10/10과 정적 검사는 PASS했습니다.
- reproduction 단일 실행은 key 52ms, idle/active CPU 16.16/16.78%까지 기록했으나 후반 lifecycle 완료가 불안정해 archive/restore 승격 수치로 사용하지 않습니다.
- 따라서 v0.6.10 목표는 아직 미달입니다.

다음 반복 계획:

1. profile lifecycle 조기 종료 원인을 먼저 재현 로그와 보존 run directory로 분리합니다.
2. archive 단일 snapshot 최적화가 archive 파일 내용과 restore invariant를 유지하는지 독립 fixture로 검증합니다.
3. archive/restore가 안정화된 뒤에만 3회 reproduction 중앙값을 다시 산출합니다.
4. CPU는 Bash timed-read 자체와 animation 렌더를 별도 계측으로 분리하며, interval 조정은 key/gradient invariant가 확인된 경우에만 재검토합니다.

## 3차 실행 결과 및 재계획

- idle read timeout 500ms 실험은 idle/active CPU 25.19/24.63%로 악화되어 즉시 원복했습니다.
- archive history append를 외부 `sed`에서 Bash builtin loop로 변경했습니다.
- regression suite 10/10과 정적 검사는 PASS했습니다.
- 재측정은 idle/active CPU 15.98/15.46%, key 48ms까지 기록했으나 attached-client 후반 단계가 조기 종료되어 archive/restore 결과는 승격용으로 채택하지 않습니다.
- 유효한 이전 reproduction 기준 archive 370ms, restore 436ms이며 목표 250/300ms에는 여전히 미달입니다.

다음 반복 계획:

1. profile script 자체의 attached-client 정리 충돌을 launcher 측정과 분리해 재현합니다.
2. archive/restore fixture를 독립 실행해 제품 결과와 측정부 종료 문제를 분리합니다.
3. restore startup에서 `switch-client`, `set-option`, `list-panes`, `open_sidebar` 각 명령의 내부 elapsed를 trace합니다.
4. 3회 완주한 동일 조건 중앙값이 확보되기 전에는 추가 성능 최적화를 승격하지 않습니다.

## 4차 실행 계획

목표 미달의 직접 원인을 추정하지 않도록 restore 내부를 다음 단계로 trace합니다.

- archive history append
- archive pane/window 복원
- active window 선택
- client 전환
- force-refresh option 설정
- restore target pane 탐색
- sidebar startup

trace가 비활성화된 일반 실행의 동작과 비용은 변경하지 않습니다. trace를 포함한 1회 진단 후 가장 오래 걸린 단일 구간만 다음 반복에서 최적화합니다.

## 4차 실행 결과

- restore sidebar startup을 `tmux run-shell -b`로 비동기 dispatch하는 실험을 적용했습니다.
- 전체 regression/lifecycle 10/10 및 정적 검사는 PASS했습니다.
- 1회 reproduction 결과: idle 16.55%, active 17.43%, key 51ms, switch 370ms, archive 345ms, restore 476ms입니다.
- 직전 유효 sample 대비 restore는 499ms에서 476ms로 개선됐지만, restore 300ms와 CPU/key/switch 목표는 여전히 미달입니다.
- 따라서 비동기 sidebar dispatch만으로는 목표 달성이 불가능하며, v0.6.10 승격은 보류합니다.

## 5차 실행 계획

현재 병목은 Bash의 150ms timed-read polling과 동기식 tmux IPC가 결합된 실행 모델입니다. 다음 반복은 다음 순서로 진행합니다.

1. 기본 동작을 유지하는 opt-in event-loop 실험을 추가합니다.
2. 입력이 없을 때 timed-read 반복 대신 maintenance deadline까지 대기하도록 합니다.
3. maintenance 실행은 입력 처리와 별도 경로로 두고, 입력 발생 시 즉시 read를 재개합니다.
4. event-loop 실험에서 lifecycle/cursor 회귀가 없을 때만 기본값 전환을 검토합니다.
5. 3회 완주한 reproduction 중앙값으로 CPU와 latency를 다시 판정합니다.

## 5차 실행 결과

- animation이 없는 idle loop의 timeout을 1초로 늘리는 opt-in 적응형 read를 구현했습니다.
- 정적 검사와 전체 regression/lifecycle 10/10은 PASS했습니다.
- 1회 reproduction 결과: idle 15.19%, active 16.34%, key 64ms, switch 295ms, archive 365ms, restore 496ms입니다.
- CPU 개선은 목표와 큰 차이가 있고 key/restore도 개선되지 않았으므로 기본값은 비활성화했습니다.
- 단순 timeout 조정은 polling 구조의 근본 문제를 해결하지 못했습니다.

## 6차 실행 계획

적응형 timeout 실험은 폐기하고, 다음에는 실제 event-driven wake-up을 별도 구현합니다.

- 기본 경로를 변경하지 않는 opt-in 모드로 시작합니다.
- input read와 maintenance wake-up을 FIFO/self-pipe 또는 검증된 signal 경로로 분리합니다.
- timeout polling 없이 입력 또는 maintenance deadline에만 launcher를 깨웁니다.
- 1초 maintenance 정확도, key latency, cursor/lifecycle invariant를 먼저 검증합니다.
- 안정적인 경우에만 3회 reproduction으로 CPU 목표를 재평가합니다.

## 6차 실행 결과

- opt-in blocking read와 signal timer event-loop를 구현했습니다.
- 기본 경로 regression/lifecycle 10/10과 정적 검사는 PASS했습니다.
- opt-in reproduction은 lifecycle을 끝까지 완료했습니다.
- idle/active CPU 0.00%, key 57ms, switch 299ms, archive 404ms, restore 496ms를 기록했습니다.
- CPU는 개선됐지만 나머지 목표는 미달이며, 0.00%는 `/proc` tick 분해능을 포함할 수 있어 3회 반복 전 승격 근거로 사용하지 않습니다.

## 7차 실행 계획

1. event-loop 3회 완주로 CPU 결과 재현성을 확인합니다.
2. archive를 history, snapshot, window preparation, file write, delete/kill 단계로 세분화합니다.
3. restore의 pane 생성과 layout 적용을 별도 계측합니다.
4. key/switch의 내부 dispatch와 외부 capture 관측을 분리합니다.
5. 미달 구간 하나만 선택해 다음 반복을 진행합니다.

## 7차 실행 결과 및 8차 계획

- event-loop reproduction 3회가 모두 lifecycle까지 완료됐습니다.
- 중앙값은 idle CPU 0.28%, active CPU 0%, key 66.5ms, switch 299ms, archive 363ms, restore 466ms입니다.
- 기존 regression/lifecycle 10/10과 navigation/layout/cursor/integrity invariant는 PASS했습니다.
- event-loop는 CPU 개선 가능성을 보여주지만 key/session/archive/restore 목표는 미달입니다.
- 올바른 trace 실행에서 archive launcher 구간 약 88ms, restore history→sidebar dispatch 약 211ms를 확인했습니다. 외부 profile 수치에는 tmux/PTY settlement와 polling이 포함됩니다.
- `tests/profile-reports/v0.6.10-reproduction.md`에 결과를 기록했으며 승격하지 않습니다.

8차 계획:

1. 선택 session에서 실제 AI-like animation을 활성화한 active CPU를 측정합니다.
2. key/switch/archive/restore에서 외부 관측 시간과 launcher 완료 시간을 분리합니다.
3. 내부 시간과 외부 시간이 일치하는 restore pane/layout 구간만 최적화합니다.
4. 전체 목표 matrix 재검증 전에는 event-loop 기본값을 변경하지 않습니다.

## 8차 실행 결과 및 9차 계획

- active CPU fixture를 sidebar 소유 session인 `baseline-1`로 보완했습니다.
- 기본 회귀/lifecycle 10/10과 정적 검사는 PASS했습니다.
- 선택 session active 1회 결과: idle CPU 0%, active CPU 0.28%, key 86ms, switch 294ms, archive 422ms, restore 521ms입니다.
- 선택 session workload에서도 CPU spike는 없었고, 외부 key/archive/restore 관측 시간이 증가했습니다.
- 남은 병목은 animation 계산보다 tmux/PTY settlement와 profile observer 경로일 가능성이 높습니다.

9차 계획:

1. launcher 내부 완료 timestamp와 외부 capture/session settlement timestamp를 각각 report합니다.
2. key/switch/archive/restore를 내부 목표와 외부 관측 목표로 분리합니다.
3. 내부 목표가 통과한 구간은 추가 product fork 최적화 대상에서 제외합니다.
4. 외부 목표가 필요하면 observer가 아닌 tmux client settlement 자체를 별도 benchmark로 측정합니다.

## 9차 실행 결과 및 10차 계획

- profile에 `INTERNAL` phase metric을 추가하고 trace reproduction으로 검증했습니다.
- 외부 archive 356ms 대비 내부 archive launcher 91.6ms를 기록했습니다.
- 외부 restore 489ms 대비 내부 restore launcher 189.2ms를 기록했습니다.
- 내부 selection render는 약 1.3ms, 외부 key는 50ms였습니다.
- archive/restore 내부 목표는 통과했으며, 외부 목표 미달은 tmux client/PTY settlement와 observer 경로로 분리됐습니다.

10차 계획:

1. 내부 metric과 외부 metric을 report에서 항상 별도 표로 유지합니다.
2. tmux client settlement benchmark를 profile polling과 분리합니다.
3. event-loop를 장시간·active animation 조건에서 검증합니다.
4. 내부 목표가 통과한 archive/restore에는 추가 fork 최적화를 적용하지 않습니다.

## 10차 실행 결과 및 11차 계획

- archive observer wait와 restore client settlement phase를 profile에 추가했습니다.
- 기본 regression/lifecycle 10/10과 정적 검사는 PASS했습니다.
- 장시간 event-loop profile은 archive 이후 restore 단계에서 조기 종료되어 성능 결과로 채택하지 않았습니다.
- 짧은 재실행에서도 archive observer wait는 113~120ms로 관측됐습니다.
- restore 실패는 제품 metric이 아니라 profile lifecycle 안정성 문제로 분리해야 합니다.

11차 계획:

1. restore 시작 전 sidebar pane 존재와 launcher process 상태를 profile에 기록합니다.
2. restore 실패 시 tmux pane/session 목록과 launcher log를 보존합니다.
3. archive와 restore settlement benchmark를 profile 전체 lifecycle과 독립 실행합니다.
4. 안정된 benchmark에서만 외부 settlement 목표를 판정합니다.

## 11차 실행 결과 및 12차 계획

- restore 조기 종료 원인은 제품이 아니라 trace 비활성 상태에서 `emit_internal_trace_metric`이 status 1을 반환한 profile `set -e` 버그였습니다.
- 빈 internal metric도 성공적으로 종료하도록 수정했습니다.
- 수정 후 event-loop profile이 lifecycle을 완주했습니다.
- 결과: idle/active CPU 0/0%, key 83ms, switch 384ms, archive 366ms, archive observer wait 114ms, restore 510ms, restore client settlement 247ms입니다.
- cursor/layout/integrity는 PASS했습니다.

12차 계획:

1. profile의 모든 optional metric 함수가 trace 비활성 상태에서도 성공 status를 반환하는지 정적 검증합니다.
2. event-loop 조건에서 3회 완주 측정을 다시 수행합니다.
3. restore client settlement 247ms를 독립 benchmark와 비교합니다.
4. 외부 목표 미달과 내부 launcher 목표를 분리해 최종 판정합니다.

## 12차 실행 결과 및 13차 계획

- 수정된 profile로 event-loop 3회 재측정을 모두 완주했습니다.
- 중앙값: idle/active CPU 0/0%, key 69ms, switch 294ms, archive 365ms, archive observer wait 116ms, restore 475ms, client settlement 251ms입니다.
- 독립 `tests/profile-tmux-settlement.sh`는 sidebar/archive 없이 switch command 중앙값 29ms, client settlement 중앙값 85ms를 기록했습니다.
- restore settlement 251ms는 tmux client 전환만의 비용이 아니라 pane/layout 복원과 observer가 포함된 복합 구간으로 판정합니다.

13차 계획:

1. restore를 pane creation, layout, switch-client, observer 단계로 독립 benchmark에서 재현합니다.
2. session switch 294ms에서 sidebar force-refresh와 client settlement를 분리합니다.
3. key는 pipe observer와 capture observer를 같은 입력으로 비교합니다.
4. 내부 목표와 외부 목표를 별도 표로 유지하며, 외부 목표만 미달인 구간은 product 승격 판단과 분리합니다.

## 14차 실행 결과 및 15차 계획

- trace를 `restore.pane`, `restore.layout`, `switch.sidebar.ensure`, `switch.client` 등으로 세분화했습니다.
- 기능 regression/lifecycle 10/10, 정적 검사는 PASS했습니다.
- 1회 trace reproduction은 lifecycle과 모든 invariant를 통과했으며 외부 결과는 key 77ms, switch 293ms, archive 366ms, restore 521ms였습니다.
- session switch 내부 290ms 중 sidebar 보장 구간이 약 212.7ms로 가장 컸고, client 조회 20.4ms, client 전환 20.0ms, 최종 force-refresh 24.8ms였습니다.
- restore 내부에서는 history 35.9ms, pane 생성 약 97.9ms, layout 적용 60.4ms, switch-client 11.7ms, 대상 pane 탐색 18.1ms가 측정됐습니다.
- restore launcher trace의 history 시작부터 sidebar dispatch까지는 211.0ms였지만, 외부 restore는 521ms로 약 310ms의 observer/settlement 차이가 남았습니다.
- 따라서 session switch의 1차 product 후보는 `ensure_session_sidebar`이며, restore는 pane/layout보다 외부 settlement 계측을 먼저 분리해야 합니다.

15차 계획:

1. `ensure_session_sidebar`의 existing-sidebar 조회, resize, pane 생성 여부를 다시 세분화해 212.7ms의 원인을 확인합니다.
2. restore 독립 fixture에서 pane 생성/layout만 실행하고 attached client/observer를 제외한 launcher 시간을 측정합니다.
3. restore의 sidebar readiness와 capture-pane 관측을 별도 phase로 기록해 310ms 차이가 observer인지 product startup인지 구분합니다.
4. 원인이 확인되기 전에는 restore pane 생성 명령을 추가로 변경하지 않습니다.

## 15차 실행 결과 및 16차 계획

- 세부 trace 후 restore readiness 검증에서 async sidebar가 생성되지 않는 lifecycle 문제를 발견했습니다.
- 원인은 `ensure_sidebar_for_session`의 tmux format `\t`가 실제 탭이 아닌 문자 두 개로 전달되고 awk는 실제 탭을 기대한 구분자 불일치였습니다.
- 구분자를 `|`로 수정하고 target session async ensure 회귀 시나리오를 추가했습니다.
- 최소 fixture에서 수정 전에는 sidebar가 생성되지 않았고, 수정 후에는 target session에 sidebar가 정확히 하나 생성됐습니다.
- 전체 sidebar regression/lifecycle은 3개 launcher lifecycle 시나리오를 포함해 PASS했습니다.
- reproduction 1회는 lifecycle을 완주했고 async sidebar readiness 336ms, restore 467ms, restore client settlement 246ms, switch 324ms, archive 393ms, key 64ms를 기록했습니다.
- 기능상 transient ESC가 switch settled frame에서 9회 관찰된 실행도 있어 cursor/observer 안정성은 별도 재현 대상으로 남겼습니다.

16차 계획:

1. `ensure_sidebar_for_session` format 불일치가 다른 `\\t` 기반 tmux 조회에도 없는지 전수 점검합니다.
2. restore readiness 336ms를 sidebar process startup, pane title, 첫 render/capture 단계로 분해합니다.
3. switch/resize 직후 ESC count와 최종 cursor invariant를 3회 반복해 transient observer 문제인지 product 출력 문제인지 구분합니다.
4. async readiness와 cursor 안정성이 확인되기 전에는 archive/restore 추가 최적화나 버전 승격을 진행하지 않습니다.

## 16차 실행 결과 및 17차 계획: 세 축 분리

- `tests/profile-observer-settlement.sh`를 추가해 동일 sidebar 입력을 capture-pane polling과 pipe-pane raw observer로 비교했습니다.
- observer 3회 중앙값은 capture 51ms, pipe 40ms였습니다.
- 기존 독립 tmux settlement 3회는 switch command 중앙값 27ms, client settlement 71ms였습니다.
- 수정 후 trace reproduction 1회에서 launcher 내부 archive 160.7ms, restore 289.6ms, selection trace 대부분 1~2ms를 기록했습니다.
- 같은 reproduction의 외부 결과는 key 92ms, switch 408ms, archive 540ms, restore 634ms였습니다.
- 이 결과는 세 비용이 실제로 분리됨을 보여주지만, 단일 실행 내부값이 변동하므로 아직 최종 승격용 수치가 아닙니다.

| Axis | Diagnostic result | 다음 판정 대상 |
|---|---:|---|
| Launcher internal | archive 160.7ms / restore 289.6ms | restore 내부 3회 p95 |
| tmux/PTY settlement | command 27ms / settlement 71ms | topology restore settlement |
| Observer | capture 51ms / pipe 40ms | readiness·cursor false positive |

17차 계획:

1. launcher trace, tmux settlement, observer benchmark를 각각 3회 이상 반복합니다.
2. archive/restore internal trace와 external profile을 같은 run ID로 묶습니다.
3. capture observer의 polling interval과 pipe observer를 동일 입력으로 10회 비교합니다.
4. 각 축에서 가장 큰 p95만 다음 코드 개선 대상으로 선택합니다.

## 17차 실행 결과 및 18차 계획: 반복 통합

세 축 반복 측정을 완료했습니다. p95는 현재 표본에서 nearest-rank 방식으로 계산했으며, launcher reproduction은 3회이므로 p95를 사실상 최대값으로 해석합니다.

| Axis / Metric | p50 | p95 | max | Runs |
|---|---:|---:|---:|---:|
| Launcher internal archive | 100.3ms | 115.9ms | 115.9ms | 3 |
| Launcher internal restore | 212.1ms | 238.7ms | 238.7ms | 3 |
| Sidebar readiness | 314ms | 322ms | 322ms | 3 |
| Archive observer wait | 117ms | 124ms | 124ms | 3 |
| Restore client settlement | 249ms | 252ms | 252ms | 3 |
| External key | 86ms | 87ms | 87ms | 3 |
| External session switch | 297ms | 310ms | 310ms | 3 |
| External archive | 405ms | 409ms | 409ms | 3 |
| External restore | 507ms | 515ms | 515ms | 3 |
| tmux command | 23.5ms | 63ms | 63ms | 10 |
| tmux client settlement | 61ms | 114ms | 114ms | 10 |
| capture observer | 62ms | 74ms | 74ms | 10 |
| pipe observer | 54.5ms | 87ms | 87ms | 10 |

반복 결과상 가장 큰 차이는 launcher 내부가 아니라 external archive/restore의 observer와 topology settlement 구간입니다. session switch는 이전 phase trace에서 sidebar ensure 약 212ms가 확인되어 별도의 product 병목으로 유지합니다.

18차 계획:

1. 동일 run ID로 launcher trace·external profile·observer phase를 묶어 중복 합산을 제거합니다.
2. restore topology fixture에서 sidebar readiness와 client settlement의 overlap을 분리합니다.
3. session switch의 sidebar ensure를 existing-sidebar와 pane-create 두 fixture로 나눠 10회 측정합니다.
4. archive observer wait 124ms와 restore readiness 322ms가 profile 관측 오차인지 실제 startup인지 pipe marker로 교차검증합니다.

## 18차 실행 결과 및 19차 계획: campaign correlation

- campaign ID `separation-20260719-01`을 reproduction, settlement, observer benchmark에 공통으로 기록했습니다.
- launcher reproduction은 key 75ms, switch 295ms, archive 395ms, restore 494ms를 기록했고 내부 archive 110.2ms, restore 228.8ms였습니다.
- 같은 campaign의 phase는 archive observer wait 120ms, restore sidebar readiness 321ms, restore client settlement 257ms였습니다.
- settlement fixture는 command p50/p95 23/39ms, client settlement p50/p95 59.5/77ms였습니다.
- observer fixture는 capture p50/p95 48.5/90ms, pipe p50/p95 37.5/71ms였습니다.
- campaign ID 연결은 완료됐지만 fixture가 분리되어 있으므로 phase를 단순 합산하지 않고 correlation key로만 사용합니다.

| Campaign axis | p50 | p95 |
|---|---:|---:|
| Launcher archive internal | 110.2ms | single run |
| Launcher restore internal | 228.8ms | single run |
| External archive | 395ms | single run |
| External restore | 494ms | single run |
| tmux command | 23ms | 39ms |
| tmux client settlement | 59.5ms | 77ms |
| capture observer | 48.5ms | 90ms |
| pipe observer | 37.5ms | 71ms |

19차 계획:

1. reproduction 내부에 동일 입력의 capture/pipe observer phase를 직접 포함해 fixture 차이를 제거합니다.
2. restore topology fixture에 sidebar readiness 전후의 client settlement timestamp를 함께 기록합니다.
3. session switch에서 existing-sidebar와 pane-create를 각각 10회 반복합니다.
4. correlation 결과가 확인되기 전에는 observer 방식 변경을 제품 기본값으로 승격하지 않습니다.

## 19차 실행 결과 및 20차 계획: 동일 lifecycle phase

- reproduction profile 내부에 동일 navigation sidebar 입력의 capture/pipe observer phase를 추가했습니다.
- reset race를 한 단계씩 대기하도록 수정한 뒤 lifecycle은 정상 완료됐습니다.
- 동일 lifecycle capture observer는 53ms, pipe observer는 45ms였습니다.
- restore dispatch→sidebar child `sidebar.open.end` trace는 362.7ms, profile sidebar readiness는 314ms, client settlement는 254ms였습니다.
- 같은 실행의 external key 62ms, switch 387ms, archive 384ms, restore 510ms와 archive observer wait 110ms도 기록됐습니다.
- cursor, layout, archive/restore integrity, navigation, resize invariant는 PASS했습니다.

| Same-lifecycle phase | Result |
|---|---:|
| capture observer | 53ms |
| pipe observer | 45ms |
| restore dispatch→sidebar create trace | 362.7ms |
| restore sidebar readiness | 314ms |
| restore client settlement | 254ms |
| external restore | 510ms |

20차 계획:

1. restore dispatch→sidebar create trace를 process startup, pane title, first render로 세분화합니다.
2. readiness 314ms와 trace 362.7ms의 기준시점 차이를 동일 timestamp로 재정의합니다.
3. same-lifecycle observer를 3회 반복해 capture/pipe p95를 산출합니다.
4. restore topology와 sidebar startup 중 p95가 더 큰 한 구간만 다음 제품 개선 대상으로 선택합니다.

## 20차 실행 결과 및 21차 계획: collect_sessions 병목 확인

- pane ID를 trace event에 포함하고 restore target pane 기준으로 phase를 상관시켰습니다.
- restore process→pane title은 52.2ms였습니다.
- pane title→`collect_sessions` 완료는 1238.8ms였습니다.
- collect 완료→first render는 16.5ms였습니다.
- 따라서 이전 1.2~1.4초 startup 병목은 render가 아니라 초기 session collection입니다.
- 같은 실행에서 dispatch→process start 458.7ms, dispatch→sidebar create 370.2ms, sidebar readiness 318ms, external restore 505ms였습니다.
- same-lifecycle capture/pipe observer는 48/50ms였고 전체 invariant는 PASS했습니다.

| Restore startup phase | Result |
|---|---:|
| dispatch→sidebar create | 370.2ms |
| dispatch→process start | 458.7ms |
| process→pane title | 52.2ms |
| pane title→collect end | 1238.8ms |
| collect end→first render | 16.5ms |
| sidebar readiness | 318ms |
| external restore | 505ms |

21차 계획:

1. `collect_sessions` 내부를 list-sessions, list-clients, pane snapshot, AI probe, fingerprint 단계로 세분화합니다.
2. restore 직후에는 target session만 수집하는 경로와 전체 session scan을 비교합니다.
3. AI inactive/cache-hit 조건에서 collection이 왜 1.2초를 소비하는지 command trace로 확인합니다.
4. 원인이 확인되기 전에는 render 경로를 추가 수정하지 않습니다.

## 21차 실행 결과 및 22차 계획: session parsing 병목

- `collect_sessions` 내부 phase trace를 추가하고 restore reproduction 1회를 측정했습니다.
- collection setup/list-sessions는 176.4ms, list-panes는 84.0ms, pane parsing은 58.3ms였습니다.
- session parsing·상태 전이·AI probe가 포함된 구간은 855.8ms로 가장 컸습니다.
- collect 완료→first render는 27.5ms였고, render는 여전히 주 병목이 아니었습니다.
- title→collect end는 1177.6ms였으며, session parsing 구간이 약 73%를 차지했습니다.
- lifecycle, archive/restore integrity, layout, cursor, navigation, resize는 PASS했습니다.

| collect_sessions phase | Result |
|---|---:|
| setup/list-sessions | 176.4ms |
| list-panes | 84.0ms |
| parse-panes | 58.3ms |
| parse-sessions + state/AI | 855.8ms |
| collect end→first render | 27.5ms |

22차 계획:

1. parse-sessions 내부의 AI probe aggregate와 fingerprint aggregate를 별도 trace합니다.
2. restore 직후 target session만 parse하는 target-only 통제 경로를 benchmark로 추가합니다.
3. full scan, target-only, cache-hit의 session parsing p50/p95를 비교합니다.
4. target-only가 first render과 external restore를 개선하는 것이 확인될 때만 제품 경로 변경을 검토합니다.

## 22차 실행 결과 및 23차 계획: animation seed 비용 분리

- AI state 전체는 61.5ms였지만 parse-sessions는 454.8ms였습니다.
- 따라서 parse-sessions의 잔여 비용은 AI probe보다 session loop의 부수 계산에 있었습니다.
- `session_animation_seed_for`가 문자마다 외부 `printf`를 실행하던 구조를 단일 `cksum` 호출로 변경했습니다.
- 동일 reproduction에서 parse-sessions는 1126.7ms에서 454.8ms로 약 59.6% 감소했습니다.
- title→first render는 1342.2ms에서 700.6ms로 감소했고, collect end→first render는 20.9ms로 유지됐습니다.
- archive 370ms, restore 501ms, key 60ms, switch 392ms를 기록했으며 모든 invariant는 PASS했습니다.

| Restore collect phase | 이전 | 개선 후 |
|---|---:|---:|
| parse-sessions | 1126.7ms | 454.8ms |
| AI state total | 73.0ms | 61.5ms |
| collect end→first render | 20.9ms | 40.0ms |
| title→first render | 1342.2ms | 700.6ms |

23차 계획:

1. `session_status`, animation seed, state transition을 각각 독립 측정합니다.
2. session loop에서 남은 외부 명령 호출을 식별하고 단일 snapshot 또는 순수 bash 계산으로 치환합니다.
3. target-only collection 통제군을 추가해 전체 session scan 제거 효과를 분리합니다.
4. 3회 reproduction 중앙값과 p95를 확인한 뒤 다음 최적화 대상을 선택합니다.

## 24차 실행 결과 및 25차 계획: restore session loop 세분화와 순수 Bash seed

- `session_status`와 animation seed를 마지막 restore `parse-sessions` 구간 안에서만 합산하도록 계측 경계를 보정했습니다.
- animation seed의 `cksum` 외부 프로세스를 제거하고 Bash 내장 문자 해시로 변경했습니다.
- 보정된 reproduction에서 parse-sessions 339.1ms, session status 합계 282.7ms, animation seed 합계 319.6ms를 기록했습니다. 두 합계는 세션별 구간의 합이며 parse-sessions와 일부 순차·계측 구간이 겹치므로 직접 합산하지 않습니다.
- title→first render 580.1ms, collect end→first render 32.7ms였고, key 70ms, switch 284ms, archive 382ms, restore 496ms였습니다.
- archive/restore integrity, layout, cursor, navigation, resize와 same-lifecycle observer는 모두 PASS했습니다.

| Restore subdivision | Result |
|---|---:|
| parse-sessions | 339.1ms |
| session status total | 282.7ms |
| animation seed total | 319.6ms |
| AI state total | 95.5ms |
| title→first render | 580.1ms |
| collect end→first render | 32.7ms |

25차 계획:

1. status/seed 합계를 3회 reproduction으로 반복해 trace overhead와 실행 편차를 분리합니다.
2. session status의 `session_is_busy`와 `session_activity_age`를 분리해 snapshot 재사용 효과를 측정합니다.
3. animation seed를 session snapshot 변경 시에만 계산하는 cache-hit 통제군을 추가합니다.
4. 두 통제군 중 중앙값 개선이 확인된 경로만 제품 동작에 적용하고, target-only collection은 별도 비교군으로 유지합니다.

## 26차 실행 결과 및 27차 계획: 영향 최소화 aggregate log

- trace 파일의 per-event append는 성능 분석을 오염시킬 수 있어, 별도 `TMUX_SESSION_LAUNCHER_METRICS_FILE` aggregate log를 추가했습니다.
- 기본값은 비활성이고, 활성 시에도 collection 한 회의 요약을 메모리에 누적한 뒤 2초 간격으로 한 번만 flush합니다.
- 로그에는 session 수, requested target, list-sessions/list-panes, parse-panes/parse-sessions, status/AI/seed 시간과 호출 수를 기록합니다.
- 직접 append 방식은 idle CPU 12.18%, 무로그 8.33%로 영향이 확인되어 폐기했습니다.
- 버퍼링 방식은 idle CPU 8.03%, 무로그 8.33%였고 key 51/61ms, archive 369/386ms, restore 468/492ms였습니다. active CPU는 6.95/4.78%로 편차가 있어 3회 중앙값 검증이 필요합니다.
- 로그에서 requested target이 있어도 20개 session 전체에 대해 `status_count=20`, `seed_count=20`이 반복되는 사실을 확인했습니다. target-only collection은 아직 구현되지 않았습니다.

| 계측 방식 | Idle CPU | Active CPU | Key | Archive | Restore |
|---|---:|---:|---:|---:|---:|
| 무로그 5초 | 8.33% | 4.78% | 61ms | 386ms | 492ms |
| buffered aggregate log 5초 | 8.03% | 6.95% | 51ms | 369ms | 468ms |
| 직접 append log 5초 | 12.18% | 6.65% | 91ms | 394ms | 499ms |

27차 계획:

1. buffered log와 무로그를 동일 조건 3회 반복해 계측 오버헤드의 중앙값/p95를 확정합니다.
2. `requested`가 있는 collection에서도 전체 session loop를 도는 원인을 분리합니다.
3. status/seed 캐시 hit/miss를 추가해 실제 재계산 횟수를 확인합니다.
4. target-only 실험군을 별도 profile로 만들고, 기능 invariant가 유지될 때만 제품 경로에 적용합니다.

## 28차 실행 결과 및 29차 계획: operation correlation과 cache 상태 계측

- collection aggregate에 `operation_id`, `scan_scope`, AI cache hit/refresh 수, status/seed cache 상태를 추가했습니다.
- selection input, archive complete, restore complete에도 동일 run ID 기반 operation 로그를 추가했습니다.
- process별 sequence 중복을 피하기 위해 operation ID에 run ID, pane, Bash PID, sequence를 포함했습니다.
- 로그 결과 `scan_scope=target-requested-full-loop`에서도 20개 session 전체를 순회했고, `status_count=20`, `status_cache=miss`, `seed_count=20`, `seed_cache=miss`가 반복됐습니다.
- 반면 AI 상태는 같은 조건에서 `ai_cache_hits=19`, `ai_refreshes=1`까지 확인되어 AI probe cache는 부분적으로 동작합니다.
- input 내부 selection render는 약 3.5~7.7ms, archive 내부는 약 90ms, restore 내부는 약 263ms로 측정됐습니다.

| Logged operation | Evidence |
|---|---:|
| target requested collection | 20-session full loop |
| status cache | miss × 20 |
| seed cache | miss × 20 |
| AI cache | hit 19 / refresh 1 |
| input selection render | 3.5~7.7ms |
| archive internal | 90ms |
| restore internal | 263ms |

29차 계획:

1. status/seed cache를 실제로 유지하는 통제군을 별도 구현합니다.
2. target-requested-full-loop와 target-only를 동일 fixture에서 비교합니다.
3. operation ID로 input/archive/restore 내부와 외부 settlement를 연결합니다.
4. 로그 활성/비활성 3회 중앙값과 p95를 산출한 뒤에만 성능 개선 여부를 판정합니다.

## 30차 실행 결과 및 31차 계획: status/seed 증분 cache 적용

- session loop에 persistent status/seed cache를 적용했습니다.
- status cache는 session 생성시각, activity busy 경계, busy command, pane generation 변경 시 무효화합니다.
- seed cache는 `session_name + session_created`가 바뀔 때만 다시 계산합니다.
- 20개 session target collection에서 반복 구간은 `status_cache_hits=19`, `status_cache_misses=1`, `seed_cache_hits=20`, `seed_cache_misses=0`까지 확인됐습니다.
- parse-sessions는 cache 적용 전 반복 구간 약 360~700ms에서 적용 후 약 100~330ms 구간으로 감소했습니다.
- 최신 external sample은 idle 8.33%, active 4.74%, key 60ms, switch 278ms, archive 363ms, restore 502ms였습니다. 외부 latency는 단일 실행이므로 개선 확정이 아니라 내부 collection 개선만 확정합니다.
- 테스트 harness에 unchanged session의 status/seed cache 재사용 회귀를 추가했고 전체 regression은 PASS했습니다.

| 항목 | 이전 | cache 적용 후 |
|---|---:|---:|
| status cache | miss × session 수 | hit 19 / miss 1 |
| seed cache | miss × session 수 | hit 20 / miss 0 |
| 반복 parse-sessions | 약 360~700ms | 약 100~330ms |
| external key | 51ms | 60ms |
| external archive | 369ms | 363ms |
| external restore | 468ms | 502ms |

31차 계획:

1. 현재 full pane snapshot과 전체 session 배열 재구축을 target-only 증분 경로로 줄입니다.
2. cache 무효화 사유를 pane ID/command/activity/session 생성 변경별로 로그에 기록합니다.
3. 동일 fixture 3회에서 internal collection p50/p95와 external latency p50/p95를 각각 산출합니다.
4. target-only 적용 후 AI waiting/stable transition, resize/client switch, archive/restore lifecycle을 재검증합니다.

## 32차 실행 결과 및 33차 계획: target-only pane snapshot 적용

- target requested collection에서 전체 cached pane을 다시 합쳐 parse하던 경로를 제거했습니다.
- target session의 기존 pane metadata를 제거한 뒤 target snapshot만 다시 parse하고, 다른 session의 pane snapshot·command signature·AI metadata는 보존합니다.
- 로그에서 `pane_scan_scope=target`, `incremental_pane_scan=true`를 확인했습니다.
- target pane parse는 약 6~20ms로, full pane parse 약 59~95ms보다 감소했습니다.
- session row 배열은 표시 순서 유지를 위해 아직 전체 session 목록을 순회하므로, session array reconstruction은 완전히 제거되지 않았습니다.
- 최신 external sample은 idle 5.18%, active 4.39%, key 66ms, switch 413ms, archive 497ms, restore 884ms였습니다. 내부 pane/collection 개선은 확인됐지만 외부 latency는 실행 편차와 restore settlement 영향을 받아 목표 달성으로 판정하지 않습니다.
- 다른 session metadata 보존과 target pane 교체 regression을 추가했고 regression 12개가 PASS했습니다.

| Collection phase | Full snapshot | Target snapshot |
|---|---:|---:|
| pane parse | 59~95ms | 6~20ms |
| session row traversal | 전체 | 전체 유지 |
| status/seed cache | cache 기반 | cache 기반 |
| target metadata | 전체 재구축 | target만 교체 |

33차 계획:

1. session row 배열을 name-index cache 기반으로 유지해 target 변경 시 해당 row만 교체합니다.
2. session 생성/삭제/순서 변경일 때만 전체 row index를 재구축합니다.
3. target-only archive/restore에서 full collection fallback이 발생하는 조건을 로그로 분리합니다.
4. 동일 fixture 3회에서 pane parse, parse-sessions 내부 p50/p95와 external settlement를 각각 재측정합니다.

## 34차 실행 결과 및 35차 계획: session name-index row cache 적용

- session 목록을 `session_name + session_created` 순서 signature로 비교하고, 기존 `name → row index` cache를 유지하도록 변경했습니다.
- session 생성·삭제·순서 변경이 없고 target session이 cache에 있으면 전체 row 배열을 초기화하거나 append하지 않고 target index의 row만 교체합니다.
- session topology가 바뀌거나 target index를 찾을 수 없으면 기존 full row rebuild 경로로 fallback합니다.
- 안정 구간 로그는 `scan_scope=target-requested-target-row`, `row_cache_reusable=true`, `status_count=1`, `seed_count=1`로 확인됐습니다.
- 20-session 안정 target collection의 `parse_sessions_us`는 약 92~175ms였고, session 추가 후에는 `target-requested-full-row`, `row_cache_reusable=false`, `status_count=21`로 fallback했습니다.
- 최신 external reproduction 단일 sample은 idle 8.51%, active 5.18%, key 78ms, switch 404ms, archive 361ms, restore 523ms였습니다. 단일 실행값이므로 3회 중앙값 승격 결과로 사용하지 않습니다.
- full regression은 `pass=12`, lifecycle e2e는 `pass=4`, launcher lifecycle은 `pass=3`으로 완료했습니다.

| 조건 | row 처리 | pane 처리 | fallback |
|---|---|---|---|
| startup/force/topology 변경 | 전체 row rebuild | 전체 snapshot | 적용 |
| target 요청 + session 순서 불변 | target row 교체 | target snapshot | 미적용 |
| session 생성·삭제·순서 변경 | 전체 row rebuild | 전체 snapshot | 적용 |

35차 계획:

1. 동일 reproduction을 3회 실행해 row-cache 내부 p50/p95와 외부 latency p50/p95를 분리 산출합니다.
2. order signature 불일치, target index 누락, pane generation 변경 등 row cache 무효화 사유를 별도 counter로 기록합니다.
3. full startup에 남은 `list-sessions`와 초기 status/AI probe 비용을 target-row 경로와 분리해 측정합니다.
4. archive/restore 외부 settlement 편차를 포함한 승격 기준을 재검토한 뒤에만 버전 승격을 판단합니다.

## 36차 실행 결과: switch·key·archive phase 계측

동작 경로는 변경하지 않고 버퍼링 metrics에 세부 phase 시간을 추가했습니다.

| Operation | Phase median | Total/internal median | External median |
|---|---:|---:|---:|
| switch | sidebar ensure 210ms, client lookup 31ms, client switch 13ms | 302ms | 389ms |
| key | update 3.0ms, visibility 2.6ms, render 4.0ms | 17.9ms | 55ms |
| archive | snapshot 47ms, write 43ms, rename 7ms | 106ms | 401ms |

병목은 switch의 sidebar ensure, key의 내부 phase 외부 settlement, archive의 run-shell dispatch와 observer settlement로 분리됐습니다. archive는 내부 106ms에 비해 외부 401ms였고, dispatch 280ms와 file observer wait 119ms가 대부분을 차지했습니다.

기존 lifecycle test가 한 차례 timing race를 보였으나 단독 재실행과 전체 suite 최종 실행은 모두 PASS했습니다. 계측만 적용했으며 제품 동작 최적화는 아직 수행하지 않았습니다.

## 37차 실행 결과: switch·archive 최적화 및 key observer 검증

- target sidebar가 cached pane snapshot에 있으면 ensure 경로에서 `list-panes`, width 조회, resize를 생략합니다.
- target sidebar가 없으면 switch를 동기 생성하지 않고 `--ensure-sidebar-session`을 `run-shell -b`로 dispatch해 client switch와 sidebar 생성이 겹치도록 변경했습니다.
- archive profile은 제품 경로와 동일한 `run-shell -b`를 사용하고, final archive가 atomic rename 결과라는 점을 이용해 중복 안정화 sleep을 제거했습니다.
- key pipe observer와 1ms polling 대조군은 기존 polling보다 개선되지 않아 기본 observer를 원래 polling으로 유지했습니다.

| Metric | 이전 phase 계측 중앙값 | 최적화 후 중앙값 | 결과 |
|---|---:|---:|---|
| switch external | 389ms | 202ms | 개선 |
| switch internal | 302ms | 약 122ms | 개선 |
| archive external | 401ms | 310ms | 개선 |
| archive internal | 106ms | 약 110ms | 변화 없음 |
| key external | 55ms | 70ms | 개선 없음 |

최적화 후 switch 로그는 `sidebar_ensure_async=true`, `ensure_sidebar_us` 약 29~33ms로 확인됐습니다. archive는 dispatch 약 24~34ms, file readiness 약 289~336ms였고 내부 archive 자체보다 process/observer settlement가 여전히 큽니다. key는 내부 제품 render 문제가 아니라 observer 경계 및 실행 편차가 지배적이므로 제품 경로 최적화 대상에서 제외합니다.

전체 sidebar regression은 regression 14개, lifecycle e2e 4개, launcher lifecycle 3개 PASS입니다.

## 38차 실행 결과: idle shell-child probe 및 blocking key observer

- 선택 session이 shell pane만 가지고 AI child process도 없을 때는 target full state snapshot을 실행하지 않고 cached pane ID에 대한 저비용 process probe만 수행하도록 변경했습니다.
- 선택적 `PROFILE_PIPE_OBSERVER=true`에서는 marker 파일 polling 대신 FIFO blocking reader를 사용해 observer 자체의 polling 지연을 제거했습니다. 제품 launcher의 key/render 경로는 변경하지 않았습니다.
- event-loop timer 실험은 idle 0.16%였지만 active 0%로 state refresh가 누락되어 폐기했습니다.

| Metric | Run 1 | Run 2 | Run 3 | Median | Target | Result |
|---|---:|---:|---:|---:|---:|---|
| idle CPU | 2.95% | 2.23% | 2.76% | 2.76% | ≤3% | PASS |
| active CPU | 5.73% | 5.39% | 4.31% | 5.39% | ≤5% | FAIL |
| key latency | 35ms | 44ms | 36ms | 36ms | ≤40ms | PASS |
| switch | 132ms | 214ms | 121ms | 132ms | ≤1200ms | PASS |
| archive | 355ms | 303ms | 312ms | 312ms | ≤350ms | PASS |
| restore | 481ms | 484ms | 511ms | 484ms | ≤2200ms | PASS |

측정 경로의 key 목표는 통과했지만 active CPU 중앙값이 5.39%로 전체 승격 기준을 충족하지 못했습니다. 따라서 이번 단계는 관찰 경로 개선 및 idle 개선의 부분 성공으로 기록하며, 성능 목표 달성 또는 버전 승격으로 판정하지 않습니다. 다음 단계는 active animation의 실제 frame/render 비용을 별도 계측해 5% 경계 초과 원인을 분리하는 것입니다.

전체 회귀는 regression 15개, lifecycle e2e 4개, launcher lifecycle 3개 PASS이며 정적 검사와 `git diff --check`도 PASS했습니다.

## 39차 분석 결과: frame/render 비용과 active CPU 분리

metrics를 켠 active reproduction에서 frame 및 render 비용을 누적 계측했습니다. 측정 오염을 줄이기 위해 frame hot path의 시간 읽기는 subprocess 없는 `EPOCHREALTIME` 변수 캡처를 사용했습니다.

| 구간 | 누적 결과 | 환산 |
|---|---:|---:|
| animation frame | 136 frames / 298ms | 약 2.19ms/frame |
| name format | 139ms | 약 1.02ms/frame |
| ANSI emit | 40ms | 약 0.29ms/frame |
| full render | 4회 / 105ms | 약 26.3ms/회 |
| state-change render | 2회 / 4.8ms | 약 2.4ms/회 |

동일 reproduction의 animation 비활성 대조군은 active CPU 5.38%였고, animation 활성 계측 실행은 계측 오버헤드가 포함된 6.96%였습니다. 이전 비계측 활성 결과도 약 5%대였으므로, animation을 제거해도 active CPU가 유지됩니다. frame/name format/emit 합계는 약 0.44초로 active CPU 초과를 설명하기에 부족합니다.

결론적으로 현재 5% 초과의 1차 원인은 frame/render가 아니며, 다음 계측 대상은 active session의 maintenance loop, `refresh_sidebar_state_if_due`/target collection, `read_key` timeout loop 및 그 안의 외부 observer 호출입니다. 이번 단계에서는 제품 동작을 변경하지 않고 원인 범위만 확정했습니다.

## 40차 후보 검증 결과: fingerprint·refresh 주기 조정

- waiting 상태에서 unchanged fingerprint 재호출을 더 억제하는 후보는 회귀는 통과했지만 active CPU 5.49%로 기준 약 5%대와 차이가 없어 제거했습니다.
- 최근 pane activity가 있는 direct AI pane은 fingerprint를 건너뛰는 후보도 active CPU 5.68%로 개선되지 않았습니다. 현재 profile의 `session_activity`가 pane 출력 활동을 충분히 나타내지 않아 안전한 근거로 사용할 수 없습니다.
- state refresh 주기를 10초로 늘린 대조군은 active CPU 9.29%, key 72ms로 악화되어 채택하지 않았습니다.

따라서 이번 수정에서는 기능 동작을 바꾸는 후보를 남기지 않고, frame/render 계측과 외부 관찰 결과만 유지합니다. 다음 실제 최적화 전에는 maintenance tick 내부를 `read wait`, age render, force-refresh option lookup, state refresh/target collection으로 다시 세분화해야 합니다.

## 41차 maintenance/read 계측 및 blocking-read 검증

약 35초 active profile에서 maintenance loop는 142회 실행됐습니다.

| Phase | Calls | Accumulated time |
|---|---:|---:|
| read timeout | 140 | 39.88s wall interval |
| age render | 42 | 107.9ms |
| force-refresh lookup | 8 | 148.0ms |
| state refresh path | 42, skip 40 | 886.0ms |

read interval은 wall 대기시간이므로 CPU 비용으로 직접 환산하지 않습니다. signal timer와 blocking read를 animation에도 적용하는 실험은 active CPU 0%로 보였지만 navigation observer와 resize invariant가 FAIL해 refresh/animation 누락으로 폐기했습니다. 기본 blocking-read 조건은 원복했습니다.

다음 단계에서는 `/proc` CPU tick을 maintenance phase 경계와 함께 샘플링하거나 phase별 외부 command count를 추가해 wall time과 CPU time을 구분합니다.

## 42차 phase command count 및 `/proc` CPU tick 계측

metrics 모드에서만 `tmux`/`pgrep` 호출을 phase별 counter로 기록하고, read·age·force·state 경계에서 launcher Bash의 user+system CPU tick(`/proc/$$/stat`)을 샘플링했습니다. command substitution 내부 호출도 잃지 않도록 별도 append 파일을 사용했습니다.

| Phase | 외부 command count | wall time | Bash CPU tick |
|---|---:|---:|---:|
| read | tmux 0, pgrep 0 | 17.54s 누적/52 loop | 17 ticks |
| age | tmux 0, pgrep 0 | 47.8ms/20회 | 7 ticks |
| force | tmux 4, pgrep 0 | 73.5ms/4회 | 3 ticks |
| state | tmux 20, pgrep 8 | 550.5ms/21회, 19회 skip 포함 | 17 ticks |
| startup | tmux 24, pgrep 0 | 별도 누적 | 별도 측정 대상 아님 |

계측 오버헤드를 포함한 단일 진단 실행이므로 CPU 목표 판정용 결과는 아닙니다. read는 대부분 blocking wall wait이고, age/force는 작으며, state 경로가 반복 외부 호출과 CPU tick의 핵심 후보라는 점을 확인했습니다. 다음 최적화는 state 진입 조건과 `pgrep` probe를 더 세분화합니다.

## 43차 state 진입 gate 및 shell-child probe 최적화 결과

- maintenance tick마다 `refresh_sidebar_state_if_due`를 호출하지 않고, 별도 `state_refresh_due` gate를 통과한 경우에만 state phase를 진입하도록 했습니다. refresh 주기 자체는 유지합니다.
- shell-child probe는 collection에서 저장한 cached pane PID를 우선 사용하고 `/proc/<pid>/cmdline` 및 `/proc/<pid>/task/<pid>/children`를 순수 Bash로 탐색합니다.
- procfs가 child 목록을 노출하지 않는 PTY 환경에서는 기존 `pgrep` 경로를 compatibility fallback으로 유지했습니다.

| Metric | 이전 계측 | 최적화 후 계측 | 결과 |
|---|---:|---:|---|
| state phase calls | 19회 | 4회 | 진입 감소 |
| state `pgrep` | 8회 | 2회 | 75% 감소 |
| state CPU ticks | 17 | 16 | 소폭 감소 |
| state wall time | 550.5ms | 543.0ms | 소폭 개선 |
| no-metrics active CPU | 약 5.39% 기준 | 5.25% 단일 실행 | 개선 신호 |

metrics profile은 계측 오버헤드를 포함하므로 목표 판정에 사용하지 않았습니다. active CPU는 3회 중앙값을 다시 확인해야 하며, 아직 버전 승격 조건으로 판정하지 않습니다.

## 44차 정합성 점검 및 fallback 경로 보정 계획

최신 commit의 코드와 43차 기록을 대조한 결과, procfs child 목록을 정상적으로 읽은 뒤에도 compatibility fallback이 실행되는 불일치가 발견되었습니다. 이 경로는 Linux의 일반적인 shell-only miss마다 `tmux display-message`와 `pgrep`를 추가 실행하므로, 43차의 `pgrep` 감소 기록을 실제 hot path 최적화로 해석하기 어렵게 만들었습니다.

보정 범위는 다음으로 한정합니다.

1. procfs children 파일이 readable이면 AI child hit/miss를 그 결과로 확정합니다.
2. procfs children 파일이 unavailable한 환경에서만 기존 `tmux`/`pgrep` fallback을 실행합니다.
3. procfs hit/miss와 fallback hit/miss를 debug log로 구분합니다.
4. shell-only, AI child, pane command 변경, lifecycle 회귀를 각각 검증합니다.
5. 동일 reproduction 조건 3회 중앙값으로 active CPU와 state command count를 재측정합니다.

판정 기준은 기존 절대 목표인 idle ≤3%, active ≤5%, key ≤40ms, switch ≤1200ms, archive ≤350ms, restore ≤2200ms와 모든 invariant PASS입니다. 단일 실행 또는 metrics-enabled 실행은 원인 분석용으로만 사용하며 승격 근거로 사용하지 않습니다.

## 44차 결과 및 최종 판정 계획

fallback 경로 보정 후 정적 검사와 전체 회귀를 먼저 통과시킨 다음, 3회 reproduction을 완주합니다. active CPU가 여전히 5%를 초과하면 state probe를 추가로 줄이는 대신 로그에서 procfs probe, AI fingerprint, shell-only state refresh, 외부 observer 비용을 분리해 원인을 확정합니다.

목표를 모두 충족한 경우에만 v0.6.10 승격 기록, tag, commit, push를 수행합니다. 하나라도 미달하면 승격하지 않고 해당 phase의 3회 중앙값과 로그를 다음 개선 계획으로 기록합니다.

## 45차 공식 baseline 결과 및 다음 개선 계획

`PROFILE_RUNS=3 bash tests/compare-profiles.sh`의 공식 3회 중앙값은 idle 1.39%, active 1.69%, key 75ms, switch 151ms, archive 445ms, restore 1467ms였습니다. 기능 invariant는 모두 PASS했지만 key와 archive가 각각 40ms·350ms 목표를 초과했으므로 v0.6.10 승격 조건은 미충족입니다.

최신 metrics 로그에서는 procfs 보정 후 state phase의 `tmux=0`, `pgrep=0`을 확인했습니다. 따라서 다음 개선은 state probe가 아니라 다음 두 외부 경계로 한정합니다.

1. key: launcher selection trace와 capture/PTY observer를 분리한 상태에서 observer settlement를 줄입니다. 제품 render 내부가 목표를 이미 충족하면 renderer를 재수정하지 않습니다.
2. archive: run-shell dispatch, archive process settlement, final-file observer를 각각 측정하고, atomic rename invariant를 유지하면서 observer 중복 대기만 제거합니다.
3. 매 반복마다 동일 공식 3회 baseline과 전체 lifecycle suite를 실행합니다.
4. key ≤40ms와 archive ≤350ms를 동시에 통과하기 전에는 commit/tag/push 및 버전 승격을 하지 않습니다.

이번 결과의 root cause는 state refresh가 아니라 외부 key capture/PTY 관측과 archive process/observer settlement입니다. 이 경계를 넘지 않는 변경은 다음 반복에서 제외합니다.

## 46차 archive fast path 실행 결과

공식 archive 경로에 비연결 session fast path를 적용했습니다.

- 비연결 archive 대상은 대상 client 전환과 fallback session 조회를 생략합니다.
- 마지막 session도 별도 session 목록 조회 없이 `kill-session`으로 정리합니다.
- attached client와 delete-only 경로는 기존 동작을 유지합니다.
- archive wrapper에 preflight, fallback lookup, archive, kill phase metrics를 추가했습니다.
- archive lifecycle 회귀에 실제 archive 파일 생성 및 대상 session 제거 검증을 추가했습니다.

| 단계 | Archive median | 결과 |
|---|---:|---|
| 기존 기준 | 445ms | FAIL |
| client 전환 생략 | 418ms | FAIL |
| fallback 조회 생략 | 378ms | FAIL |
| 최종 fast path | 351ms | FAIL, 목표보다 1ms 초과 |

최종 실행의 다른 결과는 idle 1.93%, active 1.67%, key 79ms, switch 160ms, restore 1530ms이며 모든 layout/cursor/integrity invariant는 PASS입니다.

판정: archive는 실질적으로 개선됐지만 공식 350ms 기준을 중앙값으로 통과하지 못했습니다. 남은 차이는 wrapper 외부 tmux dispatch/settlement 및 측정 편차 범위로 보이며, 동일 fast path를 유지한 추가 재현성과 phase metrics를 먼저 확보한 뒤 추가 제품 변경 여부를 결정합니다. v0.6.10 승격은 보류합니다.

## 48차 통합 key/archive 결과

archive snapshot의 pane/window metadata를 한 번의 `list-panes` 호출로 통합하고, wrapper의 `list-clients` 성공 결과를 archive 존재성 검사로 재사용했습니다. archive 포맷, atomic rename, attached client 경로, restore/lifecycle 동작은 유지했습니다.

최신 공식 3회 중앙값:

| Metric | Median | Range | Target | Result |
|---|---:|---:|---:|---|
| Idle CPU | 1.12% | 1.10–1.92% | ≤3% | PASS |
| Active CPU | 1.70% | 1.12–1.94% | ≤5% | PASS |
| Key latency | 79ms | 76–81ms | ≤40ms | FAIL |
| Session switch | 171ms | 153–176ms | ≤1200ms | PASS |
| Archive | 312ms | 308–320ms | ≤350ms | PASS |
| Restore | 1511ms | 1502–1645ms | ≤2200ms | PASS |
| Functional invariants | 100% | every run | required | PASS |

archive 목표는 달성했습니다. 반면 pipe observer 진단도 key 66ms로 40ms를 넘었으며, launcher 내부 selection render는 14~25ms입니다. 따라서 다음 개선은 key observer의 blocking/event-driven 경로를 별도 설계하는 작업으로 한정합니다. 전체 목표는 key 미달로 아직 달성하지 않았습니다.

## 47차 archive 3회 phase 분리 측정

`PROFILE_METRICS=true`, `PROFILE_TRACE=true`, FIFO observer를 활성화한 reproduction 3회에서 archive 관련 phase를 분리했습니다.

| Phase | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| 외부 archive completion | 327ms | 310ms | 322ms | 322ms |
| archive wrapper total | 206.0ms | 190.8ms | 189.1ms | 190.8ms |
| archive internal total | 136.8ms | 115.2ms | 115.9ms | 115.9ms |
| wrapper preflight | 16.9ms | 20.4ms | 17.9ms | 17.9ms |
| wrapper kill | 12.0ms | 17.4ms | 21.3ms | 17.4ms |
| archive observer wait | 297ms | 274ms | 276ms | 276ms |

내부 archive 중앙값은 snapshot 47.1ms, write 49.7ms, rename 11.2ms의 합계입니다. 외부 archive completion과 wrapper total의 차이는 비동기 run-shell dispatch 및 final-file observer 대기입니다. 따라서 archive 파일 serialization을 추가로 줄이는 것보다 observer settlement와 공식 profile의 동기 `run-shell` 측정 경계를 분리하는 것이 다음 분석 대상입니다.
