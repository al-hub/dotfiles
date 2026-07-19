# Sidebar profile reports

모든 리포트는 `tests/compare-profiles.sh`가 생성하는 동일한 표 형식을 사용합니다.

- `v0.6.md`: v6.0 기준 측정
- `v0.6.1.md`: v6.1 캐시/스로틀링 1차 개선 측정
- `v0.6.2.md`: 입력 loop, topology cache, archive/restore 경로 최적화 결과
- `v0.6.3.md`: 조건부 pane 상태 갱신 및 restore 경로 개선 결과
- `v0.6.4.md`: geometry hot path와 passive probe 최적화 결과
- `v0.6.5.md`: lifecycle race 안정화 및 최종 3회 profile 결과
- `v0.6.6.md`: 선택 행 출력 최적화 및 launcher-owned lifecycle 검증 결과
- `v0.6.7.md`: 내부 render trace와 PTY/capture-pane 관측 분리 결과

`PROFILE_PIPE_OBSERVER=true`는 표준 metric을 바꾸지 않는 persistent raw-stream 진단 모드입니다.

10개 session 순차 이동 시나리오는 `tests/profile-sidebar-navigation.sh`와 `v0.6.7-navigation-10.md`에 기록합니다.

확장 자동 시나리오는 `tests/profile-isolated-sidebar-auto.sh`와 `v0.6.7-auto.md`에 기록합니다.

`docs/reproduction.md` attached-client 절차를 따르는 비교 profile은 `tests/profile-isolated-sidebar-reproduction.sh`와 `v0.6.7-reproduction.md`에 기록합니다.

reproduction profile은 source/target client session, sidebar 단일성, 실제 안정화 시간을 별도 `REPRO_*` metric으로 기록합니다.

각 파일의 geometry, 실행 횟수, metric 이름을 변경하지 않아 버전 간 직접 비교할 수 있도록 유지합니다.
- `v0.6.8-reproduction.md`: selection trace, pipe-observer, navigation p95/max를 포함한 v0.6.8 개발 측정 보고서입니다. 목표 미달 결과도 승격 보류 근거로 기록합니다.
- `v0.6.9-reproduction.md`: periodic refresh 통제군과 command signature 최적화 결과를 기록합니다.
- `v0.6.10-reproduction.md`: archive/restore phase 계측과 snapshot 단일 파싱 반복 결과를 기록합니다. 목표 미달이면 승격하지 않습니다.

세 축 분리 진단은 `tests/profile-tmux-settlement.sh`(tmux/PTY settlement)와 `tests/profile-observer-settlement.sh`(capture-pane/pipe-pane observer)로 실행하며, launcher 내부 시간은 reproduction의 `INTERNAL` trace metric으로 기록합니다.

저비용 collection 로그는 `PROFILE_METRICS=true`로 활성화합니다. launcher는 `TMUX_SESSION_LAUNCHER_METRICS_FILE`에 collection aggregate를 메모리 버퍼링 후 주기적으로 기록하며 기본 실행에서는 비활성입니다. per-event trace와 성능 판정용 metrics는 서로 구분합니다.
