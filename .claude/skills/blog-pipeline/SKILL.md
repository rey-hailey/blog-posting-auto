---
name: blog-pipeline
description: 주제 또는 키워드를 받아 한국어 블로그 글 한 편을 Researcher→Fact-Checker→Planner→Writer→Reviewer→Publisher 6단계로 생성·발행. Fact-Checker가 환각·오인용을 격리. Notion DB에 Draft 페이지 생성까지 자동화. 사용 트리거 — `/blog-pipeline <주제>` 또는 "블로그 글 자동으로 써줘" 같은 요청.
---

# /blog-pipeline

블로그 글 한 편을 6단계 서브에이전트 직렬 실행으로 생성하고 Notion에 발행하는 워크플로우. Researcher가 모은 사실을 Fact-Checker가 원본 URL 재방문으로 검증, downstream(Planner/Writer/Reviewer)은 verified.md만 사실 근거로 사용.

## 실행 순서

오케스트레이터(메인 세션)가 다음을 순서대로 수행:

### 0. 준비

1. **`RUN_ID` + `TODAY` 생성**: slug는 주제에서 한국어→영어 음차 또는 핵심 명사.
   ```bash
   RUN_ID="$(date +%Y%m%d-%H%M%S)-{slug}"
   TODAY="$(date +%Y-%m-%d)"
   mkdir -p workspace/$RUN_ID
   ```
   `TODAY`는 모든 서브에이전트 호출 시 prompt에 박아 전달 — Researcher 최신성 쿼리, Fact-Checker staleness 판정 기준.
2. **`workspace/{RUN_ID}/meta.json`** 초기 기록:
   ```json
   {
     "run_id": "...",
     "topic": "...",
     "today": "YYYY-MM-DD",
     "started_at": "ISO-8601",
     "stages": {}
   }
   ```
3. `.env` 존재 + `NOTION_DATABASE_ID` 채워졌는지 확인. 없으면 사용자에게 알리고 Publisher 단계는 skip 옵션 안내.
4. **`POST_TYPE` 분류** (`daily` 일상글 / `info` 정보글) — 기준은 `.claude/style/daily.md` "분류 기준". 사용자가 겪은 일이 중심이면 `daily`, 주제 자체를 설명·정리·비교하면 `info`. 애매하면 `daily`. `meta.json`에 `"post_type"` 기록, 이후 모든 서브에이전트 prompt에 `POST_TYPE: {값}` 전달.
   - `daily`이면 사용자 입력의 경험 서술을 Researcher prompt에 "사용자 제공 1차 경험" 섹션으로 그대로 넘기고(각색 금지), Fact-Checker는 그 섹션을 검증 면제·비율 계산 제외로 처리. 웹 조사는 이야기에 붙일 배경 사실만(병원명·제도·일정 등).
   - `daily` 글은 Planner·Writer·Reviewer가 `.claude/style/daily.md`를 우선 적용 (추천/SEO 섹션·3박자 훅·이모지 소제목 없음, 시간 순 이야기).

### 1. Researcher

```
Agent(subagent_type="blog-researcher", prompt=<<<
RUN_ID: {RUN_ID}
TODAY:  {TODAY}      ← 최신성 쿼리 기준
TOPIC:  {사용자 입력 주제}

workspace/{RUN_ID}/research.md 생성.
모든 WebSearch 쿼리에 {TODAY 연도} 또는 "최신" 키워드 포함.
각 사실에 source-date 메타 부착.
>>>)
```

검증: `workspace/{RUN_ID}/research.md` 존재 + 4KB 이상 + 각 사실에 `(source-date: ...)` 메타 존재.

### 1.5. Fact-Checker

```
Agent(subagent_type="blog-fact-checker", prompt=<<<
RUN_ID: {RUN_ID}
TODAY:  {TODAY}      ← staleness 판정 기준 (TODAY-12개월 미만 출처만 통과)

workspace/{RUN_ID}/research.md의 각 주장을 원본 URL 재방문해 검증.
time-sensitive(가격·시간·정책·버전) 사실은 source-date 12개월 초과면 rejected (stale-source).
research.verified.md + research.rejected.md 생성.
>>>)
```

검증:
- `research.verified.md` 존재 + `research.rejected.md` 존재 (빈 파일이어도 OK)
- stdout 통계 라인 `[fact-checker] ... verified=M rejected=N-M ratio=M/N%` 캡처
- **verified 비율 < 50% → 자동 RETRY**: Researcher 재호출 (최대 2회). 그래도 50% 미만이면 사용자 결정 요청.
- verified 비율 ≥ 50%면 다음 단계 진행.

### 2. Planner

```
Agent(subagent_type="blog-planner", prompt=<<<
RUN_ID: {RUN_ID}

workspace/{RUN_ID}/research.verified.md를 읽고 plan.md 작성.
research.md는 참고만, verified에 없는 사실은 절대 사용 금지.
>>>)
```

검증: `plan.md` 존재 + 섹션 5개 이상 (`daily`는 장면 흐름 3개 이상, 소제목 0~3개).

### 3. Writer

```
Agent(subagent_type="blog-writer", prompt=<<<
RUN_ID: {RUN_ID}

plan.md 따라 draft.md 작성.
사실 출처는 research.verified.md만.
>>>)
```

검증:
- `draft.md` 존재
- 금지표현 grep 0건: `grep -nE -f .claude/style/forbidden.patterns workspace/{RUN_ID}/draft.md`
- UNVERIFIED CLAIM 0건 (Writer 자가검증 #5 통과)

### 4. Reviewer

```
Agent(subagent_type="blog-reviewer", prompt=<<<
RUN_ID: {RUN_ID}

draft.md → final.md. 5단계 검사 통과시키기.
사실 근거는 research.verified.md, rejected.md의 표현은 무조건 제거.
>>>)
```

검증: `final.md` 존재 + 끝에 `<!-- reviewer: PASS / ... / UNVERIFIED K건 모호화 -->` 코멘트.

### 5. Publisher (Reviewer PASS 후 자동)

Reviewer PASS + 오케스트레이터 검증 통과 시 승인 확인 없이 바로 발행 (CLAUDE.md 규칙 4). 사용자가 해당 글에 "발행 전 확인"을 요청한 경우만 미리보기 후 승인받기.

```
Agent(subagent_type="blog-publisher", prompt=<<<
RUN_ID: {RUN_ID}

final.md를 NOTION_DATABASE_ID DB에 발행. (CLAUDE.md 규칙 4에 따른 자동 발행)
>>>)
```

검증: `meta.json.page_url` 존재. 발행 후 사용자에게 보고:

```
발행 완료: {page URL}
제목: {제목}
확인할 점: {사진 자리 / 미확인 사실 / verified 비율 등}
```

## 산출물 디렉토리

```
workspace/{RUN_ID}/
├── meta.json              # 실행 메타 (단계별 시작/종료 시각, 모델, 토큰, fact-check ratio)
├── research.md            # 1단계 산출 (원본, audit용)
├── research.verified.md   # 1.5단계 산출 (downstream의 유일한 사실 진실원)
├── research.rejected.md   # 1.5단계 산출 (탈락 사유 + 항목, audit/디버깅)
├── plan.md                # 2단계 산출
├── draft.md               # 3단계 산출
├── final.md               # 4단계 산출 (Notion 발행 원본)
└── notion-payload.json    # 5단계 직전 페이로드 (디버깅용)
```

## 오케스트레이터 규칙

- **단계 실패 시 다음 단계로 진행 금지**. 사용자에게 사유 보고 후 재시도/스킵 선택권.
- **단계 간 결과물 검증은 오케스트레이터 책임**. 서브에이전트 자체 평가 신뢰하지 말 것.
- **Fact-Checker verified 비율 < 50% 시 Researcher 재호출** (최대 2회). 그래도 미달이면 사용자 결정.
- **Publisher는 Reviewer PASS 후 자동 호출**. 발행 후 page URL과 확인할 점 보고.
- **Reviewer 실패 시**: 사유 보고 → Writer 재호출 (최대 2회) → 그래도 실패면 사용자에게 결정 요청.
- **`daily` 글은 오케스트레이터도 final.md를 한 번 더 확인**: 추천/SEO 섹션, "결론부터", 이모지 소제목, 사용자 메모에 없는 장면·감정이 남아 있으면 발행 전에 제거.
  - 출처·검증 티도 확인: `grep -nE '후기를 보니|찾아보니|알아보니|검색해 보니|업체 쪽|회사 측|공식 직함|였대요|이래요|바뀌었을 수|확인해 주세요' final.md` 0건이어야 발행. 직접 다녀온 사람의 의견 글로 읽혀야 한다 (daily.md "내 목소리로 쓰기").
  - 본문에서 뺀 불확실 사실·출처 메모는 발행 보고의 "확인할 점"으로 사용자에게 전달.

## 참고

- 톤·금지표현·체크리스트: `.claude/style/` 전체
- 참고 글 샘플: `examples/` (5개 카테고리: food / travel / tutorial / comparison / activity)
- 에이전트 정의: `.claude/agents/blog-{researcher,fact-checker,planner,writer,reviewer,publisher}.md`
- Hook 자동 체크포인트: `.claude/hooks/`
