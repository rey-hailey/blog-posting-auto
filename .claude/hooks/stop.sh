#!/usr/bin/env bash
# Stop hook — 세션 종료 직전 최종 산출 확인.
# final.md 있는데 meta.json에 page_url 없으면 미발행 알림.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

LATEST_RUN="$(ls -t "$PROJECT_DIR/workspace" 2>/dev/null | grep -v '^\.' | head -1 || true)"

if [[ -z "$LATEST_RUN" ]]; then
  exit 0
fi

RUN_DIR="$PROJECT_DIR/workspace/$LATEST_RUN"

if [[ ! -f "$RUN_DIR/final.md" ]]; then
  exit 0
fi

# meta.json에 page_url 있는지 확인.
if command -v jq >/dev/null 2>&1 && [[ -f "$RUN_DIR/meta.json" ]]; then
  PAGE_URL="$(jq -r '.page_url // empty' "$RUN_DIR/meta.json" 2>/dev/null || true)"
  if [[ -n "$PAGE_URL" ]]; then
    cat <<EOF
[blog-posting-auto] Stop check — run $LATEST_RUN 발행 완료.
페이지: $PAGE_URL
EOF
    exit 0
  fi
fi

cat <<EOF
[blog-posting-auto] Stop check — workspace/$LATEST_RUN/final.md 존재하지만 Notion 미발행 상태.
발행하려면: /blog-pipeline 재실행 후 publisher 단계만 진행하거나, 직접 blog-publisher agent 호출.
EOF

exit 0
