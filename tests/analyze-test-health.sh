#!/usr/bin/env bash
# ==============================================================================
# tests/analyze-test-health.sh
#
# dotfiles 테스트 스위트의 건전성(Health)을 정적 분석하고 진단 리포트를 생성합니다.
# - 전체 테스트 스크립트 문법(syntax) 검사
# - docs/testing/test-matrix.md 등록 여부(Orphan 탐지)
# - 임시 격리 소켓(-L) 및 cleanup trap 유무 검사
# - 레거시 아키텍처(단일 물리페인 move-pane 등) 키워드 스캔
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"
MATRIX_DOC="${REPO_ROOT}/docs/testing/test-matrix.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}======================================================${NC}"
echo -e "${BOLD}${BLUE}   Dotfiles Test Suite Health & Audit Report          ${NC}"
echo -e "${BOLD}${BLUE}======================================================${NC}"
echo -e "분석 대상 경로: ${TESTS_DIR}\n"

# 1. 전체 스크립트 수집
mapfile -t ALL_TEST_SCRIPTS < <(find "${TESTS_DIR}" -type f -name "*.sh" | sort)
TOTAL_SCRIPTS=${#ALL_TEST_SCRIPTS[@]}

echo -e "${BOLD}[1/4] Syntax Integrity Check (bash -n)${NC}"
SYNTAX_ERRORS=0
for script in "${ALL_TEST_SCRIPTS[@]}"; do
    rel_path="${script#"${REPO_ROOT}/"}"
    if ! bash -n "${script}" 2>/dev/null; then
        echo -e "  ${RED}✖ [SYNTAX ERROR]${NC} ${rel_path}"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done

if [ "${SYNTAX_ERRORS}" -eq 0 ]; then
    echo -e "  ${GREEN}✔ 전체 ${TOTAL_SCRIPTS}개 쉘 스크립트 문법 무결성 통과 (오류 0건)${NC}"
else
    echo -e "  ${RED}✖ 문법 오류 스크립트 ${SYNTAX_ERRORS}건 발견${NC}"
fi
echo ""

# 2. test-matrix.md 등록 여부 (Orphan 테스트 탐지)
echo -e "${BOLD}[2/4] Test Matrix Catalog Registration Check${NC}"
ORPHAN_COUNT=0
REGISTERED_COUNT=0
ORPHAN_LIST=()

for script in "${ALL_TEST_SCRIPTS[@]}"; do
    base_name="$(basename "${script}")"
    # test-matrix.md에 파일명이 언급되어 있는지 확인
    if grep -q "${base_name}" "${MATRIX_DOC}" 2>/dev/null; then
        REGISTERED_COUNT=$((REGISTERED_COUNT + 1))
    else
        ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
        ORPHAN_LIST+=("${script#"${REPO_ROOT}/"}")
    fi
done

echo -e "  ${GREEN}✔ test-matrix.md 공식 등록 스크립트: ${REGISTERED_COUNT}개${NC}"
if [ "${ORPHAN_COUNT}" -gt 0 ]; then
    echo -e "  ${YELLOW}▲ 매트릭스 문서 미등록(Orphan/Uncataloged) 스크립트: ${ORPHAN_COUNT}개${NC}"
    echo -e "    ${BOLD}주요 미등록 목록:${NC}"
    for orphan in "${ORPHAN_LIST[@]}"; do
        echo -e "      - ${orphan}"
    done
fi
echo ""

# 3. 소켓 격리 및 정리(Trap) 안전성 검사
echo -e "${BOLD}[3/4] Socket Isolation & Cleanup Safety Check${NC}"
UNSAFE_SOCKET_COUNT=0
for script in "${ALL_TEST_SCRIPTS[@]}"; do
    rel_path="${script#"${REPO_ROOT}/"}"
    if grep -q "tmux " "${script}" 2>/dev/null; then
        if ! grep -q -- "-L " "${script}" && ! grep -q "SOCKET" "${script}" && ! grep -q "pty-bridge" "${script}" && ! grep -q "run_gate_e" "${script}"; then
            echo -e "  ${YELLOW}▲ [소켓 격리 주의]${NC} ${rel_path}: 전용 소켓(-L) 명시 확인 권장"
            UNSAFE_SOCKET_COUNT=$((UNSAFE_SOCKET_COUNT + 1))
        fi
    fi
done
if [ "${UNSAFE_SOCKET_COUNT}" -eq 0 ]; then
    echo -e "  ${GREEN}✔ 모든 tmux 관련 테스트가 전용 소켓 격리 또는 PTY 브리지를 준수함${NC}"
fi
echo ""

# 4. 레거시(move-pane 시절) 키워드 및 패턴 검사
echo -e "${BOLD}[4/4] Legacy / Deprecated Pattern Scan${NC}"
LEGACY_COUNT=0
for script in "${ALL_TEST_SCRIPTS[@]}"; do
    rel_path="${script#"${REPO_ROOT}/"}"
    if [[ "${rel_path}" == *"analyze-test-health.sh"* ]]; then
        continue
    fi
    if grep -q "move-pane" "${script}" 2>/dev/null; then
        if grep -v "^[[:space:]]*#" "${script}" | grep -q "move-pane"; then
            echo -e "  ${YELLOW}▲ [레거시 패턴 감지]${NC} ${rel_path} (move-pane 호출 잔존)"
            LEGACY_COUNT=$((LEGACY_COUNT + 1))
        fi
    fi
done
if [ "${LEGACY_COUNT}" -eq 0 ]; then
    echo -e "  ${GREEN}✔ 활성 코드 중 레거시 move-pane 의존성 없음${NC}"
else
    echo -e "  ${YELLOW}▲ 레거시 move-pane 호출 잔존 스크립트: ${LEGACY_COUNT}건${NC}"
fi
echo ""

# 최종 종합 요약
echo -e "${BOLD}${BLUE}======================================================${NC}"
echo -e "${BOLD}   진단 결과 요약 (Health Score Summary)${NC}"
echo -e "   - 전체 테스트 스크립트: ${TOTAL_SCRIPTS}개"
echo -e "   - 문법 오류(Syntax): ${SYNTAX_ERRORS}개"
if [ "${TOTAL_SCRIPTS}" -gt 0 ]; then
    echo -e "   - 매트릭스 등록률: $(( REGISTERED_COUNT * 100 / TOTAL_SCRIPTS ))% (${REGISTERED_COUNT}/${TOTAL_SCRIPTS})"
fi
echo -e "   - 레거시 패턴 감지: ${LEGACY_COUNT}개"
echo -e "${BOLD}${BLUE}======================================================${NC}"
