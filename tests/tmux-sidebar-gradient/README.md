# tmux Sidebar Gradient Tests

이 테스트는 production launcher를 수정하지 않고 현재 gradient renderer, fingerprint, 상태 전이와 tmux lifecycle을 검증한다. 실제 AI CLI나 네트워크는 사용하지 않는다.

## 실행

```sh
bash tests/tmux-sidebar-gradient/run.sh
```

tmux socket 접근이 제한된 sandbox에서는 `test-lifecycle-e2e.sh` 실행에 추가 권한이 필요할 수 있다.

## 구성

- `test-render.sh`: frame별 ANSI gradient와 비활성 렌더 검증
- `test-fingerprint.sh`: 현재 capture 정규화와 fingerprint 변화 검증
- `test-state.sh`: 현재 `active -> waiting -> active` 상태 전이 검증
- `test-session-isolation.sh`: 여러 session의 animation 상태 독립성 검증
- `test-lifecycle-e2e.sh`: 격리 tmux와 fake `codex`를 사용한 시작, 정지, 재시작, 종료 검증
- `test-regressions.sh`: 합의된 향후 개선 대상을 XFAIL로 재현
- `lib.sh`: launcher 함수 로딩, tmux snapshot stub, assertion 공통 helper

## 결과 의미

- `PASS`: 현재 요구사항이 충족됨
- `FAIL`: 기존 동작의 회귀 또는 test harness 오류
- `XFAIL`: 아직 수정하지 않은 알려진 문제를 예상대로 재현함
- `XPASS`: 알려진 문제가 해결됐으므로 XFAIL을 일반 assertion으로 전환해야 함

현재 XFAIL은 한 번의 무변화로 즉시 waiting 전환, 본문 spinner 미정규화, 새 pane generation의 이전 fingerprint 재사용이다.
