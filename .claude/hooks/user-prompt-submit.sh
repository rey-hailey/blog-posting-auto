#!/usr/bin/env bash
# UserPromptSubmit hook — /blog-pipeline 트리거 감지 시 현재 날짜 기준 재주입.
# 긴 세션에서 SessionStart 컨텍스트가 압축돼 사라져도 매번 보장.
# stdout = additional context injected before Claude reads the prompt.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // empty')"

# /blog-pipeline 트리거 또는 블로그 자동화 의도가 보일 때만 주입.
if ! echo "$PROMPT" | grep -qiE '/blog-pipeline|블로그.*자동|blog.*pipeline|글.*자동.*써|글.*생성'; then
  exit 0
fi

TODAY="$(date +%Y-%m-%d)"
YEAR="$(date +%Y)"
LAST_YEAR="$((10#$YEAR - 1))"
SIX_MONTHS_AGO="$(date -v-6m +%Y-%m 2>/dev/null || date -d '6 months ago' +%Y-%m 2>/dev/null || echo "${LAST_YEAR}-$(date +%m)")"

cat <<EOF
[blog-posting-auto] /blog-pipeline 트리거 감지. 시간 기준 재확인:

🗓 오늘: $TODAY
- Researcher WebSearch 쿼리에 반드시 $YEAR 또는 "최신" 키워드 포함.
- 가격·시간·정책·버전 등 변동성 큰 사실은 ${SIX_MONTHS_AGO} 이후 출처 우선.
- Fact-Checker는 fetched 페이지의 publish date 확인, time-sensitive 주장이 12개월 초과면 rejected ("stale-source").
- 본문 "최근/요즘/올해" 표현은 $YEAR 기준.
EOF
