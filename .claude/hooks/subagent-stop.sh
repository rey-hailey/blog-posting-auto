#!/usr/bin/env bash
# SubagentStop hook — 서브에이전트 종료 시 산출물 파일 확인.
# 빠진 산출 있으면 stdout 경고. 차단은 안 함 (오케스트레이터가 재호출 결정).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 최신 run 디렉토리.
LATEST_RUN="$(ls -t "$PROJECT_DIR/workspace" 2>/dev/null | grep -v '^\.' | head -1 || true)"

if [[ -z "$LATEST_RUN" ]]; then
  exit 0
fi

RUN_DIR="$PROJECT_DIR/workspace/$LATEST_RUN"

# 어떤 단계까지 산출됐는지 점검.
MISSING=()
for stage in research research.verified research.rejected plan draft final; do
  if [[ ! -f "$RUN_DIR/$stage.md" ]]; then
    MISSING+=("$stage.md")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  cat <<EOF
[blog-posting-auto] SubagentStop check — workspace/$LATEST_RUN missing: ${MISSING[*]}
(파이프라인 진행 중이면 정상. 마지막 단계인데 빠지면 재호출 필요.)
EOF
fi

exit 0
