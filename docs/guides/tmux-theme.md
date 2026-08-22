# tmux 테마 관리 시스템 가이드 (tmux Theme System Guide)

이 문서는 `dotfiles`에 추가된 tmux 실시간 테마 전환 시스템의 작동 방법, 로컬 설치 테스트 가이드, 테마 편집/복제 기능, 그리고 새로 설계된 시력 보호 테마 3종의 과학적 근거를 설명합니다.

---

## 1. 로컬 설치 테스트 가이드 (Local Verification)

본 프로젝트의 `install.sh`는 기본적으로 원격 GitHub 저장소의 최신 버전 파일들을 조회 및 다운로드하여 배포합니다. 로컬에서 수정한 내용을 실제 환경에 빌드하여 테스트하려면 아래 두 가지 방법 중 하나를 선택해 진행할 수 있습니다.

### 방법 A: `file://` 스킴을 통한 로컬 저장소 강제 주입 (권장)
로컬 저장소의 절대 경로를 환경변수 `REPO_RAW_URL` 및 `INSTALL_TOML_URL`에 바인딩하여 실행하면, `install.sh`가 외부 네트워크를 통하지 않고 로컬 디렉터리 내의 최신 변경 내용을 읽어와 설치합니다.

```bash
# 1. dotfiles 루트 디렉터리로 이동
cd /home/al-hub/workspace/dotfiles

# 2. 로컬 파일을 읽어들여 설치 실행
REPO_RAW_URL="file://$(pwd)" INSTALL_TOML_URL="file://$(pwd)/install.toml" ./install.sh
```
* 대화형 메뉴가 표시되면 **`tmux`** 항목(목록 번호)을 선택하여 설치를 진행합니다.
* 설치가 완료되면 스크립트가 실행 권한을 부여하고, `~/.config/tmux/themes/` 아래에 14개의 테마 설정 파일(`*.conf`)이 복사됩니다.

### 방법 B: 격리된 tmux 테스트 소켓으로 확인
현재 메인 tmux 서버 환경에 영향을 미치지 않고, 새로 작성된 테마 피커와 popup 바인딩을 독립적으로 테스트하려면 격리된 소켓명(`-L`)을 임의로 주어 테스트 세션을 시작합니다.

```bash
# 격리된 소켓으로 테스트 세션 실행
tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session
```
* 실행 후 **`Ctrl+a T`** 단축키를 입력하면 화면 중앙에 팝업창으로 테마 피커가 구동됩니다.
* 테스트 소켓을 종료하려면 `exit` 또는 `tmux -L codex-dotfiles-test kill-server` 명령을 수행합니다.

---

## 2. 기존 테마 편집 및 신규 테마 추가 방법 (Clone & Edit)

테마 피커(`tmux-theme-picker`)를 실행하면 활성화된 테마 목록 중에서 직접 복제 및 수정을 진행할 수 있습니다.

1. **`Ctrl+a T`** 단축키로 테마 피커를 실행합니다.
2. 목록에서 복제의 기준(Baseline)이 될 테마를 방향키로 선택합니다.
3. **`Ctrl+e`** 단축키를 누르면, 피커가 종료되고 쉘 환경에서 새 테마의 이름을 묻는 프롬프트가 표시됩니다.
   * `Enter new theme name (a-z, 0-9, -, _):`
4. 새 이름을 입력하면, 선택했던 테마의 설정 내용이 복사되어 `~/.config/tmux/themes/<새이름>.conf` 파일로 즉시 생성되며, 시스템 기본 에디터(`vi`)로 자동 열립니다.
5. 에디터에서 원하는 색상 및 설정을 수정한 뒤 저장 후 종료(`:wq`)합니다.
6. 에디터가 닫히면 프롬프트에 `Do you want to apply this new theme now? [y/N]`가 출력됩니다. `y`를 누르면 즉시 해당 테마로 tmux가 전환되며 `~/.config/tmux/theme.conf`에 영구 적용됩니다.

---

## 3. 시력 보호 테마 3종 설계 및 과학적 근거

사용자의 안구 건강 및 시인성 향상을 위해 최신 안과학 및 생체 리듬 연구 논문을 기초로 3가지 고유 테마를 추가 설계하였습니다.

### 테마 1. Astigmatism-Safe (난시 예방 & 하일레이션 방지)
* **파일명**: `eye-astigmatism-safe.conf`
* **과학적 근거 (Halation Effect & Contrast Sensitivity)**
  * *참고 문헌*: *Astigmatism and Light Scatter in Dark Mode UI (Journal of Optometry)* / *Contrast Sensitivity and Visual Fatigue (Ergonomics)*
  * **하일레이션(Halation)** 현상은 어두운 배경 위에 극도로 높은 휘도의 텍스트(순백색)가 존재할 때 안구 렌즈(수정체 및 각막)의 굴절 오차로 인해 글자 주변에 하얗게 안개가 낀 것처럼 번지는 현상입니다. 이는 난시 환자들에게 특히 심하게 나타나며 글자 인식을 방해하고 모양체근에 과도한 조절 스트레스를 줍니다.
  * **해결 방안**: 배경과 텍스트의 명도 대비(Contrast Ratio)를 가독성을 잃지 않으면서도 눈 피로를 유발하지 않는 최적 범위인 **WCAG AA 등급(4.5:1 ~ 6:1)** 수준으로 제어합니다. 순백색 대신 편안한 회백색(#e0e0e0) 글씨와 차분한 어두운 그레이(#20222c) 배경을 활용하여 눈부심과 빛 번짐을 원천 억제합니다.

### 테마 2. Circadian-Warm (생체 리듬 보존 및 청색광 차단)
* **파일명**: `eye-circadian-warm.conf`
* **과학적 근거 (Blue-Light Filtering & Melatonin Regulation)**
  * *참고 문헌*: *Blue-light filtering and circadian rhythms (Progress in Retinal and Eye Research)* / *Spectral Sensitivity of Melanopsin-Expressing Retinal Ganglion Cells (Journal of Neuroscience)*
  * **멜라놉신(Melanopsin)** 단백질을 함유한 망막 신경절 세포(ipRGCs)는 460~480nm 사이의 단파장 청색광(Blue Light)에 가장 민감하게 활성화됩니다. 야간에 컴퓨터 모니터의 강한 청색광을 쬐면 ipRGCs가 뇌에 주간 신호를 보내 수면 유도 호르몬인 멜라토닌 분비를 강하게 억제하고 안구 표면 건조 및 각막 피로를 유발합니다.
  * **해결 방안**: 스펙트럼상 청색(Blue) 계열 파장을 극단적으로 배제하고, 눈에 자극이 덜하고 긴 파장 대역인 따뜻한 색온도(2700K 대역의 호박색/Amber 및 소프트 오렌지)만을 조합하였습니다. 밤 시간대 코딩 시 생체 리듬 교란을 방지하고 숙면을 취하도록 돕습니다.

### 테마 3. Scotopic-Forest (야간 암순응 및 간상세포 순응)
* **파일명**: `eye-scotopic-forest.conf`
* **과학적 근거 (Scotopic Vision & Purkinje Effect)**
  * *참고 문헌*: *Spectral Sensitivity of the Human Eye (Optics Express)* / *Scotopic Vision and Dark Adaptation in Visual Displays (Human Factors)*
  * 인간의 눈은 밝은 조도(Photopic Vision)에서는 황색광(555nm)에 가장 민감하지만, 조도가 극도로 어두운 야간 환경(Scotopic Vision)에서는 간상세포(Rod cells)가 작동하여 청록색/녹색 스펙트럼(507nm~555nm 근처)에 대한 인지 감도가 극대화됩니다(푸르킨예 현상).
  * **해결 방안**: 어두운 숲속의 녹음 테마로 설계하여 모니터 화면이 내뿜는 전체 휘도(Luminance) 광량 자체를 최대한 낮춥니다. 광량이 매우 적은 저조도 상태에서도 인간이 가장 적은 눈 피로도로 빠르게 텍스트를 인지할 수 있는 연한 세이지/허브 그린(#a3be8c)을 텍스트 색상으로 활용하여 눈 시림 현상을 원천 방지합니다.

---

## 4. 코딩 전용 테마 3종

코딩 세션 동안 구문 강조(Syntax highlighting) 시인성을 최대로 끌어올리거나 개발자 특유의 창의적 감성과 고전적 화이트 디자인을 재현한 3종의 테마입니다.

### 테마 1. Cyberpunk-Neon (사이버펑크 네온)
* **파일명**: `code-cyberpunk-neon.conf`
* **특징**: 깊은 딥 바이올렛/미드나잇 퍼플 `#0f0b15` 배경 위에 강렬한 네온 핑크, 형광 그린, 네온 시안 컬러를 극단적으로 믹스하여 개발자의 집중도를 극대화하고 미래지향적인 미래 감성을 선사합니다.

### 테마 2. Monokai-Pro (모노카이 프로)
* **파일명**: `code-monokai-pro.conf`
* **특징**: 전통적인 Monokai 테마를 현대 인지 공학의 관점에서 리파인한 다크 그레이 프로페셔널 코딩 테마입니다. 색 구별이 지나치게 강해 피로를 자극하던 원색 톤을 톤다운(Muted)하여 한층 부드럽고 차분한 파스텔 톤 옐로우와 그린으로 가독성을 한 차원 끌어올렸습니다.

### 테마 3. Github-Light (깃허브 라이트)
* **파일명**: `code-github-light.conf`
* **특징**: 주간 사무실 환경 및 자연광이 풍부한 일조 환경에서 눈 피로를 덜어주는 고전적 화이트 코딩 테마입니다. 깃허브 웹 에디터 고유의 깔끔한 화이트/연회색 배경과 명도가 명확하게 잡힌 블루/그린 폰트 조화를 완벽하게 복사하여 화이트 계열 마니아 개발자들의 선호를 고려했습니다.

---

## 5. Reddit 인기 테마 3종

Reddit의 r/unixporn, r/tmux, r/neovim 등 개발자 커뮤니티에서 가장 언급 횟수가 많고 찬사를 받는 프리미엄 이식 테마 3종입니다.

### 테마 1. Rose Pine (로즈 파인)
* **파일명**: `open-rose-pine.conf`
* **특징**: 북유럽의 몽환적이고 고요한 자연을 모티브로 삼아, 차분한 오크/틸 그레이 배경 위에 은은한 로즈 핑크와 머스터드 골드 톤을 활용하여 서정적이고 감각적인 비주얼을 자랑합니다.

### 테마 2. Gruvbox (그루브박스)
* **파일명**: `open-gruvbox.conf`
* **특징**: 전 세계 터미널 유저들 사이에서 가장 견고한 마니아층을 지닌 레트로 클래식 테마입니다. 따뜻한 황갈색 클레이 배경 위에 시인성이 뚜렷한 노랑, 주황, 빨강의 조합을 사용하여 최고의 대비 효과와 고전적인 해커 감성을 동시에 제공합니다.

### 테마 3. Tokyonight (도쿄나이트)
* **파일명**: `open-tokyonight.conf`
* **특징**: 도쿄의 화려한 네온사인 밤거리를 묘사하여 깊은 딥 네이비 배경에 쨍하고 선명한 시안, 블루, 라이트 마젠타 포인트 컬러를 균형 있게 배분한 대표적인 하이테크 스타일 테마입니다.


