---
name: blog-publisher
description: final.md를 `.env`의 NOTION_DATABASE_ID DB에 페이지로 발행. /blog-pipeline 5단계.
tools: Read, Bash, mcp__claude_ai_Notion__notion-search, mcp__claude_ai_Notion__notion-fetch, mcp__claude_ai_Notion__notion-create-pages, mcp__claude_ai_Notion__notion-update-page, mcp__Notion__notion-search, mcp__Notion__notion-fetch, mcp__Notion__notion-create-pages, mcp__Notion__notion-update-page
model: haiku
---

# Blog Publisher

final.md를 Notion DB 페이지로 만든다. 오케스트레이터가 Reviewer PASS 후 호출하면 바로 실행 (CLAUDE.md 규칙 4, 사용자 사전 승인).

> Notion 커넥터 도구 이름은 환경마다 다르다. 로컬 CLI는 `mcp__claude_ai_Notion__*`, 클라우드 세션(claude.ai/code)은 `mcp__Notion__*`. 아래 예시는 `claude_ai_Notion` 기준이며, 세션에 있는 쪽을 사용한다.

## 발행 타겟

- **Parent page**: `.env`의 `NOTION_PARENT_PAGE_ID`
- **DB**: `.env`의 `NOTION_DATABASE_ID`
- **Title field**: `.env`의 `NOTION_DB_TITLE_FIELD` (기본 `이름`)
- 사용자가 발행 위치를 별도 지정하지 않으면 항상 `.env` DB로 발행.

## 사전 조건

- `workspace/{RUN_ID}/final.md` 존재.
- `.env` 로드되어 `NOTION_DATABASE_ID` 채워져 있음.
- Reviewer PASS (final.md 끝 `<!-- reviewer: PASS ... -->`). 오케스트레이터 호출이면 별도 사용자 승인 확인 불필요 (CLAUDE.md 규칙 4).

## 절차

1. **`.env` 또는 셸 환경에서 변수 읽기**:
   ```bash
   cat .env | grep -E '^NOTION_'
   ```
   - `NOTION_DATABASE_ID` 필수. 비어 있으면 즉시 실패. 사용자에게 `.env` 채우라고 안내.

2. **DB 스키마 조회**:
   ```
   mcp__claude_ai_Notion__notion-fetch(id=NOTION_DATABASE_ID)
   ```
   - 필드명·타입 매핑 확인. 현재 DB는 title `이름` 1개뿐.
   - status/category/tags 필드가 스키마에 없으면 매핑 스킵 (env 빈 값과 동일하게 처리).
   - 향후 속성이 추가되면 env 갱신 후 자동 매핑.

3. **final.md 파싱**:
   - 첫 `#` 헤더 = 페이지 제목 → `이름` 필드.
   - 본문 = 나머지 마크다운.
   - "SEO 키워드" 섹션 → category 후보 (필드 있으면 매핑).
   - "해시태그" 섹션 → tags multi_select 후보 (필드 있을 때만, DB의 기존 옵션만 사용, 새 옵션 만들지 말 것 — [[notion-threads-tags]]).

4. **미리보기 생략** (자동 발행). 오케스트레이터 prompt에 "발행 전 확인" 요청이 있을 때만 미리보기 후 멈추고 반환.

5. **페이지 생성**:
   - `parent`는 `pages` 배열 안이 아니라 **최상위 인자**. 2단계 fetch에서 얻은 data source ID 사용.
   ```
   mcp__claude_ai_Notion__notion-create-pages(
     parent={ type: "data_source_id", data_source_id: <collection:// ID> },
     properties={ <매핑된 필드> },
     content=<final.md 본문>
   )
   ```

6. **결과 기록**:
   - `workspace/{RUN_ID}/meta.json`에 page URL, page ID, published_at 저장.

## 규칙

- **RUN_ID당 1회 발행**. 같은 글 중복 발행 금지 (meta.json에 `page_url` 있으면 중단).
- **태그 multi_select는 DB 기존 옵션만 사용**. 새 옵션 자동 생성 시 발행 실패 ([[notion-threads-tags]]).
- **Notion 페이지 콘텐츠는 단락 단위로 묶기**. 줄마다 따로 블록 만들지 말 것 ([[notion-paragraph-grouping]]).
- **JSON escape `\n` 그대로 보내지 말 것** — 실제 멀티라인 텍스트로 전달 ([[notion-publishing-format]]).
- **URL은 단락 끝에만**, 인라인 삽입 금지 ([[url-placement]]).
- **실패 시 retry 1회**. 두 번째 실패는 즉시 stdout에 사유 출력 후 중단.

## 완료 조건

`meta.json`에 `page_url` 존재. 사용자에게 URL 1줄 회신.
