# 📚 dotfiles 문서 허브 (Documentation Hub)

본 디렉터리는 dotfiles 저장소의 아키텍처, 사용자 가이드, 상세 설계, 테스트 계획 및 과거 분석 문서를 체계적으로 정리한 문서 허브입니다.

---

## 📖 1. 표준 도메인 용어 사전 (Canonical Glossary)

프로젝트 전반(코드, 설정, 주석, 문서)에서 일관되게 사용하는 핵심 표준 용어입니다:

| 표준 용어 (영문/한글) | 정의 및 역할 | 관련 식별자 / 구현 파일 |
| :--- | :--- | :--- |
| **Sidebar (사이드바)** | 화면 좌측에 고정 폭으로 도킹되는 전체 영역 (세션 런처 및 서브페인 포함) | `@dotfiles_sidebar_managed`, `scripts/tmux-session-launcher` |
| **Presenter (프레젠터)** | 각 관리 윈도우의 사이드바 내에 상주하는 Thin TUI 렌더링 페인 | `dotfiles-session-sidebar`, `scripts/lib/sidebar_port_tmux.sh` |
| **Subpane (서브페인)** | 사이드바 컬럼 내부 상단 또는 하단에 위치하는 보조 터미널 페인 | `dotfiles-sidebar-subpane`, `@dotfiles_sidebar_subpane` |
| **Subpane Hub (서브페인 허브)** | 서브페인의 단일 물리 인스턴스를 보관·이동시키는 백그라운드 싱글톤 세션 | `dotfiles-subpane-hub`, `scripts/lib/sidebar_subpane_hub.sh` |
| **Work Pane (작업 페인)** | 사이드바를 제외한 실제 사용자의 작업 터미널 / 에디터 페인 | `@dotfiles_work_pane` |
| **Managed Window (관리 대상 윈도우)** | 사이드바가 프로비저닝되는 대상 사용자 윈도우 | `ensure_sidebar_window` |
| **Marker Handover (마커 핸드오버)** | 세션 전환 시 타겟 사이드바에 선택 마커(`*`, `>`)를 원자적으로 전달·동기화하는 메커니즘 | `@dotfiles_sidebar_target_marker`, `sidebar_switch.sh` |
| **Selection Coordinator (선택 코디네이터)** | 세션 인덱스 정합 및 마커 델타 렌더링 범위를 계산하는 순수 도메인 리듀서 | `scripts/lib/sidebar_coordinator.sh` |

---

## 🗂️ 2. 문서 분류 및 색인 (Documentation Index)

### 📌 주요 진입점 (Top-Level)
- [**`keybindings.md`**](keybindings.md): 전체 단축키 & 마우스 조작 가이드
- [**`architecture.md`**](architecture.md): 전체 dotfiles 설치 모델 및 모듈 아키텍처

---

### 📘 사용자 및 설정 가이드 (`guides/`)
- [**`guides/tmux-theme.md`**](guides/tmux-theme.md): 16종 프리미엄 컬러 테마 및 실시간 테마 피커 가이드
- [**`guides/opencode.md`**](guides/opencode.md): OpenCode 설정 및 CLI 설치 가이드
- [**`guides/vim.md`**](guides/vim.md): Vim 플러그인 및 설정 가이드
- [**`guides/reproduction.md`**](guides/reproduction.md): 실환경 재현, 테스트 및 문제 해결 가이드

---

### 📐 핵심 컴포넌트 설계 (`design/`)
- [**`design/tmux-single-sidebar.md`**](design/tmux-single-sidebar.md): Window-Local Thin Presenter 기반 단일 사이드바 설계
- [**`design/tmux-session-launcher-internals.md`**](design/tmux-session-launcher-internals.md): 세션 런처 내부 동작 원리 및 IPC 파이프라인 마스터 문서
- [**`design/architecture-review.html`**](design/architecture-review.html): **[인터랙티브 웹 보고서]** Tailwind & Mermaid 기반 아키텍처 다이어그램 및 리팩토링 리뷰

---

### 🧪 테스트 계획 및 검증 (`testing/`)
- [**`testing/test-matrix.md`**](testing/test-matrix.md): 테스트 Gate A~E 분류, 변경 범위별 최소 실행 세트
- [**`testing/window-local-test-plan.md`**](testing/window-local-test-plan.md): 윈도우 로컬 사이드바 테스트 경계 및 정량 기준
- [**`testing/user-tmux-required-test.md`**](testing/user-tmux-required-test.md): 사용자 기본 tmux 환경 필수 동작 검증 가이드
- [**`testing/live-full-monitored-test.md`**](testing/live-full-monitored-test.md): 실시간 모니터링 E2E 테스트 가이드

---

### 📜 과거 분석 및 벤치마크 기록 (`archives/`)
- [**`archives/live-session-switch-regression.md`**](archives/live-session-switch-regression.md): 세션 전환 회귀 분석 및 원인 규명
- [**`archives/live-usage-side-effects.md`**](archives/live-usage-side-effects.md): 실사용 사이드이펙트 및 버그 오딧 기록
- [**`archives/profile-baseline-report.md`**](archives/profile-baseline-report.md): 성능 프로파일링 기준선 측정 리포트
- [**`archives/sidebar-transition-measurement.md`**](archives/sidebar-transition-measurement.md): 사이드바 전환 레이턴시 측정 리포트
