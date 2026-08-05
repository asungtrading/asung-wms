# Asung WMS — 프로젝트 규칙

Cin7 Core를 장기적으로 대체할 커스텀 IMS의 첫 모듈. 추측으로 코드를 쓰지 말고 아래를 지킬 것.

## 0. 먼저 읽을 것

`.claude/skills/asung-wms/SKILL.md` — 아키텍처·스키마·규칙 1~23이 전부 여기 있다.
관련 스킬: `cin7-api`, `asung-bq-data-model`, `asung-apps-script`

## 1. 환경 (2026-07-26 갱신 — 이전 기록은 Windows 경로였음)

- 개발 경로: `~/asung/asung-wms` (WSL2 Ubuntu)
- Supabase project-ref: `gftpcnkxbdjzzfvzwcfl` (ca-central-1)
- 배포: GitHub Pages -> `wms.asung.ca` (repo `asungtrading/asung-wms`, PUBLIC)
- 빌드툴 없음. 순수 HTML/JS + Supabase JS CDN
- Cin7 API: `https://inventory.dearsystems.com/ExternalApi/v2`

⚠️ `/mnt/c/...` 아래에서 작업하지 말 것 — WSL 파일 I/O가 크게 느려진다.
⚠️ 스킬에 남은 PowerShell 예시(`Invoke-RestMethod`, `cd ~\asung-wms`)는 낡았다. 이제 bash + curl.

## 2. DB 스키마 — 마이그레이션만 (2026-07-26 확립)

베이스라인: `supabase/migrations/20260101000000_baseline.sql` (테이블 20 · 정책 22)
원격 히스토리와 정렬됨(`migration repair` 완료). 이 파일은 수정하지 말 것 — 변경은 새 마이그레이션으로.

허용된 절차:
1. `supabase migration new <name>`
2. SQL 작성
3. `supabase db reset` — 로컬에서 처음부터 재생해 검증
4. `supabase db push` — ⚠️ 사람이 직접만 실행. Claude는 명령만 제시한다.

금지:
- 대시보드 SQL Editor로 스키마 변경 — 로컬과 원격이 어긋나 이 체계가 무의미해진다.
  급히 했다면 즉시 `supabase db dump --linked`로 되받아 반영.
- `supabase db push` 자동 실행
- `supabase stop --no-backup` — 로컬 볼륨 삭제
- `db pull` 의존 — 이 프로젝트에서 diff 단계가 조용히 실패한 이력이 있다. `db dump --linked`를 쓴다.

드리프트 확인: `supabase db diff --linked`
작업 후 `supabase stop` (개발 머신 RAM 8GB 상한)

pg_cron 스케줄은 dump 대상이 아니라 `supabase/ops/cron.sql`에 기록만 해둠(마이그레이션 아님).
Edge Function secrets, Auth 설정(Site URL / Redirect), Storage 버킷 설정도 dump에 없다.

## 3. 불변식 — 어기면 재고·픽 수량이 틀어진다

- `factor`는 `asung_product_master.unit` 컬럼에서 온다. SKU 접미사로 추론하지 말 것.
- `required_base = qty × factor`
- bin은 `base_sku` 기준
- Cin7에 쓰는 bin은 GUID(이름 아님)
- warehouse: Location에 `Edmonton` 포함 -> `edmonton`, 그 외 -> `toronto`. EF와 GAS 양쪽 동일 적용.
- `Order_Progress` = `AdditionalAttributes.AdditionalAttribute1` — 백오더 `'Backordered'`와 같은 필드를 공유.
  `saleList`는 이 필드를 주지 않으므로 `/sale` 상세로 확인.
- WMS가 소유하는 단계는 `2.Release to WMS` 하나. MVP에서 WMS는 Cin7에 재고를 쓰지 않는다(리시빙 Apply는 예외).
- PO stock received: 문서당 bin 1개(bin별 분할 POST) · 같은 SKU+bin 병합 · authorize는 POST(PUT은 405) · Invoice First 선승인
- 트랜스퍼 풋어웨이: `From`은 항상 `det.To`
- 한 PO = receipt 1개. `applied_at` 있으면 재적용 거부.

## 4. 비밀값

- anon(publishable) key = 커밋 OK. RLS + 로그인이 보호한다.
  `wms-config.js`의 실제 key가 든 버전을 유지하고 placeholder로 덮어쓰지 말 것.
- service_role key = 절대 금지. GAS Script Property와 EF 자동주입에만 존재.
  (`staff-create` EF가 Auth admin API에 쓰는 것은 서버사이드 정상 경로 — 금지 대상은 프론트엔드 노출이다.)
- 로컬 Supabase가 출력하는 key는 공유 기본값이다. 프로덕션과 혼동하지 말 것.

## 5. 코드 규칙

- UI 문자열은 영어. 개발 대화·주석은 한국어 가능.
- 건드리지 말 것: `CNAME`(`wms.asung.ca`), `.nojekyll`(supabase/ 폴더 때문에 필수), `wms-config.js`의 key
- 상태를 `localStorage`에 저장하지 말 것 — 다른 태블릿에서 로그인하는 시나리오가 깨진다. 서버 저장(예: `held_by`).
- 전체 파일 교체를 선호. 부분 패치 지양.
- Edge Function 배포: `supabase functions deploy <name>` (Docker 불필요)

## 6. 작업 습관

- 편집 전 `git pull`, 세션 끝에 `git push`.
  ⚠️ 집·회사 두 대에서 개발하며 오래된 로컬 사본으로 덮어써 기능을 날린 이력이 있다.
- 데이터·숫자는 검증 후 진행. 추정치로 넘어가지 말 것.
- 정리 대기: `web/staff-admin.html`은 루트 버전과 중복된 낡은 사본 -> 삭제 대상.

## 7. 스킬 description은 1024자 이하 (2026-07-27 — 업로드 거부 반복)

claude.ai 스킬 업로드는 `SKILL.md` frontmatter의 `description`을 **1024 문자**로 제한한다.
넘으면 `field 'description' in SKILL.md must be at most 1024 characters`로 거부된다.
바이트가 아니라 문자 수로 세는 것으로 보인다(1201자 / 1782바이트에서 "1024 characters" 거부).
확증은 없으니 검사 스크립트가 둘 다 출력한다.

- 여러 줄 `>` 블록은 줄바꿈이 공백으로 접히고 끝 줄바꿈 1개가 남는다 -> 원문 길이 ≠ 실제 길이.
  눈으로 세지 말고 스크립트로 잴 것.
- 줄일 때 트리거 키워드를 먼저 버리지 말 것. description은 스킬이 **언제 로드될지**를 정한다.
  키워드를 자르면 필요할 때 스킬이 안 뜬다. 순서: 일반어·중복어(영/한 같은 뜻 쌍) -> 문구 압축 -> 그 다음 키워드.
- ⚠️ 불변식 문구(factor는 unit 컬럼, bin은 base_sku, Cin7 bin은 GUID, Invoice First,
  service_role 금지, UI 영어, stock received는 문서당 bin 1개, authorize는 POST)는 마지막까지 유지.
- 현재 여유 (2026-08-05 실측): `asung-wms` **722자(302자)** · `shopify-tracking` 855자(169자) ·
  `cin7-api` 840자(184자) — **이제 가장 빡빡한 것은 `shopify-tracking` 이다.**
  (2026-07-29: 규칙 29~33 키워드 `on_conflict`/`exported_base`/`재평가` 를 넣으며
  본문 "Cin7 Core multi-packing … 처리합니다" 압축 + "리시빙·동시 작업(규칙 20~22/24~28)" → "규칙 20~33" 로 상계.)
  (2026-08-04: `stock_short`·`픽리스트 인쇄` 추가 + `규칙 20~41`, 상계 후 **여유 7자**까지 몰렸다.)

- ✅ **2026-08-05 감축 — 1017 → 722자 (여유 7 → 302자).** 규칙 42 를 만들 여유가 없어 별건 작업으로 처리했다.
  **무엇을 뺐나** (다음에 "왜 이 키워드가 없나" 를 다시 추측하지 않게):
  1. **키워드 9개** — `"Supabase"`·`"Edge Function"`(⚠️ 삭제가 아니라 중복 제거: 바로 앞 문장
     "Supabase(Postgres+Edge Function) 기반" 에 산문으로 남아 트리거 신호는 유지) ·
     `"authorize"`·`"동시 작업"`(과도하게 일반적 — 무관한 작업에서 스킬을 띄우는 **잘못된 트리거**였다) ·
     `"Lines is invalid"`·`"스캔 이어받기"`(해소된 함정어) ·
     `"unconfirmed"`/`"writeChain"`/`"serverChecks"`(규칙 24 내부 구현명)
  2. **열거 압축** — `아키텍처·스키마·인증·배포·규칙 20~41` → `아키텍처·스키마·배포·규칙 20~41`
  3. **⚠️ 불변식 9개 → 4개** (사용자 결정). **유지** = factor는 unit 컬럼 · bin은 base_sku 기준 ·
     service_role 금지 · 리시빙 저장은 라인 단위/.select() 1행.
     **제외** = Order_Progress(규칙 1) · Cin7 bin GUID · Invoice First 선승인 · 문서당 bin 1개/authorize POST
     (이 3개는 `cin7-api` description 이 이미 갖고 있어 Cin7 쓰기 작업엔 그쪽이 먼저 뜬다) ·
     UI 영어(위 5절 + 규칙 11 에 있고, 어겨도 되돌릴 수 있다)
  ⚠️ **본문에서 빠진 사실은 없다** — description 에서 뺀 것은 트리거·요약이지 사실이 아니다.
  ⚠️ 앞으로 키워드를 더할 땐 압축 순서(①범위 표기 ②해소된 함정어 ③`cin7-api` 중복어 ④일반어·영한 중복쌍)를
  따르고, **남은 불변식 4개는 마지막까지 유지.** 같은 내용이
  `.claude/skills/asung-wms/SKILL.md` 「이 스킬 문서를 갱신할 때」 절에도 있다(스킬만 읽는 세션 대비).

검사:
```bash
scripts/check-skill-desc.sh            # 전체 (초과 시 exit 1)
scripts/check-skill-desc.sh --staged   # 스테이징된 것만 — hook이 쓰는 모드
```

### hook 설치 — 클론한 머신마다 1회

`.git/hooks`는 커밋되지 않으므로, hook 본체는 `scripts/hooks/`에 커밋해 두고 git이 그쪽을 보게 한다:

```bash
git config core.hooksPath scripts/hooks
```

집·회사 두 대 모두에서 한 번씩 실행할 것. 안 하면 아무 경고 없이 검사가 통째로 빠진다.
확인: `git config core.hooksPath` -> `scripts/hooks`

- hook은 이번 커밋이 건드린 `SKILL.md`가 초과하면 커밋을 **막고**, 무관한 스킬이 이미 초과면
  경고만 한다(무관한 커밋을 붙잡지 않는다).
- `git commit --no-verify`로 우회 가능하지만 업로드는 여전히 거부된다.
- PyYAML이 있으면 그걸로 파싱하고, 없으면 stdlib 폴백 파서를 쓴다(`>`/`|`/단일행 모두 동일 결과 검증됨).
