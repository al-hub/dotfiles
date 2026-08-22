# tmux Sidebar Baseline Guide

이 저장소의 성능 baseline은 사용자 실시간 tmux 서버가 아니라, 매 run마다 새로 만드는 전용 tmux socket과 attached `urxvt` client에서 측정합니다. 측정 대상은 설치된 `~/.local/bin/tmux-session-launcher`가 아닌 현재 checkout의 `scripts/tmux-session-launcher`입니다.

## 실행

```bash
bash tests/compare-profiles.sh
```

기본값은 3회 반복입니다. 반복 횟수와 보고서 경로는 명시적으로 바꿀 수 있습니다.

```bash
bash tests/compare-profiles.sh --runs 5 --report /tmp/sidebar-baseline.md
```

결과는 기본적으로 `tests/profile-comparison-report.md`에 기록됩니다. 수치는 중앙값과 전체 관측 범위를 함께 표시합니다.

## 측정 원칙

- 각 run은 고유 tmux socket, 100x30 `urxvt` client, 임시 history directory를 사용합니다.
- idle/active CPU는 `ps %cpu`의 프로세스 생애 평균이 아니라 측정 구간의 `/proc/PID/stat` tick 차이로 계산합니다.
- RSS는 같은 측정 구간에 반복 수집한 launcher process의 peak 값입니다.
- key 반응, session 전환, archive, restore는 실제 완료 조건까지 측정하며 각 준비 조건의 30초 deadline을 넘기면 run을 실패시킵니다.
- restore pane/window 수, 반복 sidebar open/close 뒤 layout, grid 폭과 cursor 개수는 모든 run에서 invariant를 만족해야 합니다.
- 실패나 빈 capture를 음수 overflow 같은 정상 수치로 변환하지 않습니다.

`tests/profile-active-sidebar.sh`는 호환성을 위해 남아 있지만 동일한 격리 측정을 호출합니다. 과거 구현은 사용자 세션을 만들고 마지막에 기본 tmux server를 종료했기 때문에 재현 가능한 baseline으로 사용하지 않습니다.

서로 다른 revision을 비교할 때는 같은 장비, terminal geometry, `PROFILE_SECONDS`, run 횟수를 유지하고 두 보고서의 revision 및 dirty 상태를 함께 보관합니다.
