# TUI Sidebar Performance Baseline Report (Current Version)

이 보고서는 tmux 세션 런처 TUI 사이드바의 현재 버전 성능 및 안정성 baseline 측정 데이터를 영구 기록한 문서입니다. 실시간 사용자 세션(Active Session)과 격리된 X11 가상 터미널 환경(Isolated Sandbox Session)에서의 실측 비교 지표를 다룹니다.

---

## 1. 종합 성능 비교 대조표 (Performance Baseline Table)

| 시나리오 / 정량 평가 지표 | Active Session (pts/x) | Isolated Sandbox (WSLg) | 환경적 변이 및 원인 분석 |
| :--- | :--- | :--- | :--- |
| **1. Idle CPU (Peak) / RSS** | 4.2% (7.5%) / 3859 KB | 5.3% (9.0%) / 5141 KB | 격리 샌드박스의 개별 tmux 데몬 구동 오버헤드로 인해 물리 메모리(RSS) 점유가 약 1.2MB 높게 나옵니다. |
| **2. Active CPU (Peak) / RSS** | 3.2% (3.7%) / 3918 KB | 3.0% (3.5%) / 5144 KB | 그라디언트 렌더 루프 및 애니메이션 갱신 시 두 프로필 모두 3%대 안팎의 낮은 CPU 자원을 사용합니다. |
| **3. Switch Latency** | **11,954 ms** <br>(Reactivity: 1,835 ms) | **35,856 ms** <br>(Reactivity: 5,015 ms) | 격리 환경이 약 23.9초 느립니다. 순수 첫 키 입력 반응속도(TUI 커서 이동)의 경우 로컬 액티브는 **1.8초**, 가상 XWayland 루프백 환경은 **5.0초**가 소요됩니다. |
| **4. Archive Metadata Size** | 8.50 KB <br>(Duration: 818 ms) | 8.41 KB <br>(Duration: 781 ms) | CLI 기반 삭제-아카이브 백업 명령은 약 **780~820 ms** 내에 수행 완료되며, 생성되는 TSV 메타데이터 규격은 완벽히 대등합니다. |
| **5. Layout Preservation** | 100% (Matched) <br>(Leak: +0 KB) | Mismatched <br>(Leak: +0 KB) | 연타 스트레스 테스트 시 양쪽 환경 모두 메모리 누수(`+0 KB`)는 없습니다. 다만, 격리 환경은 WSLg 기동 해상도 변이로 인해 사이드바 재기동 후 윈도우 레이아웃이 어긋납니다. |
| **6. Restore Accuracy** | **Restore Failed** <br>(Duration: 4,977 ms) | **Restore Failed** <br>(Duration: 4,940 ms) | 세션 구조(Pane, Window)와 작업 경로를 아카이브 파일로부터 복원하는 과정이 두 환경 모두 실패하며, 복원 엔진의 구조적 버그가 존재합니다. |
| **7. Grid & Resize Resilience** | Overflow by -35 cols <br>(Cursor Count: 0) | Overflow by -35 cols <br>(Cursor Count: 0) | 판넬 가로폭을 극단적 수준인 `15cols`로 찌그러트린 뒤 원래 크기(`35cols`)로 복원했을 때, 그리드 깨짐이나 문자열 흘러내림 없이 회복됩니다. |

---

## 2. 정량 지표 기반 병목 지점 정밀 진단 (Diagnostic Details)

### 1) 세션 전환(Switch Client) 지연 원인
* **현상**: 전환 지연이 최소 11.9초에서 35.8초까지 지속됩니다.
* **진단**: 첫 방향키 조작 반응성(Reactivity)은 1.8초/5.0초에 불과합니다. 지연의 80% 이상은 `switch-client` 동작 직후 tmux가 원래 터미널 클라이언트를 분리하고, 타겟 세션으로 넘겨 repainting을 완료하는 과정에서 발생합니다.

### 2) 세션 복원 실패 (Restore Failed)
* **현상**: 시나리오 6의 구조적 무결성 체크에서 복원된 세션이 정상 마운트되지 않습니다.
* **진단**: 아카이브 메타데이터 파일(.tsv)의 작업 경로 및 패널 윈도우 맵 파싱 과정 중 세션 구조의 무결성 복원 엔진 오작동이 확인되었습니다.

### 3) 샌드박스 레이아웃 불일치 (Layout Mismatch)
* **현상**: 실시간 액티브 세션에서는 레이아웃이 100% 원복되는 반면, 격리 가상 터미널 환경에서는 불일치(Mismatched)합니다.
* **진단**: 가상 X11 디스플레이를 띄우는 `urxvt` 기동 시점이 연타 스트레스 토글 속도(0.15초)보다 느려 해상도 초기값 지연으로 인한 윈도우 지오메트리 불일치가 관찰됩니다.

---

## 3. 재현 및 성능 지표 검증 가이드 (Reproduction Guide)

이 성능 baseline 보고서는 다음 단일 커맨드로 완전히 자동화 측정하여 재현 및 대조할 수 있습니다.

```bash
# 전체 대조 프로파일링 구동 (X11 클라이언트 자동 기동 및 클린업 연동)
bash tests/compare-profiles.sh
```

측정이 완료되면 실시간 데이터 분석 테이블이 `tests/profile-comparison-report.md`에 실시간으로 작성 및 갱신되며, 백그라운드 프로세스로 생성되었던 임시 터미널과 tmux 소켓 서버는 깔끔히 종료(Terminated) 처리됩니다.
