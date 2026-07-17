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

각 파일의 geometry, 실행 횟수, metric 이름을 변경하지 않아 버전 간 직접 비교할 수 있도록 유지합니다.
