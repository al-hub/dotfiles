#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh
#
# dotfiles 통합 테스트 러너 (Unified Test Suite Runner)
# Gate A~E, 서브페인, 그래디언트 및 헬스 체크를 통합 실행하고 리포트를 제공합니다.
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"
SINGLE_DIR="${TESTS_DIR}/tmux-single-sidebar"
GRADIENT_DIR="${TESTS_DIR}/tmux-sidebar-gradient"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TARGET_SUITE=""
FAIL_FAST=0
QUICK_MODE=0

usage() {
    cat <<EOF
사용법: $0 [옵션]

옵션:
  -a, --gate a, --gate-a    Gate A: 빠른 계약 및 단위 테스트 (Fast Contracts & Units)
  -b, --gate b, --gate-b    Gate B: 격리된 Attached-PTY 기능 회귀 (Isolated PTY E2E)
  -c, --gate c, --gate-c    Gate C: 멀티 클라이언트 및 소유권 (Multi-client & Ownership)
  -s, --subpane             서브페인(Subpane) 종합 스위트 (Unit/Contract/Position/Fidelity)
  -g, --gradient            사이드바 애니메이션 및 웨이브폼 스위트 (Waveform & Renderer)
  --stress                  스트레스 및 고속 연속 전환/락 회수 스위트
  --edge                    복원 엣지케이스, 손상 복구 및 관측성 스위트
  -h, --health              테스트 스위트 건전성(Health) 분석 및 감사 리포트
  --all                     Gate A, B, C, Subpane, Gradient 순차 종합 실행
  --quick                   빠른 실행 모드 (긴 PTY 대기 테스트 제외)
  -f, --fail-fast           테스트 실패 시 즉시 중단
  --help                    도움말 출력
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--gate-a|--gate\ a) TARGET_SUITE="gate_a"; shift ;;
        --gate)
            if [[ "${2:-}" =~ ^[a-eA-E]$ ]]; then
                TARGET_SUITE="gate_$(echo "$2" | tr '[:upper:]' '[:lower:]')"
                shift 2
            else
                echo -e "${RED}잘못된 Gate 지정: ${2:-}${NC}" >&2; exit 1
            fi
            ;;
        -b|--gate-b) TARGET_SUITE="gate_b"; shift ;;
        -c|--gate-c) TARGET_SUITE="gate_c"; shift ;;
        -s|--subpane) TARGET_SUITE="subpane"; shift ;;
        -g|--gradient) TARGET_SUITE="gradient"; shift ;;
        --stress) TARGET_SUITE="stress"; shift ;;
        --edge) TARGET_SUITE="edge"; shift ;;
        -h|--health) TARGET_SUITE="health"; shift ;;
        --all) TARGET_SUITE="all"; shift ;;
        --quick) QUICK_MODE=1; shift ;;
        -f|--fail-fast) FAIL_FAST=1; shift ;;
        --help) usage ;;
        *) echo -e "${RED}알 수 없는 옵션: $1${NC}" >&2; usage ;;
    esac
done

if [ -z "${TARGET_SUITE}" ]; then
    usage
fi

if [ "${TARGET_SUITE}" = "health" ]; then
    exec bash "${TESTS_DIR}/analyze-test-health.sh"
fi

TEST_LIST=()

case "${TARGET_SUITE}" in
    gate_a)
        TEST_LIST=(
            "${SINGLE_DIR}/test-domain-unit.sh"
            "${SINGLE_DIR}/test-presenter-unit.sh"
            "${SINGLE_DIR}/test-coordinator-unit.sh"
            "${SINGLE_DIR}/test-archive-unit.sh"
            "${SINGLE_DIR}/test-topology-unit.sh"
            "${SINGLE_DIR}/test-contract.sh"
            "${SINGLE_DIR}/test-window-local-contract.sh"
            "${SINGLE_DIR}/test-active-window.sh"
            "${SINGLE_DIR}/test-hook-target-regression.sh"
            "${SINGLE_DIR}/test-managed-sessions.sh"
            "${SINGLE_DIR}/test-session-name-zero.sh"
            "${SINGLE_DIR}/test-raw-layout-snapshot.sh"
            "${SINGLE_DIR}/test-layout-metadata-failure.sh"
            "${SINGLE_DIR}/test-failure-injection.sh"
            "${SINGLE_DIR}/test-subpane-unit.sh"
            "${SINGLE_DIR}/test-subpane-contract.sh"
            "${SINGLE_DIR}/test-layout-subpane-isolation.sh"
            "${SINGLE_DIR}/test-width-persistence-contract.sh"
            "${SINGLE_DIR}/test-width-clamping-single-line.sh"
            "${SINGLE_DIR}/test-cold-provisioning-contract.sh"
            "${SINGLE_DIR}/test-batch-restore-observability.sh"
            "${SINGLE_DIR}/test-restore-history-no-pollution.sh"
            "${SINGLE_DIR}/test-help-viewer.sh"
        )
        ;;
    gate_b)
        TEST_LIST=(
            "${SINGLE_DIR}/test-keyboard-e2e-repeat.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-direct-layout.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-split-cycle.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-split-cycle-vertical.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-arbitrary-topology.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-multi-window-topology.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-pane-reorder.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-history-select-all.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-rapid-operations.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-rename-roundtrip.sh"
            "${SINGLE_DIR}/test-delete-zero-stale-row.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-window-local-switch.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-window-local-toggle.sh"
            "${SINGLE_DIR}/test-batch-restore-layout-integrity.sh"
            "${SINGLE_DIR}/test-split-restore-edge-cases.sh"
        )
        ;;
    gate_c)
        TEST_LIST=(
            "${SINGLE_DIR}/test-multi-client-ownership.sh"
            "${SINGLE_DIR}/test-multi-client-operation-conflict.sh"
            "${SINGLE_DIR}/test-window-local-multi-client.sh"
            "${SINGLE_DIR}/test-window-local-lifecycle-contract.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-window-local-lifecycle.sh"
        )
        ;;
    subpane)
        TEST_LIST=(
            "${SINGLE_DIR}/test-subpane-unit.sh"
            "${SINGLE_DIR}/test-subpane-hub-unit.sh"
            "${SINGLE_DIR}/test-subpane-contract.sh"
            "${SINGLE_DIR}/test-subpane-hub-contract.sh"
            "${SINGLE_DIR}/test-subpane-position-contract.sh"
            "${SINGLE_DIR}/test-layout-subpane-isolation.sh"
            "${SINGLE_DIR}/test-subpane-work-isolation.sh"
            "${SINGLE_DIR}/test-atomic-subpane-lease.sh"
            "${SINGLE_DIR}/test-subpane-height-persistence.sh"
            "${SINGLE_DIR}/test-subpane-mouse-resize-fidelity.sh"
            "${SINGLE_DIR}/test-subpane-swap-manual-resize-fidelity.sh"
            "${SINGLE_DIR}/test-subpane-switch-position-contract.sh"
            "${SINGLE_DIR}/test-subpane-ctrl-alt-swap.sh"
            "${SINGLE_DIR}/test-subpane-swap-switch-immediate.sh"
            "${SINGLE_DIR}/test-subpane-top-switch-decay.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-subpane.sh"
            "${SINGLE_DIR}/test-subpane-default-bottom-off-height-persist.sh"
            "${SINGLE_DIR}/test-subpane-p-key-rapid-loop.sh"
            "${SINGLE_DIR}/test-subpane-multi-session-stress.sh"
        )
        ;;
    stress)
        TEST_LIST=(
            "${SINGLE_DIR}/test-rapid-15-switches-lock-reclaim.sh"
            "${SINGLE_DIR}/test-consecutive-session-switches.sh"
            "${SINGLE_DIR}/test-rapid-input-drain.sh"
            "${SINGLE_DIR}/test-subpane-multi-session-stress.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-rapid-operations.sh"
        )
        ;;
    edge)
        TEST_LIST=(
            "${SINGLE_DIR}/test-width-persistence-contract.sh"
            "${SINGLE_DIR}/test-width-clamping-single-line.sh"
            "${SINGLE_DIR}/test-long-session-name-switching-flicker-detect.sh"
            "${SINGLE_DIR}/test-negative-width-substring-regression.sh"
            "${SINGLE_DIR}/test-eager-warm-provisioning-restore.sh"
            "${SINGLE_DIR}/test-cold-provisioning-contract.sh"
            "${SINGLE_DIR}/test-batch-restore-observability.sh"
            "${SINGLE_DIR}/test-split-restore-edge-cases.sh"
            "${SINGLE_DIR}/test-first-enter-warm-session-flicker-detect.sh"
            "${SINGLE_DIR}/test-mouse-width-resize-switch.sh"
            "${SINGLE_DIR}/test-incremental-session-discovery-stale-footer-detect.sh"
            "${SINGLE_DIR}/test-sidebar-ghost-row-stale-footer-detect.sh"
            "${SINGLE_DIR}/test-missing-session-switch-graceful.sh"
            "${SINGLE_DIR}/test-find-global-pane-regression.sh"
            "${SINGLE_DIR}/test-restore-history-no-pollution.sh"
            "${SINGLE_DIR}/test-help-viewer.sh"
        )
        ;;
    gradient)
        TEST_LIST=(
            "${GRADIENT_DIR}/test-render.sh"
            "${GRADIENT_DIR}/test-fingerprint.sh"
            "${GRADIENT_DIR}/test-state.sh"
            "${GRADIENT_DIR}/test-session-isolation.sh"
            "${GRADIENT_DIR}/test-lifecycle-e2e.sh"
            "${GRADIENT_DIR}/test-regressions.sh"
            "${SINGLE_DIR}/test-animation-lut-unit.sh"
        )
        ;;
    all)
        TEST_LIST=(
            "${SINGLE_DIR}/test-domain-unit.sh"
            "${SINGLE_DIR}/test-contract.sh"
            "${SINGLE_DIR}/test-window-local-contract.sh"
            "${SINGLE_DIR}/test-failure-injection.sh"
            "${SINGLE_DIR}/test-subpane-unit.sh"
            "${SINGLE_DIR}/test-subpane-contract.sh"
            "${SINGLE_DIR}/test-subpane-position-contract.sh"
            "${SINGLE_DIR}/test-layout-subpane-isolation.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-repeat.sh"
            "${SINGLE_DIR}/test-keyboard-e2e-window-local-switch.sh"
            "${SINGLE_DIR}/test-batch-restore-layout-integrity.sh"
            "${SINGLE_DIR}/test-multi-client-ownership.sh"
            "${GRADIENT_DIR}/test-render.sh"
            "${GRADIENT_DIR}/test-state.sh"
        )
        ;;
esac

echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}${CYAN}   Running Test Suite: ${TARGET_SUITE^^}               ${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "총 실행 대상 테스트: ${#TEST_LIST[@]}개\n"

PASSED_TESTS=()
FAILED_TESTS=()
SKIPPED_TESTS=()
TOTAL_START_TIME=$(date +%s)

for test_script in "${TEST_LIST[@]}"; do
    rel_name="${test_script#"${REPO_ROOT}/"}"
    if [ ! -f "${test_script}" ]; then
        echo -e "${YELLOW}[SKIP]${NC} ${rel_name} (파일 없음)"
        SKIPPED_TESTS+=("${rel_name}")
        continue
    fi

    echo -n -e "▶ Running ${BOLD}${rel_name}${NC} ... "
    t_start=$(date +%s%N 2>/dev/null || date +%s)
    
    # 임시 로그 파일 생성
    tmp_log=$(mktemp)
    if bash "${test_script}" > "${tmp_log}" 2>&1; then
        t_end=$(date +%s%N 2>/dev/null || date +%s)
        if [ ${#t_end} -gt 10 ] && [ ${#t_start} -gt 10 ]; then
            duration_ms=$(( (t_end - t_start) / 1000000 ))
        else
            duration_ms=$(( (t_end - t_start) * 1000 ))
        fi
        echo -e "${GREEN}[PASS]${NC} (${duration_ms}ms)"
        PASSED_TESTS+=("${rel_name}")
    else
        t_end=$(date +%s%N 2>/dev/null || date +%s)
        if [ ${#t_end} -gt 10 ] && [ ${#t_start} -gt 10 ]; then
            duration_ms=$(( (t_end - t_start) / 1000000 ))
        else
            duration_ms=$(( (t_end - t_start) * 1000 ))
        fi
        echo -e "${RED}[FAIL]${NC} (${duration_ms}ms)"
        echo -e "${RED}--- Failure Output (${rel_name}) ---${NC}"
        tail -n 15 "${tmp_log}" | sed 's/^/    /'
        echo -e "${RED}-----------------------------------${NC}"
        FAILED_TESTS+=("${rel_name}")
        rm -f "${tmp_log}"
        if [ "${FAIL_FAST}" -eq 1 ]; then
            echo -e "\n${RED}Fail-fast 활성화: 즉시 중단합니다.${NC}"
            break
        fi
    fi
    rm -f "${tmp_log}"
done

TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$(( TOTAL_END_TIME - TOTAL_START_TIME ))

echo -e "\n${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}   테스트 실행 결과 요약 (Test Execution Summary)${NC}"
echo -e "   - 총 실행 시간: ${TOTAL_DURATION}초"
echo -e "   - 성공 (PASS) : ${GREEN}${#PASSED_TESTS[@]}${NC}"
echo -e "   - 실패 (FAIL) : ${RED}${#FAILED_TESTS[@]}${NC}"
if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
    echo -e "   - 생략 (SKIP) : ${YELLOW}${#SKIPPED_TESTS[@]}${NC}"
fi
echo -e "${BOLD}${CYAN}======================================================${NC}"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}실패한 테스트 목록:${NC}"
    for f in "${FAILED_TESTS[@]}"; do
        echo -e "  - ${f}"
    done
    exit 1
else
    echo -e "${GREEN}${BOLD}모든 테스트가 성공적으로 통과했습니다! (All tests passed)${NC}"
    exit 0
fi
