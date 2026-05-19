#!/usr/bin/env bash
# PreToolUse hook — Write/Edit 직전 금지표현 차단.
# Claude Code는 hook에 JSON을 stdin으로 보냄. tool_input.content / new_string를 grep.
# Exit 2 = block, Exit 0 = allow.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PATTERNS="$PROJECT_DIR/.claude/style/forbidden.patterns"

if [[ ! -f "$PATTERNS" ]]; then
  exit 0
fi

INPUT="$(cat)"

# tool 이름과 입력값 추출. jq 없으면 통과 (best-effort).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
case "$TOOL_NAME" in
  Write)
    CONTENT="$(echo "$INPUT" | jq -r '.tool_input.content // empty')"
    FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"
    ;;
  Edit)
    CONTENT="$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')"
    FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"
    ;;
  *)
    exit 0
    ;;
esac

# style 파일·hook 자체는 검사 제외 (메타 콘텐츠).
case "$FILE_PATH" in
  */.claude/*) exit 0 ;;
  */examples/*) exit 0 ;;
esac

# workspace의 draft.md / final.md만 체크. research·plan은 메타라 통과.
case "$FILE_PATH" in
  */workspace/*/draft.md|*/workspace/*/final.md) ;;
  *) exit 0 ;;
esac

MATCHES="$(echo "$CONTENT" | grep -nE -f "$PATTERNS" || true)"

if [[ -n "$MATCHES" ]]; then
  cat >&2 <<EOF
[blog-posting-auto] PreToolUse blocked — forbidden expressions detected in $FILE_PATH:

$MATCHES

→ .claude/style/forbidden.md 참고해서 자연스러운 표현으로 치환 후 재시도.
EOF
  exit 2
fi

exit 0
