# v0.6.8 reproduction performance improvement plan

## 목적

v0.6.7 reproduction profile의 평균적인 navigation latency는 40~90ms였지만, 일부 단계에서 1.2초대 outlier가 관찰되었습니다. v0.6.8은 이 outlier를 제거하고, 내부 render 시간과 외부 terminal 관측 시간을 분리하여 성능 개선을 검증합니다.

기존 v0.6.7 profile과 auto profile은 보존합니다. v0.6.8의 결과는 신규 reproduction report에 기록하고, 사용자 리뷰 전에는 commit/tag/push를 만들지 않습니다.

## 최종 승격 목표

| Metric | v0.6.7 reproduction | v0.6.8 final target |
|---|---:|---:|
| idle CPU median / p95 | 15.96% | ≤8% / ≤12% |
| active CPU median / p95 | 15.11% | ≤8% / ≤12% |
| key latency median / p95 | 54ms | ≤30ms / ≤80ms |
| session switch median / p95 | 301ms | ≤180ms / ≤300ms |
| archive median | 345ms | ≤250ms |
| restore median | 491ms | ≤300ms |
| navigation step median / p95 | 54~91ms | ≤40ms / ≤150ms |
| navigation maximum | 1.2s대 관찰 | <500ms |
| five-key burst | 110~130ms | ≤70ms |
| periodic refresh input | 47~60ms | ≤40ms |

추가 invariant:

- navigation 500ms 초과 0회
- cursor count, sidebar count, client alignment, layout, lifecycle, archive/restore integrity 100%
- 동일 HOME/shell/history/layout fixture에서 archive bytes 편차 ±5%
- 최종 판정은 최소 30회 측정으로 수행하며, 개발 중에는 10회 smoke sample을 사용

## 구현 범위

### 1. 내부 selection trace

`move_selection()`에 monotonic selection event id를 부여하고 다음 구간을 trace합니다.

```text
read.begin/end
selection.update.begin
selection.render.begin/end
selection.update.end
```

profile은 각 navigation step에 대해 다음을 함께 기록합니다.

- external capture latency
- internal selection render latency
- direction/target/index
- trace event id
- 마지막 refresh/force-refresh 상태

### 2. Key path와 refresh path 분리

키 입력 직후에는 selection 변경과 필요한 row 출력만 수행합니다. 다음 작업은 key path 밖에서 수행하도록 검토합니다.

- `collect_sessions`
- `list-panes`/tmux IPC
- AI fingerprint 검사
- force-refresh 확인
- animation frame
- full render

trace에서 selection render가 짧은데 external latency만 긴 경우에는 측정부/terminal 관측 문제로 분류하고, 두 값이 함께 긴 경우에만 launcher hot path를 수정합니다.

### 3. Outlier context 수집

각 step에 다음 상태를 기록합니다.

- down/up 방향 및 target
- selected index
- animation active 여부
- state refresh 경과시간
- force-refresh 여부
- pane generation
- tmux IPC duration
- internal render duration

이를 통해 refresh boundary, animation, resize, pane command 변화와 outlier의 상관관계를 확인합니다.

### 3-1. Controlled A/B matrix

동일 geometry, session 목록, HOME, shell, history, run order를 유지한 채 다음 조건을 분리합니다.

| Variant | Animation | Observer | 목적 |
|---|---|---|---|
| A | on | capture-pane | v0.6.7 호환 기준 |
| B | off | capture-pane | animation 영향 확인 |
| C | on | pipe-pane | capture polling 영향 분리 |
| D | off | pipe-pane | 출력 backlog와 animation 상관관계 확인 |
| E | on | trace only | 내부 render 비용 확인 |

각 variant는 warm-up 1회 후 최소 10회 실행하며, A/B 결과는 동일한 run order로 비교합니다.

### 4. 측정 통계 보강

- 기본 smoke run은 10회
- 최종 승격 run은 30회
- warm-up run은 통계에서 제외
- p50/p95/max와 outlier count를 출력
- capture polling latency와 trace latency를 별도 metric으로 유지
- archive는 pending 파일이 아닌 최종 window archive 파일만 측정

### 5. CPU 및 fixture 통일

- idle은 10초 안정화 후 측정
- active는 동일한 AI-like command와 10초 구간 사용
- auto/reproduction 모두 동일 temporary HOME, shell, history, tmux config, pane/window layout 사용
- 측정부 자체 CPU 사용량을 별도 확인

## 테스트 시나리오

1. 10-session down navigation
2. 10-session up navigation
3. five-key burst
4. 5초 refresh 경계 navigation
5. AI-like active command 중 navigation
6. pane command/generation 변경 직후 navigation
7. resize 직후 navigation diagnostic
8. session switch와 target cursor settlement
9. archive/restore 동일 fixture
10. lifecycle/layout/cursor invariant 반복

## 승격 조건

다음 조건을 모두 만족해야 v0.6.8로 기록합니다.

- 30회 최종 측정에서 목표 수치 충족
- navigation 500ms 초과 0회
- internal/external latency 모두 기록
- auto/reproduction fixture 일치 확인
- 정적 검사, gradient, fingerprint, hot-path, state, isolation, lifecycle 회귀 PASS
- 결과 report와 HISTORY/CONVERSATION 기록 완료

목표 미달 시 v0.6.8 tag/승격은 보류하고, outlier trace를 근거로 다음 수정 단계를 정합니다.

## 예상 시사점

- CPU가 개선되지 않고 trace상 tmux IPC가 주원인이면 launcher refresh 구조를 수정합니다.
- internal render는 빠르고 external latency만 높으면 capture/PTY 측정 경로를 분리합니다.
- archive/restore 차이가 fixture 통일 후에도 지속되면 archive serialization/restore layout을 제품 코드 관점에서 분석합니다.

## 현재 개발 결과

- launcher에 selection trace id와 selection update/render trace를 추가했습니다.
- reproduction profile에 `PROFILE_TRACE=true` 내부 측정과 `PROFILE_PIPE_OBSERVER=true` 외부 pipe 측정을 추가했습니다.
- `PROFILE_ANIMATION_ENABLED=false` A/B 모드로 animation 비활성 조건을 동일 profile에서 실행할 수 있게 했습니다.
- animation/age/state row 출력을 batching했습니다.
- auto/reproduction 각각 3회 측정과 reproduction pipe 57 step 측정을 완료했습니다.
- reproduction pipe 결과는 p50 32ms, p95 1188ms, max 1214ms, 500ms 초과 3회입니다.
- 내부 selection render는 진단 sample에서 약 1~7ms로 측정되어 selection 계산보다 tmux/PTY output delivery를 우선 조사해야 합니다.
- animation ON/OFF A/B에서 각각 3/57 step의 500ms 초과가 발생해 animation이 주원인이 아님을 확인했습니다.
- key가 있는 tick에서 age/force-refresh/state maintenance를 다음 tick으로 defer하도록 수정했습니다.
- 수정 후 3회 reproduction pipe 결과는 p50 26ms, p95 37ms, max 51ms, 500ms 초과 0/57입니다.
- capture 기준도 p50 64ms, p95 78ms, max 93ms, 500ms 초과 0/57로 안정화됐습니다.
- 10회 smoke에서는 190 step 중 189개가 500ms 미만이었고, 1개가 `periodic_refresh_collision`에서 1128ms로 재발했습니다.
- 10회 smoke 전체 pipe p50/p95는 27/41ms였으며, 재발 조건 분석을 위해 periodic delay를 환경변수화했습니다.
- `send-keys` dispatch와 pipe observation을 분리한 최신 3회에서는 send p50/p95/max 20/28/33ms, pipe 14/22/25ms, 500ms 초과 0회였습니다.
- 10회에서 관찰된 periodic outlier는 send dispatch가 아닌 pane output observation 단계로 분리되었습니다.
- 30회 final sample(570 navigation step)에서는 periodic outlier 4회가 재발했습니다. pipe p50/p95/max는 14/22/1765ms입니다.
- 30회 기준 idle/active CPU p50은 16.08/15.99%, key 51ms, switch 298ms, archive 350ms, restore 509ms로 최종 목표를 충족하지 못했습니다.
- 기능 run 30/30과 lifecycle/cursor/layout/archive/restore invariant는 PASS했지만 v0.6.8 승격은 보류합니다.
- 현재 CPU, key, switch, archive, navigation p95 목표는 미달이며 v0.6.8 승격은 보류합니다.
- cursor/lifecycle/layout/archive/restore integrity 회귀는 PASS입니다.

## 리뷰 항목

- 30회 최종 표본 수가 적절한지
- navigation resize를 승격 조건에 포함할지 diagnostic으로 유지할지
- physical `Ctrl+a s` 입력 미지원 편차를 허용할지
- archive bytes ±5% 기준을 적용할 동일 fixture가 준비됐는지
- maintenance defer가 30회 sample에서도 안정적인지
- periodic refresh collision을 독립적으로 해결할 방법과 범위
