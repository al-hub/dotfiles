# v0.6.9 reproduction navigation tail 개선 계획

## 목적

v0.6.8의 30회 reproduction에서 일반 navigation은 안정화되었지만, periodic refresh와 PTY 출력 관찰이 겹친 4/570 단계가 1초 이상 지연되었습니다. v0.6.9는 상태 갱신 기능을 유지하면서 입력 직후 maintenance가 출력 경로를 점유하지 않도록 하고, 동일한 reproduction profile로 효과를 검증합니다.

## 구현 범위

1. 입력 후 maintenance cooldown

   - 마지막 입력 시각을 microsecond 단위로 기록합니다.
   - 기본 250ms 동안 age-cell, force-refresh 확인, periodic state refresh를 defer합니다.
   - defer는 state refresh를 삭제하는 것이 아니라 다음 idle tick으로 미룹니다.
   - `TMUX_SESSION_SIDEBAR_KEY_MAINTENANCE_COOLDOWN_MS`로 실험값을 조절합니다.

2. trace 및 profile 검증

   - `recent-input` defer 이벤트를 trace에 남깁니다.
   - send dispatch, pipe observation, capture observation을 계속 분리합니다.
   - 3회 smoke로 회귀 여부를 확인한 뒤 10회, 필요하면 30회로 확대합니다.
   - `PROFILE_STATE_REFRESH_SECONDS=3600` 통제군을 기본 5초 refresh군과 비교해 periodic refresh 원인을 분리합니다.

3. 기능 보존

   - 5초 fallback refresh와 force-refresh IPC는 유지합니다.
   - session switch, AI 상태 전이, archive/restore, lifecycle/layout/cursor invariant를 재검증합니다.

## 측정 목표

| 항목 | v0.6.8 30회 결과 | v0.6.9 단계 목표 |
|---|---:|---:|
| pipe navigation p95 | 22ms | ≤30ms |
| pipe navigation max | 1765ms | <500ms |
| navigation 500ms 초과 | 4/570 | 0/570 |
| key latency p50 | 51ms | ≤45ms |
| 기능/수명주기 invariant | PASS | PASS 유지 |

CPU와 archive/restore 목표는 이번 단계의 직접 승격 조건이 아니라 별도 후속 최적화 대상으로 계속 기록합니다.

## 검증 순서

```sh
bash -n scripts/tmux-session-launcher
bash -n tests/profile-isolated-sidebar-reproduction.sh
PROFILE_RUNS=3 bash tests/profile-isolated-sidebar-reproduction.sh
bash tests/tmux-sidebar-gradient/run.sh
git diff --check
```

3회 결과가 안정적이면 동일 fixture로 10회 smoke를 실행합니다. periodic outlier가 남으면 cooldown 값을 100/250/400ms로 controlled A/B 비교합니다. refresh 비활성 통제군에서도 outlier가 남으면 제품 코드보다 tmux/PTY 측정 경로를 우선 조사합니다.

## 승격/리뷰 원칙

- 목표와 회귀 invariant를 모두 만족하기 전에는 v0.6.9 승격, tag, commit, push를 하지 않습니다.
- 결과는 v0.6.8 reproduction report와 동일한 metric명으로 기록합니다.
- worker/background 구조는 cooldown 실험 결과로도 outlier가 남을 때 별도 설계·리뷰 대상으로 분리합니다.

## 현재 단계 결과

- 입력 직후 cooldown만 적용한 smoke에서는 periodic 단계가 1791ms로 재발했습니다.
- `PROFILE_STATE_REFRESH_SECONDS=3600` 통제군에서는 동일 periodic 단계가 67ms였습니다.
- 선택 session의 pane command signature가 안정적이면 전체 `collect_sessions`를 건너뛰도록 수정했습니다.
- 수정 후 기본 5초 refresh 조건의 periodic 단계는 69ms였고, navigation 기능·layout·cursor·archive/restore invariant가 PASS했습니다.
- idle/active CPU는 16.14/15.66%, key 47ms, switch 292ms, archive 357ms, restore 502ms로 전체 도전 목표는 아직 미달입니다.
- 전체 gradient/fingerprint/hot-path/state/isolation/regression/lifecycle 회귀 테스트는 PASS했습니다.
- 남은 위험은 AI child process가 shell pane 안에서 command 이름을 유지한 채 시작되는 전이입니다. 이 경우 command signature만으로는 감지하지 못할 수 있으므로 AI 상태 전이 회귀를 추가 확인해야 합니다.
- command signature가 안정적인 busy session의 snapshot 생략과 `sleep → codex` command transition 재스캔 regression을 추가했고 9/9 PASS했습니다.
- shell pane은 선택 session refresh에서만 child AI probe를 허용하고 startup 전체 scan에서는 생략하도록 범위를 조정했습니다.
- shell child AI process fixture regression까지 추가해 10/10 PASS했습니다.
- 최종 reproduction에서 periodic 단계는 68ms, key 47ms, layout/cursor/archive/restore invariant는 PASS했습니다.
- hot-path activity display 호출 수는 기존 기준 4회로 유지됐습니다.
- idle/active CPU 16.63/16.40%, switch 864ms, archive 381ms, restore 484ms로 전체 도전 목표는 여전히 미달입니다.

## CPU polling 실험 결과

- blocking `read`와 signal timer를 결합하는 실험을 수행했습니다.
- blocking `read`는 `USR1`에 의해 안정적으로 깨어나지 않아 lifecycle-e2e가 실패했습니다.
- timeout read를 유지하고 signal timer만 활성화한 reproduction 결과는 idle/active CPU 16.33/16.66%로 개선되지 않았습니다.
- key 49ms, switch 724ms, archive 325ms, restore 440ms, periodic navigation 91ms였습니다.
- 따라서 polling 제거는 별도 event/input reader 구조 없이는 달성되지 않는 것으로 결론 내리고 해당 변경은 채택하지 않습니다.

## 비선택 process probe 제한 결과

- 선택 session 외에는 AI 명령으로 식별된 pane만 process probe하도록 제한했습니다.
- 전체 sidebar regression 10/10과 lifecycle/layout/cursor/archive/restore invariant는 PASS했습니다.
- reproduction 결과 idle/active CPU 16.95/16.27%, key 50ms, switch 483ms, archive 345ms, restore 510ms, periodic navigation 71ms였습니다.
- CPU가 개선되지 않아 process probe는 전체 CPU 병목이 아닌 것으로 판정합니다.
- archive/restore 목표도 미달이므로 다음 단계에서는 archive 실행·restore sidebar 생성·측정부 대기 구간을 별도 계측합니다.

## restore sidebar direct-open 결과

- restore 완료 후 `ensure_sidebar_for_session`의 중복 전체 pane 조회를 제거했습니다.
- 저장된 sidebar width를 직접 사용하고 target session에 `open_sidebar`를 호출하도록 변경했습니다.
- restore 단일 reproduction은 510ms에서 418ms까지 개선된 sample을 확인했습니다.
- archive 322ms, idle/active CPU 16.27/16.13%, key 46ms, switch 525ms로 나머지 목표는 미달입니다.
- restore 순서 변경은 sample 편차가 커 효과가 확인되지 않아 원래 switch 순서로 유지합니다.
