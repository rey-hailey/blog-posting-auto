#!/usr/bin/env bash
# SessionStart hook — 세션 시작 시 style 컨텍스트 + 현재 날짜 기준 주입.
# stdout으로 출력하면 Claude의 컨텍스트에 추가됨.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STYLE_DIR="$PROJECT_DIR/.claude/style"

if [[ ! -d "$STYLE_DIR" ]]; then
  exit 0
fi

TODAY="$(date +%Y-%m-%d)"
YEAR="$(date +%Y)"
MONTH="$(date +%Y-%m)"
LAST_YEAR="$((10#$YEAR - 1))"

cat <<EOF
[blog-posting-auto] SessionStart hook loaded.

🗓 오늘 날짜: $TODAY (YYYY=$YEAR, YYYY-MM=$MONTH)

자료 조사·검증 시 시간 기준 (강제):
- Researcher: 모든 WebSearch 쿼리에 최신성 키워드 포함 ("$YEAR", "$LAST_YEAR", "최신", "recent")
- Researcher: 가격·시간·일정·버전·정책 같은 time-sensitive 사실은 최근 6개월(>=${LAST_YEAR}-$(date +%m)) 출처 우선
- Fact-Checker: WebFetch한 페이지의 publish/updated 날짜 추출 후 staleness 판단
  · time-sensitive 주장인데 출처 12개월 초과 → rejected.md "stale-source" 카테고리
  · evergreen 주장(역사·개념·작동 원리)은 staleness 관대
- 본문에 "최근", "요즘", "올해" 같은 시간 표현 쓸 때 $YEAR 기준임을 인지

스타일 규칙 요약:
- 톤: .claude/style/voice.md
- 가독성: .claude/style/readability.md
- 금지표현: .claude/style/forbidden.md (+ forbidden.patterns)
- 체크리스트: .claude/style/checklist.md (정보글)
- 일상글 모드: .claude/style/daily.md (POST_TYPE=daily일 때 구조 규칙 우선)

블로그 글 자동화 트리거: /blog-pipeline <주제>
워크스페이스: workspace/{run_id}/
Notion 발행은 Reviewer PASS 후 자동 (CLAUDE.md 규칙 4). 판단이 필요한 경우만 발행 전에 묻기.
EOF
