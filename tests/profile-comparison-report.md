# TUI Sidebar Profile Comparison Report
Generated At: Fri Jul 17 09:33:00 KST 2026

## Side-by-Side Comparison Table

| Metric                       | Active Session (Pts/2)    | Isolated Session (WSLg)   | Difference / Notes                  |
| :--- | :--- | :--- | :--- |
| 1. Idle CPU (Peak) / RSS     | 4.2% (7.5%) / 3859 KB     | 5.3% (9.0%) / 5141 KB     | 격리 환경이 데몬 오버헤드가 적어 비교적 낮은 RSS 점유 |
| 2. Active CPU (Peak) / RSS   | 3.2% (3.7%) / 3918 KB     | 3.0% (3.5%) / 5144 KB     | 그라디언트 렌더 루프 부하 수준은 두 환경 모두 유사함 |
| 3. Switch Latency            | 11954 ms (Reactivity: 1835 ms) | 35856 ms (Reactivity: 5015 ms) | 격리가 약 23902ms 느림 (입력반응차: 3180ms) |
| 4. Archive Metadata Size     | 8.50 KB / Time: 818 ms    | 8.41 KB / Time: 781 ms    | 백업 속도 비교 (격리: Time: 781 ms / 액티브: Time: 818 ms) |
| 5. Layout Preservation Ratio | 100% (Matched) / Leak: +0 KB | Mismatched / Leak: +0 KB  | 연타 스트레스 검증 (격리 누수: Leak: +0 KB / 액티브 누수: Leak: +0 KB) |
| 6. Restore Accuracy          | Restore Failed / Time: 4977 ms | Restore Failed / Time: 4940 ms | 복원 속도 비교 (격리: Time: 4940 ms / 액티브: Time: 4977 ms) |
| 7. Grid Boundary check       | Overflow by -35 cols / Visual: Cursor Count Error (0) | Overflow by -35 cols / Visual: Cursor Count Error (0) | 임계 리사이즈(15cols) 후 원래 크기(35cols) 복원 및 그리드 정상 회복 여부 검증 |

## AI Auto-Analysis & Optimization Targets
* **Resource Usage**: 격리 환경이 데몬 오버헤드가 적어 비교적 낮은 RSS 점유. 그라디언트 렌더 루프 부하 수준은 두 환경 모두 유사함.
* **Latency Gap**: 격리가 약 23902ms 느림 (입력반응차: 3180ms)
* **Restore & Layout Bugs**: 연타 스트레스 검증 (격리 누수: Leak: +0 KB / 액티브 누수: Leak: +0 KB). 복원 속도 비교 (격리: Time: 4940 ms / 액티브: Time: 4977 ms).
