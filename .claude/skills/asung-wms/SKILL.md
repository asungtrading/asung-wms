---
name: asung-wms
description: >
  Asung Trading 커스텀 WMS(IMS 첫 모듈)를 다룰 때 먼저 읽으세요.
  Supabase(Postgres+Edge Function) 기반, Cin7 multi-packing 한계를 넘는
  대형오더 분할 동시 픽/팩 + 리시빙/풋어웨이.
  "WMS", "픽킹", "패킹", "wms_orders", "Release to WMS", "오더 분할",
  "discrepancy", "base 정규화", "factor", "wms-auth", "perms", "wms.asung.ca",
  "Finalize", "Health 탭", "리시빙", "receiver.html", "풋어웨이",
  "라스트 로케이션", "wms_receipts", "Apply to Cin7", "stock received",
  "bin transfer", "트랜스퍼", "Invoice First", "held_by", "presence", "bcMap",
  "CAS", "on_conflict", "exported_base", "stock_short", "픽리스트 인쇄" 등이
  나오면 추측하지 말고 이 스킬의 아키텍처·스키마·배포·규칙 20~41 을 확인하세요.
  특히 ⚠️factor는 unit 컬럼, ⚠️bin은 base_sku 기준, ⚠️service_role 금지,
  ⚠️리시빙 저장은 라인 단위(전체 덮어쓰기 금지)·성공 판정은 .select() 1행 —
  어기면 재고·픽 수량이 틀어지거나 남의 작업이 사라집니다.
---

# Asung Trading WMS 스킬

Asung은 Cin7 Core를 장기적으로 대체할 커스텀 IMS를 짓고 있고, **WMS가 그 첫 모듈**입니다. 이 문서는 "우리가 WMS를 짓는 방식"을 인코딩합니다. 세부 스키마·코드는 `references/`에 있으니 필요할 때 읽으세요.

## 왜 만드나 (스코프의 근거)

Cin7 Core는 multi-picking은 되지만 **multi-packing이 사실상 안 됩니다** — 모든 픽이 끝나야 팩을 시작할 수 있습니다. 라인 최대 ~1000개짜리 대형오더를 여러 작업자가 **나눠서 동시에 픽/팩**하려는 것이 이 WMS의 목적입니다. 완료된 픽 배치는 다른 배치와 무관하게 독립적으로 팩됩니다.

반대 방향도 있습니다: **소량 오더 여럿을 한 작업자가 한 동선으로 묶어 픽**하는 것(cluster/batch picking). 이건 **wave(웨이브)** 로 처리하며 — 핵심은 "대형 오더는 쪼개고(split), 소량 오더는 묶는다(wave)"입니다. 둘 다 결국 **같은 pick 배치 출구 하나**로 수렴하게 설계됨(규칙 18).

## 확정된 아키텍처 (⚠️ 바꾸기 전 반드시 이해)

```
Cin7 Core ──(폴링)──> Supabase Edge Function ──> Supabase Postgres(RLS ON)
                            │                          ↑   ↑
   BQ 마스터 ──(GAS 복제)──> Supabase 복제테이블 ───────┘   │
                                                            │
브라우저 6화면 + 런처 (GitHub Pages, wms.asung.ca)          │
  wms-config.js(anon key) + wms-auth.js(로그인) ──(anon)────┘
  직원 로그인 → wms_staff role → 화면 접근/메뉴 필터
```

- **Edge Function은 BQ에 직접 안 붙습니다.** 조직정책 `iam.disableServiceAccountKeyCreation`이 서비스계정 JSON 키 생성을 차단(Google Secure by Default)했기 때문. Workload Identity는 과함. → **제3의 길**: GAS가 BQ 마스터를 Supabase로 복제하고, Edge Function은 Cin7 읽기 + Supabase 조인만. BQ 인증 관문 자체가 소멸.
- **WMS는 Cin7에 쓰지 않습니다(MVP).** 작업 완료 시 담당자에게 알림만 → 담당자가 Cin7에서 pack authorize → Cin7 automation('pack is authorized' 이벤트)이 Order_Progress를 `3.Finalized`로 전환 + 재고차감. 즉 재고 무결성은 Cin7이 지키고 WMS는 안 씀.
- **WMS가 소유하는 단계는 Cin7 Order_Progress = `2.Release to WMS` 하나뿐.** 흐름: `1.New`(오더생성) → 매니저 authorize → `2.Release to WMS`(수동) → [우리 WMS: 분할·분배·병렬 픽/팩] → `3.Finalized`(Cin7 automation 자동전환).
- **프론트엔드는 순수 HTML/JS + Supabase JS CDN.** 빌드툴 없음. GitHub Pages(public repo)로 `wms.asung.ca`에 배포. 스캔 = Bluetooth HID(키보드처럼 입력+Enter).

## 환경 상수

| 항목 | 값 |
|------|-----|
| Supabase 프로젝트 | `asung-WMS` (org: Asung Trading, Free) |
| Supabase URL | `https://gftpcnkxbdjzzfvzwcfl.supabase.co` |
| project-ref | `gftpcnkxbdjzzfvzwcfl` |
| region | `ca-central-1` (캐나다) |
| 로컬 개발폴더 | `~/asung/asung-wms` (WSL2 Ubuntu). 집·회사 동일 세팅. ⚠️ `/mnt/c/...` 아래에서 작업 금지 — WSL 파일 I/O가 크게 느려짐 |
| GitHub | `asungtrading/asung-wms` — ⚠️ **PUBLIC** (Pages 무료 배포 위해 전환) |
| 배포 URL | `https://wms.asung.ca` (커스텀 도메인, DNS CNAME→asungtrading.github.io) |
| BQ Project | `geometric-rock-487814-k4` |
| Cin7 API Base | `https://inventory.dearsystems.com/ExternalApi/v2` |

Cin7 키는 **양쪽에** 등록됨(별개 저장소): GAS Script Properties(`CIN7_ACCOUNT_ID`/`CIN7_APPLICATION_KEY`) + Supabase secrets(동일 이름). `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`는 Edge Function에 **자동 주입**(별도 등록 불필요). GAS가 Supabase에 쓸 땐 GAS Script Property의 `SUPABASE_URL`/`SUPABASE_SERVICE_KEY` 사용.

**⚠️ 비밀값 규칙 (매우 중요):**
- **anon(publishable) key = 커밋/공개 OK.** RLS + 로그인이 데이터를 보호하므로 `wms-config.js`에 넣어 public repo에 올려도 안전. 브라우저에 어차피 노출되는 값.
- **service_role key = 절대 금지.** GAS Script Property + Supabase Edge Function 자동주입에만 존재. 코드·커밋·스킬·스크린샷에 절대 안 넣음.
- Cin7 키를 `supabase secrets set`으로 넣을 때 터미널 화면·셸 히스토리에 값이 남으므로, 민감 시 rotate 권장(그럼 GAS+Supabase 양쪽 갱신).

**저장소에 있어야 하는 파일 (루트, 모두 같은 폴더):**
7개 화면 + 공유 2개 + 로고 2개 + 배포 파일.
- 화면: `index.html`(런처) `picker.html` `packer.html` `manager.html` `admin.html` `staff-admin.html` `fulfillment.html`
- 공유: `wms-config.js`(anon key — ⚠️실제 key 든 버전 유지, 덮어쓰지 말 것) `wms-auth.js`(로그인 모듈)
- 로고: `asung-logo-white.png`(런처=어두운 테마용) `asung-logo-dark.png`(6화면=밝은 헤더용, 흰로고 RGB를 잉크색으로 recolor해 생성)
- 배포: `CNAME`(내용 `wms.asung.ca`, 건드리지 말 것) `.nojekyll`(Jekyll 빌드 스킵 — supabase/·.vscode/ 폴더 때문에 필수)
- ⚠️ `tools.asung.ca`(customer-portal, 별도 repo `asungtrading/tools`)는 반드시 PUBLIC 유지(private면 무료 Pages 죽음).

## DB 스키마 변경 절차 (⚠️ 2026-07-26 확립 — 이 문서 전체에 우선)

**베이스라인 = `supabase/migrations/20260101000000_baseline.sql`** (테이블 20 · 정책 22). 원격 히스토리와 정렬됨(`migration repair` 완료). **이 파일은 수정하지 말 것** — 변경은 항상 새 마이그레이션으로.

허용된 절차:
1. `supabase migration new <name>`
2. 생성된 파일에 SQL 작성
3. `supabase db reset` — 로컬에서 처음부터 재생해 검증
4. `supabase db push` — ⚠️ **사람이 직접만 실행. Claude 는 명령만 제시한다.**

금지:
- **대시보드 SQL Editor 로 스키마 변경** — 로컬과 원격이 어긋나 이 체계가 무의미해진다. 급히 했다면 즉시 `supabase db dump --linked` 로 되받아 반영.
- `supabase db push` 자동 실행
- `supabase stop --no-backup` (로컬 볼륨 삭제)
- `db pull` 의존 — 이 프로젝트에서 diff 단계가 조용히 실패한 이력이 있다. `db dump --linked` 를 쓴다.

드리프트 확인 `supabase db diff --linked` · 작업 후 `supabase stop`(개발 머신 RAM 8GB 상한).

⚠️ **dump 에 안 잡히는 것** — pg_cron 스케줄(`supabase/ops/cron.sql` 에 기록만, 마이그레이션 아님) · Edge Function secrets · Auth 설정(Site URL / Redirect) · Storage 버킷 설정.

⚠️ **이 문서 곳곳의 `wms_*.sql` 파일 이름은 역사적 기록**(`wms_waves.sql`·`wms_receipts.sql`·`wms_healthcheck.sql` 등). 그 파일들은 repo 에 더 이상 없고 내용은 전부 baseline 에 흡수됐다. **다시 실행하지 말 것** — 스키마 계보를 볼 땐 baseline 을 읽는다.

## 이 스킬 문서를 갱신할 때 (⚠️ 2026-08-04 — 규칙보다 먼저 읽을 것)

### description 예산 — ✅ 2026-08-05 감축 완료 (1017 → 722자 · 여유 302자)

**현재 `asung-wms` frontmatter description = 722자 / 한도 1024자 → 여유 302자**(2026-08-05 `scripts/check-skill-desc.sh` 실측. 넘으면 claude.ai 업로드가 `must be at most 1024 characters` 로 **거부**된다 — 바이트가 아니라 문자 수).

⚠️ **2026-08-04 기록은 "여유 7자 — 다음 규칙 하나면 초과" 였다.** 그 상태에서 규칙 42 를 만들지 못하고 미뤘으므로, 2026-08-05 에 **별건 작업으로 감축**했다(사용자 결정). **무엇을 뺐는지 남긴다 — 다음에 "왜 이 키워드가 없나" 를 다시 추측하지 않게:**

- **키워드 9개 제거**: `"Supabase"`·`"Edge Function"`(⚠️ **삭제가 아니라 중복 제거** — 바로 앞 문장 "Supabase(Postgres+Edge Function) 기반" 에 산문으로 남아 있어 트리거 신호는 그대로다) · `"authorize"`·`"동시 작업"`(과도하게 일반적 — 무관한 작업에서 스킬을 띄우는 잘못된 트리거였다) · `"Lines is invalid"`·`"스캔 이어받기"`(해소된 함정어 — 압축 순서 2번) · `"unconfirmed"`·`"writeChain"`·`"serverChecks"`(규칙 24 구현 내부 이름 — 사용자가 이 단어로 말할 일이 드물다).
- **열거 압축**: `아키텍처·스키마·인증·배포·규칙 20~41` → `아키텍처·스키마·배포·규칙 20~41`.
- **⚠️ 불변식 목록 9개 → 4개** (사용자 결정 — 남긴 기준 = "몰라서 어기면 재고·수량이 틀어지거나 남의 작업이 사라지는 것" + "다른 스킬 description 이 커버하지 않는 것"): **유지** = factor는 unit 컬럼 · bin은 base_sku 기준 · service_role 금지 · 리시빙 저장은 라인 단위/.select() 1행. **제외** = Order_Progress=AdditionalAttribute1(규칙 1) · Cin7 쓰기 bin은 GUID · PO는 Invoice First 선승인 · stock received 문서당 bin 1개·authorize POST(이 3개는 `cin7-api` description 이 `bin GUID`·`Invoice First`·`stock received 쓰기` 로 이미 갖고 있어 **Cin7 쓰기 작업엔 그쪽이 먼저 뜬다**) · UI 영어(CLAUDE.md 5절 + 규칙 11, 어겨도 되돌릴 수 있다).
- ⚠️ **본문에서 빠진 것은 없다.** 위 5개는 전부 해당 규칙 본문에 그대로 있다 — description 에서 뺀 것은 **트리거·요약이지 사실이 아니다.**

**다음에 규칙 42 를 추가할 때**: `규칙 20~41` → `규칙 20~42` 로 1자 + 새 키워드 몇 자 — 여유 302자 안에서 문제없다. **그래도 무제한은 아니니** 압축 순서(CLAUDE.md 7절과 동일)를 남겨 둔다:

1. **규칙 번호 범위 표기** — 이미 범위형이라 줄일 게 없다. 앞의 열거도 2026-08-05 에 압축됨.
2. **해소된 함정어를 뺀다** — 그 함정이 다시 오지 않으면 트리거 가치가 낮다. (2026-08-05 에 위 4개를 이 기준으로 뺐다.)
3. **다른 스킬 description 에 이미 있는 중복어를 뺀다** — `cin7-api` 가 가진 단어는 그쪽이 먼저 뜬다.
4. **일반어·영한 중복쌍**을 뺀다.

⚠️ **트리거 키워드를 먼저 버리지 말 것** — description 은 "이 스킬이 **언제 로드될지**"를 정한다. 키워드를 자르면 필요한 순간에 스킬이 안 뜬다. 남은 **불변식 4개는 마지막까지 유지**.
검사: `scripts/check-skill-desc.sh` (커밋 hook = `scripts/hooks`, 클론한 머신마다 `git config core.hooksPath scripts/hooks` 1회).

### 기록 규칙 (이 문서가 신뢰를 유지하는 방식)

- **틀린 기록은 지우지 않는다 — "정정임을 명시하며 교체"한다.** 무엇이 틀렸는지·왜 틀렸는지·정답을 함께 남긴다(예 규칙 20 의 `RestockReceivedStatus` 오타 절, `references/schema.md` 의 `note` 컬럼 부존재 절). 지워버리면 같은 오류를 또 저지르고, 그때 "전에 이거 확인했는데" 가 근거로 재활용된다.
- 📌 **2026-08-12 세션의 잘못된 판단 12건 — 오후 8 + 저녁 4 (요약 — 전문·표는 `docs/sessions/2026-08-12-hold-and-postgrest-cap.md` 9장·12장 · 저녁분 `docs/sessions/2026-08-12-evening-addendum.md` D절)**: 팩 대기열 장애의 원인을 두 번 헛짚음(최근 배포한 보류 필터 → 되돌려도 그대로 / order_id 매칭 가설 → 코드로 반증. 진짜 원인은 1000행 캡) · Pick 목록을 Pack 으로 착각(⚠️ **어제와 똑같은 실수 — 어느 화면·어느 탭을 보고 있는지 먼저 확인**) · 훅 원안 A 가 사고 5건 중 4건을 놓침 · Stats 대조 기준 오인(completed_by ≠ assigned_to) · dry-run 이 저장된 cin7_type 을 보는 것 미확인 · "#11 폴백 제거" 제안(폴백의 존재 이유와 순환) · herd 오판(어제 건). **공통 원인 = 한 개의 관측·미확인 가정으로 단정. 유효했던 대응 셋 = 재측정 · 되돌려서 배제 · 코드로 확인 — 셋 다 이날 실제로 효과가 있었다.** 이날의 도구 교훈 둘은 본문에 산다: 📌 **"되돌리기는 원인 배제의 도구다"** — 되돌렸는데 증상이 남으면 그 배포가 원인이 아니다(오진 2건을 그것이 끊었다) · 📌 **"이 도구가 있었으면 그 사고를 막았는가"가 도구 규칙 채택의 유일한 시험**(규칙 20 캡 절의 소급 검증 — 훅 원안의 구멍을 그 시험이 잡았다). ① Pick 목록을 Pack 으로 착각해 "다른 사람 배치 섞임" 결함을 만들어냄 — **틀린 전제로 조사를 시작시키면 없는 결함을 "찾아내" 멀쩡한 코드를 고친다**(즉시 중단으로 무피해 — 어느 화면·어느 탭인지 먼저 확인) ② herd 동시 만료를 "checked_at 미갱신"으로 오판 ③ 같은 것을 "절감이 사라졌다"로 오판(5분 뒤 재측정이 정정) ④⑤ 컬럼명 확인 없이 사용 2회(created_at/kind — 실제는 updated_at/action). **공통 원인 = 한 개의 관측으로 원인 단정 — 어제(스크린샷 2장=1회차 단정)와 동일 패턴. 대응 = 재측정·교차 확인 후 판단**(재측정이 두 번 다 정정을 만들었다). 부수 교훈: 행에 증거가 없으면(picked_at 전 행 null) **사람에게 묻는 것이 유일한 방법** — ⚠️ 추궁으로 들리지 않게("시스템이 시간을 잘못 재고 있어서 원인을 찾는 중"). **저녁 4건 (admin 표시 작업 중)**: SO-14496-10 을 "팩 시작 후 Hold"로 추정(실제 held_by·started_at 전부 null — 아무도 안 열었다) · "코드 에러 같다"에 동조할 뻔(status pending + 전부 null = 정상 상태) · "Packing = 팩 태스크 유무" 판정을 데이터 오독(-11 에도 태스크가 있다고 잘못 읽음)으로 뒤집을 뻔 · 컬럼명 확인 없이 사용 3회째(`wms_pack_tasks` 는 created_at — updated_at 아님). 📌 **이날 "최근 배포를 먼저 의심"이 세 번 빗나갔다**(팩 대기열 장애 · SO-14496-10 · PHASE 라벨) — **데이터부터 보는 것이 매번 옳았다.**
- 📌 **2026-08-10 세션의 잘못된 판단 6건 (요약 — 전문·표는 `docs/sessions/2026-08-10-transfer-parallel-and-clamp.md` 4장·9장)**: ① 처리량 계산에 콜당 지연을 0 으로 놓음("한도 60/60 → 이론상 4분" — 실제 21분, POST 1건 6~9초) ② 스크린샷 2장 사이를 1회차로 단정("N=12 로 뛰었다" — 실제 6회차) ③ **화면에 답이 적혀 있는데 추정을 앞세움**(alert 원문 `round limit (30) reached` 를 두고 "무한루프 가드" 추정) ④ t0 역산이 다른 가정 위(`booted` 로그로 반증 — EF 준비 시간은 0) ⑤ "폴링 먼저 안 고치면 429 가 더 난다" 순서 강제 근거 약함(병렬화가 총 소요를 줄여 겹칠 횟수도 줄인다) ⑥ 완료 PUT(6~9초)의 예산 소모 누락("회차당 8그룹" 예측 실패). ⬜ 1회차가 배치 1개로 끝난 이유는 미해결(t0 역산이 booted 로그와 모순).
- **실측에는 날짜·문서번호·값을 붙인다** — "2026-08-04 실측, `StockReceivedStatus=NOT AVAILABLE` Total 585", "TR-03144 327라인/100+그룹". 근거 없는 숫자는 다음 사람이 검증할 수 없다.
- **추정은 추정으로, 미검증은 미검증으로 표시한다** — `WORK_HOURS`(09–17) 같은 추정 상수, "배포됐으나 실전 미검증"(규칙 36·40). ⚠️ **"동작한다"고 쓰기 전에 실물에서 봤는지 확인할 것.**
- ⚠️⚠️ **근거의 출처를 표시한다 — 관찰 / 증언 / 일반적 동작 설명은 다른 등급이다** (2026-08-05 사용자 결정 · SO-14129 교훈). 사고 조사에서 **"완료 후 다음 스캔 시 alert 가 떴다"** 가 조사 프롬프트에 "재현으로 확인" 으로 적혀 있었지만, 실제로는 **일반적인 초과 스캔 동작에 대한 설명**이 조사 과정에서 **사고 당시 관찰로 승격된 것**이었다. 그 위에서 코드 분석이 하루 진행됐고 가설(H1)도 그 전제에 얹혀 있었다. 규칙 27 **R11**("쓰기 실측의 근거는 200 이 아니라 되읽은 값")과 **같은 계열** — 결론이 아니라 **근거의 출처**가 문제다.
  - 표기: **관찰**(누가·언제·무엇을 봤나) / **증언**(사람 말 — 확인 전) / **설명**(코드·일반 동작에서 유추) / **실측**(날짜·값). 조사 문서는 이 넷을 섞지 말 것.
  - ⚠️ 특히 **내가 앞선 세션에서 쓴 문장을 다음 세션이 근거로 재활용한다.** "확인함" 이라고 쓸 때 **무엇으로 확인했는지**를 같은 줄에 남길 것 — 없으면 다음 사람(=다음 세션의 나)이 검증 없이 얹는다.
- ⚠️⚠️ **UI·입력 동작은 코드 읽기로 결론내지 않는다 — 실물 1회가 코드 조사 4시간보다 값싸다** (2026-08-05 · SO-14129 교훈). 재포커스·`focus()`·모달 포커스 코드가 전 지점에 있어서 "스캐너 Enter 가 confirm 을 승인했다" 가 코드상 그럴듯했지만, **안드로이드 태블릿 실측에서 반증**됐다(스캐너는 읽었으나 다이얼로그 무반응). 진짜 원인은 코드에 없던 것 — **footer 인접 버튼 오탭**이었다. 브라우저·OS·스캐너 HID·터치는 코드가 말해주지 않는다 → **실물 1회를 먼저.** 관련: 규칙 17(렌더/스캔 함정), 규칙 34(태블릿 실물 확인 대기).
- **새 교훈은 다음 규칙 번호로** 만들고, **기존 규칙에는 참조 한 줄만** 더한다(본문 중복 서술 금지 — 두 곳이 갈라지면 어느 쪽이 최신인지 알 수 없다).
- ⚠️ **규칙 번호로 승격할지의 기준 = "모르면 사고가 나는가"** (2026-08-04 사용자 결정). 재고·수량·Cin7 반영이 틀어지거나 남의 작업이 사라지는 것이면 번호를 준다. **UI 입도·표시 방식처럼 몰라도 사고가 안 나는 것은 `references/` 절 + 관련 규칙 각주로 충분하다** — 번호는 description 예산(위)을 먹기 때문에 값을 치를 만한 것에만 쓴다. 실제 사례: 풋어웨이 완료 입도(2026-08-04)는 규칙 42 로 올리지 않고 `references/frontend.md` 「풋어웨이 완료 입도」절 + 규칙 37 각주로 남겼다. **같은 고민을 다시 하지 말 것.**
- **백로그는 「백로그 / 미해결」 단일 목록이 유일한 출처다** — 규칙 본문·`references/` 에 "백로그" 라고만 적고 그 목록에 올리지 않으면 잊힌다. 규칙 번호를 달아 분류 중 하나에 넣을 것.

### 앵커 — 주관이 안 섞인 숫자 (추세는 이걸로 읽는다)

점수(보안/효율/기능)는 **더 알게 되면 저절로 내려간다** — 코드가 나빠지지 않았는데도. 추세선으로 쓸 수 없다. 앵커는 세면 나오는 숫자라 그 문제가 없다. (정본·경위: `docs/sessions/2026-08-11-polling-and-stats.md` 13장)

| | 08-06 | 08-07 | 08-11 | 08-12 |
|---|---|---|---|---|
| 애플리케이션 트리거 | 0 | 0 | 0 | **0** |
| 트랜잭션 안 다중행 쓰기 | 0곳 | 4곳 | 4곳 | **4곳** |
| 자동 테스트 | 0 | ~38케이스 | ~47케이스(+`po_clamp` 9) | **~47 + 훅 9**(`test-caps-hook.sh`) |
| DB 제약(unique·check) | 5 | 8 | 9 | **10** (hold_state CHECK) |
| 쓰기 무확인 | 26 | 5 | 5 (미감사) | 5 (미감사) |
| 되돌릴 수 없는 쓰기 잠금 | 0/2 | 2/2 | 2/2 | 2/2 |
| 조사 없이 구현 | 0 | 0 | 0 | **0** |
| Cin7 하루 콜 | — | ~26,000 | ~12,000 | ~12,000 |
| **세션당 조용한 결함 발견** | — | — | 3 | **6** |
| **`caps-ok: TODO`** | — | — | — | **13 → 0** ← 신규 |
| **하루 배포** | — | — | — | **15**(오후 14 + 저녁 1) ← 신규 |
| **하루 정정(잘못된 판단)** | — | — | — | **12**(오후 8 + 저녁 4) ← 신규 |

⚠️ **트리거 0과 트랜잭션 4가 나흘째 그대로다** — 그 벽 뒤에서 08-11 결함 3건이 나왔고, 08-12 는 6건 중 5건이 또 한 뿌리(1000행 캡 — "전부 가져와 클라이언트가 거른다" 구조)였다.
08-12 의 6건 = Rollback Finalize 오판(513건 노출·실사고 1건) · pallet_items 2517 초과 · admin 배치 카드 과소(33→30 표시) · sku_bins 8배 초과(빈 드롭다운 1481 중 1000만) · Stats All 기간 과소 · 롤백 다운스트림 `.in` 잘림. ⚠️ **팩 대기열 정지는 세지 않았다**(작업자 신고 + 시스템 정지 — 정의 4조건 미충족). 세션 성격 = 캡 전수 조사(깊이 판 세션 — 신규 앵커 정의의 주의 ② 그대로). 정본: `docs/sessions/2026-08-12-hold-and-postgrest-cap.md` 10장. **저녁 작업(admin 표시 3건)에서 추가 발견 없음** — PHASE 라벨(SO-14496)은 표시 오해지 데이터 오류가 아니라서 정의 ④ 미충족. 저녁분 정본: `docs/sessions/2026-08-12-evening-addendum.md`.

**신규 앵커 「세션당 조용한 결함 발견」** — 정의: 다음 넷을 **모두** 만족한 것만 센다 — ① 에러가 나지 않았다 ② 시스템이 멈추지 않았다 ③ 아무도 신고하지 않았다 ④ 그런데 데이터가 틀렸다. **세지 않는 것**: 에러로 알게 된 것(429 alert 등) · 기능 요청 · 이미 알던 백로그 항목을 그냥 구현한 것. 이 숫자는 **"프론트엔드가 불변식을 소유한다"는 구조의 실제 비용**을 직접 잰다(계속 높으면 구조 문제 — 트리거·트랜잭션으로 DB 에 내리기 전엔 안 떨어진다 / 낮아지면 진짜 개선). 테스트 케이스 수와 달리 의미 없는 걸 늘려 올릴 수 없다. ⚠️ **읽을 때의 주의 둘**: ① **표본 1개는 아무 의미 없다** — 몇 세션 쌓여야 추세다 ② **발견 수는 "얼마나 파고들었느냐"에 좌우된다** — 08-11 은 Stats 확장으로 깊이 파서 3건이 나왔다. **얕게 지나간 세션의 0건은 "결함이 없다"가 아니라 "안 봤다"일 수 있다** — 세션 성격을 같이 적을 것.

---

## 규칙 1 — Cin7 오더 구조 (실측 확정, 추측 금지)

- **Order_Progress = `AdditionalAttributes.AdditionalAttribute1`** ⚠️ 백오더 `'Backordered'`와 **같은 필드를 공유**. 진행단계일 땐 `'2.Release to WMS'`/`'5.Fulfilled'` 등이 들어감.
- **saleList는 AdditionalAttributes를 안 줌** → 반드시 `/sale` 상세로 확인.
- **AUTHORISED에 여러 진행단계가 혼재**(Fulfilled/Packed도 AUTHORISED) → saleList로 후보 좁힌 뒤 상세에서 `AdditionalAttribute1='2.Release to WMS'`만 필터 필수.
- `/sale` 상세 최상위: `AdditionalAttributes`(객체) / `Location`(창고명 문자열) / `Order`(라인) / `Fulfilments` / `Status`(='ORDERED'). ⚠️ `OrderStatus`·`OrderLocationID`는 상세엔 없음(saleList에만).
- 라인 = `Order.Lines[]`, 필드: `SKU`/`Name`/`Quantity`/`Price`/`AverageCost`/`BackorderQuantity`/`ProductWeight`.
- Cin7 헤더: `api-auth-accountid` / `api-auth-applicationkey`.

## 규칙 2 — warehouse 정규화

```
Cin7 Location에 "Edmonton" 포함  → 'edmonton'
그 외 ("Asung Trading Inc." 등)   → 'toronto'
```
"Edmonton 포함 여부"로 판정(Toronto 문자열이 뭐든 안전). 오더 유입(Edge Function)과 bin 동기화(GAS) **양쪽에 동일 적용**해야 매칭됨.

## 규칙 3 — base 정규화 & factor (⚠️ 재고 수량의 핵심)

Cin7 UOM: 재고는 대부분 **낱개(base=EA)**로 추적, 판매단위는 제품마다 다름. 판매단위는 SKU 형태로 판별 불가 — Cin7 `Sellable` 필드(=`is_selling`)가 유일한 진실. 오더 라인엔 `is_selling=Yes` SKU만 옴.

- **factor 소스 = `asung_product_master.unit` 컬럼** (base='EA'→1, 변형=숫자 12/48/240…). ⚠️ **접미사 아닌 unit 값을 신뢰**(ALT-UPC·PIN-1/-2처럼 접미사가 factor 아닌 케이스 존재. 검증: 변형 6,270행 중 오염 0.05%).
- **정규화**: `required_base(낱개) = ordered_qty × factor`. factor = 오더SKU가 변형이면 그 unit, base면 1.
- **⚠️ bin 조회는 order_sku가 아닌 `base_sku` 기준**. 재고는 낱개(base)로 쌓이므로 변형 오더도 base 위치에서 픽.
- 무결성 가드: 라인에 `is_selling=false`면 플래그(오더에 온 것 자체가 이상).

## 규칙 4 — 바코드 스캔 3-tier & scannable_barcodes

픽커 스캔 fallback: ①변형 바코드(+factor) ②base 바코드(+1) ③수동입력(+flag). `verification_method` 추적: `scanned_variant`/`scanned_base`/`manual`. 커버리지: 변형 78%·base 98.5%(base 없는 137개는 완전수동).

`wms_sku_snapshot.scannable_barcodes`(jsonb `[{barcode,factor,type}]`)를 GAS가 조립: 자기 바코드 + base 바코드 + **ALT-UPC 별칭**(하나의 SKU에 바코드 여러개 담는 레코드, `%-ALT-UPC`). ALT-UPC를 base에 묶는 로직은 `Binstockdata.gs`의 products.json 생성부(base 첫하이픈앞 매칭 + LIKE)를 재사용.

## 규칙 5 — zone 파싱 & 동선

- **edmonton bin = `E`+zone문자 체계**(`isEdmontonCode=/^E[A-Z]/`). zone = bin[1] (E 다음 글자). 예: `EU020303`→U, `EZ010101`→Z, `ED020101`→D.
- **toronto bin = zone이 첫 글자**.
- 동선 순서는 `wms_zone_sequence`(WarehouseMap `toronto.zpos`/`edmonton.zpos` 좌표 기반 초안). 사용자가 UPDATE로 zone별 조정. 좌표(center_x/y)도 저장돼 나중 경로 최적화·시각화 확장 가능.
- 좌표 기준 초안 순서 — toronto: D-C-A-Z-B-E-G-J-H-R-F-W-K / edmonton: F-E-D-C-B-A-U-Z-G-I.

## 규칙 6 — 마스터 복제 동기화 (길 A: 테이블 고정 + 데이터 통짜교체)

`WmsSync.gs`(System_Automation)의 `runWmsMasterSync()`가 BQ 3테이블을 조인→Supabase 2테이블 **truncate + 재적재**(PostgREST delete-all + 500개씩 배치 insert). 트리거 `setupWmsSyncTrigger()`=매일 6:30.

- **길 A 이유**: PostgREST는 행 삽입만 되고 DDL(CREATE TABLE) 불가. 그래서 테이블 구조는 **마이그레이션으로 미리 고정 생성**(baseline 에 포함됨), GAS는 데이터만 교체. "BQ가 진실, Supabase는 최신 복사본"은 그대로 달성. ⚠️ 여기서 "미리 생성"은 **SQL Editor 가 아니라 마이그레이션** — 위 「DB 스키마 변경 절차」 참조.
- **스키마 드리프트 대응**: WMS 스냅샷은 master에서 4개만 씀(product_name·barcode·unit=factor·is_selling). BQ에 무관한 컬럼이 생겨도 **아무것도 안 함**. WMS에서 쓰고 싶을 때만 의식적 3줄(**새 마이그레이션의 ALTER** + GAS SELECT + 프론트).
- **복제 소스 3개**: (1)`Cin7_Master_Data.asung_product_master` (2)`Cin7_Master_Data.asung_bin_stock`(grain sku×wh×bin, sticky=재고0도 is_current=FALSE 자리보존, Binstockdata.gs 관리) (3)`Cin7_Sales_Data.asung_product_images`(sku→image_url, customer-portal·warehousemap 동일소스). ⚠️ **(3)의 image_url 은 2026-08-14 부터 6:30 재적재 직후 `product-images` EF 가 Cin7 값으로 매일 덮어쓴다**(BQ 값은 폴백·타 앱용 — 아래 「상품 이미지 파이프라인」 절).

## 상품 이미지 파이프라인 — 7주 묵은 CSV 실사고와 Cin7 직결 EF (2026-08-14)

**[실사고] WMS 상품 사진이 7주 묵어 있었다 — GHO57212 미표시 보고로 발견.**
사슬: ①Cin7 → ②BQ `asung_product_images` → ③`wms_sku_snapshot`(매일 6:30 WmsSync 재적재 — 규칙 6) → ④`wms_order_lines`(유입 시점 동결). **원인은 ②** — CSV 수동 3단계(Cin7 export → Drive 업로드 → GAS `loadProductImagesFromCsv`)인데 **6월 26일 이후 아무도 안 돌렸다**(Drive 폴더 `1A0r8zRz2wTfQJVGvsXVeTXlXPPMe2mpG` 에 `ImagesAndAttachments_20260626.csv` 하나뿐이었다). 📌 **뿌리는 "CSV 가 묵은 것"이 아니라 "7주 묵은 것을 아무도 몰랐다"** — 처방의 중심이 자동화만이 아니라 감시(`image_sync_stale`)인 이유.

- **[부수 발견 — 원 목적보다 큰 수확] 대표 이미지(Default=Yes) 미지정 SKU 427개.** 사진이 첨부돼 있는데도 WMS·포털 어디에도 안 나오고 있었다(BQ 적재가 Default 로 거르므로 양쪽 다 비어 있었다). 첨부 1개뿐인데 미지정 327 / 첨부 2개+ 미지정 100 — 담당자의 대표 지정 누락이었고 **426개를 CSV 재업로드로 수정**(8,327 → 8,753). 남은 1개(AES15203-12)는 **사진이 필요 없는 변형 SKU** = 정상 상태. 📌 **"IsDefault 없음"은 예외가 아니라 정상일 수 있다 — 경고로 취급하지 말 것**(EF 의 `no_default_but_has_attachments` 가 카운트만 하고 경고하지 않는 근거 — 사용자 결정).

**[Cin7 API 실측 — 2026-08-14 GAS 프로브]**
- ⚠️ `GET /product?Page=N&Limit=100&IncludeAttachments=true` — 파라미터명이 정확히 **IncludeAttachments**(IncludeAttachment/IncludeAll 은 빈 배열 — 규칙 20 "조용히 무시" 계열: 이름이 틀려도 200 이다). `Attachments[]`: `{ID, ContentType, FileName, IsDefault, DownloadUrl}`. Total 14,718 → **148페이지 · 페이지당 325ms·328KB**.
- ⚠️ **URL 은 DownloadUrl 을 쓰지 말고 ID 로 조립**: `https://inventory.dearsystems.com/Product/Download?id=<Attachment ID>` — CSV 가 쓰던 형태와 GUID 동일함을 실측 확인 · DownloadUrl 에는 timeStamp 서명이 붙어 만료 위험 · 조립 URL 의 `<img>` 표시 확인(2048x2048 — 주소창 직접 열기는 다운로드되지만 `<img>` 는 렌더된다).
- ⚠️ `GET /product/attachments` 는 **ProductID 필수** — 전체·SKU·페이지 조회 전부 400. 개별 조회면 14,590콜이라 부적격 — IncludeAttachments 148콜이 답.
- ⚠️ **ModifiedSince 는 증분 필터로 못 쓴다** — 파라미터 자체는 작동하지만(전체 14,718 vs 08-13 이후 4,010) 재고 변동 등이 LastModifiedOn 을 올려 하루 4,010건이 나온다 → **매번 전량 148콜**(쓰기 최소화는 EF 의 diff 가 담당).

**✅ `product-images` EF 구현 완료 (커밋 `d8367e9` → 같은 날 v2 `7180f15`)** — pg_cron 이 매일 Cin7 대표 이미지를 받아 `wms_sku_snapshot.image_url` 을 덮어쓴다. **BQ CSV 경로와 WmsSync 의 BQ 이미지 조인은 유지**(사용자 결정 — 이중 안전: EF 가 실패해도 다음날 아침 옛 사진이 남는다. 완전 분리는 원장 착수 때 BQ 의존 정리와 함께). 흐름: 인증 → 쿨다운 → **202 즉시 응답** → 백그라운드(수집 → all-or-nothing 관문 → 스냅샷 diff → 변경분만 upsert → run 기록).
- ⚠️⚠️ **150초 IDLE_TIMEOUT 실측 — 긴 EF 를 만들 때 반드시 고려할 것 (이 프로젝트의 다른 EF 에도 적용된다)**: 첫 수동 실행(동기 v1)이 504 `{"code":"IDLE_TIMEOUT","message":"Request idle timeout limit (150s) reached"}` 로 끊겼다. 📌 **wall-clock 400초와 별개로 "응답 바이트가 150초간 안 나오면" 게이트웨이가 끊는다.** → **EdgeRuntime.waitUntil** 로 해결(Supabase 문서: 백그라운드 상한은 wall-clock/CPU/메모리 limits = 유료 400초). 인증·쿨다운은 동기 구간 유지 — 401/403/SKIPPED 는 즉시 알아야 한다. 백그라운드는 클라이언트가 결과를 못 보므로 **결과 확인 창구는 `wms_image_sync_runs` 뿐**(최상위 try/catch 가 ok=false 도 기록).
- **all-or-nothing 3조건**(수신==Total · 429 조기 종료 없음 · non-200 페이지 없음) — 하나라도 어긋나면 **한 행도 안 쓴다**. ✅ 첫 실패(504) 때 실제로 작동했다: runs 0행 · 스냅샷 has_image 8,754 그대로 = 부분 갱신 없음.
- ⚠️ **존재 필터가 급소** — 없으면 스냅샷에 없는 Cin7 SKU 가 유령 행으로 insert 된다(PostgREST merge-duplicates 는 없는 행을 insert 한다). 페이로드의 sku 는 **스냅샷 행의 원문**(대소문자 이중 방어).
- ⚠️ **SKU 매칭은 sku 정확 일치(base_sku 아님)** — Cin7 에서 GHO57212 와 GHO57212-50 은 별개 product 로 각자 Attachments 를 갖는다([실측]). base 폴백도 넣지 않는다(BQ/포털 동작과 갈라진다).
- ⚠️ **대표 이미지 없으면 그 행 무접촉** — 빈 값을 쓰는 경로 자체를 만들지 않는다(이중 안전의 전제: BQ 유래 값이 남아야 한다).
- ⚠️ **ContentType image/ 가드** — PDF 가 대표로 지정된 경우 깨진 URL 로 멀쩡한 BQ 이미지를 덮는다. 그 외: 페이지 원문 비누적(148페이지 ~48MB vs EF 메모리 256MB) · 시간 가드 330초는 **쓰기 앞**(receiving `APPLY_TIME_BUDGET_MS` 원칙) · duplicate SKU 가드 · `synced_at` 무접촉("GAS 가 마지막으로 적재한 시각" 의미 보존).
- **인증**: `x-wms-cron-key` 시크릿(⚠️ hello 폴링식 무인증 복제 금지 — 호출 1번 = Cin7 148콜 증폭, secret 미설정이면 500 fail-closed·레포 PUBLIC 이라 실제 값은 secrets+대시보드 cron 등록에만) + **쿨다운 20h**(ok=true 최신 행 기준 — 실패는 재시도를 안 막는다) + `force=1` 은 authgate(verifyCaller/hasApply). [검증 2026-08-14] 시크릿 없이 호출 → 401.
- **cron**: `wms-image-sync` **12:30 UTC**(여름 토론토 8:30 — WmsSync 6:30 ±15분 이후·창고 9시 전. ⚠️ pg_cron 은 UTC 라 DST 로 계절마다 1시간 밀린다) + **재시도 13:30**(성공 시 쿨다운이 자동 no-op — 등록 비용 0). `supabase/ops/cron.sql` 잡 4·5.
- **`wms_image_sync_runs` 가 세 역할**: 관측(diag jsonb — EF 로그는 휘발) · Health 알림 · 쿨다운 가드. 90일 보존 정리는 EF 가 기록 직후(health_snapshot 의 "쓰기 지점에서 정리" 패턴).
- **`wms_health_check()` 에 `image_sync_stale`(warn·sort 120) 추가**(`20260814030000_image_sync_runs.sql`) — 마지막 성공 48h 초과 **또는 한 번도 없음**. ⚠️ **후자도 warn 인 것이 의도다** — cron 등록을 잊어도 조용한 것이 CSV 7주 사고의 재판이다(push 후 첫 성공까지 warn 1 상주가 정상). 기존 12검사는 **바이트 대조로 보존 확인**(추가 2블록을 빼면 baseline 원문과 동일).
- **[검증 2026-08-14] 첫 성공**: 148페이지 · **3분 32초(211,641ms)** · updated 6 · aborted null · no_default 1 · default_not_image 0 · missing_in_snapshot 0 · Health warn 소멸. 📌 **updated 6 은 같은 날 CSV 로 최신을 넣은 뒤라 정상** — CSV 경로와 API 경로가 거의 같은 결과를 낸다는 교차 확인이기도 하다. ⬜ cron 자동 회차·재시도 no-op 은 미관찰(「검증 대기」).
- ⚠️ **화면 반영 범위**: receiver 는 스냅샷 라이브라 즉시 / picker·packer·fulfillment 는 `wms_order_lines` 동결(유입 시점 복사)이라 **신규 유입 오더부터** — 결함이 아니라 기대치. 아침 6:30(재적재)~EF 실행 사이는 BQ 값으로 보이는 것도 정상 동작.

## 규칙 8 — 인증 & RLS (⚠️ 2026-07-19 도입)

- **개인 계정 방식**(공용 계정 아님). 직원마다 본인 이메일/비번. Supabase Auth에 20명 계정 생성됨(dashboard Add user + 임시비번 + Auto Confirm). 임시비번은 Caleb이 배포, 각자 앱에서 변경.
- **`wms_staff` 테이블이 권한의 진실.** 로그인 → auth 이메일로 `wms_staff` 행 조회(email unique) → 그 행의 `role`(worker/manager/admin) 사용. **이름↔이메일은 이미 매칭됨** — 이름에 준 권한 = 이메일에 연결된 권한. 따로 이메일에 권한 안 줘도 됨.
- **`wms-auth.js` = 공유 로그인 모듈.** 각 화면이 `wmsAuth.start({requireManager:bool}, (sb,me)=>{...})` 호출. 이메일/비번 `signInWithPassword`, 세션 자동 유지(localStorage — 진짜 브라우저라 동작, Claude.ai 아티팩트 아님). `wms_staff` maybeSingle로 신원 확인. requireManager=true면 worker 차단. 로그인 화면·"Forgot password"(resetPasswordForEmail)·로그인 후 #logoutBtn 옆 "Change Password" 자동삽입 다 포함.
- **화면별 requireManager**: picker/packer/**fulfillment=false(작업자 화면!)**, manager/admin/staff-admin=true.
- **런처(index.html) 로그인 게이트**: 로그인 전 오버레이만, 로그인 후 role 따라 메뉴 필터(worker=Picking/Packing/Fulfillment만, mgr/admin=+Order Splitting/Admin/Staff). ⚠️ role 필터는 `classList.remove("mgr-only")`로(‌CSS `.mgr-only{display:none}` 때문에 `style.display=""`는 안 먹음).
- **RLS ON**: wms_ 테이블 전부(신규 `wms_waves` 포함) `rowsecurity=true` + 정책 `auth_all`(`for all to authenticated using(true) with check(true)`). anon 거부, authenticated 전체허용. service_role은 RLS 우회(GAS 동기화가 RLS 켜진 뒤에도 작동하는 이유 = 설계 증명). `wms_health_check()`는 `security definer`. 세분화(직원 쓰기/불일치 해소=매니저만)는 백로그.
- ⚠️⚠️ **EF 에는 서버측 사용자 권한 검사가 없다 — 실측 확인 (2026-08-12, 규칙 43 작업 중 발견)**: receiving apply 의 "3중 게이트"는 전부 클라이언트다(admin.html — 버튼 표시 2곳 + JS 함수 진입 `applyToCin7` 머리의 `me.role==="admin"||perms.includes("apply")` 검사). **EF 자체는 플랫폼 verify_jwt 뿐이라 anon JWT 로 통과**하고, ⚠️ 레포가 PUBLIC 이라(환경 상수 표 — Pages 무료 배포) **anon 키는 누구나 볼 수 있다** — 즉 EF 호출 자체는 누구나 가능하다(RLS 가 DB 쓰기는 막지만 EF 가 service_role 로 하는 일은 못 막는다). **첫 서버측 게이트 = hello `hold_recheck`**(2026-08-12, 규칙 43 — `/auth/v1/user` 로 호출자 검증 후 wms_staff 권한 확인, staff-create 의 검증 패턴 이식). ~~다른 EF(특히 receiving apply — Cin7 쓰기)로의 확대와 레포 비공개 전환은 별건 백로그 — 이번 범위에서 고치지 않았다~~ → ✅ **확대는 2026-08-13 완료**: 게이트를 `_shared/authgate.ts` 로 추출해 **receiving 도 2단 게이트**(read 5종=로그인한 active 직원 / apply 는 dry-run·commit 둘 다 admin·'apply')를 쓴다(커밋 `c76729b` — 상세·검증·구현 판단은 백로그 「보안」). ⚠️ **레포 비공개는 그 항목에서 분리**(2026-08-13 정정 — anon 키는 F12 로 보이므로 비공개는 근본 방어가 아니라 로직 노출을 줄이는 별개 항목).
- **⚠️ 비번 재설정 이메일 링크**: Supabase Authentication→URL Configuration의 Site URL=`https://wms.asung.ca` + Redirect URLs=`https://wms.asung.ca/*` 설정해야 링크가 맞음(안 하면 localhost:3000으로 감). 배포 후 필수 설정.

## 규칙 9 — 프론트엔드 7화면 (순수 HTML/JS + Supabase CDN)

각 화면 `<head>`에 `wms-config.js` → `supabase CDN(@supabase/supabase-js@2)` → `wms-auth.js` 순 로드. 헤더에 로고+화면명, `me.name` 표시, ☰ Menu(드롭다운 내비)·Change Password·#logoutBtn.

**⚠️ 2026-07-21 세션에서 대량 추가됨 (아래 규칙 12~16 + references/frontend.md 참조).**

1. **index.html(런처)** — 다크테마, 로그인 게이트, role별 메뉴 카드. ⚠️ 메뉴 카드 클래스 `.card`가 `display:flex` → wms-auth 로그인 카드도 `card`면 충돌. **로그인 카드는 `wcard`로 격리됨**(교훈: 공유 모듈 클래스는 페이지와 안 겹치게).
2. **picker.html** — 셀프서브 픽킹, 낙관적 잠금, 홀드/재개, 스캔=factor 증가, WebAudio 삐+진동+플래시, 부족→"Complete as incomplete"→discrepancy. **`⚠ Not enough stock` 선언 토글**(2026-08-04, 규칙 41): 선반이 정말 비었을 때 short 를 실수가 아닌 **재고 불일치(`stock_short`, responsible=null, declared_by 기록)**로 재분류 — 선언된 라인은 finish() 가 short_pick 을 안 만든다.
3. **packer.html** — 전량 재스캔 검수, 목표=required(주문량) not expected(픽량), **부족 3갈래**: 팩커 부족분 보충("Pack fill") / **`⚠ Not enough stock` 선언**(선반 확인 후 보조 선언, source='packing') / 그대로 완료→short_after_pack. 픽커가 선언한 라인은 `Stock short — declared by {picker}` 칩 표시(선반 재수색 방지). **초과스캔 소프트경고 + 완료시 라인별 2택 모달**(2026-08-04 — "실물을 세어라": `Picker brought extra`→over_pick responsible=picker+반납 / `I scanned twice`→pack_scan_mistake 선해소 기록·실수 집계 제외), 회수된 부족→픽 discrepancy 해소, 전배치 팩완료→order status='ready_to_close'+알림. 상세는 `references/frontend.md` 「2026-08-04」.
4. **manager.html** — 오더 분할 + wave. **Split | Group 토글**. Split=하이브리드 분할(라인 한도 or 낱개 한도 먼저 걸리는 쪽, 동선순 정렬, 1라인=1배치 최소보장, 미리보기=생성 일치). Group=소량 오더 wave 그룹핑(규칙 18).
5. **admin.html** — 매니저 허브 **8탭**(Status/Discrepancy/Reports/Stats/Rollback/Finalized/Work Screens + **Health**), 기간필터+달력. 불일치 "Fixed in Cin7" 처리(사람이 Cin7 backend 수정 후). Health=불변식 검증 탭(규칙 19).
6. **staff-admin.html** — 20명 직원 목록, 인라인 창고/역할 드롭다운(변경즉시저장), active토글, 추가/삭제. **여기서 4명(Ho Kang·Ted Shin·Changmo Ku·Jan Ko)을 manager로 설정** → 그래야 그들에게 매니저 메뉴 보임.
7. **fulfillment.html** — 팔레타이징+팩킹리스트. **멀티오더**(고객별 그룹 체크리스트→여러 오더 동시), 오더→배치 2단 그룹 드래그, 부분수량 모달, 박스→팔렛 중첩, 혼합 팔렛 오더별 추적. **프랜차이즈**(여러 고객 혼합 허용, "N customers mixed" 경고만). **팩킹리스트 2종**: 유닛별 / **스토어별 종합**(각 스토어 1페이지, 그 스토어 물건이 어느 팔렛·박스에 있는지 + ⚠️미배정 경고). requireManager=false. **스캔 배정**(2026-07-29, 세 번째 입력 수단): 유닛 탭=타깃 → 상품 스캔 배정 — Scan qty|Move all 토글, 오더 귀속 3단(1오더 자동/유닛 내 오더 자동/모달), 박스=오더 하나 원칙(혼합 가드 `New box for …` + `⚠ N orders mixed` 배지), Undo 5건, 낙관적 렌더+저장 실패 롤백 — **규칙 36**(⚠️ 실전 미검증) · 상세는 `references/frontend.md` 「스캔 배정」. **분할 팩 완료 게이트 (2026-08-06 · ⚠️ 현장 미검증)**: 부모 오더의 **모든 분할이 팩 완료되기 전에는 보드에 안 보인다**(전부 아니면 전무 — 5분할 중 1개 미완이면 5개 전부 숨고 마지막 완료 순간 함께 등장. 현장 사고: 일부만 팩 완료된 오더가 진행돼 분할 누락 — 표시는 아무도 안 읽는다, SO-14129 동류). **판정 = `wms_order_pack_progress` 뷰 한 곳**(`20260806110000_…view.sql`, security_invoker + ⚠️ GRANT 필수 — 빠지면 보드 전체가 빈다): ⚠️ **분모는 픽 배치 수**(팩 태스크 수로 세면 팩 미시작 배치가 빠져 오판 — 실측 SO-14188 pick 2·pack 1) · `ready_to_close` 상태 비의존(전이 유실·롤백에도 사실 계산이 자동 복구 — 롤백이 pack_tasks 를 지우면 스스로 다시 숨는다) · 뷰에 행 없음 = 미자격(fail-closed). 소비 4곳이 전부 이 뷰만 읽는다: ①보드 필터(`loadOrders`) ②차단 오더 스캔 시 "N/M packed" 안내 토스트 ③**Finalize 직전 재확인 벨트**(로드 후 롤백 대비 — 미달이면 전체 중단) ④admin Status 의 `Fulfillment hold` 카드+행 칩(`⏳ N/M packed` — 숨긴 오더의 박스가 쌓이는 걸 매니저가 볼 유일한 신호). **예외 없음**(사용자 결정 — 갇히면 매니저가 롤백으로 재구성, 예외 컬럼 미리 안 만든다) — 나중에 예외가 생기면 **뷰의 all_packed 식 한 줄**만 고친다. ⚠️ **뷰 조회 실패는 "주문 없음"과 구분해 크게 표시**("Couldn't check pack status — NOT an empty queue" + Retry) — 빈 보드로 위장하면 작업자가 일이 없는 줄 알고 기다린다. ⚠️ 배포 순서: SQL(뷰) 먼저 → 프론트 나중. **팔렛 조작 쓰기 확인 (2026-08-06 감사 후속 · ⚠️ 현장 미검증)**: onDropToUnit·mergeOrInsert·delUnit·removeItem·노트 입력의 무확인 쓰기 11곳에 `mustRows` 헬퍼(error + `.select()` 행 수 — 규칙 20, 삭제는 0행 허용) 적용. PostgREST 는 실패해도 throw 하지 않아 바깥 try/catch 가 무의미했다. 실패 메시지 3등급(재시도 "drop it again" / **분할 이동 부분 실패 = 유실 방향** — "그 수량은 어느 팔렛에도 없음, pool 에서 다시 끌 것" / poolMany 집계 "N placed, M FAILED"), 실패 시 refresh() 재조회, **보상 쓰기 금지**. ⚠️ **분할 이동 순서는 감소→추가 유지(역전안 기각 — 사용자 결정)**: pool 이 rem>0 만 표시해 **증식은 숨고 유실은 보인다** — 일반론과 반대. 기준선·경위는 `docs/audits/2026-08-06-write-verification-baseline.md`(145곳 중 무확인 28+ — 패턴 26 + 정독 2, 하한).

- ⚠️ **완료 확인은 공용 마찰 모달 `wms-confirm-modal.js` (2026-08-05, SO-14129 팩 무단완료 후속)**: picker `Complete as incomplete`·packer `Complete pack` 의 native confirm 은 **물리 탭 2회**(footer 완료 버튼 오탭 → OK 오탭)로 스캔 0건 60줄 오더가 완료되는 결함이었다(상시 재현 검증). ~~스캐너 CR 이 confirm 을 승인한다는 가설(H1)~~ 은 실측 반증 — 안드로이드에서 스캐너는 읽었으나(비프) 다이얼로그에 무반응, 접미는 CR 뿐. **대응은 모달 강화 하나** — 하드 차단·버튼 위치 변경은 하지 않는다(사용자 결정). 모달: 부족 수량(base)을 정확히 타이핑해야 End 활성화 · Enter 확정 불가(캡처 차단, 스캐너 CR 포함) · Escape=취소(비표시 단축키) · autofocus 금지 · 표시 중 `scanBusy` 로 processScan 차단(packer overModal 도 포함) · 티어 2(부족 ≥ 주문 base 의 50%, 검수 0건=100%)는 빨간 경고문 추가 — **마찰 로직은 티어 무분기, 문구·라벨은 호출 화면이 넘긴다**(하드코딩 금지). ⚠️ **stock_short 선언 라인은 부족 계산에서 제외** — 선언만 남으면 모달 없이 가벼운 confirm(규칙 41: 정직한 기록을 벌주지 않는다). picker `Pick complete` 의 기존 toast 차단은 그대로(올바른 가드). 완료 UPDATE 는 `completed_by`, packer discrepancy insert 4곳은 `pack_task_id`·picker insert 2곳은 `pick_task_id` 를 남긴다(`20260805000000_completed_by_pack_link.sql` — **FK 없음**(롤백 delete 에도 증거 보존), **읽는 쪽 미구현(의도)**: 나중 롤백 무효화 근거, 무효화 판단은 reason 으로 — stock_short 는 선언 산물이라 대상 아님). 상세는 `references/frontend.md` 「2026-08-05」.

- **팩 완료는 RPC 한 트랜잭션 — `wms_complete_pack` (2026-08-06 8단계 · ⚠️ 현장 미검증 · 이 코드베이스의 첫 RPC/트랜잭션, 재고 원장의 예습)**: packer `doneBtn` 의 완료 쓰기 전부(라인 최종 저장 → discrepancy 3종 생성 → stock_short 정리 3종 → **CAS 플립** → ready 판정)가 `20260806150000_wms_complete_pack_rpc.sql` 함수 안에서 **전부 성공하거나 전부 취소**된다. ⚠️⚠️ **먼저 시도한 7단계(라인 묶음 upsert)는 구조적 불가로 폐기 — 재시도 금지**: `INSERT..ON CONFLICT` 는 **NOT NULL 검사를 충돌 판정보다 먼저** 하므로 NOT NULL 컬럼(pack_task_id 등)이 페이로드에 없으면 행이 이미 있어도 **항상 23502**(2026-08-06 프로덕션 실측 — 이전 조사의 "페이로드 키로만 SET 조립" 은 맞지만 검사 시점을 놓친 "설명" 등급이었다). 설계 골자: ① **thin 함수** — 수량·판정은 JS 가 보낸다(required 출처가 재개=reqMap/시작=assigned_base 로 경로마다 달라 서버 재유도 위험) ② **CAS 플립이 첫 쓰기** — 0행이면 예외 없이 `{completed:false, worker}` 반환(아무것도 안 씀 → **재호출 멱등, discrepancy 중복 원천 불가**), 1행이면 행 잠금이 트랜잭션 끝까지 유지돼 이어받기가 커밋까지 블로킹(확인-쓰기 창 소멸) ③ **완료자·픽커(responsible)는 서버 유도** — `auth.email()` → `wms_staff.name`(wms-auth.js:170 과 같은 행이라 me.name 과 같은 문자열) · 픽커는 `wms_pick_tasks.assigned_to`. ⚠️ **이름 드리프트**(매니저가 wms_staff.name 변경 → 진행 중 태스크 완료 불가)는 반환된 `worker` ≠ `me.name` 으로 프론트가 감지해 전용 프리즈 안내(`freezeScreen(null, msg)` — msg 파라미터 2026-08-06 추가) ④ 라인 UPDATE 는 `pack_task_id` 조건 필수(타 태스크 오염 차단) + **행 수 ≠ 배열 길이면 예외 = 플립 포함 전체 롤백**(메시지에 "removed by a rollback — ask a manager" — 원인 없는 실패는 작업자가 계속 다시 누른다) ⑤ ready 판정(checkOrderReady 상당)은 **예외 격리 서브블록(비치명)** — 실패해도 완료는 커밋, `ready_error` 반환(JS `checkOrderReady` 는 completeCasFailed 분기 ① 용으로 유지) ⑥ SECURITY INVOKER(전 테이블 RLS auth_all — 우회할 것 없음) + ⚠️ **함수 EXECUTE 는 PUBLIC 기본 부여라 명시 revoke**(뷰 기본 권한 실측과 같은 계열) ⑦ reason 화이트리스트 3종(플립 전 검증). CAS 0행 시 프론트 3분기(`completeCasFailed`)는 그대로. 라인 id 는 `20260806140000` 으로 **GENERATED ALWAYS 복원**(BY DEFAULT 는 upsert 용이었고 RPC 는 진짜 UPDATE — 왕복 사유는 마이그레이션 주석·schema.md). 로컬 테스트 `supabase/tests/wms_complete_pack_test.sql`(8케이스 — 이름 드리프트·전체 롤백·멱등·ready 비치명 포함). ⚠️ 배포 순서: SQL 먼저(함수 없이 프론트가 나가면 완료 전면 중단 PGRST202). ~~픽 완료·wave 는 다음 차례~~ → **✅ 같은 날 `wms_complete_pick` 으로 이식(아래 항목)**. ~~Hold·리시빙은 여전히 다음 차례~~ → **✅ Hold 는 2026-08-07 `wms_hold_pick`/`wms_hold_pack` 으로 이식(아래 Hold RPC 항목)** — 리시빙은 대상 아님(규칙 24/28: 소유자 없음). 남는 것은 규칙 28 한계 절.
- **픽 완료도 RPC — `wms_complete_pick` (2026-08-06 · ⚠️ 현장 미검증 · 팩 RPC 와 같은 골격 + wave)**: picker `finish` 의 쓰기 전부(라인 최종 저장 → `short_pick` 생성 → stock_short 갱신/stale delete → CAS 플립)가 `20260806160000_wms_complete_pick_rpc.sql` 한 트랜잭션. **단일/wave 한 함수** — 몸통이 동일해 나누면 복제·드리프트, `p_task_id`/`p_wave_id` 중 정확히 하나. 팩과 다른 점: ① **wave 모드 CAS = `wms_waves` 행**(소유권 단위 — 규칙 18/28)이 첫 쓰기 — 0행 무기록 반환이라 **재호출 멱등이 팩과 동일 강도로 성립**(이 함수가 만든 completed wave 는 멤버도 반드시 completed — 원자. "completed wave + 미완 멤버" 잔재는 과거 2단 쓰기에서만 가능 → 배포 전 감사 SQL 확인, 테스트 ⓚ 가 그 상태의 동작 문서화: `{completed:false}`·무변) ② **멤버 task 는 함수가 wave_id 로 서버 유도**(클라이언트 배열 아님) + 플립 행 수 ≠ 멤버 수면 예외 = 전체 롤백 — **종전 "멤버 먼저 → wave 나중" 순서 규칙은 원자성이 대체(규칙 28 의 wave 틈 소멸)** ③ ⚠️⚠️ **귀속 가드(이번 설계 최대 위험 — 사용자 조건)**: wave 는 discrepancy 의 `order_id`·`pick_task_id` 를 클라이언트가 라인별로 실어 보낸다(규칙 18 — 팩처럼 태스크에서 유도 불가). 잘못 실리면 부족이 엉뚱한 오더에 **조용히** 붙는다 → 세 배열(p_disc·p_short_refresh·p_short_delete) 전부 완료 범위의 order/task 검사, 벗어나면 예외 = 전체 롤백. `order_number` 는 아예 안 받고 서버 유도 ④ **reason 은 파라미터가 아니라 함수가 `'short_pick'` 고정**(responsible 미설정 — 규칙 41) · 선언 라인 제외 필터(`stockFlagged`)는 JS 잔류 ⑤ stale stock_short 는 현행대로 **delete**(⚠️ 팩은 resolve — 비대칭, 원장 원칙 1번과 상충 → 백로그 「원장 선행」). 공통 골격(auth 유도·이름 드리프트 `worker` 반환+전용 프리즈·INVOKER+revoke·라인 수 불일치 메시지·scanBusy)은 팩 항목 그대로. `Pick complete` 의 short 토스트 차단·마찰 모달은 쓰기 전 단계라 무변. 로컬 테스트 `supabase/tests/wms_complete_pick_test.sql`(12케이스 — wave 정상/멱등/멤버 어긋남·귀속 가드·잔재 상태 포함). ⚠️ 배포 순서 SQL 먼저.
- **Hold 도 RPC — `wms_hold_pick`(단일+wave 한 함수)·`wms_hold_pack` (2026-08-07 · ⚠️ 현장 미검증 · 완료 RPC 와 같은 골격, `20260807000000_wms_hold_rpc.sql`)**: picker/packer `holdBtn` 의 쓰기 전부(CAS 플립 in_progress→pending·assigned_to null·`held_by`=작업자 → 라인 최종 저장)가 한 트랜잭션. 완료와 다른 점: ① **discrepancy·stock_short 배열이 없다**(Hold 는 discrepancy 를 안 만든다 — 현행 확인) → wave 귀속 가드 불필요, 라인 UPDATE 의 `pick_task_id`/`pack_task_id` 스코프가 유일한 오염 방어 ② `started_at`·`work_started` 무접촉(진행 흔적 보존 — 현행 동일), 팩 `verified_at` 도 안 찍음(완료 전용) ③ ⚠️ **라인 수 불일치도 전체 롤백 확정(2026-08-07 사용자 결정)** — "스캔이 남아야 한다"는 요구는 **saveLine 증분 저장(스캔당 1행)이 이미 충족**하므로 Hold 시점 라인 저장은 최종 flush 일 뿐, 부분 저장이 나은 실패 모드가 없다(CAS 0행=스테일 쓰기 금지·라인 소멸=롤백된 태스크 오염·네트워크=재시도) ④ **재호출 멱등의 "내 Hold" 판정 = pending + assigned_to null + held_by=나**(`holdCasFailed` — claim 이 held_by 를 null 로 정리하므로 이 조합은 내 Hold 뿐. 완료의 completed_by 판정과 동형) — 이 분기는 반드시 **목록으로 복귀**시킨다(화면 복귀가 "Hold 됐다"는 신호) ⑤ ⚠️ **실패는 토스트가 아니라 `alert`** — Hold 는 눌러놓고 자리를 뜨는 동작이라 실패를 흘리면 배치가 in_progress 로 잠긴 채 방치되어 남이 못 잡는다. 문구는 "NOT held / still assigned to you / will NOT appear in the queue" 를 명시(단일 OK 버튼이라 SO-14129 류 오탭 위험 없음) ⑥ 플립이 assigned_to 를 null 로 놓아도 **행 잠금은 커밋까지 유지** — 남의 claim 이 블로킹되어 확인-쓰기 창 소멸은 완료와 동일. 공통 골격(auth 유도·이름 드리프트 worker 반환+전용 프리즈·INVOKER+revoke·scanBusy·ensureMine 은 값싼 선확인으로 유지)은 완료 항목 그대로. **packer Hold 의 플립 error 무확인(revert `ae1a623` 로 잔존)과 픽·팩 라인 루프 무확인 2곳이 이 이식으로 소멸** — 기준선 `docs/audits/2026-08-06-write-verification-baseline.md` 후속 ③. 로컬 테스트 `supabase/tests/wms_hold_pick_test.sql`(11케이스)·`wms_hold_pack_test.sql`(7케이스). ⚠️ 배포 순서 SQL 먼저(함수 없이 프론트가 나가면 Hold 전면 중단 PGRST202) — 창고 휴식 시간에.
- **리로드 복원 URL + 이미지 lazy + overscroll (2026-08-07 · ⚠️ 현장 미검증 — "스크롤 중 리프레시로 배치 이탈" 청취 대응)**: ① **URL 복원** — 배치 진입 수렴점(picker `enterPickView`/packer `enterPack`)에서 `history.replaceState` 로 `?batch=<pick_task_id>`(단일)·`?wave=<wave_id>`(wave — 소유권 단위가 wave 행이라 wave id, 멤버는 재로드)·`?pack=<pack_task_id>` 를 남기고, 목록 복귀 수렴점(`loadBatches`/`loadQueue`)에서 제거. 파라미터는 **스크립트 파싱 시점 1회 캡처**(`RESTORE` 상수)라 제거와 복원이 경합하지 않는다. 부트 시 파라미터가 있으면 서버 재조회 후 **`in_progress`+내 것일 때만** 재진입(wave 는 기존 `resumeWave` 재사용, packer 는 행을 `packLookup` 에 넣고 기존 `resumePack` 재사용) — ⚠️⚠️ **URL 은 소유권 증명이 아니다(규칙 28)**: 자동 클레임/이어받기 절대 금지, 그 외 상태는 사유 toast(남의 것/완료됨/롤백됨/대기 복귀) 후 목록. toast 의 담당자 이름은 **RLS 확인 완료** — 전 테이블 auth_all(규칙 8)이고 freezeScreen·이어받기 confirm 이 이미 같은 이름을 보여주므로 **기존 노출 범위 내**(신규 노출 아님). localStorage 불사용(규칙 5) · pushState 금지(뒤로가기 스택 무증가 — 규칙 16 경로와 안 꼬임). 기존 딥링크(`receiver.html?receipt=`·`?debug=perf`)와 파라미터 충돌 없음(실측). ② **이미지 lazy** — picker/packer 의 라인 이미지가 background-image(지연 로딩 불가, 60줄=60장 즉시 디코딩)에서 **고정 크기 컨테이너 안 `<img loading="lazy" decoding="async">`** 로(레이아웃 불변, object-fit contain/cover). ⚠️ **"렌더러 OOM → 자동 리로드 빈도 감소" 는 미검증 가설** — 배포 후 작업자 청취로만 확인 가능(검증 대기 항목). ③ **overscroll-behavior:none 을 html 에도**(picker/packer/receiver — 종전 body 만) + fulfillment 신설. ④ 원인 분류 정정은 규칙 16 항목 참조(탭 폐기·OOM 복구는 bfcache 가 아니다).
- **리스트뷰 정보 접근성 (2026-08-05 · ⚠️ 현장 미검증)**: packer 에 available 칩(picker 의 `wms_sku_bins` **일괄 1요청** 패턴 이식 — 진입 시 1회, ⚠️ 라인당 개별 조회 금지 = 직렬 60요청) · picker/packer **리스트 행 탭 → 그 SKU 임시 싱글뷰**(`viewOverride` 별도 변수 — 뷰 선호 `view` 는 세션 메모리 변수라 불변 유지, 배치 진입·세그 토글 시 해제) + **`← Back to list`**(탭 진입시만 표시, 탭한 행으로 scrollIntoView+하이라이트 — 상태는 메모리만, localStorage 금지) · 스크롤 직후 350ms 고스트 탭 무시(fulfillment `__justDragged` 패턴) · packer 행 탭 시 900ms auto-advance 억제 · 행 안 컨트롤(스테퍼·Clear over)은 탭 영역 제외. 상세는 `references/frontend.md` 「2026-08-05 — 리스트뷰」.

## 규칙 10 — GitHub Pages 배포

- **Source**: Deploy from a branch, `main`/`(root)`. 파일은 전부 repo **루트**(web/ 폴더 아님) → URL 짧게(`wms.asung.ca/picker.html`).
- **`.nojekyll` 루트에 필수** — `supabase/`(.ts)·`.vscode/` 때문에 Jekyll 빌드가 실패함. 없으면 3~4분 돌다 실패(빨간 X). 있으면 스킵하고 성공.
- **"Startup failure"(0초, Total duration `-`)는 우리 잘못 아님** = GitHub Actions 인프라 장애(githubstatus.com 확인). 파일 문제면 "빌드 후 실패"지 "시작 실패" 아님. → 복구 대기 후 Re-run/재커밋.
- **커스텀 도메인**: Settings→Pages Custom domain `wms.asung.ca`, DNS CNAME `wms`→`asungtrading.github.io`. Pages 열 때마다 "DNS Check in Progress"→"successful"은 정상(매번 실시간 재확인). Enforce HTTPS 체크.
- 순서: Pages Source 저장(배포 살리기) → 성공 확인(github.io 기본주소) → Custom domain 저장. **도메인보다 배포를 먼저.**

## 규칙 11 — UI 영어화 & 로고

- **모든 화면 UI는 영어**(픽커 중 한국어 못 읽는 사람 있음). 개발자 주석도 영어로 정리됨. 용어 통일: Picking/Packing/Fulfillment/Order Splitting/Staff Management/My In Progress/Waiting Batches/Hold/Complete as incomplete/Pack fill/Over-scan/discrepancy/Short/Over/Recovered/Needs review/Toronto/Edmonton/Sign out.
- **로고**: 런처=흰색(`asung-logo-white.png`, tools repo에서 가져옴), 6화면=어두운색(`asung-logo-dark.png`, 흰로고 alpha 유지+RGB를 #12161c로 recolor해 PIL로 생성). 헤더 `.logo{display:flex;align-items:center;gap:7px}` + `.logo .logo-img{height:15px}`, 런처 `.brand .logo-img{height:38px}`.
- 새 화면 만들 때 번역 방식: python 정규식으로 한국어 런 추출→긴 것부터 dict 치환→`re.findall(r'[가-힣]+')`로 0 확인→마지막 `<script>` `node -e`로 문법검사. `grep -o '[가-힣]'` 카운트는 로케일 오탐이니 Python으로 검증.

## 규칙 12 — 자동 폴링 & Cin7 병행운영 (⚠️ 2026-07-21)

- **자동 유입 = pg_cron + pg_net.** `wms_schedule_polling.sql`로 잡 `wms-poll-orders` 등록(`*/5 * * * *`, Edge Function `?commit=1` anon Bearer 호출). 확인: `select * from cron.job;`, 실행이력 `cron.job_run_details`, 응답 `net._http_response`.
- **⚠️ pg_net 응답이 null로 남을 수 있음** — 확대폴링이 상세조회 여럿 돌면 pg_net 기본 타임아웃(~5초) 초과. **응답 수신 실패 ≠ 저장 실패.** 진짜 확인은 **`wms_orders` 테이블의 `imported_at`** (진실). net._http_response는 참고용.
- **확대 폴링**: saleList AUTHORISED 페이지네이션(POLL_LIMIT 100 × POLL_MAX_PAGES 3=300스캔), SKIP_PICKED(CombinedPickingStatus='PICKED' 제외), **상세조회 전 dedup**(existingSaleIds), MAX_DETAIL 60캡(**최신 오더번호부터** — 아래 2026-08-04 ②). 진단필드(dry-run·commit 공통): `pages_scanned/candidates/after_skip_picked/already_exists/fresh_candidates/detail_fetched/detail_capped(+detail_capped_orders)/would_insert` + **2026-08-04 추가**: `list_total/list_fetched/truncated`(스캔 잘림)·`oldest_scanned/newest_scanned`(스캔 범위)·`rate_limited(+rate_limited_at_page)`(429 조기 종료). `skipped_detail` 은 `already_exists` 에 더해 **`skip_picked` 제외분도 포함**(오더번호+사유). ⚠️ 이 필드들이 응답에 **없으면 옛 버전** — 재배포 필요.
- **⚠️ Cin7 병행운영 3케이스**: (A) 유입 전 `2.Release to WMS`→`3.Finalized` 등으로 바뀌면 → 유입 안 됨(정상). (B) Cin7에서 픽됨(PICKED) → SKIP_PICKED로 제외(두 시스템 동시작업 방지, 의도됨 — "안 들어온다"의 최빈 원인. 2026-08-04 부터 `skipped_detail` 의 `skip_picked` 로 응답에서 바로 보임). (C) ~~**유입 후 Cin7에서 바뀜 → WMS는 모름**(dedup으로 재조회 안 함). 자동감지는 백로그.~~ → ✅ **2026-08-12 해소 — Updated 트리거 감지(규칙 43)**: 유입 오더의 `cin7_updated` 와 목록 Updated 를 비교해 바뀐 것만 상세 재조회 → `On Hold` 보류 / 예상 밖 값 admin 알림. ⚠️ 감지 범위는 **AdditionalAttribute1 변경**(보류 안전장치) — 종전 백로그 문구의 needs_review/voided 자동 전환까지는 아니다(needs_review 는 여전히 미구현 · **void 는 2026-08-14 별도 감지 루프로 해소** — 목록 부재 감지 + 2회차 완충, status 전환은 ⊘ Void 수동. 백로그 「신규 기능」 void 항목).
- **⚠️⚠️ 2026-08-04 실사고 — SO-14100·SO-14106 미유입 (원인 2개, 스캔 범위는 무죄)**:
  - ① **429 로 페이지 순회 중단** — 예전 saleList 루프는 `!ok` 즉시 throw 라 1페이지 성공 후 2·3페이지 429 면 회차 전체가 500 으로 죽었다(~~pg_cron 5분 + GAS 들이 같은 Cin7 계정 공유~~ → 08-10 부터 GAS 는 별도 키·한도는 **키 단위 60/60**(08-18 실측 — `cin7-api` 11번). 그래도 같은 WMS 키 안에서 폴링·Apply 가 겹쳐 429 는 일상 전제). → **공용 `_shared/cin7.ts`**(receiving 의 `cin7()` 를 추출 — 백오프 1.5s→3s 상한 2회, 소진 시 `err.status=429` throw)로 재시도하고, 소진되면 **throw 없이 회차 조기 종료** + `rate_limited`/`rate_limited_at_page` 노출(조용한 부분 스캔이 가장 위험). 429 외 4xx/5xx 는 기존대로 throw. ⚠️ **`_shared/cin7.ts` 를 바꾸면 hello·receiving 둘 다 재배포** — 각 함수는 배포 시점 번들을 쓰므로 한쪽만 배포하면 조용히 갈라진다. `supabase functions deploy` 가 `_shared` 상대 import 를 번들에 포함함은 실증됨(Supabase 공식 권장 패턴).
  - ② **MAX_DETAIL 캡 + 오름차순 = 최신 오더 영구 굶주림** — saleList 는 오더번호 **오름차순**이고, `2.Release to WMS` 가 아닌 오더는 상세조회만 하고 저장되지 않아 **다음 회차에도 fresh_candidates 에 계속 남는다** → 오래된 비대상 오더들이 매 회차 60건 예산을 선점, 뒤쪽(최신) 오더는 영구히 순번이 오지 않았다(SO-14106 이 캡에 잘리는 2건 중 하나였다). → **상세조회를 최신 오더번호부터(내림차순)** 하도록 수정. **규칙 20 purchaseList 오름차순 함정의 두 번째 사례.** 잘린 목록은 `detail_capped_orders` 로 노출(최신 우선이라 잘리는 건 가장 오래된 fresh) — **이 목록이 회차마다 계속 자라면** "확인했으나 비대상" 기억 테이블(재조회 스킵 + `Updated` 변경 시 재확인) 도입을 재검토. 지금은 fresh ≈ 62 vs 캡 60 이라 과설계로 판단해 안 만들었다.
  - ③ **스캔 범위는 문제가 아니었다** — 실측 `list_total` 140 / `truncated` false. `Limit` 상향·`UpdatedSince` 병용 **불필요**. 📌 AUTHORISED 총량이 300(POLL_LIMIT×POLL_MAX_PAGES)을 넘으면 재검토 — `truncated:true` 가 그 신호.
  - ④ **`Status=ORDERED` 여도 정상 유입된다** — EF 필터는 `OrderStatus=AUTHORISED`(saleList 파라미터)다. Simple/Advanced 모두 `Status` 는 ORDERED 로 남을 수 있다.
  - ⑤ **Advanced Sale 도 정상 처리된다** — SO-14023(Advanced Sale)의 WMS 라인 15개가 Cin7 과 일치 확인. **Type(Simple/Advanced) 필터는 코드에 없고, 없어도 된다** — "Simple 만 가져오게 설정했나?" 는 오해이니 반복하지 말 것.
- **"안 들어온다" 진단 순서 (2026-08-04 확립 — 위에서부터)**: ① dry-run 진단 필드 — `rate_limited`(429 조기 종료)·`truncated`(스캔 잘림)·`detail_capped`+`detail_capped_orders`(상세조회 캡 굶주림) ② `skipped_detail` 의 사유(`skip_picked`=병행운영 (B) / `already_exists`=dedup) ③ Cin7 쪽 필드 — `OrderStatus`(AUTHORISED 인가)·`AdditionalAttribute1`(`2.Release to WMS` 인가)·`CombinedPickingStatus`(PICKED 인가) ④ 스캔 범위(`list_total`·`oldest/newest_scanned` vs 문제 오더번호).

## 규칙 13 — Finalize 완료흐름 & 통계 (⚠️ 2026-07-21)

- **fulfillment "✓ Finalize order(s)" 버튼** — 팔렛/박스 유무 무관하게 완료 가능(픽업·즉시출고 대응). 판정: 그 오더 품목이 pallet_items에 하나라도 있으면 `packing_list`, 없으면 `direct`.
- **⚠️ 저장 status 값은 `closed` 그대로, 화면 표시만 "Finalized".** status가 enum일 수 있어 `finalized` 문자값을 직접 넣으면 제약위반 위험 → 표시만 바꿈(STATUS_LABEL.closed="Finalized"). loadOrders는 `closed` 제외.
- **통계 컬럼**(`wms_fulfillment_stats.sql`): `fulfillment_type`(packing_list/direct)·`finalized_by`·`finalized_at`. Finalize 시 기록(컬럼 없으면 status만 저장하는 폴백 포함).
- admin **Status 탭에 Finalized 섹션·카드**(closed 최근 40 — finalize 오더가 진행중 목록에서 빠져 안 보이던 문제 해결).

## 규칙 14 — 워커 리포트 & 롤백 (⚠️ 2026-07-21)

- **`wms_reports`**(별도 테이블, `wms_reports.sql`): 데이터품질 리포트 전용 — discrepancy(재고수량) 큐와 분리. kind=`wrong_location`(picker만)/`barcode_mismatch`(picker+packer+receiver)/**`image_mismatch`(picker+packer, 2026-07-30 / +receiver 2026-08-05)**/**`box_barcode`(receiver만, 2026-08-05)**. picker 싱글뷰 ⚑Wrong location/⚑Barcode changed/⚑Image differs, packer 싱글뷰 ⚑Barcode changed/⚑Image differs, **receiver recvView 싱글뷰 ⚑Barcode changed/⚑Box barcode/⚑Image differs(2026-08-05, ⚠️ 현장 미검증)**. admin **Reports 탭**에서 리뷰/resolve(kind 필터 + open 건수), 미해결 배지(kind 무관 전체 집계). ⚠️ **`⚠ Not enough stock`(2026-08-04, 규칙 41)은 같은 reportrow 에 있지만 wms_reports 가 아니라 `wms_discrepancies`(stock_short) 에 쓴다** — 재고 수량 문제라 discrepancy 큐 소관.
  - **리시빙 리포트 귀속(2026-08-05, `20260805200000_reports_receiving.sql`)**: receiver 는 오더가 없어 **`receipt_id`+`po_number` 신규 컬럼**으로 귀속(order_id=null — `wms_discrepancies` 리시빙 전례와 같은 구조), `source='receiver'`. admin Order 열은 `order_number||po_number`. **리포트는 매니저에게 알리기만 한다 — Cin7 쓰기·bcMap 수정 없음**(사용자 확정): `box_barcode` 는 작업자가 스캔한 **새 박스 바코드 값을 note 에 담고**(`New box barcode X · listed ×12 Y` — 스캔 값이 본체라 필수, 빈 값은 거부) 매니저가 Cin7 backend 에서 반영. barcode_mismatch 는 packer 와 같은 프롬프트(새 값 optional). 이미지 토글 키는 `receiptId|sku`. wrong_location 은 리시빙에 해당 개념이 없어 안 넣음(Last bin 은 풋어웨이 추천값일 뿐). factor(박스당 수량) 리포트는 범위에서 제외(사용자 결정 — 바코드만).
- **`image_mismatch` 는 토글**(2026-07-30): 상세 프롬프트 없이 체크만 — note 는 코드가 고정 문구(`Image does not match the physical product`)로 생성. 같은 **order_id+sku+kind 의 미해결(resolved_at is null) 행 1개**가 불변식이고, 다시 누르면 그 행을 **delete**(⚠️ `.is("resolved_at",null)` 조건 필수 — 해소된 감사기록은 지우지 않는다). 진입 시 `loadImageFlags()` 가 미해결 행을 읽어 눌린 상태를 복원한다(⚠️ 상태를 localStorage 에 두지 말 것 — 규칙 5, 태블릿 교체 시나리오). 쓰기 중 `imgBusy` 로 버튼 비활성 = 연타 중복 insert 방지.
  - ⚠️⚠️ **wave 모드의 귀속 — ~~기존 두 kind 는 버그다~~ → ✅ 2026-08-11 수정**: picker 의 `image_mismatch` 만 `wave? l._orderId : task.order_id` 로 **라인별 귀속**이라 옳고(finish() discrepancy 와 같은 규칙 — 규칙 18), 기존 `wrong_location`·`barcode_mismatch` 는 `task.order_id` 고정이라 wave 에서 엉뚱한 오더에 귀속됐다(2026-07-30 발견 → 백로그). **수정(2026-08-11)**: picker `reportIssue` 가 `lineOrder(l)` 로 `order_id`/`order_number` 를 **짝으로** 귀속 + `!o.id` 가드(toast 문구까지 image_mismatch 와 동일 — 같은 상황에 다른 메시지 금지). 비-wave 경로는 `lineOrder` 가 `task.order_id` 를 돌려줘 무변. ⚠️ **종전 백로그의 "범위: picker + packer(barcode_mismatch)" 는 과잉 표기였다 — packer 는 구조적으로 이 버그가 불가능하다**: pack task 는 **오더당 1개**라 packer 화면의 모든 라인이 `packTask.order_id` 한 오더 소속이고, packer 에는 `wave` 분기도 `l._orderId` 도 존재하지 않는다(2026-08-11 코드 대조 — packer 의 barcode_mismatch 는 이미 자기 파일의 image_mismatch 와 동일 형태). 방어적 변경도 안 했다(바꿀 실질이 없는데 손대면 "고쳤다"는 잘못된 기록만 남는다 — 사용자 결정). ⚠️ 수정 전에 쌓인 잘못된 행은 소급 정정 불가(어느 오더였는지 복원할 정보가 행에 없다) — 2026-08-11 이후 행부터 옳다.
  - ⚠️ **2026-08-06 정정 — `kind` 에 CHECK 가 생겼다.** 종전 기록("baseline 에서 CHECK 없는 `text` → 스키마 변경 불필요")은 그날까지만 사실이다. `20260806000000_receipts_uq_disc_reports_checks.sql` 이 4개 값(wrong_location·barcode_mismatch·image_mismatch·box_barcode) CHECK 를 건다 → **새 kind 추가는 이제 CHECK 를 바꾸는 마이그레이션이 코드보다 먼저**(규칙 41 의 reason 과 동일 절차). 실물 확인은 여전히 `pg_constraint` 조회(규칙 29 — 문서 말고 DB 를 믿는다).
- **롤백**(admin Rollback 탭, `wms_rollback_log.sql`): 매니저 전용, 한 단계씩 최심단계만(Undo Fulfillment→Undo Pack→Reset Pick→Undo Split), `wms_rollback_log`에 감사기록. closed 오더도 롤백 대상.
  - **✅ 2026-08-06 — delete → 아카이브 + discrepancy 무효화 (SO-14129 증거 소멸 후속 · ⚠️ 현장 미검증)**: ~~discrepancy는 자동삭제 안 함(방치)~~ → 아래로 대체. `20260806120000_rollback_archive_disc_void.sql`.
    - **아카이브**: 롤백/삭제(배치·오더 팩, split, void, unwave, fulfillment, admin 리시빙 receipt 삭제 — receipt 은 라인이 FK CASCADE 라 함께 보존)가 지우는 행을 **지우기 전에** `wms_rollback_archive`(범용 JSONB 1테이블)에 복사. Reset Pick 의 0 덮어쓰기도 덮기 전 스냅샷. ⚠️ **순서 불가침: insert 성공(행 수 일치) 확인 후에만 delete — 실패 시 롤백 전체 중단, 아무것도 안 지움.** ⚠️ 정직한 한계: **클라이언트가 직접 쓰는 사고 조사용 기록이지 보안 경계가 아니다**(EF 경유 전환 백로그). 권한은 authenticated 의 INSERT+SELECT 만(기본 default privileges 회수 — append-only). fulfillment 게이트(`wms_order_pack_progress`)는 물리 delete 유지라 무영향(뷰가 아카이브를 세지 않는다).
    - **무효화**(voided_at/by/reason — 삭제 금지): 화이트리스트 = 팩 롤백 `short_after_pack·over_pick·pack_scan_mistake` / 픽 롤백·split·unwave·void `short_pick`. **절대 자동 무효화 금지** = `stock_short`(선반 사실 — void 여도)·`recv_*`·`cin7_corrected=true`(→ 이력에 `⚠ batch rolled back — reverse adjustment?` 배지: 링크 태스크가 라이브에 없으면 계산 표시)·**링크 null 옛 행**(→ "N old rows — review manually" 알림만). 링크 컬럼으로만 잡고 order_id 로 긁지 않는다. 큐·배지·Stats(mistake tally 포함)는 voided 제외, 해소 이력에 `Voided (rollback)` 태그로 남는다.
    - **양방향**: 오더 단위 팩 롤백·Void 는 `resolved_pack_recovery` 를 `short_pick` 으로 **자동 재개**(안 하면 실재하는 부족이 조용히 해소된 채 남는다). ⚠️ **배치 단위는 표시만**("이 배치가 해소한 픽 부족이 있을 수 있음 — 확인 필요") — recovery 행에 pack_task_id 가 없어 귀속 불가, 근사 매칭은 없는 문제를 조사하게 만든다(사용자 결정). packer 가 recovery 에 pack_task_id 를 남기는 것은 백로그. packer recovery UPDATE 에 `.is("voided_at",null)` 1줄 추가(무효화 행 부활 방지 — 승인된 최소 접촉).

## 규칙 15 — 프린트/다운로드 (⚠️ 2026-07-21)

- **배치별 픽리스트**(manager Create batches 시 자동): **배치 1개 = 1페이지**(page-break), 각 페이지 = 로고 + **배치라벨 CODE128 바코드** + 오더/창고/고객/총라인·총유닛/Picked By + **Zones 요약**(품목표는 뺌). 바코드=배치라벨(SO-X-N) → 픽커 스캔진입과 정확일치.
- **팩킹리스트**(fulfillment 유닛/스토어별, admin Finalized 탭 재출력): 컬럼 **SKU·Barcode·Product·Qty**(바코드=스냅샷 sku별 대표바코드). admin에서 **🖨 Print · ⬇ PDF · ⬇ CSV**. direct 오더는 "Direct pack" 태그(팩킹리스트 없음).
- **⚠️ 로고 in 프린트창**: `window.open` 새 문서라 상대경로 안 됨 → `location.origin+"/asung-logo-dark.png"` 절대URL. fulfillment은 같은문서 #printArea라 상관없지만 통일. PDF=jsPDF+autotable(CDN, 첫클릭시 lazy-load), CSV=BOM+CRLF.
- 바코드 라이브러리: JsBarcode `cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js`.
- ⚠️ **픽리스트 인쇄는 `wms-picklist.js` 한 곳에서만** (2026-08-02, manager/picker/packer 공용 · picker·packer 재인쇄 🖨 Print · 픽리스트 Order Date · fulfillment/admin 팩킹리스트 혼합 팔렛 표기) → `references/frontend.md` 「2026-08-02」 절.

## 규칙 16 — 매니저 세부권한 & 공용 내비 (⚠️ 2026-07-21)

- **`wms_staff.perms`**(jsonb, `wms_staff_perms.sql`, 기본 `["split","admin","staff"]`): 매니저별 화면권한. admin 역할=항상 전부, worker=해당없음. staff-admin에 Access 체크박스 3개.
- **wms-auth `requirePerm`**: manager.html=`split`·admin.html=`admin`·staff-admin.html=`staff`. 권한 없는 매니저는 URL 직접접근도 차단. index 런처는 perms별 카드 표시.
- **공용 ☰ Menu 드롭다운**(wms-auth `setupNavMenu`): 모든 화면 공통, 권한반영 목록(순서: Admin→Order Splitting→Picking→Packing→Fulfillment→Staff→Home). onReady에서 자동설치.
- **⚠️ bfcache 수정**: wms-auth에 `pageshow`(persisted) → `location.reload()`. 뒤로가기 복원 시 죽은 요청으로 스피너 무한대던 문제 근본해결(전 화면). **2026-08-07 재검토 — 유지 결정**: "스크롤 중 리프레시로 배치 이탈" 조사에서 이 핸들러가 의심됐으나, **탭 폐기(discard)·렌더러 OOM 크래시 복구는 bfcache 복원이 아니라 신규 로드**(`persisted=false`)라 이 핸들러와 무관 — 목적(죽은 in-flight 요청)은 여전히 유효하고, `location.reload()` 는 쿼리스트링을 보존하므로 규칙 9 의 리로드 복원 URL 이 어느 경로의 리로드든 배치로 되돌린다. **핸들러를 없애지 말 것.**
- **모바일**: 각 화면 `@media` 추가(헤더 줄바꿈·버튼축소, admin 테이블 가로스크롤·탭 스와이프, manager 컨트롤 줄바꿈+선택시 작업영역 자동스크롤+"✓ selected"). 데스크톱 우선이나 폰서 안 깨지게.
- **⚠️ 스캔 오류음**: 저음 180Hz→**2400/1600Hz 교차 사이렌, 볼륨 1.0, 0.72초**(작은 스피커 대응). picker/packer `beep("bad")`. 성공음은 유지(구분).

## 규칙 17 — 렌더/스캔 함정 (⚠️ 2026-07-21 디버깅 교훈)

- **진입 즉시 렌더 후 enrich**: picker loadLines·packer enterPack은 라인 로드 후 **즉시 화면전환+렌더**, 재고/바코드는 뒤이어 독립 try로 채우고 재렌더. 세 조회를 순차 await 후 렌더하면 지연·한 조회 실패가 전체 렌더를 막음.
- **⚠️ 존재하지 않는 DOM id 참조 금지**: 옛 UI 제거 후 남은 `getElementById("drop")` 한 줄이 렌더 도중 TypeError→리스트 공백+enrich 중단. 배포 전 **누락 id 전수검사**(`getElementById` vs `id=` 차집합) 습관.
- **-12 박스 바코드 스캔**: 오더가 base SKU로 들어오면 scannable_barcodes에 변형(-12) 바코드가 없음(백엔드 조립규칙 방향성 공백) → 픽커가 박스 스캔 시 거부됨. **프론트에서 형제 스냅샷 바코드를 bcMap에 병합**해 해결(picker/packer). 근본수정은 GAS scannable_barcodes 조립에 형제변형 추가(백로그).
- **ALT-UPC 표시**: 싱글뷰 barcodeBlock이 base+변형(factor>1)에 더해 `l.barcodes` 중 type='alt'를 "ALT-UPC"로 표시.
- **자동이동**: 스캔뿐 아니라 **수동 +/−·수량입력으로 목표 도달 시에도 autoAdvance**(picker). packer는 목표 초과 시 confirmFillIfNeeded(소리+플래시+확인).
- **⚠️ periodBar custom 인자는 객체**(`{from,to}`) — null 넣으면 `custom.from` 접근에서 TypeError로 boot 중단(admin 초기 로딩 공백 원인이었음). periodBar 내부 null 방어 추가됨.
- ⚠️ **입력·포커스·터치 동작은 코드 읽기로 결론내지 말 것 (2026-08-05 SO-14129)** — 같은 계열의 일반 원칙은 「기록 규칙」의 "UI·입력 동작은 코드 읽기로 결론내지 않는다" 항목.

## 규칙 18 — Wave: 소량 오더 그룹 픽킹 (⚠️ 2026-07-22)

**핵심 원칙: wave는 pick 배치를 "만드는" 게 아니라 이미 만들어진 pick 배치들을 "묶기만" 한다.** split과 wave는 사실 같은 일(오더 라인을 pick 배치로 나눠 담기)을 방향만 반대로 하는 것 — split은 오더 1개→배치 N개, wave는 오더 N개→각자 배치 1개를 한 묶음으로. **픽킹 출구는 여전히 하나(pick 배치 생성)라 하류(packer·fulfillment·rollback·Health)에 구멍이 안 생김.** 만약 wave를 "새 종류의 배치를 만드는" 것으로 설계하면 "픽 준비됐다=pick 배치가 있다"는 불변식이 깨지고 하류가 조용히 흔들림 → 반드시 그룹핑 레이어로만.

- **`wms_waves` 테이블**(B 최소형, `wms_waves.sql`) + `wms_pick_tasks`에 `wave_id`(FK, NULL=평범한 split 배치)·`tote_no`(1..10 물리 토트 슬롯) 컬럼. 별도 테이블인 이유: wave 단위 claim/상태/heartbeat/목록이 필요(A안=컬럼만 추가로는 부족). ⚠️ **`wms_waves.sql`을 `wms_healthcheck.sql`보다 먼저 실행**(health 함수가 wms_waves 참조).
- **각 소량 오더 = 자기 pick 배치 `{order_number}-1`**(split의 "1라인=1배치 최소보장"이 여기서도 그대로) + `wave_id`·`tote_no` 꼬리표. **토트 = 그 오더의 pick 배치**, 토트 번호 = 물리 카트 칸 번호. **선택 순서 = 토트 번호**.
- **분류(sort)는 픽커 스캔 시점에**(sort-to-tote) — 스캔이 order_line에 귀속되므로 그 순간 화면이 "→ TOTE 2 (고객명)"으로 안내, 픽커는 그 칸에 넣음. **분류를 팩커로 미루면 안 됨**(팩커가 "이 SKU가 어느 오더 것?"을 다시 풀어야 하고, 섞인 더미는 실수 유발). 팩커는 토트 하나=오더 하나로 기존 그대로 전량 재스캔 검수.
- **매니저 수동 선택만**(자동 추천 없음). manager.html **Split | Group 토글**. Group 모드에서 필터(기본 라인≤5·낱개≤100, 조정 가능) 통과한 소량 오더만 표시, 탭으로 담음. **같은 창고만**(toronto/edmonton 혼합 금지), **최소 2오더**, **카트 토트 최대 `WAVE_MAX=10`**.
- **wave 라벨 `W-MMDD-n`**(당일 생성 수+1). 프린트물 = wave 바코드 1개 + 토트 배정표(한 장). 픽커가 이 바코드 스캔 시 wave 로드.
- **픽커 wave 모드**: "Waiting Waves" 섹션 별도(⚠️ **wave 멤버 배치는 개별 배치 목록에서 숨김** — `loadBatches` 3쿼리에 `.is("wave_id",null)`, 누가 한 오더만 빼가는 것 방지). start/resume/takeover/hold/finish/back 전부 wave 단위로 동작(멤버 태스크 일괄 + wave 행 동시). heartbeat = wave 행 + 멤버 태스크 동시. 라인은 wave 전체를 zone 순 병합(tote는 타이브레이커라 동선 유지). `loadLines`·`loadWaveLines` 꼬리를 **`enterPickView` 공유 함수**로 추출(정렬+bcMap+렌더+enrich 공유).
- **⚠️ discrepancy 오더별 귀속**: wave에서 short 나면 그 라인의 `_orderId`/`_orderNumber`(loadWaveLines가 태스크→오더 매핑으로 채움)로 discrepancy insert. task.order_id 쓰면 안 됨(전부 한 오더로 잘못 귀속). **2026-08-06 부터 서버 귀속 가드가 이중 방어** — `wms_complete_pick` 이 완료 범위 밖 order/task 가 실려 오면 예외로 전체 롤백(규칙 9 픽 RPC 항목 ③).
- **wave 완료는 2026-08-06 부터 RPC 한 트랜잭션 (⚠️ 현장 미검증)**: 종전 "멤버 task 들 UPDATE → wave 행 UPDATE" 2단 쓰기(그 사이 틈이 규칙 28 한계였다)가 `wms_complete_pick` 안에서 원자화 — **CAS 는 wave 행(소유권 단위)이 첫 쓰기, 멤버는 함수가 wave_id 로 유도해 일괄 플립**(행 수 ≠ 멤버 수면 전체 롤백). "멤버 먼저" 순서 규칙은 폐기(원자성이 대체). 상세는 규칙 9 픽 RPC 항목. **wave Hold 도 2026-08-07 부터 같은 골격의 `wms_hold_pick`(⚠️ 현장 미검증)** — CAS 는 wave 행, 멤버 서버 유도, held_by 는 wave 행·멤버 모두에 기록. 상세는 규칙 9 Hold RPC 항목. ⚠️ 부수 관찰(백로그): `startWave` 는 멤버 held_by 만 정리하고 **wave 행 held_by 는 정리하지 않는다** — "남이 claim 후 무작업 Back" 뒤 held_by 가 스테일로 남는 표시성 엣지(실해 없음 — holdCasFailed 의 "내 Hold" 오판 케이스도 실상과 결과가 같다).
- **⚠️ v1 한계**: admin Batch activity에서 wave 멤버 배치를 **개별** Release하면 wave 행은 남는 엣지(픽커엔 안 뜨니 실해 없음, wave 해제 필요 시 멤버 전부 Release). wave 카드 라인수는 3단 중첩 쿼리(wms_waves→pick_tasks→task_lines count)라 0으로 뜨면 표시만의 문제(픽킹 무관).

## 규칙 19 — 불변식 자동검증: `wms_health_check()` & admin Health 탭 (⚠️ 2026-07-22)

**규칙 3의 불변식(factor·required_base·분할 합계 등)을 사람이 눈으로 지키는 대신 DB 함수가 상시 검증한다.** 병행 운영·wave·리시빙처럼 경로가 늘어날 때 조용히 새는 것을 잡는 안전망.

- **`wms_health_check()` DB 함수**(`wms_healthcheck.sql`, `security definer`+authenticated grant, 읽기 전용, `create or replace`라 재실행 안전). admin.html **Health 탭**이 `sb.rpc("wms_health_check")`로 호출, 검사당 카드 하나. **0행=건강**(fail_count>0이면 깨진 것, sample은 위반 최대 8행 jsonb). ~~⚠️ 자동 실행은 없다 — 사람이 탭을 눌러야 돈다~~ → ✅ **2026-08-14 자동 실행**: pg_cron 1시간 주기(사용자 결정)로 `wms_health_snapshot()` 이 `wms_health_runs` 에 1행 append(90일 보존 정리는 함수 안 — reap 패턴 · `20260814000000_health_snapshot.sql` · cron.sql 잡 3). admin 배지는 최신 1행만 읽는다(종전엔 부팅마다 12검사 전체 — [실측 2026-08-14] 1,271ms·shared hit 70,550). Health 탭은 라이브 RPC 유지. 스냅샷 없음·3시간+ stale·조회 실패 = 회색 "?" 배지("이상 없음"과 구분 — 백로그 「신규 기능」 완료 항목 참조).
- **검사 항목**(sort 순): factor_math(critical, required_base=qty×factor)·factor_drift(warn, 라인 factor vs 스냅샷)·split_sum(critical, 분할 배치 assigned 합=required_base)·short_no_disc(critical, short인데 discrepancy 없음)·pick_over(warn)·progress_leak(warn, order_progress≠`2.Release to WMS`)·dup_sale(critical, cin7_sale_id 중복)·finalize_recon(critical, clean-closed인데 picked≠required)·orphan_pick(warn)·orphan_pack(warn)·**wave_state(warn, 규칙 18)**·**image_sync_stale(warn, 2026-08-14 신설 — 이미지 EF 마지막 성공 48h 초과/전무, 「상품 이미지 파이프라인」 절)**·last_import(info). **critical 하나라도 깨지면 탭에 빨강 배지**(discBadge와 동일 패턴).
- **⚠️ orphan_pack은 반드시 배치 기준**: "오더가 picking인데 pack task 있음"으로 짜면 **오탐**(분할 오더는 일부 배치가 이미 팩 단계인 게 정상 — 이 WMS의 존재 이유). 올바른 조건 = **pack 배치의 짝 pick 배치(`pick_task_id`)가 completed 아닐 때만** 플래그. SO-13443(8배치 중 -1~-4 Packed·-5~-8 Waiting) 같은 정상 병렬을 안 걸러야 함. (2026-07-22 실데이터로 오탐 확인 후 수정한 교훈.)
- **⚠️ short_no_disc 매칭 키 = `order_id + order_sku`**: 실제 `wms_discrepancies.sku`에 order_sku가 아닌 base_sku가 저장되고 있으면 이 검사가 전건 오탐. 처음 돌렸을 때 잔뜩 뜨면 매칭 키 문제이니 SQL 한 줄 수정.
- **Health가 wave의 안전망**: wave 추가로 "픽 준비됐다"의 정의가 넓어져도, split_sum·orphan_pack·wave_state가 데이터 구조 정합성을 상시 검증 → 병행 운영 중 조용히 새는 걸 잡음.
- ⚠️ **리시빙 검사는 아직 없다**(`wms_receipts`·`wms_receipt_lines` 무검증). 규칙 27 의 R3(중복 receipt)·R4(이중 Apply)는 지금은 Health 로 안 잡힌다 — 검사 추가는 백로그.
- ⚠️ **`short_no_disc` 는 픽킹 전용이다** — `wms_pick_task_lines` 기준이라 **리시빙 discrepancy 가 한 건도 안 들어가고 있던 것을 못 잡았다**(규칙 29). 추가할 검사 2개: ①리시빙용 short/over ↔ `wms_discrepancies(source='receiving')` 대조 ②`wms_receipt_lines.putaway_bin` ↔ `asung_bin_stock` 대조(규칙 32) — 둘 다 백로그.

## 규칙 20 — 리시빙 모듈: PO/트랜스퍼 입고 + 라스트 로케이션 풋어웨이 (⚠️ 2026-07-23)

**핵심 목적: Cin7 다이나믹 로케이션의 두 빈틈 — (1)sold-out 시 라스트 로케이션 망각 (2)매번 수동 풋어웨이 강제 — 를 메운다.** 우리 sticky bin 데이터(`asung_bin_stock` → `wms_sku_bins`)가 라스트 로케이션을 이미 보존하므로, 리시빙 시 자동으로 그 자리로 풋어웨이한다.

- **화면 = `receiver.html`** (requireManager:false, 픽커 톤·bcMap·factor·사운드 재사용, Single|List 뷰 + Last bin 칩). **Edge Function = `receiving`** (hello 와 별개 함수). **데이터품질 리포트 ⚑ 3종(barcode_mismatch/box_barcode/image_mismatch, 2026-08-05 ⚠️ 현장 미검증)은 규칙 14 「리시빙 리포트 귀속」** — receipt_id+po_number 귀속, Cin7 쓰기 없음.
- **유입은 온디맨드** (버튼/PO 바코드 스캔, 폴링 없음). ⚠️⚠️ **PO 는 `Status=INVOICED` + `Status=RECEIVING` 을 각각 조회해 ID 기준 dedup 병합 (2026-08-04 전환 — 종전 `InvoiceStatus` AUTHORISED+PAID 서버 필터 방식 폐기)**. 전환 이유: PAID 는 창업 이후 지불을 마친 **모든** PO(실측 877건)라 리시빙 대상 0건을 위해 전량을 긁어 클라이언트 필터로 버리고 있었다 — PO 는 계속 쌓이므로 언젠가 페이지 상한(1000×3)에 닿고, **정렬이 오름차순이라 잘리는 쪽은 항상 최신 PO** 다(PO-01081 형 조용한 누락의 재발 경로 — 상한 증설은 시간 벌기일 뿐이라 유입 자체를 좁혔다). **Invoice First 검사(InvoiceStatus=AUTHORISED 또는 PAID 만 통과)는 클라이언트 코드로 이동** — 좁히는 필터라 서버에서 빼도 안전. ⚠️ 이 검사만 **정확 값 비교**(예상 밖 값은 제외 + 값별 카운트를 console.warn 로그), 아래 제외 4종은 복합 상태(`RECEIVED / CREDITED` 실재) 때문에 **includes 유지**. 실측 2026-08-04 (purchaseList, 전체 PO 1,129건 — Status 분포: COMPLETED 768 · RECEIVED 95 · VOIDED 89 · INVOICED 24 · ORDERING 8 · RECEIVED/CREDITED 6 · CREDITED 4 · ORDERED 3 · RECEIVING 2 · COMPLETED/CREDIT NOTE CLOSED 1):

  | 서버 파라미터 | 결과 |
  |---|---|
  | `Status=INVOICED` | **Total 73 — 동작** |
  | `Status=RECEIVING` | **Total 5 — 동작** |
  | `Status=INVOICED,RECEIVING` / `INVOICED\|RECEIVING` | Total 0 — **여러 값 동시 요청 불가** → 상태별 개별 조회 + dedup |
  | `StockReceivedStatus=NOT AVAILABLE` | Total 585 — **동작**. ⚠️ 7/28 의 "무시된다"는 `RestockReceivedStatus` 로 **파라미터 이름을 잘못 쓴 것**이었다(정답은 `StockReceivedStatus`) |
  | `Type=Simple/Advanced/Service Purchase` | 585 그대로 — **무시됨** → Service 제외는 클라이언트 유지 |
  | `InvoiceStatus=PAID` | 877 (그중 `Status=INVOICED` 교집합은 **1건**) |

  ⚠️⚠️ **2026-08-04 정정 — 7/28 기록이 틀렸다.** 스킬에 *"Cin7 이 `StockReceivedStatus` 서버 필터를 무시한다(NOT AVAILABLE·DRAFT 모두 Total 825)"* 로 적혀 있었는데, 실제로 보낸 파라미터 이름은 **존재하지 않는 `RestockReceivedStatus`** 였고 Cin7 이 그것을 무시한 것이다. 올바른 이름(`StockReceivedStatus=NOT AVAILABLE`)은 **동작한다**(Total 585 vs 오타 877). 이 오기록 때문에 **"서버 필터는 불가능하다" 는 잘못된 결론이 일주일간 유지**됐고 클라이언트 전량 필터를 계속 짊어졌다.
  - 📌 **교훈(다른 API 에도 적용)**: **파라미터가 무시되는 것처럼 보이면 이름 오타를 먼저 의심하라.** Cin7 은 모르는 파라미터를 **조용히 무시**하므로 "오타" 와 "미지원" 이 응답에서 **구별되지 않는다** — 둘 다 "무필터와 같은 Total". 검증 절차: ① 문서·`references/` 의 정확한 스펠링과 대조 ② **동작을 아는 파라미터**(`Status=INVOICED` 등)를 같은 방식으로 같이 보내 배선이 살아 있음을 확인 ③ 그래도 Total 이 안 변하면 그때 "미지원" 으로 기록. **응답이 200 이라는 것은 파라미터를 받아들였다는 뜻이 아니다**(규칙 21 의 "쓰기 검증은 되읽기로" 와 같은 계열).

  현재 리시빙 대상 8건은 전부 `Status=INVOICED` / Simple Purchase / StockReceivedStatus=NOT AVAILABLE. `Status=RECEIVING` 5건은 전부 StockReceivedStatus=AUTHORISED 라 지금은 클라이언트 필터에서 걸러지지만 "부분입고 진행중은 유지" 의도로 조회는 유지한다 — 같은 이유로 `StockReceivedStatus` 서버 필터도 안 건다(동작하지만 RECEIVING 유지 의도와 충돌). ⚠️ `Limit=1000`(`PO_PAGE_LIMIT`)·페이지 상한 3(`PO_MAX_PAGES`)·조회 사이 sleep 유지 — 조기 종료 조건도 **같은 상수**(`items.length < PO_PAGE_LIMIT`), 어긋나면 첫 페이지에서 루프가 끊긴다. 📌 **오름차순 함정(잘리면 최신부터 누락 — 규칙 12 상세조회 굶주림과 동일 계열)은 Status 전환 후에도 전제** — ⚠️⚠️ **세 번째 실사고 (2026-08-12 SO-14532, packer)**: packer 대기열의 donePick 쿼리(`wms_pick_tasks` status=completed)가 **무LIMIT·completed_at 오름차순**이라 완료 픽 누적이 PostgREST 기본 캡 1000 을 돌파하는 순간 **새 완료 픽이 응답 밖으로 밀려** 팩 대기열·스캔 진입이 전 계정에서 죽었다(탄생 시점부터 있던 폭탄 — 데이터 누적이 뇌관). allPack(`wms_pack_tasks` 전체)도 같은 폭탄이었고 실측 997건(3건 전)에 함께 수정. 처방 = **내림차순 + 명시 LIMIT**(표시 FIFO 는 클라이언트 재정렬로 보존) → ✅ **2026-08-14 `!inner` 근본 수정 완료**(캡 표 각주 참조 — [실측] 완료 픽 1,140행으로 **이미 캡 초과 상태**였다. 안 닫힌 오더 소속 13행만 남아 캡 구조적 무관·desc+LIMIT 은 이중 안전 유지). **목록 쿼리를 쓸 때마다 "누적되는 테이블인가 · 잘리면 어느 쪽이 사라지는가"를 물어라.** 같은 날 전수 조사(2026-08-12)로 **4호**(fulfillment 보드 완료 팩 — 998/1000 에서 2건 전 응급, 내림차순+LIMIT)와 **5호**(admin Finalized 팔렛 배지 pallet_items 전량 — **이미 2517/1000 초과 상태로 발견, 언제부터 틀렸는지 불명**. LIMIT 으론 부족해 화면 300개 오더 `.in` 축소 + range 페이지네이션으로 캡 무관화)를 함께 처방 — 잔여 위험 목록은 백로그 「캡 위험 전수조사」 표(#1~#11)가 정본. 📌 **"뷰로 하면 되지 않나" — 안 된다 (2026-08-12 #11 에서 확정한 원리)**: 캡은 **행을 반환하는 모든 것**에 걸린다 — 테이블 직조회든 distinct 뷰든 setof RPC 든, 결과가 1000행이면 똑같이 잘린다(#11 실측: distinct bin 이 toronto 1481 > 1000 — 뷰를 만들어도 여전히 잘린다). 캡을 **구조적으로** 무관화하는 형태는 둘뿐 = ①**단일 값 반환**(`jsonb_agg` RPC — 행 1개에 전부, 첫 적용 `wms_warehouse_bins`) ②**count-head**(`{count:"exact",head:true}` — 행 0개, 개수만 필요할 때). 전량 행이 정말 필요하면 range 페이지네이션(캡 무관이지만 왕복 = 행수/1000 — #11 은 9왕복이라 기각). 📌 **PostgREST 문법 4종 실측 통과 (2026-08-13~14 — 다음에 다시 의심하지 말 것)**: ① `or()` 안의 **중첩 `and()` + ISO 타임스탬프**(콜론·마침표 포함 그대로) → 정상(브라우저 콘솔 count=376 · error null — Finalized 카드의 coalesce 기간 표현이 이걸로 산다) ② **3단 임베드** `wms_pick_tasks→wms_pack_tasks→wms_pack_task_lines` → 정상(n=2 — Finalized 배치 펼침의 lazy 1왕복이 이걸로 산다) ③ **`!inner` + dotted 임베드 필터**(`.not("wms_orders.status","in","(closed,voided)")` — 2026-08-14 레포 첫 실사용 · error null · to-one 임베드는 여전히 객체. ⚠️ 임베드를 select 에서 빼면 400 으로 거부 — 시끄러움 / **임베드는 있는데 !inner 만 빠지면 부모 행 잔존 + 임베드 null — 조용히 틀림**) ④ **`not.is.true`**(boolean 의 false·null 둘 다 — 2026-08-14 count 30 · error null. `or(is.null,eq.false)` 를 한 필터로). 📌 **버튼 괄호 숫자 = 표시 건수, 총수는 캡션 (2026-08-13 사용자 결정 — Rollback finalize 토글에서 확립한 표시 관례)**: 캡션("Latest N of M listed")이 이미 총수를 들고 있으면 버튼 숫자를 표시 건수로 바꿔도 정보 손실이 없다 — 두 숫자가 나란히 다른 것을 가리키면 헷갈리므로 역할을 나눈다(manager ⊘ 버튼처럼 캡션이 없는 곳은 버튼이 총수 + "latest N shown" 병기). ⚠️⚠️ **재발 방지 훅 도입(2026-08-12, 같은 함정 5번째 만에)** — `scripts/check-caps.sh`(pre-commit): 무제한 조회는 커밋 거부, 통과 = `.limit`/`.range`/`count:`/single/**식별자 컬럼**(`…id`/`sku`/`barcode`/`email`)의 `.eq·.in`/`// caps-ok: <사유>`(사유 필수). 📌 **규칙 채택의 검증 방법 자체를 남긴다**: "**이 훅이 있었으면 그 사고를 막았는가**"로 소급 검증했다 — 원안(.eq/.in **아무 컬럼** 통과)은 5건 중 **4건(3·4호·manager voided·admin closed)을 통과**시켰다(`.eq("status")` 는 행 수를 한정하지 않는다). 그래서 식별자 컬럼만 통과로 좁혔고, **소급 5건이 전부 거부되는 것을 `scripts/test-caps-hook.sh` 가 테스트로 고정**한다(Promise.all 형제 쿼리의 .limit 이 옆 쿼리를 통과시키는 시제품 오판정도 세그먼트 분리로 잡고 테스트에 포함). 미수정 위험은 `// caps-ok: TODO(캡 위험 #n — 미수정, …)` 로 통과시키되 **"미수정" 명문**(caps-ok 를 "검토 끝"으로 오독 방지) — 추적: `grep -rn "caps-ok: TODO" *.html supabase/functions | wc -l` (줄어야 정상). → 진단 강화: 응답에 **`scanned`**(상태별 필터 전 행수, 예 `{INVOICED:73, RECEIVING:5}`) + **`totals`**(상태별 서버 보고 Total) + **`truncated`**(**Total 대비 덜 받으면 true** — 페이지 상한이든 응답 잘림이든). `pos` 배열 구조·필드명은 불변(receiver.html 이 소비, 진단 필드는 추가만). 클라이언트 제외 4종(모두 includes): Status 에 VOID/COMPLETED/CREDITED 포함 · RECEIVED 포함(단 RECEIVING=부분입고 진행중은 유지) · Type 에 Service 포함(운송·관세 — 물건 없음) · StockReceivedStatus=AUTHORISED. **트랜스퍼는 Status='IN TRANSIT'**, 창고는 ToLocation 정규화 — 리시버 warehouse_access 필터.
  - ⚠️ **검증 범위 (2026-08-04)**: 확인된 것은 **EF 응답 수준까지**다(위 실측 표 + 973행→78행 · 대상 8건 동일, 배포 전후 diff). **receiver.html 로 실제 PO 를 받아 완료까지 가는 흐름은 미검증** — 백로그 「검증 대기」.
- **추천 빈 규칙** (base_sku × warehouse): ①`is_current=TRUE` 우선 ②없으면 `last_seen` 최신(=sold-out 자리 중 마지막) ③available 많은 곳. ⚠️ `wms_sku_bins.last_seen` 은 2026-07-23 추가(ALTER + `wms_buildBins_` SELECT/map 각 1줄) — sticky MERGE 가 last_seen 을 갱신 안 하고 얼려두므로 "마지막 재고 있던 날"이 됨. 초기엔 전부 같은 날짜(소급 불가)라 시간이 지나야 갈림.
- ⚠️ **라스트빈 "no last bin" 근본 한계 (2026-07-24 규명)**: sticky 이력이 **2026-07-06 first_seen 부터** 시작(BQ `min(first_seen)`). 그 전에 이미 0 이 된 과거 bin 은 Cin7 productavailability 가 0-재고 bin 을 아예 안 줘서 sticky 가 **본 적이 없음 → 보존 불가**. 예: CAN01545 는 2/19 트랜스퍼로 에드먼튼 EC010303 에 있었다가 팔려 0 → 7/6 시작 땐 이미 0 → no last bin. **버그 아님, 데이터 시작점 한계.** 복구책: (가)Cin7 movements API 백필 or (나)지금부터 축적+수동지정(권장, 한 번 지정하면 재고 앉을 때 sticky 가 기억). bin 단위 과거이력은 movements 에만 있음(BQ asung_stock_daily 는 warehouse 레벨).
- **빈 지정 UI (2026-07-24)**: 라스트빈 없거나 바꿀 때 — **스캔(1순위)+드롭다운 검색(폴백) 모달**. 드롭다운 소스 = EF `action=bins&warehouse=`(Cin7 `/ref/location` 전체 bin, **빈 자리 포함** — 신제품 새 자리 지정 가능), 실패 시 wms_sku_bins 폴백. 알려진 bin 아니면 confirm(신규 bin 허용). bin 있는 라인엔 **"Change" 버튼**(다른 자리로 바꾸면 putaway_done 자동 해제).
- **검수 정렬 4종 (2026-07-24)**: Sort 드롭다운 = PO순 / Zone·Last bin순 / Product(A-Z, 브랜드가 앞이라 자연 브랜드정렬) / SKU순. ⚠️ **`lines` 배열은 안 건드리고 표시 인덱스만 정렬**(bcMap·스캔 무결성 보존). 싱글뷰 Prev/Next 는 표시 순서를 따름. ⚠️ **2026-07-27 갱신 — 여기에 "채운 라인 아래로" 1차 키가 추가되고 `autoAdvance` 는 표시 순서를 쓰지 않게 바뀜: 규칙 26 참조.**
- **Zone→Bay 점프 (2026-07-24)**: 검수(Zone정렬시)·풋어웨이에 **sticky 칩 바**(스캔+정렬+칩 한 묶음 sticky top:55px). Zone 칩 클릭 → 그 zone 의 Bay 칩 펼침 → Bay 클릭 시 스크롤. 풋어웨이는 진행률(3/8)도 표시. **bayOfBin 규칙**: [E?]Zone Rack(숫자2) 뒤가 숫자4+면 베이(2)+셸프(2)→bay=존+랙+베이2, 문자 섞이면(Pallet05·HAIR) 나머지 전부가 베이=bin 통째. 토론토 C020303→C0203, 에드먼튼 EZ010101→EZ0101(E 포함 표시), EZ01Pallet05→통째.
- **모바일(태블릿 세로) 최적화**: 칩·스테퍼·Placed/Change/Assign 버튼 터치 ≥40px. HID 블루투스 스캐너(=키보드 입력, focusScan 이 처리). `receiver-preview.html`(실제 CSS+샘플, 정적)로 태블릿 실물 확인 가능.
- **흐름**: PO/TR 선택 → PO-guided 스캔 검수(초과=confirm 후 허용+over 플래그, 홀드 가능) → **오프-PO 는 매니저 승인 대기**(needs_approval, 승인 전 풋어웨이·Apply 차단) → **Putaway→ 버튼이 빈 자동확정** → 풋어웨이 가이드(빈별 그룹, zone 동선순, Placed 체크; 신규 SKU=빈 지정 필요 그룹에서 스캔/입력) → 부분완료(PO 열림) / 최종완료.
- **⚠️⚠️ 기대치(expected_base)는 인보이스 기준 (2026-08-05 전환 — 종전 오더 라인 기준은 가짜 discrepancy 를 만들었다)**: 공장이 실제로 보내는 것은 authorize 된 **인보이스** 라인이다. 실측 PO-01068(Advanced): Order 92줄 vs Invoice 77줄 · ORS11021 오더 360 → 인보이스 264 — 오더 기준이던 동안 이 차이가 전부 가짜 `recv_short` 로 기록됐다. ⚠️ **리시빙 대상 PO 에 Advanced 가 실재한다**(같은 PO-01068) — 규칙 20 위쪽의 "대상 8건 전부 Simple" 은 그날 스냅샷일 뿐, 일반화하지 말 것.
  - EF `poDetail` 이 **PO 상세 응답의 Invoice 블록**에서 SKU 별 수량을 집계해 expected 를 만든다(추가 호출 없음). 접근자는 `invoiceBlock()` 하나 — Simple=객체·Advanced=배열[0] (실측 구조는 cin7-api `references/purchase.md` 「인보이스 블록 실측」).
  - **라인 집합은 Order.Lines 유지 + 수량만 덮어쓰기.** 라인을 제거하면 그 SKU 스캔이 off-PO(needs_approval)로 빠져 승인 전까지 풋어웨이·Apply 가 막힌다 — 오더에 있는 물건이 "PO 에 없는 것" 취급되는 왜곡. 인보이스에 없는 오더 라인 = **expected 0**(~~공장 백오더~~ — short 아님·received 0 이면 discrepancy 도 없음: buildApplyPlan 이 rb≤0 라인을 건너뜀). UI 는 "Not on invoice" 그룹으로 맨 아래·흐림 + NOT INVOICED 칩, 스캔은 가능(첫 스캔부터 over confirm). ⚠️ **2026-08-12 부터 expected 0 에 물건이 오면 Apply 는 0 을 쓴다**(전량 초과 클램프 — 아래 ① 정정 참조. "공장 백오더" 라는 이름 자체가 전제 오류였다 — 백오더는 물건만 따로 오지 않는다). 인보이스에만 있는 SKU 는 **정상 기대 라인으로 추가**(is_off_po 아님).
  - `NonInventory=true` 라인 제외(사용자 결정 2026-08-05 — 재고로 안 받는 항목, 넣으면 영영 미충족). AdditionalCharges 는 별도 배열이라 애초에 안 읽힌다. 제외 건수는 console.warn.
  - ⚠️ **인보이스 블록이 없거나 쓸 라인이 없으면 오더 기준 폴백 + 경고**(EF console.warn + receiver 토스트) — 조용히 expected 0 으로 만들면 전 라인이 recv_over 로 잡힌다.
  - **`wms_receipts.expected_source`**('order'|'invoice', 기존 행은 'order' — 같은 컬럼에 두 기준이 표식 없이 섞이면 해석 불가) + **`cin7_type`**(Apply 게이트의 엔드포인트 선택 근거 — 규칙 21). SQL `20260805100000_receiving_expected_invoice.sql`, **배포 순서 SQL → EF → 프론트**(규칙 23).
  - 트랜스퍼는 무관 — 인보이스가 없고, expected 는 보낸 수량 그대로(`normLine` 의 override 파라미터를 안 넘김) — bin 이동 캡 `min(received, expected)` 의 근거라 섞이면 깨진다. ⚠️ Advanced **다중 인보이스**(부분 출하)는 [0]만 본다 — 실측 len=1, 복수가 실측되면 합산·receipt 단위 재설계 필요.
- **테이블**: `wms_receipts`(po_number·cin7_purchase_id·warehouse·status[in_progress/held/partial/completed]·**source_type[po/transfer]**·**applied_at/by/note**·**expected_source·cin7_type(2026-08-05)**) + `wms_receipt_lines`(expected_base·received_base·putaway_bin·zone·putaway_done·is_off_po·needs_approval). ⚠️ wms_sku_bins 에는 절대 안 씀(6:30 truncate). SQL: `wms_receipts.sql` + `wms_receipts_apply.sql`.
- **admin Receiving 탭**: Off-PO approvals(Approve/Reject, 배지) + **Apply to Cin7**(completed & 미반영만; dry-run 계획 confirm → commit — 규칙 21) + History(✓ Applied 배지, Delete=WMS 전체 리셋·단계 없음·Applied 후엔 Cin7 안 되돌아감 경고).
  - **Review 버튼 (2026-07-24)**: Apply 옆·History 에. 읽기전용 요약 모달(bin 별 그룹핑된 풋어웨이 결과·수량·OVER/SHORT/OFF-PO·Placed). 하단: Apply→Cin7 / **Reopen for edit**(status→in_progress + `receiver.html?receipt=N` 딥링크로 이동해 기존 화면에서 수정 — 새 수정 UI 안 만들고 검증된 화면 재활용). applied 된 건 Reopen 잠금.
  - **Apply 권한 (2026-07-24)**: perms 에 `apply` 키 추가(staff-admin PERMS 배열). admin 역할 항상 통과. 권한 없으면 Apply 버튼→"no permission", 함수 진입도 차단(3중 게이트). ⚠️ 기존 매니저에 apply 기본 없음 — 신뢰하는 소수만 체크.
- **Resume/열기 필터 (2026-07-24)**: `loadMyReceipts` 는 `applied_at IS NULL` 만(반영된 건 목록에서 제외). openReceipt 도 applied 면 차단.
  - **중복 카드 숨김 (2026-07-28)**: Resume 섹션에 **이미 카드로 떠 있는 문서**는 아래 "Ready to receive (Cin7)" 목록에서 감춘다(키 = `po_number` 대문자 비교, 헤더에 "— N already open above" 표시). ⚠️ **기준은 "화면에 렌더된 `myReceipts`" 뿐이다** — "receipt 행이 존재하면 숨김"으로 짜면 안 된다: 창고 접근 밖 등으로 Resume 에 안 뜨는 문서까지 사라져 **스캔 이어받기 진입로가 막힌다**. 빈 목록 판정도 `openPos` 가 아니라 `visPos` 기준(전부 숨겨졌는데 "없음"이 안 뜨던 문제).
- **리시빙 리스트 프린트 (2026-07-25)**: receiver 검수 헤더 **🖨 Print** → 픽리스트와 동일 형식 새 창(팝업차단 회피: 클릭 핸들러 안에서 `window.open`). 로고 + "PO/TRANSFER RECEIVING" + **문서번호 CODE128 바코드**(인쇄물 스캔으로 재진입) + 공급사/루트·창고·총라인/수량·Received By 서명란 + 라인표(**Last bin** · SKU · 제품명 · Qty · ✓체크박스). **라스트빈(존) 순 정렬**(창고 동선), no-bin 은 주황 "no bin" 으로 눈에 띄게. `zoneOfBin`/`zOrder` 재사용.
- **차이(불일치) 처리 정책 (2026-07-25 사용자 결정 · 중요 / 2026-07-28 트랜스퍼 예외 / ⚠️⚠️ 2026-08-10 초과 클램프 개정)**: ① ~~Cin7 에는 **초과/부족 무관 "들어온 대로"**(received) 쓴다~~ → ⚠️⚠️ **2026-08-10 개정(사용자 결정): 부족만 "들어온 대로", 초과(received > expected)는 인보이스 수량(expected_base)까지 클램프해서 쓴다.** 종전 문장은 2026-08-10 까지의 정책 — PO stock received 의 **초과 허용 자체는 여전히 실측 사실**이고 API 제약이 아니라 **정책으로** 자른다(초과를 그대로 쓰면 매니저 조정 전까지 Cin7 재고가 부푼다). 경계: **`expected_source='invoice'` receipt 만**(구형 'order'·인보이스 폴백은 무클램프 — 오더 기준으로 자르면 정상 수량이 잘린다) · SKU 단위 budget 을 planLines(라인 id) 순으로 소진 → **마지막 PO 라인부터 잘림**(⚠️ "마지막 bin 부터"가 아니다 — 작업자가 bin 을 채운 시각은 어느 컬럼에도 없다: `updated_at` 은 bin 변경·승인에도 갱신되는 최종 수정 시각이라 부적격. id 순 = PO 라인 순이 결정론적 대용물이고, 진짜 시간 순서가 필요하면 `first_received_at` 신설이 선행 — 2026-08-10 확인) · ~~⚠️ **SKU 합계 expected 0 = 공장 백오더 — 클램프 제외, 받은 대로**(0 으로 자르면 받은 물건이 Cin7 에 아예 안 들어간다 = 재고 누락, 절대 금지)~~ → ⚠️⚠️ **2026-08-12 반전(사용자 결정 — 이것이 정본): 인보이스가 기준이다. 인보이스에 없는데 물건이 왔다면 전부 초과 클램프 = move 0.** Cin7 반영 0 · 전량 recv_over(ordered 0 · actual 전량 — 클램프와 독립 산출이라 자동 기록) · 매니저 Cin7 수동 조정이 유일한 반영 경로(인보이스에 없는 물건 = 공급사 정산이 안 된 것, 자동 투입 금지). **왜 뒤집혔나: 논리가 틀린 게 아니라 전제가 틀렸다** — "공장 백오더가 물건만 따로 온다"는 시나리오는 실제 업무에서 일어나지 않는다(2026-08-12 사용자 확인). 실사고 PO-01027 이 그 증거다: Cin7 이 "doesn't exist in purchase invoice" 로 400 거부, 2 bin 전부 실패(0 group posted · 문서 DRAFT 잔류 19/44 exported — 클램프 자체는 정상 작동, CRO71965 writes 12 of 24). move 0 → pending 0 → POST 그룹에서 제외라 400 원인 소멸. 가시성: writes 0 라인은 dry-run·commit 로그에 **"NOT ON INVOICE - writes 0 of N"** 표식 + 요약 병기("물건은 창고에 있는데 Cin7 에는 없다"가 전달되게). 테스트 ④·⑧ 도 같은 날 정반대로 뒤집음(옛 정책을 고정하면 다음 사람이 그걸 근거로 되돌린다) · `exported_base` 도 클램프값(markExported 가 move_base 기준) · `received_base` 는 실물 그대로 · recv_over discrepancy 는 종전대로 expected vs received(③ 수동 조정 흐름 무변). 가시성 4겹: dry-run steps "1b) CAPPED…" · plan `capped_to_invoice[]` · commit 로그/apply_note "CAPPED to invoice quantity"(계약 마커 아님) · admin Review 모달(라인 `[capped at invoice qty]` + ⚠ 블록). ⚠️ 수식은 트랜스퍼 캡(아래 예외 ④)과 쌍둥이고 ~~expected 0 처리가 정반대~~ **2026-08-12 부터 동일**(둘 다 전량 제외 — 트랜스퍼는 물리 강제, PO 는 정책 + PO-01027 실측상 사실상 물리 강제이기도) — 공용 헬퍼 통합은 트랜스퍼 경로가 다음에 열릴 때 별건(2026-08-10 결정). 구현 = `supabase/functions/receiving/po_clamp.ts`(순수 함수 — index.ts 의 최상위 Deno.serve 때문에 분리) · 검증 = `po_clamp_test.ts`(deno test, 합성 라인 ①~⑧ — ⚠️ 2026-08-10 실측: 초과 PO 실물이 아직 없어(PO-01121 61라인 전부 일치) 이 스위트가 유일한 사전 검증). ② 기대치와의 차이는 **`wms_discrepancies` 큐에 자동 기록**(`source='receiving'`, reason `recv_over`/`recv_short`/`recv_off_po`, `po_number`/`receipt_id`, responsible=received_by — ⚠️ received_by 는 "시작한 사람"이라 이름 표시가 정확하지 않을 수 있다(2026-08-17 규칙 24 라인별 작업자 항목 · recv_* 는 NOT_MISTAKE 라 실수 집계엔 무영향 · 교체는 백로그)). ③ 매니저가 admin Discrepancy 탭에서 보고 **Cin7 backend 에서 수동 stock adjustment** → "Cin7 Fixed" 버튼으로 정리. **자동 adjustment 는 하지 않음**(사람 판단 유지 = 안전). **2026-08-04 부터 픽·팩의 재고 부족 선언(`stock_short`, 규칙 41)도 같은 큐·같은 흐름으로 합류** — 리시빙과 동일하게 매니저 Cin7 수동 조정이 유일한 보정 경로다. `receipt_id+sku` **전체 유니크**로 재적용 중복 방지. SQL `wms_disc_receiving.sql`(order_id NULL 허용 + source/po_number/receipt_id + 유니크 인덱스). ⚠️⚠️ **2026-07-29 정정 — 원래 이 인덱스는 `WHERE receipt_id IS NOT NULL` 부분 유니크였고, 그 때문에 PostgREST `on_conflict` 가 깨져 리시빙 discrepancy 가 구현 이후 한 건도 기록되지 않았다: 규칙 29.**
  - ⚠️ **기록 시점 = Cin7 쓰기 "앞"** (2026-07-28 역전). 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 차이 기록이 통째로 유실됐다(TR-02935 실사고). 이 큐가 **유일한 보정 지시서**이므로 **insert 실패 = Apply 중단**(Cin7 을 건드리지 않는다) — 여기서만 "실패해도 Apply 성공(WARN)" 방침을 의도적으로 뒤집는다. 자세한 원칙은 규칙 27 **R12**.
- **⚠️⚠️ 트랜스퍼 예외 (2026-07-28 사용자 결정 — API 제약 때문)**: 트랜스퍼는 "Cin7 에 received 를 쓴다"가 **API 레벨에서 불가능**하다(완료 PUT 의 `TransferQuantity` 변경은 무시된다 — 규칙 21 정정 항목).
  - ① **완료 수량 = 보낸 수량(주문 수량) 그대로 확정.** 실물 수량 덮어쓰기 로직은 제거했다.
  - ② 실물과의 차이는 **반드시 discrepancy 에 명시** — 여기선 큐가 유일한 정정 근거다.
  - ③ 매니저가 **Cin7 에서 수동 stock adjustment** 로 정리.
  - ④ **bin 이동은 `min(received_base, expected_base)` 캡.** 초과 라인은 expected 만큼만(초과분은 Cin7 에 없다 → 옮기려면 400). 부족 라인은 received 만 옮기고 `expected − received` 는 착지 지점에 남는다.
  - ⑤ **잔량이 착지 지점에 남는 것은 의도된 동작이다.** 남은 수량 = 매니저가 제거해야 할 양이고, 남아 있다는 것 자체가 "미정리" 신호가 된다. 보정 트랜스퍼 자동 생성은 **채택하지 않음**(부족분을 기계적으로 되돌리면 실제 분실을 "토론토에 있다"고 잘못 기록할 위험).
  - ⑥ ⚠️ **잔량의 위치 표현이 (a)/(b) 로 다르다**(규칙 21 착지 지점 2가지): **(b)** 집결 bin → **bin 이름**(예 `EZ010101`) / **(a)** 창고에 bin 없이 → **`"Asung - Edmonton (no bin)"`** 처럼 창고명+`(no bin)`. 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다 → EF 는 `to_location_raw` 원문을 그대로 쓰고 `leftover_at_landing[].where`·`apply_note`·Review 모달에 같은 문자열을 싣는다. ⚠️ `landingBin = to_location_raw` 의 콜론 뒤 부분은 **반드시 trim + undefined 방어** — (a) 는 콜론이 없어 `split(":")[1]` 이 undefined 이고, 앞 공백이 남으면 "이미 제자리" 스킵 판정이 어긋나 From==To 이동을 쏴서 400 이 난다.
- ⚠️ **CSV 경로는 폐기** — Cin7 직접 쓰기 검증(규칙 21)으로 대체. **`exported_base` 는 2026-07-28 부터 트랜스퍼 bin 이동 체크포인트로 사용**(옮긴 수량 기록 → 재Apply 시 그 라인 건너뜀). **PO 도 2026-07-31 부터 사용 — 단 의미가 다르다: Simple = "Cin7 stock received 문서에 실은 양"(규칙 21 PO 이식 절 · ⚠️ 2026-08-10 부터 초과 클램프 반영값 — received 가 아니라 클램프된 move_base) / ⚠️ Advanced(2026-08-07) = "put-away 로 선반 지정까지 끝난 양"**(수량 단계의 진행은 컬럼 없이 Cin7 되읽기 — 규칙 21 Advanced 절).
- **Apply 는 completed receipt 만**: Simple PO 는 stock received 를 한 번만 authorize 가능(Cin7 제약) → 분할 배송은 최종완료 때 일괄 반영.
  - ⚠️ **"검수 직후 Apply(풋어웨이 전)" 로 앞당기지 않는다 — 2026-08-04 재검토 후 유지 결정.** ①**authorize 1회 제약과 정면충돌**한다: bin 이 아직 안 정해진 상태로 문서를 authorize 하면 나중에 bin 을 API 로 채울 방법이 없다(규칙 21 authorize 게이트가 미처리·실패·격리·스킵 하나만 있어도 DRAFT 로 남기는 이유와 같다). ②**PO 의 유일한 구조적 장점을 버린다** — PO 는 `POST /purchase/stock` **라인에 `LocationID` 를 실을 수 있는** 유일한 경로다(트랜스퍼는 완료 시 bin 지정이 불가 — 규칙 21). 검수 직후 Apply 는 이걸 포기하고 PO 를 트랜스퍼처럼 **"착지 → bin 재배치" 2단계**로 만든다(=콜 수·실패면 수 증가, 규칙 30 의 청크 문제를 PO 로 수입). 즉 풋어웨이가 Apply 앞에 있는 것은 절차 취향이 아니라 **API 제약이 정한 순서**다.
- ☰ Menu 에 Receiving(전 작업자), index 런처에 카드.
- 📌 **"지우지 않는다" 원칙의 예외 사례 (2026-08-11 — wave id 21/W-0806-4 삭제)**: completed 인데 멤버 0 인 wave(08-06 테스트 잔재)를 삭제했다. 정당화 근거 셋이 **전부** 성립했다 — ① 관리자 본인이 만든 테스트 ② 멤버 0 이라 잃을 정보 없음 ③ **Health 경고가 상주하면 사람이 Health 탭을 안 보게 된다**(다음 진짜 불변식 위반도 "또 그거겠지"로 넘김 — 상주 경고의 실질 피해가 더 크다). ⚠️ 셋 중 하나라도 빠지면 예외가 아니다 — 운영 데이터·정보가 있는 행은 여전히 무효화(voided)·아카이브가 원칙(규칙 14). ⚠️ 테스트 조작으로 이 상태가 만들어졌다 = 운영에서도 가능하다는 뜻 — 백로그 「completed wave + 멤버 0 잔재」(세션 문서 11장).

## 규칙 21 — Cin7 쓰기 (⚠️ 2026-07-23 실측 검증 — MVP "안 쓴다" 원칙의 첫 예외)

리시빙은 Cin7 에 **직접 쓴다** (매니저 Apply 게이트 경유). 실측으로 확정된 규칙:

- **bin = GUID.** `From`/`To`/`LocationID` 에 bin 이름("창고: bin")을 넣으면 400 "not found in Locations reference book". `/ref/location` 에서 GUID 조회 (EF `binGuid()`/`binMap()`).
  - ⚠️ **`/ref/location` 은 Total 2678 인데 Limit 500 로 잘린다. bin GUID 는 최상위 창고 행(`ParentID` 없음)의 `Bins[]` 에서 뽑아라**(에드먼튼 628·토론토 2047 전부 포함 — 페이지네이션 불필요). **child-location 의 `Name` 은 bin 이름이 아니다**(예 "071164313169" 바코드류 — 매칭 불가한 죽은 경로였고 제거했다). 실측 2026-07-28 **TR-02935**: 잘린 500행에 에드먼튼 child 가 0행이어서 bin GUID 조회가 첫 호출부터 throw → Apply 의 bin 이동이 **한 건도 실행되지 않고** 전 품목이 집결 bin EZ010101 에 남았다. 토론토도 우연히 앞 페이지였을 뿐 안전하지 않았다. 이름 비교는 `trim().toUpperCase()`, `IsDeprecated` 제외. `?action=bins` 도 같은 소스.
  - ⚠️ **GUID 를 못 찾으면 그 라인만 스킵**(전체 throw 금지) → 응답 `skipped_bins:[{sku,bin,reason}]` + `apply_note`. 트랜스퍼는 PUT COMPLETED 이후 절대 throw 안 함(Cin7 은 이미 바뀌었는데 `applied_at` 이 null 로 남아 큐에 갇히고 discrepancy 까지 유실된 게 TR-02935 의 2차 피해). PO 는 하나도 못 찾으면 throw(아직 안 썼으므로 재Apply 가 맞다) · **스킵이 있으면 auto-authorize 생략**(DRAFT 유지 → Cin7 에서 수동 보정).
- **트랜스퍼 (TR-03236 실측)**: `POST /stockTransfer` 로 **즉시 Status=COMPLETED 생성 가능**(DRAFT 불필요). **같은 창고 bin↔bin 은 InTransitAccount 불필요.** 수량은 델타(TransferQuantity)라 절대값 위험 없음 — stock adjustment(절대값)보다 안전해 bin 이동의 표준 수단. 되돌리기 = 반대 방향 트랜스퍼(상쇄).
- **트랜스퍼 리시빙 완료** = PUT 원 TR→COMPLETED(전량 헤더 기본 To bin 착지 — 트랜스퍼 라인엔 bin 없음, 문서 구조상 불가) → **bin 그룹별 미니 트랜스퍼**(기본 bin→목적지 bin)로 재배치. Cin7 WMS 앱의 라인별 무한 풋어웨이 반복을 API 콜 몇 개로 대체. (UI 의 라인별 `Put away` 는 v2 API 에 없다 — 탐색 종결, 규칙 38.)
- **PO stock received (PO-01084·PO-00965 실측)**: `POST /purchase/stock` — `{TaskID: PO GUID, Status:'DRAFT', Lines:[{Date, SKU, Quantity(라인 단위 — received_base÷factor), LocationID(bin GUID), Received:false}]}`. **입고 시점에 bin 직접 지정.**
  - ⚠️⚠️ **문서당 bin 1개만! (2026-07-24 실측 — 가장 중요)**: 한 `POST /purchase/stock` Lines 에 **서로 다른 bin(LocationID)을 섞으면 400 "Lines is invalid"**. 같은 bin 여러 SKU 는 OK. → **putaway_bin 으로 그룹핑해 bin 마다 별도 POST** (콜 간 sleep 300~400). 이게 오랫동안 "Lines is invalid" 로 헤맨 진짜 원인. (트랜스퍼 bin↔bin 은 되는데 stock received 는 안 됨 — API 마다 다름)
  - ⚠️ **같은 (SKU+bin) 중복 라인 금지**: 400 "Cannot add duplicate value". EF 가 plan 만들 때 같은 SKU+bin 은 수량 합산 병합.
  - ⚠️ **Authorize = `POST` (PUT 아님!, 2026-07-24 실측)**: `POST /purchase/stock {TaskID, Status:'AUTHORISED', Lines:[]}`. **PUT 은 405 "does not support http method 'PUT'"**. 성공 시 재고 확정. 실패해도 DRAFT 는 남아 Cin7 화면 수동 Authorize 가능(EF WARN 로그).
  - **✅ Apply in-flight 잠금 (2026-08-06, 규칙 27 R4 해소 — ⚠️ 현장 미검증 · PO·트랜스퍼 공통, 같은 날 트랜스퍼 확장)**: `wms_receipts.apply_lock_at/apply_lock_by`(`20260806100000_receipts_apply_lock.sql`)를 applyCommit 진입에서 **조건부 PATCH(원자 UPDATE)** 로 선점 — ① `apply_lock_at=is.null` 획득 ② 0행이면 90초(`APPLY_LOCK_STALE_MS`) 경과 잠금을 관찰값 eq CAS 로 **만료 탈취**(EF 사망 자동 회복 — ⚠️ **조용히 탈취하지 않는다**: 응답 로그에 WARN "stale apply lock taken over … died mid-round" — 이상 신호) ③ 둘 다 0행 → 차단 `"Apply is already running for PO-x - started {t} by {who} ({N}s ago)"`(수행자 필수 — 없으면 매니저가 기다릴지 다시 누를지 판단 불가). **획득은 ⓪ discrepancy 선기록보다 앞** — 차단된 중복 요청은 아무 행도 만들지 않는다. 획득 PATCH 의 반환 행으로 `applied_at` 재확인(read-then-check 창 마감, 추가 요청 0 — R4 의 종전 제안 "최종 PATCH 조건부"는 이걸로 대체). 해제 = 회차 종료 PATCH 에 병합, throw 경로는 catch 에서 best-effort 해제, 실패해도 90초 만료로 회복. **순차 재시도 3종(청크 자동 반복·부분 실패 재개·retry_failed=1)은 회차마다 획득→해제라 막히지 않는다** — PO·트랜스퍼 공통 구조(마커·청크·격리 공유)임을 확장 전에 확인. "already applied" 계열 메시지에 `applied_by` 추가. **트랜스퍼 확장 근거·주의(2026-08-06)**: ① mini transfer 의 `TransferQuantity` 는 델타라 멱등이 아니고 Cin7 duplicate 거부(PO 의 400)도 없어 **동시 실행이면 진짜 이중 이동** — exported_base 는 순차만 수렴시킨다. ② 차단·탈취 메시지의 번호 자리는 `rcpt.po_number` — 트랜스퍼 receipt 에선 TR-xxxxx 가 저장돼 있어(생성 경로 PO/TR 공통) 수정 없이 TR 번호+수행자가 표시된다. ③ ⚠️ **미실측**: 이미 COMPLETED 인 TR 에 두 번째 완료 PUT 이 거부되는지 무시되는지는 확인된 바 없다(R11 — 200 이 아니라 되읽은 값이 근거. 잠금이 있으면 그 상황 자체가 안 생기므로 실측 없이 둔다). ④ **부수 효과**: 잠금이 "동시 실행이 만든 체크포인트 꼬임"을 제거하므로 `Available quantity … is 0` checkpoint repair 의 발동 원인이 하나 줄었다 — **앞으로도 `checkpoint_repaired` 가 계속 뜨면 동시 실행이 아닌 다른 원인이라는 신호다**(R10 신호의 해상도 상승).
  - **Date 형식**: `YYYY-MM-DDT00:00:00Z` (자정, 밀리초 없이). 밀리초 포함 ISO(`.948Z`)는 의심스러워 자정 고정으로 통일. `Date` 필드는 필수.
  - **빈 DRAFT 문서 함정**: Cin7 화면 Stock Received 탭이 "비어있음"으로 보여도 API GET 은 NOT AVAILABLE 반환할 수 있음 — 화면 표시와 API 상태가 다를 수 있으니 GET 결과로 판단.
- ⚠️ **Invoice First 게이트**: 인보이스 미승인 PO 에 stock received POST 하면 400 "'Invoice First' approach... authorise Invoice before StockReceived". EF Apply 가 **PO 상세 응답의 Invoice 블록**(`poRaw()`+`invoiceBlock()`, `wms_receipts.cin7_type` 으로 /purchase vs /advanced-purchase 선택)으로 선확인. Status=INVOICED PO 도 stock received 통과(실측).
  - ⚠️⚠️ **2026-08-05 정정 — 종전 `GET /purchase/invoice` 선확인은 Advanced PO 에서 400** ("deprecated and does not support Advanced Purchase", 실측): Advanced receipt 의 Apply 가 "Invoice not authorised" 라는 **오진 메시지**로 막히는 구조였다(리시빙 PO 에 Advanced 실재 — PO-01068). 상세 응답 invBlock 은 Simple/Advanced 공통이고 호출 수 동일(1 GET 대체). ~~판정은 fail-open 유지(Status 못 읽으면 통과): fail-closed 전환은 EF 로그 관찰 후 별건 결정~~ → **✅ 2026-08-06 fail-closed 전환 완료 — 아래 정정 항목 참조.** 구형 receipt(cin7_type NULL)은 /purchase 로 — 종전 게이트도 Simple 전용이라 회귀 없음. **단 구형 NULL receipt 이 Advanced PO 면 그 /purchase 가 400** — 아래 폴백이 잡는다.
  - **엔드포인트 폴백 (2026-08-05 추가, ⚠️ 현장 미검증)**: `poRaw()` 가 **400** 을 받으면 반대 엔드포인트(/purchase ↔ /advanced-purchase)로 **1회만** 재시도한다 — 위험 구간이던 "구형 NULL receipt 이 Advanced PO" 를 자가 치유. ⚠️ 429·404·5xx 는 폴백 대상이 아니고(기존 백오프·throw 경로 불변) 반대쪽도 실패하면 **원래 에러**를 던진다(무한 재시도 없음). 폴백 성공 시: ① **console.warn 필수**(시도 순서·성공 경로·저장돼 있던 타입 — 조용히 넘기면 cin7_type 이 틀렸다는 사실을 아무도 못 본다) ② Apply 게이트는 `wms_receipts.cin7_type` 을 교정 PATCH(⚠️ 기록 실패가 Apply 를 막지 않는다 — 부가 정보, 다음 회차에 폴백이 또 잡는다) ③ `poDetail` 은 교정 타입을 `cin7_type` 반환값에 실어 receiver 가 **receipt 생성 시** 저장한다(receiver.html `po.cin7_type||p.type` — 저장 안 되면 매번 폴백 발동). 에러 메시지도 분리 — **PO 상세 조회 실패(폴백 포함)는 "Invoice check failed - could not read the PO detail..."** 로, 인보이스 미승인만 "Invoice not authorised - authorize..." 로(종전엔 조회 실패도 authorize 처방이 나가는 오진). ~~판정 로직(fail-open)은 불변~~ → 2026-08-06 fail-closed 전환(아래).
  - ⚠️⚠️ **2026-08-06 정정 — Apply 인보이스 게이트 fail-closed 전환 (⚠️ 현장 미검증)**: ~~종전 판정 `if (st && st !== "AUTHORISED" && st !== "PAID")` 는 st 가 빈 값·null 이면 **통과**시키는 fail-open 이었다~~ — "확인 결과 문제 있음"은 막고 "확인 자체 실패"는 묵과하는 방향 역전을, 되돌릴 수 없는 Cin7 쓰기 직전의 마지막 관문에서 정정했다. 전환 조건이던 관찰은 완료(엔드포인트 폴백 배포 v30 으로 400 경로 폐쇄 + 그 코드로 PO-01076 Apply 성공 6.6초/200). **현재 판정 3분기(전부 차단)**: ① Invoice 블록 없음 → "No invoice on this PO - create and authorize..." ② 블록은 있는데 Status 빈 값/없음 → "Invoice status could not be read..."(⚠️ 승인 처방을 주지 않는다 — 오진 메시지 방지) ③ 허용 외 값 → "Invoice not authorised - authorize..."(실제 상태값 표기). **허용 목록 = `PO_INVOICE_OK`(AUTHORISED/PAID) 상수를 목록 필터와 공유** — 두 곳이 갈라지면 "목록은 통과시키는데 게이트는 막는" 가장 찾기 어려운 불일치가 된다(사용자 결정). 비교 전 `trim().toUpperCase()` — 종전 게이트는 trim 이 없어(목록 필터에만 있었다) 공백 붙은 정상 값이 오차단될 수 있었다. PAID 포함 근거: 블록에는 `Payments`·`Paid` 필드가 따로 있어 결제 정보가 Status 와 분리돼 있고(2026-08-05 실측 — 블록 Status 실측은 AUTHORISED 만), 블록 레벨 PAID 는 미실측이지만 헤더 `InvoiceStatus=PAID` 실측(PO-01081)이 정상 후속 상태라 **보험으로 포함** — 빼면 그 상태 PO 전부 차단. **실질 적용 구간은 좁다**: 목록 필터가 미승인 PO 를 이미 제외하므로 남는 것은 목록 통과↔Apply 시간차(수시간~수일)에 Cin7 쪽 인보이스가 변한 경우 + 상태 판독 실패 — 위험 제거보다 원칙 일관성·메시지 개선이 주목적(범위 확장 금지). ⚠️ 게이트는 ⓪ discrepancy 선기록 **뒤**라 차단돼도 disc 행이 남는다 — `on_conflict=receipt_id,sku`+ignore-duplicates 라 재Apply 에 무해(R12 "Supabase 먼저" 순서 그대로). ⚠️ 기대치의 오더 기준 폴백(규칙 20 — 블록 없으면 수령은 계속)과 Apply 차단은 **의도된 비대칭**: 스캔·수령은 진행하되 되돌릴 수 없는 쓰기만 멈춘다. ⚠️ dry-run(`action=apply`, commit 없음)은 buildApplyPlan 만 돌고 게이트를 타지 않는다 — 게이트 검증은 commit 경로에서만 가능(차단 분기는 첫 Cin7 쓰기 앞이라 commit 테스트도 Cin7 무해).
- ⚠️⚠️ **Advanced PO 는 stock received 가 2단이다 (2026-08-07 · PO-01094 실사고+프로브 · ⚠️ 현장 미검증)**: `POST /purchase/stock` 은 Advanced 에서 400 deprecated(8개 bin 그룹 전멸이 발견 경위 — 위 Simple 규칙들은 **Simple 전용**이 됐다). Advanced 는 `/advanced-purchase/stock`(수량)과 `/advanced-purchase/put-away`(선반)가 분리돼 있고 **stock 라인의 LocationID 는 200 후 되읽으면 null**(bin 을 못 싣는다) — 실측·스펙은 `cin7-api` 주의사항 13 + `stock-write.md` Advanced 절. EF 구현(`applyCommitRun` Advanced 분기):
  - **분기 판정은 cin7_type 이 아니라 게이트가 방금 읽은 상세의 `Invoice` 블록 모양**(배열=Advanced — 서버 진실). 타입 오기록 receipt 도 그 회차부터 맞는 경로. ⚠️ **쓰기 폴백은 만들지 않았다** — 역방향(advanced 주소로 Simple PO 에 쓰기)은 **PO 를 조용히 Advanced 로 변환**하므로 금지(cin7-api 13), 순방향은 이 분기 설계로 불필요해졌다.
  - **stage1 = 수량**: 전 라인 SKU 합산(같은 SKU 를 bin 그룹별로 나눠 보내면 location null 중복 400 — 합산 필수) **단일 POST**(기존 DRAFT 태스크 재사용 — DELETE 가 무력해 재사용이 필수) → 되읽기 수량 검증 → **authorize = ★유일한 진짜 불가역 지점**(재고가 창고 레벨로, bin 없이 들어간다). 문서가 계획보다 많이 들고 있으면 authorize 전 중단(초과 확정 방지).
  - **⚠️ pre-flight 하드 게이트 (2026-08-07 사용자 결정 — 확인 모달 대신)**: stage1 authorize **앞**에서 전 bin GUID 를 해석, 하나라도 실패 = 전량 중단·무기록. 매니저 확인창은 추가하지 않았다 — 읽어도 바꿀 선택이 없는 정보는 읽지 않는 줄만 늘린다(SO-14129 계열 판단).
  - **stage2 = 선반**: put-away **단일 AUTHORISED POST**(X-b — 그룹별 DRAFT 안은 폐기: "invoice lines match the receiving → only AUTHORISED accepted" 조건이 정확 수령에서 DRAFT 를 결정론적 400 으로 만들고, 전환 판정을 에러 문자열로 하지 않는다는 조건과 겹쳐 막다른 길. AUTHORISED POST 는 스펙상 항상 허용). ⚠️ **"잘못 놓인 bin 은 stockTransfer 로 정정"은 미실측 추정이다** — bin↔bin 이동 자체는 표준 실측 경로(TR-03236)지만 put-away 로 놓인 재고에 실측한 적은 없다. 확정처럼 쓰지 말 것(검증 대기 항목). 발동 시 로그에 `IRREVERSIBLE CALL` 명시. POST 후 **되읽어 LocationID 실저장 확인 후에만 체크포인트** — 이 API 는 "200 인데 무시" 전과가 둘이다. **실패 문구는 전부-아니면-전무를 명시**("ALL-OR-NOTHING … NO bin was placed") — `failed_moves(N)` 마커 계약상 admin 이 "N bins failed" 로 표시해 부분 실패로 오독될 수 있어서다. **시간 예산**: 이 분기는 chunkGuard 를 안 탄다 — Cin7 왕복이 라인 수와 무관하게 고정(~10콜, 92줄도 한 페이로드 — 트랜스퍼 344줄 전례)이라 쪼갤 것이 없고, 최악 ~30초는 20초 예산을 넘지만 EF 한도·잠금 만료(90초)에 여유가 있으며 중간 사망도 되읽기 재개로 안전.
  - **stage 간 실패 상태**: stage1 완료+stage2 실패 = **재고는 들어갔는데 선반이 없는 상태**(트랜스퍼 (a) 착지와 동일한 형태 — 낯설지 않다). apply_note 에 "STOCK IS IN Cin7 WITHOUT SHELF LOCATIONS" 크게 남기고 기존 `failed_moves(N)` 마커를 실어 admin 의 "⚠ Applied (N bins failed)"+'Retry failed bins' 경로가 무변으로 재개한다. stage1 authorize 실패는 `groups_remaining` 으로 done:false(applied_at 없이 큐 잔류).
  - **`exported_base` 의미 분기(규칙 20 의 표 각주와 함께 갱신)**: Simple = "문서에 실은 양"(무변) / **Advanced = "put-away 로 선반 지정까지 끝난 양"**. stage1 진행 상태는 컬럼 없이 **Cin7 되읽기가 진실**(회차 시작 GET 으로 기실림·AUTHORISED 를 판정해 건너뜀 — checkpoint repair 와 같은 원칙). 청크·격리는 Advanced 에선 사실상 불용(stage1 콜 2개·stage2 콜 1개 — bin 1개 제약이 없어 그룹 분할 자체가 소멸).
  - ⚠️ **되돌림 없음 전제**: stock DELETE 는 200 이어도 무력(실측), put-away 는 DELETE 가 스펙에 없음, authorize 취소 API 없음 — UI void 는 미실측. 프로브·재시도 설계는 "지울 수 있다"에 기대지 말 것.
  - ⚠️⚠️ **실사고 2호 (2026-08-07 후반) — TaskID 는 I&R 그룹 식별자, 타깃은 승인 인보이스에서 유도**: stock POST 에 TaskID 를 안 실었더니 Cin7 이 **새 I&R 그룹 + 빈 DRAFT 인보이스**를 만들었고(승인 인보이스 #63467 그룹과 입고가 영구 분리), "아무 DRAFT 재사용" 로직이 그 잘못된 그룹을 계속 썼다 — 프로브 탓이 아니라 생략의 구조적 결과. **수정**: ① 타깃 = `det0.Invoice[]` 중 `PO_INVOICE_OK`+TaskID 인 인보이스가 **정확히 1개**일 때 그 TaskID(0개·2개+ = 중단 — 다중 인보이스 부분 출하 미지원) ② stock·put-away 의 **모든 쓰기에 TaskID 명시**(생략 경로 폐지) ③ **외부 그룹 가드**: 타깃 아닌 태스크에 라인이 있으면(비VOID, 상태 불문) 중단 — 승인돼 있으면 이미 재고라 재전송 시 이중 재고. 메시지가 조치를 지시("Cin7 에서 해당 그룹 라인 void/제거 후 재Apply") ④ dry-run steps 에 타깃 그룹(`Target I&R group: task … invoice …`)과 외부 그룹 경고 표시 ⑤ 회계(delta·승인 대상·존재 증명·배치)는 전부 타깃 그룹 스코프. "기본 그룹 TaskID==PurchaseID"(PO-01068 관찰)는 **미확인 · 의존하지 않음**. 상세 실측은 cin7-api `stock-write.md` 11번.
  - ⚠️⚠️ **실사고 (2026-08-07 PO-01094 첫 실전 Apply) — stage1 승인 건너뜀 → 존재 증명으로 재설계**: 첫 구현의 승인 대상 판정(`Status==="DRAFT"` 인 태스크만)이 **부재 증명**이라, Cin7 응답의 Status 가 예상 문자열로 안 읽히자 승인 루프가 **0회** 돌고 같은 잣대의 되읽기 가드도 통과 — "stage1 AUTHORISED" 를 거짓 기록하고 stage2 로 가 put-away 400("You need to authorise Stock Receiving first") 8건이 났다(인보이스 게이트 fail-open 과 같은 계열의 결함을 하루 만에 재생산). **수정**: ① 상태 비교 전부 `trim().toUpperCase()` 정규화 ② 승인 대상 = "AUTHORISED 도 VOIDED 도 아닌, **라인 있는** 모든 태스크"(상태 문자열 불문 시도 — 라인 없는 프로브 잔재는 수량 0 이라 무시+로그) ③ **stage2 진입 = 존재 증명**: 라인 있는 비VOIDED 태스크가 1개 이상이고 **전부 정확히 AUTHORISED 로 되읽힐 때만**, 아니면 fail-closed + **태스크별 Status 원문을 apply_note 에 JSON 그대로**(다음 실행이 곧 진단 데이터) ④ Cin7 무기록이므로 재시도 안전(stage0 의 SKU 별 delta 인식이 기존 라인을 건너뜀 — 중복 없음). ⚠️⚠️ **교훈 — 계획서는 검증이 아니다**: dry-run steps 문구는 buildApplyPlan 의 표시 전용이고 실행 경로와 독립이다(이번에 그 간극이 실증됨). **실행 경로 확인은 응답 로그 첫 줄 `PATH=advanced|simple`**(2026-08-07 사용자 조건 — 커밋 경로가 분기 직후 unshift). ⚠️ 부수 교훈: 미커밋 워킹트리에서 `functions deploy` 하면 어느 코드가 나갔는지 git 으로 확정할 수 없다(집·회사 2대) — PATH 로그가 그 보루이며, 배포 전 커밋이 원칙. **재개 회차 판정은 두 겹(둘 다 Cin7 되읽기)**: ① stage1 재전송 여부 = **SKU 별 수량 delta**(Status 무관 — AUTHORISED 라인도 인식, 부족분만 추가) ② stage2 진입 = **존재 증명**(위). 이미 승인된 문서에 재승인 시도는 하지 않는다(승인 대상 필터가 AUTHORISED 제외). **dry-run 계획도 Cin7 을 읽어 stage 상태를 표시한다**(표시 전용 GET, 실패해도 계획은 나감 — "Stage 1 ALREADY AUTHORISED … SKIPS stage 1 and runs stage 2 only") — 사람이 실행 전에 이번 회차의 범위를 본다. ⚠️ **`exported_base=0 + stock AUTHORISED` 는 어긋남이 아니다** — Advanced 의 exported_base 는 "선반 지정까지 끝난 양"이므로 그 조합은 "재고는 들어갔고 선반이 아직"의 정상 표현이고, stage2 성공 시 되읽기 검증 후 markExported 가 채운다(별도 정리 불요).
  - ⚠️⚠️ **Advanced Apply 의 하드 게이트 = 「승인된 인보이스가 정확히 1개」 — 0개·2개+ 모두 중단**(다중 인보이스 부분 출하 미지원). 위 실사고 2호 ①과 **같은 게이트이며 게이트가 둘인 것이 아니다** — 여기는 코드 좌표: 판정 헬퍼 `advInvoiceTargets`(`supabase/functions/receiving/index.ts` 569~572행 — `Status ∈ {AUTHORISED, PAID}`(`PO_INVOICE_OK`) **이면서** `TaskID` 보유) · 0개 throw 1233행 · 2개+ throw 1238행. 두 throw 모두 **Cin7 무기록**이라 정리 후 재Apply 가 안전하다.
  - ⚠️ **따라서 Advanced 가 Simple 보다 엄격하다** — Simple 은 Invoice First 게이트(인보이스가 승인 상태)만 통과하면 되지만, Advanced 는 거기에 **개수 1 + I&R TaskID 보유**까지 요구한다. **Advanced 경로에서 Apply 가 중단되면 이것을 가장 먼저 의심할 것**(인보이스 승인 자체는 됐는데 개수가 2 이거나 TaskID 가 없는 경우가 함정 — 화면만 보면 "승인됐는데 왜?" 로 읽힌다).
  - **Cin7 설정 `Default load advance purchase order`(모든 PO 를 처음부터 Advanced 로) 는 검토 중** — 동기는 Simple 의 인보이스/입고 수량 완전일치 제약(`cin7-api` 14번)을 없애 `Convert` 수작업을 제거하는 것. **판정 기준은 분할 인보이스 PO 의 비율**(위 게이트 때문에 그 PO 들은 Apply 자체가 불가). 정본: `docs/design/ledger-design.md` 4부 「검토 중 — Advanced PO 기본값」.
- **트랜스퍼 창고간(branch→branch) — 실측 확정 (2026-07-25, TR-03260/03261)**: 실제 IN TRANSIT 은 From/To 가 **bin 이 아니라 warehouse**(FromLocation "Asung Trading Inc." → ToLocation "Asung - Edmonton"), InTransitAccount 있음, **라인에 bin 필드 없음**(ProductID/SKU/TransferQuantity/BatchSN/ExpiryDate…). 확정 3가지:
  - **완료 = `PUT /stockTransfer` `{TaskID, Status:'COMPLETED', From, To, CostDistributionType, InTransitAccount, DepartureDate, CompletionDate, Lines, SkipOrder:true}`** → 200.
  - ⚠️⚠️ **정정 (2026-07-28, TR-03267 실측) — 완료 PUT 의 `TransferQuantity` 변경은 무시된다.** 이전 기록 *"수량 초과 완료 허용: 1개로 보낸 트랜스퍼를 라인 3개로 바꿔 완료해도 200 → 들어온 대로 쓰기 가능"* 은 **틀렸다.**
    - 정정 근거(신규 IN TRANSIT TR-03267): SENT 에 변경값이 정확히 실려 나가고 PUT 200 이 떨어지지만 **되읽으면 원본 그대로다.** `AS93113` 원본 2 → 요청 4 → **저장 2** ❌ / `AS92700` 원본 4 → 요청 2 → **저장 4** ❌ → **증가·감소 양방향 모두 무시.** 코드 버그가 아니라 API 제약이다(추정: 창고간 트랜스퍼는 발송 시점에 재고가 in-transit 계정으로 넘어가므로 거기 없는 수량을 완료로 받을 수 없다).
    - 왜 틀린 기록이 남았나 — **HTTP 200 만 보고 저장값을 되읽지 않았고**, PO stock received 의 초과 허용(이쪽은 **사실**)과 혼동됐다. 📌 **교훈: 쓰기 실측은 200 이 아니라 GET 으로 되읽은 값이 근거다.** (규칙 27 R11)
    - → **트랜스퍼 완료 수량 = 보낸 수량 확정.** 실물 차이 처리는 규칙 20 의 트랜스퍼 예외 참조. **PO 경로는 그대로 — received 그대로 쓴다.**
  - ⚠️ **완료 시 bin 지정 불가 → 착지 지점 2가지** (트랜스퍼 헤더 To 에 따라): (a) To=**창고 GUID** → **bin 없이** 창고에 재고가 뜸(Cin7 재고화면 BIN 칸 공백). PO 같은 "received 화면에서 bin 지정" 단계가 **없음**. (b) To=**특정 bin GUID** → 그 bin 에 전량(예 에드먼튼 EZ010101 — 과거 수동 워크플로의 **임시 집결지**, 실제 보관자리 아님. Cin7 WMS 가 느려 한 곳에 몰아 받고 나중에 풋어웨이하던 편법). ⚠️ **착지 정책은 2026-07-31 부로 (a) 창고만 지정으로 변경 — 규칙 40**(집결 bin 폐기).
  - **풋어웨이 = `POST /stockTransfer` `{Status:'COMPLETED', From: <트랜스퍼의 To GUID>, To: <실제 bin GUID>, Lines:[{SKU, TransferQuantity}], SkipOrder:true}`** → 200. **From 을 창고 GUID 로 주면 "bin 없는 재고"를 꺼내 옮겨줌**(실측: bin 없던 1개 → EB010204, 재고 0/23→24 확인). (b) 케이스는 From=집결 bin GUID. 즉 **From 은 항상 `det.To`** 로 두면 두 경우 다 동작.
- **트랜스퍼 리시빙 워크플로 = PO 와 동일 (2026-07-25 사용자 결정)**: 받기→풋어웨이(bin 지정)→Apply. "즉시 완료로 재고 먼저 노출"(편법)은 **채택하지 않음** — 이유: 흐름 일관성, 풋어웨이를 뒤로 미루는 나쁜 습관 방지, "보이는데 어디 있는지 모르는" 재고 구간 제거. Apply 가 뒤에서 ⓪discrepancy 선기록 →①**보낸 수량 그대로** COMPLETED →②**캡된** bin 이동(+`exported_base` 체크포인트) →③receipt PATCH 를 순차 수행 (2026-07-28 개정 — 규칙 20 트랜스퍼 예외).
  - ⚠️ **bin 이동 수량은 `min(received_base, expected_base)` 로 캡한다 — 안 하면 400.** 완료 후 착지 지점에 실제로 앉는 건 **보낸 수량**이므로 초과분은 Cin7 에 존재하지 않는다(예 APR15412 expected 24 / received 48 → 24 만 이동). off-transfer SKU 는 Cin7 보유 0 → **bin 이동 제외**, `recv_off_po` discrepancy 로만 남긴다.
  - ⚠️ **재개 경로**: 원 TR 이 **이미 COMPLETED 인데 bin 이동이 안 끝난** receipt 은 ①PUT 을 건너뛰고 ②부터 재개한다(`plan.mode="resume"`). 예전 plan 검증이 "IN TRANSIT 이어야 함" 뿐이어서 TR-02935 가 **영구히 큐에 갇혔다**. `exported_base` 가 찬 라인은 재이동하지 않는다.
  - ⚠️⚠️ **bin 이동 한 건의 실패가 나머지를 막지 않는다 — 부분 성공 + 재시도 (2026-07-28, TR-02935 재개 Apply 실측)**: discrepancy 선기록은 통과했는데 **첫 bin 그룹의 400 하나로 전체가 중단**됐다 — `POST /stockTransfer` → 400 `"Available quantity for product (SKU: AS97745 …) is 0.0000000000, cannot transfer 2"` (From = 집결 bin EZ010101 `b997fb39-…`). **344 라인 중 1 건이 나머지 143 개 bin 이동을 통째로 막았다.**
    - ⚠️ **이 400 은 버그가 아니라 정상적으로 발생하는 운영 상황이다** — 리시빙 완료(13:54)와 Apply 사이의 시차 동안 그 재고가 판매 픽킹 등으로 **이미 움직일 수 있다**. "한 건 실패"를 전제로 설계해야 한다.
    - → **그룹 실패는 수집만 하고 다음 그룹으로 진행**(루프에서 throw 금지 — 되돌릴 수 없는 구간이므로. 규칙 27 R12·R10). 수집 형태 `failed_moves:[{bin, skus[], qty, http_status, cin7_error}]` — `cin7_error` 는 Cin7 응답의 `Exception` 원문("Available quantity … is 0")이라 사람이 바로 원인을 안다. 응답 최상위 + `apply_note` 에 `failed_moves(N): [...]` 로 노출.
    - **부분 성공에서도 receipt PATCH(`applied_at`)까지 도달한다** — 실패해도 receipt 이 큐에 갇히고 discrepancy 만 남는 상태를 만들지 않는다. 대신 **실패가 하나라도 있으면 눈에 보이게**: admin History 의 CIN7 열이 `✓ Applied` 대신 **`⚠ Applied (N bins failed)`**, Apply 목록엔 그대로 남고 버튼이 `Retry failed bins`. **판정 기준은 `failed_moves.length > 0`** (log 의 WARN 문자열 아님).
    - **재시도**: 실패 그룹은 `exported_base` 를 안 찍으므로 사람이 Cin7 에서 재고를 바로잡고 **다시 Apply 하면 실패분만** 재시도된다. 이를 위해 `buildApplyPlan` 이 **`applied_at` 이 있어도 재개를 허용**한다 — 게이트 두 겹: ①`apply_note` 에 `failed_moves(N)` N>0 (트랜스퍼만) ②실제로 옮길 그룹이 남아 있음. `plan.mode="resume"` · `plan.retry=true` · 원 TR 은 COMPLETED 이므로 PUT 은 계속 SKIP · discrepancy 선기록은 `ignore-duplicates` 로 안전 재실행. ⚠️ **`failed_moves(N)` 포맷은 EF 정규식과 admin.html 이 공유한다 — 한쪽만 바꾸지 말 것.**
    - ⚠️ **재고 부족은 자동 보정하지 않는다** — 조정은 사람이 Cin7 에서(규칙 27 R13). ✅ **PO 경로에도 같은 보호를 2026-07-31 이식**(전체 throw 제거 — 아래 "PO 경로 이식" 항목·규칙 27 R10).
- ⚠️⚠️ **Apply 는 청크로 돈다 — 그룹 수(`APPLY_MAX_GROUPS = 12`) + 시간 예산(`APPLY_TIME_BUDGET_MS = 20000`) 이중 가드, 먼저 걸리는 쪽에서 회차를 끊는다 (2026-07-31 v2, 규칙 30-2 해소)**:
  - **원칙: 회차는 반드시 완주해야 한다 — 완주하지 못하면 기록(apply_note)이 남지 않아 원인 추적이 불가능하고, Stop 도 회차 경계에서만 동작하므로 듣지 않는다.** 회차가 많아지는 것보다 완주하지 못하는 게 훨씬 나쁘다.
  - **상한 30 은 부족했다(실측)**: 1차 실측(TR-03144 327라인/100+그룹 — 30~40 그룹 부근 타임아웃 / TR-02935 144그룹 동일)으로 30 을 잡았으나, **배포 후에도 첫 회차조차 완주하지 못했다** — `exported_base` 는 210→225→250 으로 전진(bin 이동은 됨)하는데 `apply_note` 는 계속 null(종료부 미도달). 실패 그룹도 Cin7 왕복+sleep 을 소비하므로 성공 수만으로는 회차 시간을 예측할 수 없다 → **12 로 인하 + 시간 가드 추가**. 시간 예산은 **요청 시작(t0)부터** 재고(buildApplyPlan·PUT 포함 — EF 한도가 보는 것도 요청 전체), 판정은 **반드시 Cin7 POST 앞**(그룹 루프 머리)에서 — 반쯤 옮긴 그룹을 만들지 않는다.
  - **가드 도달 = 예외가 아니라 정상 종료.** 응답 `{done:false, groups_total, groups_moved, groups_remaining, lines_moved, lines_total, failed_moves, rate_limited, stopped_by, note_saved}` — 그룹 카운트는 "Cin7 POST 를 시도한 그룹(성공+실패)". **`stopped_by: "groups"|"time"`** 은 어느 가드가 걸렸는지(429 만이면 null + `rate_limited`) — apply_note 에도 남겨 다음 상한 조정의 근거로 쓴다. `applied_at` 은 **모든 그룹이 끝난 회차(done:true)에만** 찍고, **`apply_note` 는 매 회차 갱신**(진행 줄 + 계약 표식 **`groups_remaining(N):`** — `failed_moves(N):` 처럼 EF 정규식·admin.html 이 공유, 한쪽만 바꾸지 말 것). 중간 회차 receipt 은 Apply 목록에 남고 버튼이 `Continue apply`.
  - **종료부(회차의 마지막)는 가장 값싸고 절대 죽지 않는다**: apply_note 갱신 + 응답 반환뿐 — Cin7 호출·무거운 재조회 금지. `lines_moved` 는 DB 재조회 없이 "회차 시작 시점 exported 합(plan.progress) + 이번 회차 markExported 수"로 계산. **receipt PATCH 가 실패해도 응답은 반환한다**(WARN + `note_saved:false` — 기록을 못 남기는 것보다 응답조차 못 주는 게 나쁘다; done 회차였다면 다음 Apply 가 DB 재조회로 수렴해 PATCH 만 재시도).
  - **청크 경계에서 이중 이동 없음**: 성공 그룹만 `exported_base` 가 찍히고, 미처리 그룹은 다음 회차 buildApplyPlan 의 DB 재조회(`pending_base>0`)가 다시 집는다 — 재시도 경로와 같은 메커니즘. `exported_base` 체크포인트·min 캡·discrepancy 선기록·COMPLETED 재개·(a)/(b) 착지 분기는 청크 경계와 무관하게 그대로.
  - **admin 자동 반복**: `done:false` 면 스스로 재호출(회차 사이 dry-run 없음), 진행률은 EF 응답 필드 그대로(`Applying… 210 / 327 lines · 58 bin groups left`) + **Stop 버튼**(회차 경계에서 멈춤 — 체크포인트까지 안전, 재개 가능). `beforeunload`·재진입 차단(applyBusy)은 반복 전체 구간 유지. **무한 루프 가드는 v3 에서 정교화** — 아래 참조(예전 `groups_moved===0` 판정은 실패 그룹이 진행을 가로막는 실측 사고의 공범이었다).
  - **429 는 failed_moves 에 넣지 않는다** — `cin7()` 백오프 재시도(1.5s→3s, 상한 2회) 소진 시 그 회차만 조기 종료(`rate_limited`), 잔여는 다음 회차. ~~그룹 간 sleep 300→150ms~~ → ⚠️ **2026-08-10 정정: 배치 간 1200ms(`TRANSFER_GROUP_SLEEP_MS`)** — 150ms(=분당 400콜)는 FREE 티어 대시보드 완화용이었지 Cin7 한도(60 calls/60s) 기준이 아니었고, TR-03259(176그룹)에서 9초 만에 한도를 소진해 매 그룹이 429 백오프를 타며 그룹당 3콜·6.7초가 됐다(아래 병렬 배치 항목). ⚠️ 429 는 **연속 실패 카운트(아래 v3)에도 넣지 않는다** — 넣으면 rate limit 가 실패로 둔갑해 멀쩡한 bin 이 격리된다.
  - ⚠️⚠️ **실패 그룹이 미처리 그룹을 가로막지 않는다 (2026-07-31 v3 — TR-03144 실측)**: 청크 v2 배포 후에도 진행이 멈췄다 — 실측 apply_note `CHUNK - 0 group(s) moved, 3 failed · stopped_by=time`: **실패 그룹 3건만으로 20초 예산을 전부 소진**(Cin7 400 응답이 느리고 한 그룹에 SKU 5~7개, 예 EU060503)했고, 실패 그룹이 plan.groups 앞쪽이라 **매 회차 그것들을 먼저 시도하고 끝나** 남은 46개 미처리 그룹이 영구히 진행되지 못했다(`groups_moved===0` → admin 무한루프 가드가 자동 반복도 중단). 실패 사유는 전부 `Available quantity … is 0` — **사람이 Cin7 재고를 고치기 전엔 재시도해도 영원히 실패한다.** 조치 3개:
    - **① 순서** — buildApplyPlan 이 그룹을 **미시도 먼저, 실패 이력(연속 실패 수 오름차순) 뒤로** 정렬 → 매 회차 실제 전진(`groups_moved>0`)이 생긴다. 순서 변경은 이중 이동과 무관: "무엇을 옮길지"는 매 회차 DB 재조회(`pending_base>0`)가 정하고 성공 그룹만 `exported_base` 가 찍힌다 — 순서는 시도 순서일 뿐.
    - **② 격리** — 같은 bin **연속 `APPLY_QUARANTINE_FAILS`(3)회 실패** 시 자동 재시도에서 제외하고 `permanently_failed` 로 분류("N bin(s) need manual fixing in Cin7"). **`groups_remaining` 에 세지 않으므로** 격리만 남으면 `done:true` 로 정상 종료(applied_at 찍힘). ⚠️ **영구 제외가 아니다** — admin `Retry failed bins`(`&retry_failed=1`, dry-run + **첫 commit 회차에만** 부착)가 카운트를 리셋해 다시 시도한다(자동 회차마다 붙이면 격리에 영영 도달하지 못한다).
    - **③ 실패 시간 상한** — 회차당 실패 이력 그룹 시도에 `APPLY_FAIL_BUDGET_MS`(6초)만 허용, 초과분은 다음 회차로(정렬상 실패 그룹은 맨 뒤라 여기 걸리면 남은 것도 전부 실패 이력). 400 은 재시도 없음 — `cin7()` 백오프는 429 전용(그대로 유지할 것).
    - **④ 목적지 되읽기 회복 — checkpoint repair (2026-07-31, TR-03144 실측)**: `Available quantity … is 0` 400 은 두 가지다 — ⓐ진짜 재고 이탈(사람이 고칠 일) ⓑ**이전 회차가 Cin7 POST 와 markExported PATCH 사이에서 죽은 잔여물**(Cin7 엔 옮겨졌는데 `exported_base`=0 → 재시도 → 재고 없음 400 → 격리). 이 400 **패턴에만**(다른 400 은 조회 무의미) 목적지 bin 을 `GET /ref/productavailability?Sku=` 로 되읽어(R11 — 근거는 되읽은 값; SKU 정확 일치 + 창고 `normWarehouse` + Bin 정확 일치, **OnHand 합** — Available 은 판매 배정 차감이라 도착 재고를 놓친다) **옮기려던 수량(pending_base) 이상이면** 그 라인의 `exported_base` 를 기록하고 완료로 간주한다. ⚠️ 오판 방지: SKU 단위·"이상" 비교(기존 재고 bin 은 더 많을 수 있음)·조회 실패/응답 잘림(Total>행수)/수량 부족이면 실패 유지·그룹 내 **전 라인 확인 = 그룹 완료**(일부만이면 그 라인만 기록, 그룹은 실패)·시간 예산(20초/실패 6초) 부족 시 조회 생략(회차 완주 최우선). 회복 건수는 응답·apply_note 의 `checkpoint_repaired: N`(측정용 — 계약 마커 아님)으로 남는다. 근본 원인(타임아웃)은 청크 v3 로 해소됐으므로 이 경로는 **잔여물 정리 + 드문 엣지 대응**이다 — v3 이후에도 N 이 계속 나오면 다른 원인 신호(규칙 27 R10).
    - **연속 실패 카운트는 apply_note 의 `fail_counts:{"BIN":n}` 마커**로 회차 간 이월(성공=삭제·실패=+1·미시도=이월). 새 컬럼 없음 — `exported_base` 는 사실 기록이라 불가침(규칙 30-4)이고 계약 마커 패턴이 이미 있어서. ⚠️ **`failed_moves(N):` 뒤의 JSON 은 900자에서 잘려 bin 목록 근거로 쓰지 말 것**(이 컴팩트 마커가 따로 있는 이유). **계약 마커는 이제 4개** — `failed_moves(N):`·`groups_remaining(N):`·`permanently_failed(N):`(격리, 재시도 게이트 + admin 표시)·`fail_counts:{...}`(EF 회차 간 전용) — EF·admin.html 이 공유, 한쪽만 바꾸지 말 것.
    - **admin (v3)**: 버튼 우선순위 = **미처리 그룹이 있으면 `Continue apply`**(실패분은 정렬 뒤에서 함께, 격리분 제외) / **미처리 0 이고 실패만 남으면 `Retry failed bins`**. 무한루프 가드 = `groups_moved===0 && groups_tried===0` 2회 연속(429 벽 등)일 때만 중단 — **시도가 있었다면 실패 카운트가 전진해 격리로 반드시 수렴**하므로 계속 돈다(회차 상한 20→30, EF 응답에 `groups_tried`·`permanently_failed` 추가).
  - ⚠️⚠️ **병렬 배치 (2026-08-10 배포 · TR-03738 실전 검증 — `TRANSFER_PARALLEL_BATCH = 4`)**: 트랜스퍼 그룹 루프가 **파티션(landing/빈 라인/격리/GUID 판정 선완결) → 미시도(prevFails=0) 최대 4개 배치 병렬 발사 → 실패 이력(prevFails>0) 1개씩 순차** 로 바뀌었다. 발사/정산 = `fireGroup`(POST + 성공 시 **즉시** markExported, 절대 throw 없음) / `settleGroup`(429·checkpoint repair·failCounts — 종전 catch 본문) 클로저. **불변 규칙 — 어기면 재고가 틀어지거나 예산이 터진다**:
    - `Promise.allSettled` 만 — **`Promise.all` 금지**(한 건의 거부가 나머지 3건 결과를 버린다).
    - **한 배치 안에 같은 `base_sku` 금지** — 출발지가 같은 착지 재고 한 곳이라 동시에 빼면 `Available quantity … is 0`. 겹치는 그룹은 다음 배치 선두로 defer(첫 그룹은 항상 들어가므로 무한 루프 없음).
    - `chunkGuard` 는 **배치 단위 · 발사 직전에만** — 배치 중간에 걸리면 반쯤 발사된 배치가 생긴다.
    - **실패 이력 그룹은 배치에 넣지 않는다** — `APPLY_FAIL_BUDGET_MS` 회계가 그룹 단위이고 격리 전까지 최대 3개뿐이라 병렬 이득이 없다.
    - checkpoint repair(`binOnHand` 되읽기)는 배치 발사가 **전부 끝난 뒤 순차로만**(안쪽 `sleep(150)` 유지) — 배치 안에서 중첩되면 예산이 터진다.
    - ⚠️⚠️ **`a += await f()` 금지** — await 앞에서 `a` 를 읽어 배치 4건 동시 실행이면 lost update(구현 중 `linesMovedNew` 에서 실제 발견·수정 — `const n = await f(); a += n;` 형태로). **순차→병렬 전환 시 이 패턴을 전수 점검할 것.**
    - **배치 크기 4 를 늘리지 말 것**(N=6/8 미측정 — 4 가 유일한 측정된 안전점) · **APPLY_\* 상수 무변**: ⚠️ 시간 예산 20초는 잠금 만료 90초와 "4.5배" 관계 — 한쪽만 올리면 회차 중 다른 Apply 가 만료 탈취해 **재고 이중 이동**. ⬜ 20초의 유래 자체는 어디에도 기록이 없다(EF 한도 역산 아님 — 미해결).
    - 📌 **근거 실측 (2026-08-10 — 인용용, 전문·타임라인은 `docs/sessions/2026-08-10-transfer-parallel-and-clamp.md` 3장)**: ① Cin7 stockTransfer POST 1건 = **6~9초(평균 7.9초, 표본 5)** — **진짜 병목은 한도가 아니라 콜당 지연**이다(순차 176그룹 = 21분, 종전 사용량은 분당 9콜 = 한도의 15%. 처리량 계산에 지연을 빼면 안 된다). ② GAS 프로브(Cin7ParallelProbe): 순차 4건 31.5초 vs `fetchAll` 동시 4건 8.1초 = **3.9배**, TR 번호 역전 배정 = 큐잉 없음 교차 확인 — ⚠️ 측정 설계는 실제 Apply 와 같은 "출발지 1 → 목적지 4 · SKU 전부 다름"으로(목적지 1로 모으면 bin 잠금 때문에 직렬로 보일 수 있다). ③ **한도 60/60 은 Application 키 단위**(Cin7 KB 확인 — 2026-08-10 부터 GAS 는 별도 키 `Asung GAS`. ⚠️ hello 폴링과 receiving Apply 는 여전히 한 키 공유 — Supabase secrets 는 프로젝트 전체 공유, 분리는 `_shared/cin7.ts` 수정 별건. ⬜ 키별 과금 여부는 `MySubscription` 의 Integration 수량으로 확정). ④ **hello 폴링 1회 = Cin7 52콜**(5분마다 → 하루 ~15,000콜 · 상세 50건×250ms ≈ 25초 버스트가 60/60 창을 통째로 소진 — **429 의 진짜 원인**, 백로그 17번). ⑤ **회차 경계 45초 공백**은 EF 밖(booted 19ms + 같은 초 첫 콜 — 백로그 18번. → ⚠️ **2026-08-12 재현 안 됨 — 경계 10초 실측**, 18번을 관찰 대기로 하향). ⑥ 진단 도구 = **Cin7 API Log**(Integration→API→앱→Log · 보관 5일 · 요청/응답 본문 열람) — ⚠️ **429 로 거부된 요청은 안 남는 것으로 보인다**: "Success 만 있다"를 "429 가 없었다"의 근거로 쓰지 말 것.
    - ✅ **실전 검증 닫힘 (2026-08-12 Cin7 API Log 실측 — 「검증 대기」에서 내림 · 저녁 문서 B절)**: 근거 셋 = ① **POST 4건이 같은 초에 발사**(17:57:56 ×4 · 18:18:20~21 ×4 등 — 여러 트랜스퍼에서 반복 확인) ② **한 회차 12그룹 = `APPLY_MAX_GROUPS` 상한 달성**(어제 예상 "8~12그룹" 실현) ③ **TR 번호 역전**(TR-03533: ED020701=3932 → EB020303=3931) = 큐잉 없음 — 어제 프로브와 같은 지문. 배치 간격 8~10초 = POST 6~9초 + sleep 1.2초(설계 그대로). 당일 4건(TR-03531·32·33·34 — 그룹 3~11 · 라인 최대 197) 전부 `ALL GROUPS DONE`·전량 exported·한 회차 완주(시간 예산 무접촉). ⬜ 176그룹급 다회차 회전은 안 겪었으나 **12그룹 상한 달성 + 병렬 지문 확인으로 충분하다고 판단해 닫는다.** ⚠️ 부수: `RETRY of a partial apply from ?` 표시 결함이 넷 다 재현 — 흔한 경로 확인(백로그 22번).
  - ✅ **PO 경로 이식 (2026-07-31)** — 청크 이중 가드·`exported_base` 체크포인트·실패 수집/격리(①순서 ②격리 ③실패 시간 상한)를 PO 경로에도 적용. 가드 판정은 공용 헬퍼 **`chunkGuard()`**(상수·판정·순서 트랜스퍼와 동일 — 그룹 12/시간 20초/429/실패 6초, Cin7 POST **앞** 판정). 재개 게이트(`retryFailed`)의 `transfer` 제한도 풀어 PO 도 `failed_moves(N)`/`groups_remaining(N)`/`permanently_failed(N)` 마커로 재개한다.
    - ⚠️ **`exported_base` 의 의미가 소스별로 다르다**: 트랜스퍼 = "목적지 bin 으로 옮긴 양" / **PO = "Cin7 stock received 문서(DRAFT)에 실은 양"**(authorize 여부와 무관). admin Stats "Moved in Cin7" 지표는 `source_type==="transfer"` 필터라 **영향 없음**(각주에 명시해 둠).
    - ⚠️⚠️ **authorize 게이트 (PO 고유 — 1회 제약이 가장 중요)**: authorize 는 Simple PO 에서 **한 번뿐**이고, 일부 bin 이 빠진 채 authorize 하면 빠진 수량을 API 로 채울 방법이 사라진다 → **미처리(`groups_remaining`)·실패(`failed_moves`)·격리(`permanently_failed`)·스킵(bin GUID)이 하나라도 있으면 authorize 하지 않고 DRAFT 로 남긴다**(기존 "스킵 시 DRAFT 유지"를 청크 경계·실패·격리까지 확장). authorize 는 **그룹 루프(청크) 밖** — 모든 bin 이 문서에 실린 마지막 회차에 딱 한 번 시도한다(회차마다 시도하면 1회 제약 위반). 노출: apply_note "Cin7 document left as DRAFT — N bin(s) pending" + admin 배지 `Cin7 DRAFT — N bin(s) pending` + 응답 `authorized: true|false|null`(null=보류/트랜스퍼). authorize 실패는 기존 방침 그대로(DRAFT 유지 + WARN — Cin7 화면 수동 authorize).
    - ⚠️ **되읽기 회복(위 ④ checkpoint repair)은 PO 미적용** — PO 는 "bin 이동"이 아니라 "입고 문서 작성"이라 되읽기의 의미가 다르다(백로그 6번). 대신 "POST 성공 후 체크포인트 누락" 잔여물의 재전송은 **400 `Cannot add duplicate value` 로 시끄럽게 거부**된다(실측 — cin7-api 스킬 stock-write.md: 같은 Product+Location 이 이미 stock received 에 있으면 발생) → 조용한 이중 계상은 구조적으로 없다. 이 에러 = 그 라인은 이미 DRAFT 에 있다는 뜻 → Cin7 화면에서 확인 후 거기서 마무리(WARN·admin 알림에 안내 포함).
    - 라인 재전송은 **all-or-nothing**(부분 exported 는 전량 pending 취급 — 부분 수량은 factor 로 안 나눠떨어질 수 있고, 중복은 어차피 400). POST 간 sleep 은 **400ms 유지**(트랜스퍼 150ms 와 다름 — 규칙 21 의 "콜 간 300~400"). 잔여 엣지: authorize 성공 직후 receipt PATCH 전에 EF 가 죽으면 다음 회차가 authorize 를 재시도해 400 (WARN "may already be AUTHORISED") — 문서는 이미 AUTHORISED 이므로 Cin7 에서 상태만 확인.
- **이중 반영 방지 (2026-07-24 강화)**: `wms_receipts.applied_at` 있으면 Apply·열기·재개 모두 거부. **한 PO = receipt 1개 강제**: startPo 가 그 PO 의 기존 receipt 전체 조회 → applied 있으면 "이미 받음" 차단, 미완료 있으면 이어받기(새로 안 만듦). 예전엔 `neq status completed` 만 봐서 applied 된 PO 에 새 receipt 이 중복 생성되던 버그. factor 로 안 나눠떨어지는 수량은 에러 차단. Apply 성공 시 status='completed' 명시(applied 인데 in_progress 로 꼬이는 것 방지).
- **자동 실행 강도**: 현재 = 매니저 admin 게이트(dry-run 계획 confirm → commit). 신뢰 쌓이면 작업자 완료 시 자동으로 전환 예정(EF 호출 위치만 이동).
- 쓰기 검증 도구: `WmsTransferWriteTest.gs`·`WmsPoStockWriteTest.gs` (System_Automation, DRY_RUN 게이트 패턴 — 새 쓰기 검증 시 재사용).
- 📌 **TR-02935 착지·수량 실측치와 Apply 운영 규칙(실행시간 예산·수동 이동 충돌·체크포인트 불가침)은 규칙 30** · **bin↔bin 이동 화면 설계는 규칙 33** · **재고 대조 리포트는 규칙 32**.

## 규칙 22 — 배터리 최적화: heartbeat 제거 → 스캔 이어받기 (⚠️ 2026-07-24)

태블릿 배터리 소모 이슈. 진단: HTML 자체가 아니라 (1)화면 상시 켜짐(디스플레이, 최대) (2)realtime presence 웹소켓 (3)20초 heartbeat 타이머 (4).live 펄스 애니. **Wake Lock 은 없음**(화면 설정 그대로 먹음 — 숨은 주범 아님).

- **heartbeat 완전 제거** (picker/packer): `HB_MS`/`beatOnce`/`hbTimer`/setInterval 삭제 → **정지 시 네트워크·CPU 0.** `startHeartbeat`/`stopHeartbeat`/`idleMin`/`staleISO` 는 no-op 스텁으로 남겨 잔여 호출 안전.
- **realtime presence 는 유지** (사용자 결정 — 생산성/LIVE NOW 우선). presence 는 웹소켓 이벤트라 heartbeat 타이머보다 가벼움.
- **heartbeat 의 원래 목적 = "열어만 두고 방치된 오더가 남에게 안 보이는 문제" 방지.** 하지만 픽리스트를 **물리적으로 인쇄**해 드는 구조라 소유권은 종이가 보증 → 상시 heartbeat 불필요. **대체 = 스캔 이어받기**: 픽리스트 스캔 시 그 오더가 이미 남이 in_progress 로 잡았으면 "X 가 열어둠, 이어받기?"(진행분 보존) → `assigned_to=me` UPDATE. (picker `scanTakeover`, packer `scanTakeoverPack`). 대기목록은 순수 pending 만(시간기반 abandoned 제거).
- **admin BATCH ACTIVITY active/idle → presence 기반** (`fresh(t)=liveBatchSet().has(t.batch_label)`). heartbeat_at 시간 판정 폐기. 🟢 active(open on screen) / 🟡 away(screen closed). **LIVE NOW 스트립은 원래 presence 라 무관 — 그대로 유지.** 범례도 idle→away 로.
- **pg_cron reaper `wms_reap_stale_claims()`**: 느슨한 백업만(work_started=false 인 유령만 해제). heartbeat 없으니 interval 넉넉히(현재 2분 → 권장 3~10분). 스캔 이어받기가 주 해결책이라 사실상 보조.
- `heartbeat_at` 컬럼은 DB 에 잔존(안 읽고 안 씀) — 나중에 drop 가능.
- ⚠️ **"종이가 소유권을 보증한다" 전제가 깨지는 경우와 그 가드는 규칙 28** 참조(종이는 보드로 돌아갔는데 화면은 열려 있는 상태).

---

## 규칙 23 — Hold 이어가기(held_by) · 픽리스트 Reference (2026-07-25)

- **held_by (Hold 한 사람에게 우선 노출)**: Hold 는 `assigned_to=null, status=pending` 으로 풀어 **누구나 이어받게** 두되 **`held_by=me.name`** 을 남긴다. picker/packer 목록 맨 위에 **"⏸ Resume your held batch"** 강조 섹션(held_by=나 인 pending). claim 시 `held_by=null` 로 정리. **서버 저장이라 화면 닫거나 다른 태블릿에서 로그인해도 보임**(브라우저 로컬은 복귀 시나리오에 부적합 — 아티팩트 localStorage 금지도 있음). 여전히 대기 풀에 있으므로 급하면 남도 집을 수 있음(= "내 것 잠금" 아님, 종이 픽리스트가 소유권). SQL `wms_held_by.sql`(pick_tasks/pack_tasks/waves 에 held_by). ⚠️ **Hold 를 눌러도 그 사람의 화면은 계속 열려 있고 계속 쓸 수 있다 — 소유권 가드는 규칙 28**(`assigned_to=null` 도 프리즈 대상). **2026-08-07 부터 Hold 의 쓰기(라인 flush + 플립)는 RPC 한 트랜잭션**(`wms_hold_pick`/`wms_hold_pack` — 규칙 9 Hold RPC 항목, ⚠️ 현장 미검증). held_by 를 남기는 의미는 불변 — 플립과 held_by 기록이 원자가 됐을 뿐.
- **픽리스트 Reference**: 화면 Cin7 "Reference"(예 `WDC-20260723`, 고객 발주번호) = **API `CustomerReference`** (기존 실측 주석 확정: Comments=`Note`, Shipping notes=`ShippingNotes`, Reference=`CustomerReference`). 폴링 EF(`hello`)가 `extractReference(d)` 로 `wms_orders.reference` 저장 → manager 픽리스트·**wave 픽리스트 둘 다** Order 줄 아래 인쇄(값 없으면 줄 생략). SQL `wms_order_reference.sql`. ⚠️ 컬럼 추가를 EF 배포보다 먼저(없으면 insert 실패). 기존 오더는 null → 신규 유입분부터 인쇄됨.

## 규칙 24 — 리시빙 동시 작업: 한 PO 를 여러 명이 나눠 받는다 (⚠️ 2026-07-27)

**배경**: 이 기능은 설계된 게 아니라 **의도치 않게 가능했고 현장에서 정착됐다**(큰 컨테이너를 두 사람이 SKU 나눠 스캔). 안전성 감사 후 아래 4개를 고쳐 **정상 기능으로 승격**했다. 되돌리면 남의 작업이 조용히 사라진다.

- **저장 모델 = 라인 단위 (`unconfirmed` Map + `writeChain`)**:
  - `unconfirmed`(line.id → {kind:qty|putaway|all})는 **"쓰려 했지만 1행 반영을 확인받지 못한 라인"만** 담는다. ⚠️ "건드린 전부(touched)"를 담으면 안 된다 — 이미 저장된 라인을 Hold/완료 때 다시 써서 그 사이 남이 바꾼 값을 스테일 스냅샷으로 되돌린다. 정상 경로에선 이 집합이 **비어 있다**.
  - **성공 판정 = `.select()` 반환 1행 확인.** ⚠️⚠️ PostgREST 는 **0행 매치도 `error=null`/204** 로 돌려준다. 그걸 성공으로 오판하면 라인이 `unconfirmed` 에서 잘못 빠져 **안전망이 사라진다**. 0행이면 `lineGone(id)` 로 갈라 판정: 삭제됨(매니저 off-PO reject) → 로컬에서도 `dropLine` / 그 외 → conflict 로 남겨 재시도.
  - **`writeChain` = 라인별 PATCH 직렬화.** 같은 라인의 쓰기가 서로 추월하면 늦게 도착한 옛 값이 DB 에 남고, 전체 배열 덮어쓰기를 없앤 뒤에는 그걸 뒤늦게 바로잡아 줄 코드가 없다. **라인별**이라 느린 라인이 다른 라인을 막지 않는다. 보낼 필드(`patchFor`)는 **호출 시점의 라인 값**에서 만들어 큐에 밀린 쓰기가 자동으로 최신값이 되게 한다.
- **⚠️⚠️ 파생 원칙 — `unconfirmed` 안전망이 있는 경로에서는 저장 실패 시 로컬 값을 되돌리지 말고 표시하라 (2026-08-04 확립).** 되돌리면 `flushUnconfirmed` **재시도가 되돌린 값을 써서** 작업자가 실제로 한 작업이 영구히 사라진다 — 이 모델에서는 **로컬이 최신이고 서버 반영은 flush 의 책임**이므로 로컬을 건드리는 것이 곧 데이터 파괴다. 대신 그 행에 **`NOT SAVED`(빨강) + 토스트**를 남겨 화면이 성공을 가장하지 않게 한다.
  - 실제 사례: 풋어웨이 bin 일괄 완료(`savePutaway`/bin 일괄) — 지시는 "실패 시 되돌려라" 였으나 위 이유로 **유지 + 표시**로 구현했다. `putawayFailed` Set 이 표시 전용이고 ⚠️ **`unconfirmed` 로 대신하면 안 된다** — 그건 쓰기 **전**에 채워지므로 정상 저장에서도 매 탭 번쩍인다.
  - ⚠️ **반대 방향(규칙 28 프리즈)과 혼동하지 말 것.** 프리즈는 소유권을 잃어 **내 로컬이 스테일임이 확정된** 상태라 로컬을 버리는 게 맞다. 여기는 소유권이 그대로이고 실패 원인이 네트워크뿐이라 로컬이 유일한 진실이다. **판단 기준 = "내 로컬이 최신인가"**, 실패 자체가 아니다.
- **⚠️ Hold / finishReceipt 는 `lines` 전체 배열을 덮어쓰지 않는다.** `flushUnconfirmed()`(실패분만 재시도) + `wms_receipts` **헤더 patch** 만. 예전의 "최종 라인 저장(authoritative)" 전체 루프가 **같은 receipt 를 함께 받던 사람의 수량·bin·placed 를 전부 되돌리던 원인**이었다. **이 루프를 되살리면 안 된다.**
- **완료 요약은 반드시 서버 재조회(`serverChecks()`)**. 메모리 스냅샷으로 계산하면 **남이 받은 물량이 전부 short 로 표시된다**(분할 수령에서 기존 동작은 이미 틀렸다). 순서도 고정: `preFinish()` = ①내 미확인분 flush ②서버 재조회 ③확인 다이얼로그. Apply 계획도 DB 를 읽으므로(EF `buildApplyPlan`) **진실은 DB 쪽**. `mergeServerRows` 는 `unconfirmed` 걸린 라인은 건너뛴다(내 값이 더 최신) + **값만 갱신하고 배열은 안 건드린다**.
- **presence = 기존 `wms-presence` 채널 재사용**, key = `me.name+"|receiver:"+receipt.id`. 헤더에 "🟢 also here: X" 배지. ⚠️ **track 페이로드에 `batch` 필드를 넣지 말 것** — batch 는 picker/packer 배치 라벨 전용으로 admin `liveBatchSet()`(BATCH ACTIVITY active/away 판정)이 소비한다. 구분 필드는 `screen:"receiver"` + `receipt`/`po` + `stage`. (2026-07-30: admin LIVE NOW 가 `screen` 값으로 전 화면 분기 — receiver 는 `stage:"receiving"|"putaway"` 를 화면 전환 시 재-track, fulfillment 도 presence 합류, **미상 screen 은 Picking 폴백 금지 → `Other`**. 상세는 `references/frontend.md` 「admin LIVE NOW 전 화면 확장」.)
- **⚠️ 타이머 폴링 금지** — 규칙 22(배터리). presence 는 이벤트 기반이라 OK. `wms_receipts.updated_at` 갱신은 `bumpReceipt()` 로 debounce(스캔당 요청 2개 → 1개).
- **Complete 는 누가 눌러도 데이터가 안전**하다(전체 덮어쓰기 제거 + 서버 요약). 단 **모두 끝난 뒤 눌러야 한다** — 아래 R5 참조.

- ⚠️⚠️ **작업자 귀속은 receipt 가 아니라 라인 단위다 (2026-08-17 · `wms_receipt_lines.last_received_by/at`)**: 나눠 받기가 이 규칙의 기능이므로 `wms_receipts.received_by` 는 **"receipt 를 처음 만든 사람"이지 "받은 사람"이 아니다.** [실례] **PO-01131** = Joyce Chang — 들어갔다 나온 사람인데 62라인·3,570유닛의 RECEIVED BY 로 표시됐다. ⚠️ **틀린 표시가 한 곳이 아니라 셋이었다**(admin 이력 열 · Stats `Receive N lines` 전량 귀속 · Stats work time·putaway%) — 📌 처음 진단은 "헤더를 STARTED BY 로 고치면 된다"였고 불충분했다: **표시 문제로 보이는 것의 뿌리가 스키마인 경우가 있다.** 컬럼 의미 = "이 라인을 **마지막으로** 만진 사람"(라인당 1명) — 한 라인을 둘이 나누면 앞사람이 사라지지만 **receipt 전체로는 참여자 전원이 드러난다**(각자 마지막으로 만진 라인이 있으므로) → 표시는 receipt 의 distinct. ⊘ 폐기 대안 = 라인당 참여자 배열(text[]) — 한 라인이 두 사람에게 각각 1줄로 세어져 **"N lines 받았다" 합계가 실제 라인 수를 넘는다.** **기록 지점**(receiver `patchFor`) = 실작업만: `qty`(스캔·스테퍼·수동입력) · `putaway`(수동 bin/Change/Placed · Place all) · `all`(병합) · off-PO 라인 생성. ⚠️ **`putaway_auto`(자동배정 신규 kind)와 `startPo` 초기 적재는 안 찍는다** — 버튼 하나로 전 라인에 누른 사람이 찍히면 **"연 사람 = 전량 귀속" 버그의 라인판 재현**(자동배정 라인도 이후 Placed/Change 때 정상 기록 · mergeKind 병합 시 all 로 승격해 찍힘 — 의도). **표시 폴백**: 라인에 값이 하나라도 있으면 라인 값만 / 전부 NULL(도입 전 — 백필 금지, received_by 복사가 특히 금지: 그게 바로 틀린 값)이면 received_by 폴백을 **회색 `~이름 (started by)`** 로 구분 — 폴백은 틀린 값이라 정확한 값처럼 보이면 수정의 의미가 없다. ⚠️ `approved_by`(off-PO 승인자) 재사용 금지.

**🆕 receipt 방치 문제와 처방 (2026-08-14 조사·구현)** — [관찰] 어제 21:33~21:40 에 **열기만 한** receipt 4건(PO-01087·PO-01117·TR-03548·PO-01131)이 14시간째 receiver RESUME 목록과 admin "N receipt(s) still receiving/held" 를 차지했다.
- ⚠️ receipt 는 **열기만 해도** in_progress 로 생성되고 라인도 전량 insert 된다(receiver `startPo` — 기대치 스냅샷). 첫 스캔이 아니다. List 로 나갈 때 서버 정리가 **없다** — 코드 주석이 "무해"라고 명시한 의도된 없음인데, 📌 그 판단이 **재개 가능성만 보고 목록 점유라는 부작용을 계산에 안 넣었다.**
- ⚠️ **reaper(`wms_reap_stale_claims`)는 리시빙을 못 다룬다 — 구조적 이유**: `wms_receipts` 에 assigned_to·work_started·heartbeat_at 이 아예 없고 되돌릴 pending 풀도 없다. 리시빙은 소유권 없는 공유 문서 설계(위 "나눠 받기"가 기능)라 **reaper 가 풀어줄 "점유"가 데이터 모델에 존재하지 않는다.**
- **작업 흔적 판정식 = `received_base>0` · `putaway_bin` · `putaway_done` · `is_off_po` 4가지.** ⚠️ **라인 수는 흔적이 아니다**(열 때 자동 생성). 시간 가드 병행 — `bumpReceipt` 가 스캔마다 updated_at 을 갱신하므로 "전부 0 + updated_at 오래됨"이면 확실. [실측] 4건 전부 received/exported/bin/placed/off-PO 0 · **created_at = updated_at 밀리초까지 동일**(스캔이 한 번도 없었다는 증거) · applied_at null.
- **처방 판단**: ⚠️ **reaper 확장(자동 삭제)은 기각** — 이 레포의 삭제는 전부 아카이브 선행 + 사람 확인인데 서버 함수 삭제는 둘 다 없다. 📌 **"확실한 판정"과 "자동 처분"은 다른 문제다**(같은 날 Cin7 void 감지에서 내린 판단과 동일). → 채택: ① 화면에 진행도를 보여 사람이 판단(아래) ② 정리는 기존 Delete 수동. ⬜ 미착수: backBtn 에서 빈 receipt 정리(재발 방지) — receiver 1429행 "무해" 주석 정정 동반.
- ✅ **진행도·작업자 표시 (커밋 `e215d6c`·`758344b` — admin history + receiver RESUME)**: 사용자 지적 "Delete 전에 무작업인지 화면으로 알 수 없어 SQL 을 돌려야 안심하고 지운다". 판정식은 위 4가지 · 추가 왕복 0(임베드에 `is_off_po` 만 추가 — 캡은 최상위 행에만 걸리므로 receipt 당 라인 50~70개여도 무관).
  - admin: Status 칸에 회색 **Empty** 태그 또는 "N/M lines · U u(+off-PO)" · Delete prompt 에 진행 요약 줄("Nothing has been received…" / "⚠️ N units already received…"). ⚠️ **placed(!inner) 전용 행은 수치를 만들지 않는다** — 임베드에 미풋어웨이 라인만 실려 합계가 부정확하다(`_embedPartial` 표식 — 선착순 dedup 이라 work/recent 에도 있으면 온전한 행이 이겨 소멸). 📌 **틀린 수치를 말하느니 침묵.** 진행률 바 기각 — 목적이 "지워도 되나"의 이진 판단이지 진척 관리가 아니다.
  - receiver: 같은 진행도 + **"Started by {name} · Last activity {시각}"**. ⚠️ **소유권 문구 금지**("Claimed by"·"Held by" 류) — assigned_to 가 없고 나눠 받기가 이 규칙의 기능이라 received_by 는 "이 사람 것"이 아니라 **"시작했다"** 는 뜻. ⚠️ 시각은 **창고별 로컬**(사용자 결정 — 작업자는 자기 벽시계로 판단한다. 📌 admin Order Trace 가 토론토+EDM 병기인 것과 다른 이유: 거기는 CCTV 를 현지 시계로 찾는 화면이라 둘 다 필요했다).
- ✅ **admin Delete 버튼 동작 (2026-08-14 조사로 확인 — 문서에 없던 것)**: `wms_receipts` 1행 delete → 라인은 **FK CASCADE**(`wms_receipt_lines_receipt_id_fkey` — baseline 실물 확인)로 함께 삭제. 확인은 confirm 이 아니라 **PO 번호 타이핑 prompt**(오탭 방어가 confirm 보다 강함). ⚠️ **applied 된 receipt 도 삭제 가능** — 차단이 아니라 경고("Deleting here does NOT undo Cin7 — correct Cin7 manually") + 아카이브가 방어. 삭제 전 receipts+lines 전 행을 `archiveRows`(`action='receipt_delete'` → `wms_rollback_archive`, insert 성공·행수 일치 확인 후에만 delete)로 보존. recv_* discrepancy 는 **의도적 무접촉**(매니저 판단 유지 — receipt_id 에 FK 없어 CASCADE 로 딸려 지워지지도 않는다).

## 규칙 25 — 라인 식별은 id 기반이 컨벤션 (⚠️ 2026-07-27)

`bcMap`·수량 핸들러·커서는 **배열 인덱스가 아니라 `line.id`** 로 라인을 찾는다.

- `bcMap[code] = [{id, factor}]`, 스캔은 `lineById(id)` 로 해석(죽은 id 는 자연히 걸러짐). 스테퍼·수동입력·autoAdvance 커서도 동일.
- **⚠️ 인덱스 기반이면**: `dropLine` 이 `lines.splice()` 한 뒤 `buildBcMap()` 재조립을 끝내기까지의 **왕복 창에서 스캔이 엉뚱한 SKU 에 수량을 넣는다.** id 기반이면 splice 후 재조립 자체가 불필요.
- 풋어웨이 뷰는 원래 id 기반이었고 **리시빙 검수만 인덱스**였다 — 2026-07-27 통일.
- ⚠️ **`picker.html`·`packer.html` 은 아직 인덱스 기반.** 지금은 안전(그 화면들은 `lines` 를 splice 하지 않는다). **lines 를 splice 하는 기능을 추가하면 같은 함정** → 백로그.

## 규칙 26 — 검수 표시 순서: 채운 라인만 아래로 (⚠️ 2026-07-27)

- **`isFilled(l) = l.expected>0 && l.received===l.expected`**(주문 수량을 정확히 채움) 인 라인만 리스트 아래로 내린다. **short 는 아직 할 일, over 는 매니저 확인 필요, 오프-PO(expected=0)는 승인 대기** → **전부 위에 유지**(isFilled 가 expected>0 을 요구하므로 오프-PO 는 자동). 완료된 라인끼리는 원래 순서를 지킨다(방금 스캔한 게 위로 튀면 "아까 뭘 찍었지"가 어려워짐).
- **정렬은 렌더 시점에만** — `orderedIdx()`/`sortedIdx()` 가 표시 인덱스만 만든다. ⚠️ **`lines` 배열 재정렬 금지**(bcMap·커서·스캔 무결성). 규칙 20 의 정렬 4종과 같은 원칙, 1차 키만 추가된 것.
- ⚠️⚠️ **`autoAdvance` 는 표시 순서가 아니라 `sortedIdx(false)`(완료 그룹화 없는 순수 sortMode 순서)로 걸어야 한다.** 표시 순서로 다음을 찾으면 방금 채운 라인이 맨 아래로 내려간 탓에 뒤가 비어 **매번 리스트 맨 위 미충족 라인으로 되돌아간다** — 존 순서로 걷던 작업자가 이미 지나온 존으로 끌려간다. `orderedIdx()=sortedIdx(true)`, `autoAdvance`/걷기 = `sortedIdx(false)`.
- 비교는 **base 단위**(expected/received = expected_base/received_base, 스캔은 이미 factor 곱함 — 규칙 3).

## 규칙 27 — 리시빙 동시 작업: 알려진 위험 (⚠️ 미해결 — 2026-07-27 감사)

규칙 24 로 "남의 작업이 사라지는" 급은 없앴지만 **아래는 그대로 남아 있다.** 리시빙을 건드릴 때 이 목록을 먼저 볼 것.

- **R1 — 같은 라인 동시 스캔 = last-writer-wins.** 두 사람이 같은 SKU 를 찍으면 한쪽 수량이 조용히 덮인다. 현재는 **팀 규칙으로 SKU 분담**(사람마다 다른 SKU) 중. 해결책 = **PostgREST 조건부 UPDATE(CAS)** — `.eq("received_base", 읽은값)` 로 보내고 0행이면 재조회 후 재시도. `writeChain`(라인별 직렬화)과 `.select()` 1행 판정이 **CAS 의 전제조건**이라 규칙 24 가 이미 절반을 깔아뒀다.
- **R3 — `wms_receipts.cin7_purchase_id` 에 유니크 없음.** (`wms_orders.cin7_sale_id` 는 유니크 있음 — baseline `wms_orders_cin7_sale_id_key`.) 밀리초 동시 진입이면 **중복 receipt 가능**. 현재 **중복 데이터 0건 확인**. 분할 입고는 새 PO 로 처리하므로 **유니크 제약을 걸어도 됨**(새 마이그레이션으로).
- **R4 — Apply 중복 실행. ✅ 2026-08-06 해소 — PO·트랜스퍼 공통 (in-flight 잠금 — ⚠️ 현장 미검증 · 규칙 21 「Apply in-flight 잠금」 항목)**: ~~해결 = 최종 PATCH 에 `applied_at is null` 조건 + 1행 확인~~ → **잠금 컬럼(`apply_lock_at/by`) 선점으로 대체** — 조건부 최종 PATCH 는 applied_at 덮어쓰기만 막고 실행 중 이중 Cin7 쓰기는 못 막았다. 잠금은 실행 자체를 하나로 만든다(90초 만료 탈취 = EF 사망 자동 회복, WARN 로그). 종전 위험 서술(read-then-check 창 · 매니저 2명 동시)은 양 경로에서 닫혔다. 위험 비대칭 기록: PO 는 잠금 이전에도 duplicate 400 이 이중 계상을 시끄럽게 막고 있었고(잠금이 추가로 없앤 것 = 거짓 부분실패 마커·authorize 재시도·applied_at 덮어쓰기), **트랜스퍼는 그 방어가 없어 동시 실행이면 진짜 이중 이동이었다**(mini transfer 델타 수량 — 같은 날 확장의 이유). ⚠️ 이미 COMPLETED 인 TR 에 두 번째 완료 PUT 의 거동은 **미실측**(R11 — 잠금으로 상황 자체가 안 생긴다).
- **R5 — Complete 후 Apply 진행 중 스캔되면 그 수량은 영구 미적용.** Apply 는 Complete 시점의 DB 를 읽고, 끝나면 `applied_at` 이 찍혀 재적용이 막힌다. → **모두 끝난 뒤 Complete 를 누를 것**(데이터는 안전하나 반영은 못 됨).
  - ✅ **2026-08-04 부분 완화 — `ensureReceiptOpen()` 가드**(receiver.html): Apply 가 **끝난 뒤**에도 작업자 태블릿의 풋어웨이 화면은 열려 있고 계속 써졌다(그 뒤의 Placed·bin 변경은 Cin7 에 절대 반영되지 않는다). 이제 풋어웨이 쓰기 직전에 `applied_at` 을 재조회해 감지되면 모달 후 목록으로 내보낸다 — 규칙 28 의 형태를 따르되 비교 대상이 소유자가 아니라 **`applied_at`** 이다(규칙 28 항목 참조). ⚠️ **여전히 남는 창**: Complete↔Apply **사이**의 스캔은 못 막는다(그 구간엔 `applied_at` 이 아직 null 이다). 그건 위 R5 그대로다.
- **R10 — bin 루프가 비트랜잭션 (⚠️ 비원자성은 여전 · 다만 2026-07-28 부터 부분 실패가 기록되고 재시도 가능하다).** bin 별 분할 POST(규칙 21) 중간에 실패하면 **Cin7 에 DRAFT/부분 이동이 남는다**. 원자성은 없고 앞으로도 없을 것이다(Cin7 에 트랜잭션이 없다) — 대신 **부분 실패를 정상 상태로 다루는 쪽**으로 바꿨다:
  - **트랜스퍼**: 그룹 실패는 `failed_moves[{bin,skus,qty,http_status,cin7_error}]` 로 **수집만 하고 루프를 계속**한다(throw 금지 — R12 의 "쓰기 뒤" 방향). 성공 그룹은 `exported_base` 체크포인트를 찍고, 실패 그룹은 안 찍으므로 **재Apply 하면 실패분만 재시도**된다(`applied_at` 이 있어도 `failed_moves(N)` + 남은 그룹이 있으면 재개 허용). `applied_at` 은 부분 성공에서도 찍히되 admin 이 **`⚠ Applied (N bins failed)`** 로 구분 표시한다. 남는 구멍: 체크포인트 PATCH 자체가 실패하면 WARN 만 남고 재Apply 가 그 bin 을 두 번 옮긴다.
  - **PO 경로 — ✅ 2026-07-31 같은 원칙 이식 (규칙 21 PO 이식 절)**: 전체 throw 제거(수집 후 계속) + `exported_base` 체크포인트(⚠️ PO 의미 = "Cin7 stock received 문서에 실은 양") + 청크 이중 가드(공용 `chunkGuard()`) + 실패 격리. ⚠️ **authorize 1회 제약** 때문에 미처리·실패·격리·스킵이 하나라도 있으면 문서를 **DRAFT 로 유지**하고, 모든 bin 이 실린 마지막 회차에만 한 번 authorize 한다. 남는 구멍은 트랜스퍼와 동류(체크포인트 PATCH 실패·회차 중 EF 사망 시 재전송) — 단 PO 는 Cin7 이 같은 (SKU+bin) 재전송을 **400 `Cannot add duplicate value` 로 거부**하므로 조용한 이중 계상은 없고 시끄럽게 실패한다(그 에러 = 라인이 이미 DRAFT 에 있음 → Cin7 에서 확인). 되읽기 회복(checkpoint repair 상당)은 미적용 — 백로그 6번.
  - ⚠️ **운영 주의 — 리시빙 완료와 Apply 사이에 재고가 움직인다.** 시차가 벌어지면 착지 지점의 재고를 판매 픽킹 등이 먼저 가져가고, bin 이동은 400 `"Available quantity … is 0"` 로 거부된다(실측 TR-02935 / AS97745). **정상적으로 발생하는 상황**이므로 ①Apply 를 완료 직후에 돌리는 게 좋고 ②실패는 사람이 Cin7 재고를 바로잡은 뒤 재Apply 로 처리한다(자동 보정 없음 — R13).
  - **실측 확인 (2026-07-31, TR-03144 — "POST 와 PATCH 사이" 구멍이 실제로 터졌다)**: 실패로 격리된 **10 bin/25 라인을 수동 확인한 결과 전부 목표 bin 에 정확히 도착**해 있었다(실패 사유는 전부 `Available quantity … is 0`). 원인은 무작위 PATCH 실패가 아니라 **타임아웃이 Cin7 POST 와 markExported PATCH 사이에서 EF 를 끊은 것** — 회차가 죽을 때 진행 중이던 그룹이 "Cin7 엔 옮겨졌는데 `exported_base`=0" 으로 남고, 다음 회차가 재시도해 재고 없음으로 거부, 3회 뒤 격리됐다(죽은 회차 수 exported 17→40→79→…→250 와 격리 bin 10개가 거의 일치). **근본 원인은 청크 v3(회차 완주 보장)로 해소**됐고, 잔여물은 **목적지 되읽기 자동 회복**(규칙 21 ④ — `checkpoint_repaired: N`)이 정리한다. v3 이후에도 `checkpoint_repaired` 가 계속 나오면 다른 원인이 있다는 신호다 — **2026-08-06 in-flight 잠금(R4)이 "동시 실행이 만든 체크포인트 꼬임" 원인까지 제거했으므로, 이제 계속 나오면 타임아웃도 동시 실행도 아닌 제3의 원인이다.**
- **R11 — 쓰기 실측의 근거는 HTTP 200 이 아니라 GET 으로 되읽은 값이다 (2026-07-28 교훈).** 트랜스퍼 완료 수량 변경이 "허용된다"는 기록이 **200 만 보고** 남았고, 실제로는 Cin7 이 조용히 무시하고 있었다(규칙 21 정정 항목). **되돌릴 수 없는 쓰기를 새로 실측할 때는 반드시 저장값을 되읽어 확인하고, 그 값을 근거로 기록할 것.** ⚠️ **일반화(2026-08-05 SO-14129)**: 이건 쓰기 실측만의 얘기가 아니라 **"근거의 출처를 표시하라"** 는 원칙의 한 사례다 — 관찰/증언/설명/실측은 다른 등급이고, 섞이면 조사가 헛돈다. 「기록 규칙」의 "근거의 출처를 표시한다" 항목 참조.
- **R12 — 되돌릴 수 없는 Cin7 쓰기 앞에 Supabase 기록을 먼저 (2026-07-28 원칙 확립).** Cin7 쓰기는 사실상 롤백이 없고 WMS 기록은 언제든 다시 쓸 수 있다 → **순서는 항상 "Supabase 먼저 → Cin7 나중"**, 그리고 **선기록이 실패하면 Cin7 을 건드리지 않고 중단**한다.
  - 사례 **TR-02935**(첫 에드먼튼 트랜스퍼 Apply): discrepancy 기록이 applyCommit **맨 마지막**에 있어서 ①원 TR 은 COMPLETED 됐고 ②bin 이동이 `/ref/location` Limit 잘림으로 첫 건부터 throw → ③receipt PATCH 미실행(`applied_at` null → 큐에 남고 Applied 배지 없음) ④**discrepancy 기록 통째로 유실**(차이를 되찾을 방법이 사라졌다) ⑤plan 검증이 "IN TRANSIT 이어야 함" 이라 재Apply 도 막혀 영구히 갇힘.
  - → discrepancy 는 **Cin7 쓰기 앞**으로 이동(실패 시 throw), 재개 경로는 COMPLETED 허용, 체크포인트는 `exported_base`. **이 세 개가 한 세트다.**
  - ⚠️ 반대 방향(되돌릴 수 없는 쓰기 **뒤**의 Supabase 기록 — receipt PATCH·`exported_base`)은 여전히 **throw 금지**다. 이미 Cin7 이 바뀐 뒤이므로 중단하면 상태만 더 갈라진다(규칙 21).
- **R14 — Apply 1회가 EF 실행 시간 한도를 넘는다(대형 트랜스퍼). ✅ 2026-07-31 해소(v2)**: 회차당 그룹 수(12)+시간 예산(20초) 이중 가드 + `done:false` 정상 종료 + 매 회차 `apply_note` 갱신 + admin 자동 반복 — 규칙 21 청크 절·규칙 30-2. ⚠️ 첫 구현(그룹 상한 30 만)은 **여전히 회차를 완주하지 못했다**(TR-03144 실측 — apply_note null 지속). 잔여: EF 호출 자체가 회차 중간에 죽으면 그 회차 note 는 없다(단 피해가 12 그룹/20초 이내로 갇히고 체크포인트로 재개된다).
- **R15 — Apply 대기 중 사람이 Cin7 에서 수동 이동하면 충돌한다.** 규칙 28(픽 중복)과 같은 종류이고 상대가 WMS 자신이다 → **규칙 30**.
- **R16 — 스키마 기록(“적용됨”)이 실물 DB 와 다를 수 있다.** 부분 유니크 인덱스가 `on_conflict` 를 깨뜨려 **리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않았다** → **규칙 29**.
- **R13 — Discrepancy 큐가 방치되면 재고가 계속 틀린 상태로 남는다 (⚠️ 미해결 · 새 정책의 구조적 대가).** 조정은 **사람이 Cin7 에서 수동**으로 하고(자동 adjustment·보정 트랜스퍼 모두 의도적으로 채택 안 함), 트랜스퍼는 완료 수량이 **보낸 수량으로 고정**되므로 **큐를 처리하지 않으면 Cin7 재고가 실물과 계속 어긋난다.** 게다가 캡 때문에 남은 잔량은 착지 지점(집결 bin 또는 창고 no-bin)에 그대로 앉아 있다. 현재 안전장치는 admin Discrepancy 탭 배지(미해결 건수)뿐 — **경과일 알림·에이징 리포트는 없다.**
- **RLS** — `wms_receipts`·`wms_receipt_lines` 정책이 `using(true)`(auth_all). **창고 스코프는 클라이언트 필터뿐** — 로그인한 직원이면 다른 창고 receipt 도 API 로 읽고 쓸 수 있다.
- **EF 권한** — ~~`receiving` EF 에 **호출자 검증이 없다**(anon Bearer 면 통과). Apply 권한(perms `apply`)은 **admin.html 클라이언트 사이드 3중 게이트뿐**이고 서버측 검증(JWT → wms_staff perms 확인)은 미구현.~~ → ✅ **2026-08-13 서버측 게이트 도입**(`_shared/authgate.ts` — read 5종은 로그인한 active 직원 · `action=apply` 는 dry-run·commit 둘 다 admin·'apply' 승격. 커밋 `c76729b` · 상세는 백로그 「보안」). **잔존**: `applied_by` 는 여전히 쿼리스트링 `&by=<name>` 이라 **위조 가능** — 게이트가 생겨 서버 유도(`caller.name`)로 교체 가능해졌다(백로그 「보안」 applied_by 항목).

## 규칙 28 — 픽 소유권 가드: 종이와 클레임이 갈라질 때 (⚠️ 2026-07-28 실사고)

**사고 경위 5단계**
1. 픽커 A 가 보드에서 오더 001 픽리스트를 떼어 태블릿에 로드했다.
2. 매니저가 홀드 지시 → A 는 픽리스트를 **보드에 다시 붙였고 WMS 화면은 그대로 뒀다**.
3. 픽커 B 가 그 픽리스트를 떼어 스캔 → `scanTakeover` 로 클레임이 B 에게 넘어갔다(**여기까지 WMS 정상 동작**).
4. A 도 "픽해도 된다"는 말을 듣고 **이미 로드된 화면에서 그대로** 픽을 시작했다. A 는 재스캔이 필요 없었으니 이어받기 프롬프트를 볼 일이 없었다.
5. A·B 가 같은 오더를 동시에 픽하고 **같은 `wms_pick_task_lines` 에 수량을 썼다.**

**규칙 22 전제가 깨지는 조건.** 규칙 22 는 heartbeat 를 없애며 "소유권은 **종이 픽리스트**가 보증한다"를 전제했다. 이 전제는 **종이와 클레임이 항상 함께 움직일 때만** 성립한다. 종이가 보드로 돌아가고 **클레임(=열린 화면)만 남으면** 물리 상태와 디지털 상태가 갈라지고, 그때 이미 열린 화면은 아무 확인 없이 계속 쓴다. ⚠️ **팀 규칙으로 못 막는다** — A 가 Hold 를 눌렀어도(규칙 23: `assigned_to=null`, `held_by=A`) A 의 화면은 여전히 열려 있고 여전히 쓸 수 있다.

**가드 = 쓰기 직전 + 복귀 시점의 소유권 재확인** (picker/packer 각각 `checkOwner`/`ensureMine`/`freezeScreen`/`guardOnReturn`)
- **쓰기 직전**: picked/verified 수량·상태를 쓰는 모든 경로에서 `pick_tasks`(packer 는 `pack_tasks`) `assigned_to` 를 **단일 컬럼 select** 로 재조회해 `me.name` 과 비교. 관문은 **`saveLine`**(스캔 가산·스테퍼·수동 입력이 전부 여기로 모인다) + **Hold** + **Complete / Complete as incomplete**(packer 는 Pack fill·Over-scan 확인을 **끝낸 뒤**).
- **복귀 시점 감지가 실질적으로 가장 중요**: `visibilitychange`(hidden→visible) + `focus` 에서 같은 확인. 태블릿을 두고 나갔다 몇 분 뒤 돌아오는 게 실제 시나리오라 **첫 스캔 전에 잡히는 게 이상적**이다.
- ⚠️ **타이머·폴링 금지**(규칙 22 배터리). **이벤트 기반만. heartbeat 를 되살리지 마라.** 이벤트가 연속으로 튈 때 중복 조회만 `lastOwnerCheck` 타임스탬프(3초)로 억제 — setInterval 아님.
- **wave 는 소유권이 wave 단위**(규칙 18)라 `wms_waves` 행의 `assigned_to` 를 본다. **멤버 task 개별 확인은 하지 않는다**(wave 행 하나로 충분, 쿼리만 늘어난다).
- ⚠️⚠️ **리시빙에는 소유자가 없으므로 이 가드를 그대로 옮기지 마라 (2026-08-04).** `wms_receipts` 에는 **`assigned_to` 컬럼이 아예 없고**, 한 receipt 를 여러 명이 나눠 받는 것은 버그가 아니라 **규칙 24 의 핵심 기능**이다 — 소유권 비교를 이식하면 그 기능을 깬다. 리시빙에서 실제로 갈라지는 상태는 **`applied_at`**(매니저가 Apply 한 뒤의 Placed·bin 변경은 Cin7 에 절대 반영되지 않는다 — 규칙 27 R5) → `receiver.html` 의 **`ensureReceiptOpen()`** 이 그 컬럼만 본다. **가드의 형태**(단일 컬럼 select · 3초 억제 · 타이머 없음 · 확인 실패 시 통과 · 감지되면 모달 후 목록으로)**는 이 규칙과 같고 비교 대상만 다르다.** ⬜ **복귀 시점 감지(`visibilitychange`/`focus`)는 리시빙에 미적용** — 백로그.

**프리즈 동작**
- 스캔 입력 `disabled` + 수량 조작 버튼 전부 비활성. **렌더 우회로를 남기지 말 것** — 핸들러 `if(frozen) return` 만으로는 부족하고 `renderSingle`/`renderList` 의 스테퍼·수동입력에 `disabled` 를 함께 넣어야 한다(`focusScan` 도 프리즈면 즉시 반환).
- 모달(UI 영어 — 규칙 11): 다른 사람 → `This batch is now assigned to {name}. Your screen is out of date.` / `assigned_to` 가 **null** → `This batch was released and is waiting to be claimed.` **버튼은 리로드 하나만 — 계속 진행하는 선택지를 주지 않는다.**
- ⚠️⚠️ **프리즈 시 로컬 수량을 flush 하지 마라.** 내 메모리 값은 스테일이고, 쓰면 **이어받은 사람의 작업을 덮는다.** 규칙 24 에서 "Hold/finish 의 전체 배열 덮어쓰기"를 제거한 것과 **같은 이유** — 로컬 상태는 버리고 **서버를 진실로** 둔다.
- ⚠️ **null(Hold 로 풀림)도 프리즈 대상이다.** 대기 풀로 돌아간 상태이므로 그때 내 화면이 계속 쓰면 남이 이어받은 뒤 충돌한다.
- 정당하게 이어받고 싶으면 **픽리스트 재스캔(`scanTakeover`)** 경로를 쓴다 — 이미 검증된 진입로다. 가드는 그 경로를 건드리지 않는다.

**실패 처리 & 한계.** 확인 select 가 네트워크 오류로 실패하면 **프리즈하지 말고 쓰기를 진행한다**(창고 와이파이 순단으로 작업이 멈추는 게 더 큰 손실). 콘솔 warn 만. 즉 이 가드는 **best-effort** 이고 원자적이지 않다 — 확인과 UPDATE 사이의 밀리초 창에서 넘어가면 통과한다. **후속: claim_seq(클레임 시퀀스) 로 원자화** — 클레임마다 증가하는 정수를 task 행에 두고 UPDATE 를 `.eq("claim_seq", 진입 시 읽은 값)` 조건부로 보내 0행이면 프리즈. 규칙 27 R1 의 CAS 와 같은 패턴이라 함께 처리.

**✅ 2026-08-06 — 완료 UPDATE 에 CAS 도입 (⚠️ 현장 미검증 — 백로그 「검증 대기」)**
- **대상 3곳**: packer 완료(doneBtn) · picker 단일 완료 · picker wave 완료. 완료 UPDATE 에 `.eq("assigned_to", me.name)` + `.eq("status","in_progress")` 조건 + **`.select()` 행 수로 성공 판정**(0행도 error null — 규칙 24). ⚠️ **wave 멤버 task 만 status 조건 없음**(소유권 조건만) — wave 행 UPDATE 만 실패한 부분 실패에서 재시도의 멤버 재플립이 막히지 않게 멱등으로 둔다. 순서는 **멤버 먼저 → wave 행**(반대면 부분 실패 시 멤버가 in_progress 로 영구히 갇힌다).
- **0행 → 재조회로 3분기** (`completeCasFailed`, 두 파일 각각): ① `completed` 이고 **completed_by=나** → 성공 처리(응답 유실 뒤 재시도 구제 — ⚠️ completed 만 보면 남의 완료를 내 성공으로 착각한다. wave 는 completed_by 컬럼이 없어 **assigned_to=나 + completed** 로 판정: 완료 UPDATE 는 assigned_to 를 안 지우고 남의 완료는 클레임 선행이 필수라 이 조합은 내 완료뿐). **packer 분기 ①은 `checkOrderReady` 를 재실행한다** — 유실된 첫 시도는 거기 도달하지 못했으므로, 안 부르면 마지막 배치의 오더가 ready_to_close 로 영영 못 넘어간다. ② assigned_to 가 남/null → **기존 `freezeScreen` 재사용**(리로드 전용 모달 — 리로드해도 라인·discrepancy 는 완료 플립 앞에서 이미 저장돼 유실 없음. packer overScans 표시 소실은 기존 백로그 그대로, 판정 행은 이미 insert 됨). ③ 재조회도 실패(네트워크) → 재시도 안내 + heartbeat/presence 복구(반영된 경우 ①이 구제). finally 의 버튼 복구는 `if(!frozen)` 가드.
- **`checkOrderReady` 멱등화**: 내부 `wms_orders` UPDATE 가 status 무조건이라 늦은 재시도가 closed(Finalize)/voided 를 ready_to_close 로 되돌릴 수 있었다 → `.in("status", pending·picking·packing·ready_to_close)` 허용 목록 추가. 정상 경로(완료 시점 packing)는 목록에 있어 동작 동일.
- **⚠️ 발견 기록**: packer 완료 UPDATE 는 CAS 이전까지 **error 를 아예 확인하지 않았다** — 완료 실패가 조용히 무시되고 화면은 성공 흐름을 탔다(CAS 와 함께 throw 로 교정). pack **라인 최종 저장 루프와 discrepancy insert 들도 같은 패턴으로 error 미확인**(picker 는 확인함) — ~~미수정, 별건~~ → **✅ 같은 날 후반 8단계 RPC(`wms_complete_pack` — 규칙 9)가 흡수**: 완료 쓰기 전부가 한 트랜잭션이라 무확인 문제 자체가 소멸(실패 = 전체 롤백 + 예외). **같은 패턴이 Hold 에도 있었다** — packer Hold 태스크 플립·픽/팩 Hold 라인 루프가 error 무확인(플립 확인을 넣은 `2cdb973` 이 `ae1a623` 으로 revert 되어 잔존) → **✅ 2026-08-07 Hold RPC(`wms_hold_pick`/`wms_hold_pack` — 규칙 9)가 흡수**(기준선 문서 후속 ③).
- **✅ 2026-08-06 후반 — packer 완료의 CAS 는 RPC 내부로 이동 (규칙 9 8단계 항목)**: 같은 조건(assigned_to + in_progress)이 함수 첫 UPDATE 가 됐고, 0행이면 `{completed:false, worker}` 반환(예외 아님 — 아무것도 안 썼으므로) → 프론트 `completeCasFailed` 3분기 그대로. **플립 성공 시 행 잠금이 트랜잭션 끝까지 유지되어 아래 "확인-쓰기 밀리초 창"이 packer 완료에서는 소멸**했다. **✅ picker 단일·wave 완료도 같은 날 `wms_complete_pick` 으로 이식**(규칙 9 픽 RPC 항목 — wave 는 CAS 가 wave 행·멤버 서버 유도, ⚠️ 현장 미검증).
- **남는 한계**: ~~finish 단계의 라인 최종 저장·discrepancy insert 는 여전히 무조건~~(→ packer 는 8단계 RPC 로 원자화 — 위) · ~~picker 단일·wave 완료는 여전히 프론트 CAS~~(→ **✅ 같은 날 `wms_complete_pick` 으로 해소** — 라인→disc→플립 원자·재시도 중복 소멸) · ~~wave 멤버 UPDATE 와 wave 행 UPDATE 사이의 밀리초 창~~(→ **✅ 같은 트랜잭션으로 소멸** — "멤버 먼저" 순서 규칙도 폐기, 규칙 18) · ~~Hold(픽·팩)는 미이식~~(→ **✅ 2026-08-07 `wms_hold_pick`/`wms_hold_pack` 으로 해소** — 규칙 9 Hold RPC 항목, ⚠️ 현장 미검증) · 남는 것 = **`saveLine`(스캔당 1행) 라인 단위 CAS**(R1 계열 백로그) · **리시빙은 대상 아님**(소유자 없음 — 규칙 20·24) · claim_seq 원자화는 완료·Hold 경로에선 행 잠금이 사실상 대체했고 saveLine 에는 여전히 미적용.

## 규칙 29 — 스키마 기록의 진실은 실물 DB 다: 부분 유니크 인덱스가 `on_conflict` 를 깨뜨렸다 (⚠️ 2026-07-29 실사고)

**증상.** 리시빙 Apply 시 Supabase 가 **400 / `42P10 there is no unique or exclusion constraint matching the ON CONFLICT specification`**. EF 는 `POST wms_discrepancies?on_conflict=receipt_id,sku` 로 선기록(규칙 27 R12)하므로 **discrepancy 기록 실패 = Apply 중단**이 되어 Cin7 을 아예 못 건드렸다.

**원인.** baseline 의 인덱스가 **부분(partial) 유니크**였다:
```sql
CREATE UNIQUE INDEX uq_disc_receipt_sku ON wms_discrepancies (receipt_id, sku)
  WHERE (receipt_id IS NOT NULL);   -- ← 이 WHERE 가 문제
```
**PostgREST 의 `on_conflict` 는 부분 인덱스를 추론하지 못한다**(Postgres 의 `ON CONFLICT (cols)` 추론이 predicate 를 요구하는 것과 같은 이유). 인덱스는 존재하는데 upsert 대상으로 지목할 수 없다.

**조치 = WHERE 절 없는 전체 유니크로 교체.** `receipt_id` 가 NULL 인 pick/pack 행은 유니크의 **NULLS DISTINCT**(Postgres 기본) 때문에 서로 충돌하지 않으므로 영향이 없다 — 부분 인덱스로 얻으려던 것을 기본 동작이 이미 해준다.
```sql
DROP INDEX IF EXISTS uq_disc_receipt_sku;
CREATE UNIQUE INDEX IF NOT EXISTS uq_disc_receipt_sku ON public.wms_discrepancies (receipt_id, sku);
```
SQL 은 **`supabase/wms_disc_uq_fix.sql`** 에 남겼다. ⚠️ 이 파일은 **기록/응급용이고 마이그레이션이 아니다** — 「DB 스키마 변경 절차」대로 `supabase migration new disc_uq_fix` 로 같은 내용을 새 마이그레이션에 담아야 로컬·원격이 다시 정렬된다(위 SQL 은 멱등이라 이미 원격에 적용됐어도 안전).

**⚠️⚠️ 파급 — 리시빙 discrepancy 는 구현 이후 한 번도 기록된 적이 없었다.** 즉 규칙 20 의 차이 처리 정책(“차이는 큐에 남기고 매니저가 Cin7 에서 수동 조정”)이 **문서상으로만 동작**하고 있었다. 트랜스퍼는 완료 수량이 보낸 수량으로 고정되므로(규칙 20 트랜스퍼 예외) **이 큐가 유일한 보정 근거**인데 그게 비어 있었다는 뜻이다. Health 의 `short_no_disc` 는 **픽킹 전용**이라 이걸 못 잡았다(규칙 19).

**⚠️ 교훈 — 스킬에 "적용됨"으로 적힌 스키마를 신뢰하지 말고 실물 DB 로 확인한다.**
```sql
select indexname, indexdef from pg_indexes where tablename='wms_discrepancies';
select conname, pg_get_constraintdef(oid) from pg_constraint
 where conrelid='public.wms_discrepancies'::regclass;
```
- 이 규칙은 **스키마 관련 서술 전부에 적용된다**(references/schema.md 포함). 문서가 아니라 `pg_indexes`/`information_schema` 가 근거다.
- 함께 볼 것: 규칙 27 **R11**(쓰기 실측은 200 이 아니라 되읽은 값) — 같은 종류의 "성공했다고 믿었는데 아니었다" 계열이다.
- **부분 인덱스는 upsert 키로 쓰지 말 것.** PostgREST `on_conflict` 를 쓸 컬럼 조합에는 반드시 **전체** 유니크를 건다.

## 규칙 30 — Apply 는 한 번에 끝나지 않는다: 실행시간 예산 · 수동 이동 충돌 · 체크포인트 불가침 (⚠️ 2026-07-28~29, TR-02935 사후분석)

TR-02935(토론토→에드먼튼, **344 라인 / 144 bin 그룹**)를 실제로 닫으면서 나온 네 가지. 대형 트랜스퍼를 Apply 할 때 반드시 먼저 읽을 것.

### 30-1. 착지·수량 실측 (movement 리포트로 재확인)
- TR-02935 는 **(b) 케이스**: 헤더 `To` = **집결 bin EZ010101 의 GUID**, **344 라인 전량이 그 bin 에 착지**했다.
- **Cin7 이 받은 수량 = 보낸 수량**(실물과 다름): APR15412 **24**(실물 48) · APR16104 **6**(12) · APR48208 **12**(24) · AJA66008 **6**(12) · WOC40103 **12**(실물 6). → 규칙 20 트랜스퍼 예외 B 정책("완료 수량 = 보낸 수량 확정")의 **직접 근거**이고, `min(received, expected)` bin 이동 캡의 근거다.
- 초과/부족 보정은 **ST-00794 / ST-00795(재고 조정)로 사람이 처리**했다 — 자동 보정은 없다(규칙 27 R13).

### 30-2. ⚠️ EF 실행 시간 한도 → 그룹 수 + 시간 예산 이중 가드 (✅ 2026-07-31 v2 구현 — 규칙 21 청크 절)
- 실측: 144 bin 그룹 중 **1회차에 81 라인 이동 후 무응답 종료**. 이후 Apply 를 **3번 더 눌러 +43 라인**만 전진. TR-03144(327 라인/100+ 그룹)에서도 동일 — 사람이 8~10회 눌러야 했다(진행 17→40→79→173→210/327).
- ⚠️ **실패한 그룹이 매 회차 앞에서 다시 시도되어 시간 예산을 먹는다** → 회차당 전진량이 **81 → 약 14/회**로 급감한다(재시도 경로 자체는 의도된 동작 — 규칙 21 — 이지만 순서가 앞이라 뒤쪽 미처리 그룹에 시간이 안 남는다). 그룹 카운트가 성공+실패 시도 기준인 이유.
- ⚠️ **타임아웃으로 죽으면 `applied_at`·`apply_note` 가 둘 다 null 로 남아 실패 목록조차 안 남는다.** 남는 것은 성공 그룹의 `exported_base` 뿐 → 진행률을 사람이 역산해야 한다.
- ⚠️ **1차 구현(그룹 상한 30 만)은 실패했다**: 배포 후에도 TR-03144 의 첫 회차가 완주하지 못했다(`exported_base` 210→225→250 전진, `apply_note` 는 계속 null). 그룹 수만으로는 Cin7 응답이 느린 날의 회차 시간을 못 가둔다.
- **구현 (2026-07-31 v2)**: `APPLY_MAX_GROUPS=12` + `APPLY_TIME_BUDGET_MS=20000`(요청 시작 t0 기준, **Cin7 POST 앞 판정**, 먼저 걸리는 쪽) + 응답 `done:false`/`groups_remaining`/`stopped_by` + **매 회차 apply_note 갱신**(`groups_remaining(N):` 계약 표식) + 종료부 불사(receipt PATCH 실패에도 응답 반환, `note_saved:false`) + admin 자동 반복·진행률·Stop·무한루프 가드. 상세는 규칙 21 청크 절 + `references/edge-function.md`. ✅ PO 경로도 2026-07-31 이식(규칙 21 PO 이식 절 — **authorize 게이트** 포함).

### 30-3. ⚠️ Apply 대기 중 Cin7 에서 수동 이동하면 충돌한다 (운영 규칙)
- TR-02935 실패의 **상당 부분이 `Available quantity … is 0`** — 사람이 이미 옮긴 재고를 WMS 가 집결 bin EZ010101 에서 꺼내려 한 것이다.
- **규칙 28(픽 중복)과 같은 종류의 사고이고, 상대가 WMS 자신이었다.** 물리 상태를 사람이 먼저 바꾸면 디지털 계획이 스테일이 된다.
- **조치**: ①admin Receiving 의 **Apply 대기 항목에 경고 문구**("Do not move this stock in Cin7 until Apply finishes") ②**운영 규칙으로 명문화** — Apply 대기 중인 문서의 재고는 Cin7 에서 손대지 않는다. ③Apply 는 **리시빙 완료 직후**에 돌린다(시차가 벌어질수록 충돌 확률이 올라간다 — 규칙 27 R10 운영 주의).

### 30-4. ⚠️⚠️ 체크포인트 컬럼을 수동으로 채워 receipt 을 닫지 마라
- TR-02935 를 닫으려고 `exported_base = least(received_base, expected_base)` 를 **344행 전체에 UPDATE** 했다. 그 순간 **"WMS 가 실제로 옮긴 것(124 라인)"과 "사람이 수동 처리한 것"을 구분할 신호가 사라졌다** → 남은 이동 목록을 **Cin7 movement 리포트에서 역산**해야 했다(규칙 32).
- **규칙: 강제 종료는 별도 마커로 한다** — `wms_receipts.closed_manually`(신규 컬럼 후보) 또는 `apply_note` 에 사유를 남기고, **`exported_base` 는 절대 손대지 않는다.**
- 이유: `exported_base` 는 **"Cin7 에 실제로 반영된 양"이라는 사실 기록**이고 재Apply 의 유일한 근거다(규칙 21). 여기에 추정치를 쓰면 그 뒤로는 어떤 재개도 신뢰할 수 없다. 규칙 28 의 "로컬 스테일 값을 flush 하지 마라"·규칙 24 의 "전체 배열 덮어쓰기 금지"와 **같은 원칙**: 사실 기록에는 추정을 쓰지 않는다.

## 규칙 31 — Cin7 원가 0 재고의 재평가 (⚠️ 미해결 — 2026-07-29 실측)

**목표**: 원가가 0 으로 들어간 재고 카드를 정상 원가로 재평가한다. **결론: 방법 미확정. 아래 실측만 확정.**

- Cin7 UI 의 재평가(Stock Revaluation) 화면은 **Non-zero stock** 탭과 **Zero stock** 탭 두 섹션이 있고, 문서상 "두 섹션을 함께 사용"한다고 되어 있다.
- ⚠️⚠️ **실측(1 SKU) — 두 섹션은 상계되지 않았다. 재고가 2배로 늘었다.** Non-zero 쪽에 0 을 넣어도 기존 수량이 **차감되지 않고**, Zero stock 쪽 입력이 **그대로 가산**됐다.
- **Non-zero 탭에는 unit cost 입력란이 없고, Zero stock 탭에만 있다** → "수량은 그대로 두고 원가만 고친다"를 한 화면에서 할 수 없다.
- **후보 (둘 다 미검증)**: ①**Zero stock 으로 정상 원가 재고를 추가한 뒤 별도 재고 조정으로 같은 수량을 감소**시켜 FIFO 가 0원 카드를 빼내게 하는 2단계 — ⚠️ 중간에 **재고가 2배인 구간**이 생기고(그 사이 판매가 잡히면 원가가 섞인다), `CostingMethod` 가 **FIFO-Batch/Serial** 이면 배치 지정 때문에 동작이 다르다. ②**원인 문서(0원으로 들어온 입고/조정)를 void 후 재작성.**
- 📌 **다음 단계**: 저가·저회전 1 SKU 로 ①을 **끝까지** 실측하고 movement 리포트로 카드별 원가를 되읽어 확인할 것(규칙 27 R11 — 200 이 아니라 되읽은 값이 근거).

## 규칙 32 — bin 재고 대조는 어느 Cin7 리포트를 쓰나 (⚠️ 2026-07-29 실측)

WMS 의 `putaway_bin` 기록과 Cin7 의 실제 bin 위치를 맞춰볼 때 **리포트 선택이 결과를 좌우한다.**

- ✅ **Inventory Products Stock Level Report 에 `Bin` 컬럼을 붙일 수 있다.** 컬럼: Location / SKU / Product / Brand / **Bin** / Unit / Qty on hand / Allocated / Unit cost / Stock on hand …  → **현재 bin 별 재고 스냅샷이 필요하면 이 리포트를 쓴다**(WMS `putaway_bin` 대조의 기본 도구).
- ⚠️ **Inventory Movement Details 는 `Reference` 필터를 걸면 유입만 보인다**(그 문서로 들어온 것만). **현재 위치를 알려면 필터 없이 뽑아 `(SKU, Bin)` 별 In − Out 을 넷아웃**해야 한다. TR-02935 의 남은 이동 목록을 이렇게 역산했다(규칙 30-4).
- ⚠️ **InventoryList CSV 의 `StockLocator`/`PickZones` 는 bin 수량이 아니다** — 제품 마스터의 참고 문자열이므로 재고 대조에 쓰면 틀린다.
- 📌 Health 검사 후보: `wms_receipt_lines.putaway_bin` vs **`asung_bin_stock`(BQ, 매일 6:30 스냅샷)** 대조 → "풋어웨이 기록과 Cin7 위치 불일치". ⚠️ **하루 지연이므로 실시간 용도는 아니다**(어제 이후의 이동은 못 본다). 백로그.

## 규칙 33 — Cin7 bin-to-bin 이동 화면 (설계만 — 백로그, 2026-07-29)

리시빙 풋어웨이와 별개로, **창고에서 자리를 옮길 때 쓰는 독립 화면**. API 근거는 전부 실측됨(규칙 21 · TR-03236).

```
POST /stockTransfer
{ Status:'COMPLETED', From:<bin GUID>, To:<bin GUID>,
  Lines:[{SKU, TransferQuantity}], SkipOrder:true }
```
- **같은 창고 bin↔bin 은 `InTransitAccount` 불필요**(TR-03236 실측). 수량은 델타라 절대값 사고가 없다.
- ⚠️ **트랜스퍼는 `From`/`To` 가 문서 레벨이라 한 문서에 여러 SKU 를 담을 수 있다** — `purchase/stock` 의 "문서당 bin 1개" 제약(규칙 21)과 **다르다**. 단 **bin 조합(From,To) 마다 문서 1개**로 쪼개야 한다.
- **단계**: **A 자유 이동**(SKU·수량·From·To 를 사람이 지정) → **B 풋어웨이 큐 소진**(receipt 의 `putaway_bin` 을 목록으로 띄워 소진). **A 를 먼저** — B 는 receipt 상태와 얽혀 Apply 경로와 충돌 여지가 있다.
- ⚠️ **`wms_sku_bins` 에 쓰지 말 것** — 매일 6:30 truncate + 재적재(규칙 6)라 조용히 사라진다. 위치의 진실은 Cin7 이고, 우리 기록은 **감사용 신규 테이블 `wms_bin_moves`**(sku·qty·from_bin·to_bin·warehouse·cin7_tr_number·moved_by·moved_at)에 남긴다.
- **미정**: 권한 범위(매니저 전용 vs 창고 직원 전체). 되돌릴 수 없는 Cin7 쓰기라 최소한 perms 키 하나(`binmove` 등)를 새로 두는 쪽이 안전하다.

## 규칙 34 — 화면 전환 앞에 N 왕복을 두지 마라: 풋어웨이 진입 프리즈 (⚠️ 2026-07-30 진단·수정)

**증상**: 리시빙/트랜스퍼에서 "Putaway →" 를 누르면 화면이 수 초~수십 초 멈춤(50라인 PO 에서도). 픽킹·팩킹은 정상.

- **원인 = 진입 핸들러의 라인별 직렬 `await`.** `toPutawayBtn` 이 자동배정 라인마다 `await queueWrite(l,"putaway")` 를 돌려 **진입 시간 = 라인 수 × DB 왕복(RTT)** 이었다. 실측 PATCH RTT 유선 55~62ms(태블릿 Wi-Fi 는 150~400ms 급) → 50라인 3~15초, 344라인(TR-02935 급) 21~100초+. 버튼 피드백도 없어 "죽었다"로 보임. 07-23 첫 버전(`await sb...update` per line)부터 존재, 07-27 queueWrite 전환 후에도 직렬 유지.
- **수정 (receiver.html)**: 로컬 배정 → **즉시 `showPutaway()`**, 저장은 `savePutawayAssigns()` 백그라운드 큐(**동시 8개 풀**)로. `queueWrite`/`unconfirmed`/`writeChain`(규칙 24) 은 그대로 — 실패는 unconfirmed 에 남아 Hold/완료 flush 가 재시도하고, 진입 직후 사용자의 Change/Placed 쓰기는 writeChain 이 배정 쓰기 뒤에 줄 세워 추월이 없다(node 모의로 순서 보존 검증). 진입 전 대기는 추천 빈 **배치 조회 1회**뿐. `putawayPrep` 플래그 + "Preparing…" 라벨로 재클릭 차단.
- **원칙**: 사용자 액션(화면 전환·스캔 피드백) 앞에 **왕복 1회 초과를 두지 말 것.** 라인 수에 비례하는 네트워크 대기는 전부 백그라운드 큐로 — `saveLine`(규칙 24)·`togglePlaced` 낙관 렌더와 같은 패턴.
- **혐의 벗은 것 (측정 근거 — 재수사 방지)**: ① **bin 선택 목록은 원인 아님** — 풋어웨이는 라인마다 목록을 그리지 않는다(빈 지정은 모달 1개, `renderBinOptions` 가 **최대 300개**만 렌더). 창고 bin 은 토론토 2047·에드먼튼 628 — **앞으로도 라인마다 전체 목록(select/datalist)을 그리지 말 것**. `action=bins` 는 0.5초/128KB(토론토)로 `loadBins()` 비동기 독립 로드라 진입을 막지 않음(07-28 bins 소스 변경은 이 건과 무관). ② **DOM 아님** — 풋어웨이 요소 노드는 50라인 ≈ 520, 344라인 ≈ 3.5k(썸네일은 40px 고정 background). ③ 렌더/정렬 아님 — 전체 재렌더는 수~수십 ms.
- **계측**: `receiver.html?debug=perf` → 콘솔 `[perf]` (putaway entry ms · bg saves ms · renderPutaway/renderRecv ms · DOM 노드 수). 평상시 no-op.
- 📌 같은 원칙의 적용 사례: **규칙 37**(Stats 리시빙 지표를 fire-and-forget + 왕복 2회로 묶어 픽/팩 렌더를 막지 않음).

## 규칙 35 — 되돌릴 수 없는 작업의 버튼 상태 머신 (admin Apply, ⚠️ 2026-07-30)

**배경**: Apply 는 Cin7 에 되돌릴 수 없이 쓰는데(규칙 21) 버튼은 눌러도 아무 변화가 없어 **"안 눌렸나?" 하고 다시 누르는** 경로가 열려 있었다(규칙 27 R4 의 사람쪽 원인). 화면 상태를 진행에 맞춰 바꾸는 것이 첫 방어선이다.

- **플래그 3개** (admin.html 모듈 스코프): `applyBusy`(진행 중 receipt id) · `applyWriting`(commit 구간인지) · `applyBtnRef`(버튼 노드). 라벨 전이 = `Apply to Cin7` → **`Checking…`**(dry-run) → **`Applying…`**(commit) → **`✓ Applied`** / **`⚠ Partial`** / **`Apply failed`**(5초 뒤 원래 라벨 복구). 진행 중엔 목록의 **다른 Apply 버튼도 비활성**.
- ⚠️ **배너·`beforeunload` 경고는 commit 직전에만 켠다.** dry-run 구간은 아무것도 안 쓰므로 거기서 "나가면 위험" 경고를 띄우면 **늑대소년**이 되어 진짜 위험한 구간의 경고가 무시된다.
- ⚠️⚠️ **재진입 차단은 버튼 `disabled` 가 아니라 플래그로 한다.** Review 모달 경로·재렌더로 새로 만들어진 버튼 노드는 이전 `disabled` 를 물려받지 않아 **우회된다**. 판정은 항상 함수 진입부에서 `applyBusy` 를 본다(규칙 20 의 Apply 권한 3중 게이트와 같은 발상 — 게이트는 렌더 결과가 아니라 상태에 건다).
- ⚠️ **rAF 리페인트에는 150ms 타임아웃을 반드시 건다.** `alert` 전에 버튼을 그리려고 `requestAnimationFrame` 을 기다리는데 **백그라운드 탭에서는 rAF 가 아예 안 돈다** → 버튼이 busy 로 영구히 굳는다. 복구는 전부 **try/finally**(사용자 취소·예외 포함).
- ⚠️ **성공 후 목록 새로고침(`loadRecv()`)은 try 밖에서 `.catch()`.** 새로고침 실패가 `Apply failed` 로 보이면 **이미 Cin7 에 반영된 receipt 을 다시 누르게 유도**한다 — 되돌릴 수 없는 쓰기에서 최악의 오표시다.
- **남은 구멍**: 플래그는 **브라우저 단위**라 매니저 두 명이 다른 기기에서 동시에 Apply 하는 것은 못 막는다. ~~최종 방어선은 서버의 `applied_at` 가드인데 그것도 read-then-check 라 창이 있다~~ → **✅ 2026-08-06 서버 in-flight 잠금이 PO·트랜스퍼 양쪽을 닫았다**(규칙 27 R4 · 규칙 21 — ⚠️ 현장 미검증).
- 구현 지도는 `references/frontend.md` 「admin.html Receiving 탭 · Apply 버튼 진행 상태」.

## 규칙 36 — fulfillment 스캔 배정: 박스는 오더 하나 (⚠️ 2026-07-29 · **실전 미검증**)

DnD·탭에 더한 **세 번째 입력 수단**. parcel 출고는 담으면서 맞추는 작업이라 집는 순간 스캔으로 배정되는 흐름이 필요했다.

- **⚠️⚠️ 아직 실물 테스트가 끝나지 않았다 (2026-07-30 기준).** 미확인: `Move all` 기본값이 현장에 맞는지 · 포커스 정책이 HID 스캐너에서 안 어긋나는지 · 오프라인/순단 시 롤백 표시 · **기존 DnD·탭 경로 회귀** · 태블릿에서 sticky 오프셋. **현장 검증 전에는 "동작한다"고 적지 말 것.**
- **프랜차이즈 전제(설계의 근거)**: 손님이 자기 창고에서 **스토어별로 재분배**한다 → **팔렛은 섞여도 되지만(박스를 얹는 그릇) 박스는 오더 하나**가 원칙. 섞이면 받는 쪽이 박스를 풀어서 다시 나눠야 한다. 그래서 혼합 가드의 **주 버튼이 `New box for SO-…`**(올바른 동작이 가장 쉬워야 한다)이고, 차단은 하지 않는다("N customers mixed" 경고와 같은 방침).
- **모드 2종**: `Scan qty`(기본, base=+1·케이스=+factor) / `Move all`(그 SKU 미배정 잔량 일괄 — 단 **대상 유닛에 담긴 오더 것만**, 오더 경계를 안 넘는다).
- **오더 귀속 3단**: ①그 SKU 잔량이 있는 오더가 1개 → 자동 ②여러 개인데 대상 유닛에 담긴 오더가 그중 하나 → 자동 ③그 외 → **모달**. 조용히 추측하지 않는다(잘못 귀속되면 스토어별 팩킹리스트가 틀어진다).
- **함정 3개 (반복하지 말 것)**:
  - ⚠️ **`wireUnitEvents` 안에서 타깃 선택 리스너를 등록하면 렌더마다 중첩 등록**되어 토글이 깨진다 → **스크립트 최상위에서 delegated 1회**(`#units`).
  - ⚠️ **분할 오더는 같은 `order_line_id`(olid)가 배치별로 `poolLines` 에 중복**된다 → 잔량은 개별 entry 가 아니라 **`remainingOl(olid)` 집계**로 계산.
  - ⚠️ **sticky 오프셋은 실측값**(`setStickyOffsets()`) — 헤더가 태블릿에서 두 줄로 접히고 `Move all` 배너로 바 높이가 변해 고정 58px 은 겹친다.
- **포커스 정책**: 오더 로드 후 기본 포커스는 `#prodScan`(HID 스캐너는 포커스된 곳에 타이핑하므로 어긋나면 **조용히 실패**한다). 단 **다른 input/textarea 편집 중엔 뺏지 않는다.** 오입력은 **양방향 감지**(`#orderScan` 에 상품 바코드 / `#prodScan` 에 오더 바코드).
- **낙관적 렌더 + 실패 롤백**: 스캔 즉시 로컬 반영·렌더·소리(규칙 24 — 피드백을 await 로 막지 않는다), 저장 실패 시 confirmed 값으로 되돌리고 빨간 경고 + 그 건의 undo 로그 무효화. Undo 최근 5건.
- **동시 작업**: 서로 다른 박스 = 다른 행이라 안전. **같은 유닛×같은 라인 동시 스캔은 last-writer-wins**(규칙 27 R1 계열, 기존 DnD 와 동일 수준).
- 상세 구현은 `references/frontend.md` 「스캔 배정」. 후속(박스 라벨에 스토어명 인쇄)은 백로그.

## 규칙 37 — admin Stats: 리시빙 지표와 근무시간 소요 (⚠️ 2026-07-30)

Stats 탭에 **리시빙/트랜스퍼(`source_type` 구분)·풋어웨이·리시빙 discrepancy(`source='receiving'`)** 를 추가했다. 기존 픽/팩과 **같은 기간 필터**를 쓰고, 조회는 `Promise.all` **2회 왕복**으로 묶어 fire-and-forget(규칙 34 — 픽/팩 렌더를 막지 않는다). 기간 연타 스테일은 `statsRange!==r` 로 버린다.

⚠️⚠️ **avg time·min/line 의 신뢰 한계 (2026-08-11 조사 — 코드로 확정된 사실)**: `started_at` 이 실제 작업 시작이 아닐 수 있다. **[확정 — 코드]** ① **스캔 이어받기**(picker `openByScan` 이어받기 분기 · packer 스캔 이어받기)가 `started_at` 을 **지금으로 덮어쓴다** — 인계자의 작업 시간이 소멸하고 완료자의 잔여 시간만 남는다(과소). confirm 문구 "quantities are kept" 는 수량만 참이다. ② **Hold→재개**: Hold RPC 는 started_at 을 의도적으로 보존하는데(마이그레이션 주석 명시) **재개가 `startBatch`/packer 큐 클레임을 재사용해 덮어쓴다**(held 카드 디스패치의 else 분기 — RPC 가 지킨 것을 재개가 무효화). ③ **wave 멤버**는 반대 방향 — `startWave` 가 전 멤버에 wave 시작 시각을 일괄 기록 + 완료도 일괄이라 **멤버 전원의 dur ≈ wave 전체 소요**(과대). **대조군(보존이 옳게 된 곳)**: `takeoverBatch`(방치 클레임)는 assigned_to·heartbeat 만 갱신 — 같은 "이어받기"인데 스캔 쪽만 리셋(설계 갈라짐). **[확정 — 증언] (2026-08-11 후반)**: SO-14464-1(68라인/218유닛을 2분 10초 기록)의 원인은 **② Hold→재개**로 확정 — ⚠️ **근거는 코드·행 데이터가 아니라 담당자 증언이다**("라인 수가 많아 중간중간 Hold/Resume 을 여러 번 했다. 2분에 끝날 특별한 상황은 없었다"). 행에는 판별 흔적이 없었다(`picked_at` 전 행 null · 롤백 로그 없음) — 증언이 유일한 판별 근거. ✅ **①②는 2026-08-11 수정 완료**: **"started_at 은 최초 시작이다 — 이어받기·재개가 덮어쓰지 않는다"** 가 명문 원칙이다. 4곳(picker 스캔 이어받기·startBatch / packer 스캔 이어받기·resumePack 클레임) 전부 SET 에서 started_at 제거 + `ensureStartedAt`/`ensureStartedAtPack` 헬퍼의 서버측 only-if-null backfill(`.is("started_at",null)` — 경합에도 최초 1회만). 최초 시작/재개의 구분자는 행의 null 여부(롤백은 null 리셋·Hold 는 보존 — 모드 분기 불필요). packer `startPack` 의 insert(진짜 최초)는 무접촉. ③ wave 멤버 과대는 **잔여**(배분 설계 필요 — 백로그). ⚠️⚠️ **수정의 부작용 — 방향 전환(과소→과대)**: 이제 avg 는 **Hold 대기 시간을 포함**한다(3시간 방치 = 3시간 기록). 매니저가 "갑자기 느려졌다"고 읽으면 오해다 — **기록이 정확해진 것**(2026-08-11 이후 데이터부터). 화면 문구는 **넣지 않기로 판단**(부제가 이미 길고, 일회성 전환이라 영구 문구는 과함 — 물으면 이 문단이 답). ⚠️⚠️ **24시간 캡 의존성(건드리기 전에 읽을 것)**: `dur()` 는 24h 초과를 이상치로 버리는데, 이 캡이 **밤샘 Hold 배치를 avg 에서 자동 제외하는 이번 수정의 안전장치**다 — 동시에 **통계 공백**이기도 하다(오래 Hold 된 배치는 avg 에 아예 안 잡힌다: "왜 이 배치가 avg 에 없지"의 답). 캡을 올리면 밤샘 Hold 가 avg 를 오염시키고, 없애면 며칠짜리 dur 이 들어온다 — **순수 작업시간(스캔 타임스탬프 집계, 백로그)이 생기기 전엔 캡 유지.** → 매니저 안내: ③이 섞인 기간의 avg·min/line 은 여전히 개인 비교 근거로 쓰지 말 것.

**2026-08-11 확장 — 라인·유닛(base) 보조 줄 + Quality reports by worker.** ⚠️⚠️ **설계 판단(사용자 확정): 처리량에 순위를 매기지 않는다** — 배치/시간·라인/시간·유닛/시간 어느 하나도 공정하지 않아(각각 작은 오더·낱개 다SKU·대량 단일SKU 유리) 세 지표를 **나란히 보여주기만** 한다. **한 숫자로 줄이면 그 숫자에 맞춰 행동이 왜곡된다**(작은 오더 골라잡기 — 규칙 41 계열). min/unit 은 왜곡에 가장 취약해 아예 없고, min/line 은 회색 텍스트만. "실제 한 일" 기준(수량>0 라인·수량 합 — 픽 picked_base/팩 verified_base)은 화면 부제에 명시. Quality reports 표는 포상 **판단용 데이터**일 뿐 화면은 상벌을 표현하지 않는다(중립 표 · receiver 포함 · "Higher is better…" 문구). 상세·쿼리 구조는 `references/frontend.md` 「Stats 라인·유닛 지표」 절.

- **작업자 통계는 별도 표가 아니라 「Throughput by worker」에 통합**한다(같은 사람이 픽·팩·리시빙을 다 하므로 표가 갈라지면 비교가 안 된다). 픽/팩 집계와 리시빙 집계를 **도착 순서 무관하게 이름 합집합으로** 합쳐 그린다. ⚠️ **2026-08-17 부터 리시빙 사람 귀속은 라인 단위**(`last_received_by` — 규칙 24 라인별 작업자 항목): 폴백 그룹(도입 전 라인) 키는 **`~이름`** 이라 실명 행과 병합되지 않는 별도 행(의도 — 그 사람 실적이라 단정할 수 없다) · **work time = 사람별 min~max `last_received_at`**(receipt 전체 구간을 사람 수만큼 주면 셋이 나눈 4시간이 12시간이 된다 — 폴백 그룹은 미계산: 없는 값을 만들지 않는다) · 받은 라인 0 인 receipt 는 byWorker 에 안 잡힌다.
- ⚠️⚠️ **receipt 건수를 배치 건수와 같은 스케일의 막대로 그리지 마라.** receipt 하나가 5~344 라인이라(TR-02935) 막대가 사실상 안 보이거나 왜곡된다 → **라인 수 기준 + 자체 스케일(`lineMax`)**.
- ⚠️⚠️ **소요 시간은 근무시간(work hrs) 기준**. 달력 경과로 계산하면 퇴근 후 밤·주말이 들어가 **26.7h 같은 쓸모없는 값**이 나온다(실제로 그랬다). 상수 `WORK_HOURS`(09–17)·`WORK_DAYS`(월–금)·`WH_TZ`, 창고별 타임존(`America/Toronto` / `America/Edmonton`, 미매핑=토론토 폴백). **`workMinutes(a,b,warehouse)` 하나를 타입 표와 작업자 행이 공유**한다 — 두 곳이 다르게 계산하면 안 된다. 0(전 구간 근무시간 밖)은 `< 1 min`(=`—` 데이터 없음과 구분). **공휴일 미반영**(백로그).
  - ⚠️ **한계 — hands-on time 이 아니다.** 이 값은 "시작~완료까지의 근무시간 경과"라 **receipt 을 열어둔 채 다른 일 한 시간이 그대로 포함**된다. 순수 작업시간은 스캔 타임스탬프 집계가 필요(백로그).
- **지체 지표도 근무시간 자다 — 달력 아님 (2026-08-13 사용자 결정 · Status 탭 BATCH ACTIVITY Elapsed 열)**: 같은 화면의 두 숫자가 다른 자를 쓰면 안 된다(Stats 소요시간과 통일) + 금요일 유입이 월요일 아침에 부당한 빨강이 되는 것 방지. 임계 = **≤16 근무시간(근무일 2일 = 목표) 회색 / 16~32h 주황 / 32h+ 빨강** — 색상값은 ageBadge(Discrepancy·Reports 의 달력 3단계)를 재사용하고 **자만 다르다**. 기준점은 **오더 `imported_at`**(배치 created_at 아님 — 분할 오더의 나중 배치가 짧게 나와 지체가 가려진다). 60일 캡 초과는 "60 d+" 빨강("—" 위장 금지).
  - [실측 2026-08-13] **`wms_orders.ship_by` 는 기한 판정에 못 쓴다**: 활성 31/36(86%) 채움·날짜 10종 분산(Cin7 기본값 아님)으로 데이터 자체는 실하지만, **26/31 이 이미 지난 날짜** — 판정에 쓰면 거의 전부 빨강이 되어 지표가 죽는다. **결론 = 판정 미사용·표시만.** 프론트 소비처는 이날까지 0곳이었다(hello EF 가 채우기만 함).
- ~~**기간 귀속은 `created_at`**~~ → ⚠️⚠️ **2026-08-17 개정 — 리시빙은 픽/팩과 다르다: 한 PO 가 며칠 열려 있고(분할 입고·held) 그동안 여러 사람이 붙어, `created_at`("언제 시작했나")으로는 "언제 일했나"를 못 센다.** [실측] PO-01113 — created 08-14 · completed 08-17 · 101라인/8,622유닛을 당일 Stats 가 통째로 누락(`Jaeyoung Choi · Receive 0 lines` — **오늘 가장 많이 받은 사람이 실적 0으로 보였다**). 수정 = 쿼리는 넉넉히(`created_at ≤ to` + `completed_at is null or ≥ from`) 받고 **귀속 판정은 라인의 `last_received_at`**(NULL 라인 = 도입 전은 receipt `created_at` 폴백 — 종전 동작. 한 receipt 가 실명·`~폴백` 그룹에 동시 기여 가능 — 의도). 📌 **receipt 단위 지표(receipts 카운트·Applied/not applied·avg receive·avg complete→apply)는 `created_at` 유지** — 라인 기준이 의미 없는 지표들이고, 종전 문장의 취지("미완료·미적용도 지표에 잡혀야 한다")도 그쪽에서 유지된다.
- ⚠️ **`exported_base` 비율("Moved in Cin7")은 트랜스퍼 라인만** 낸다(`source_type==="transfer"` 필터). 이유가 2026-07-31 에 바뀌었다: 예전엔 "PO 는 이 컬럼을 안 씀"이었지만 이제 **PO 도 쓴다 — 단 의미가 다르다**("문서에 실은 양", 규칙 21 PO 이식 절). 섞으면 "옮겼다"와 "문서에 실었다"가 한 지표에 합쳐져 뜻이 없어지므로 필터는 유지하고, 각주에 PO 제외를 명시했다.
- **화면 각주 4개는 필수 유지**(⚠️ 2026-08-04 정정 — 여기 "3개" 로 적혀 있었으나 실물 admin.html Stats 탭에는 4개다. 세는 데서 빠져 있던 것은 **①소요시간 = 근무시간 기준**(위 항목) 각주이고, 개수만 보고 지우면 26.7h 같은 값을 그대로 믿게 된다. 번호는 `references/frontend.md` 「Stats 탭 …」 항목과 **같은 순서**로 맞췄다 — 화면 배치 순서가 아니라 열거 라벨이다): ①`exported_base` 는 **수동 UPDATE 로 오염될 수 있다**(TR-02935 344행 일괄 백필 — 규칙 30-4) → "WMS 가 옮긴 것"의 **근사치** ②리시빙 discrepancy 는 유니크 인덱스 버그(규칙 29)로 **2026-07-28 이전 데이터가 없다** ③**소요시간은 근무시간(Mon–Fri 09–17, 창고 로컬)만 센다**(위 항목) ④**"Putaway done" 은 2026-08-04 이전 기간을 신뢰할 수 없다** — 그때까지 완료 표시가 **라인당 1탭**뿐이라 11라인 이상 receipt 에서는 아무도 누르지 않았다(경위·실측·근거는 `references/frontend.md` 「풋어웨이 완료 입도」절 — 📌 **번호 규칙으로 승격하지 않기로 결정**했다: UI 입도 문제라 "모르면 사고가 나는 것"이 아니다. 판단 기준은 위 「기록 규칙」). 숫자를 그대로 믿게 두면 안 되는 지표라 각주를 지우지 말 것.
- ⚠️ **mistake tally 의 집계 대상은 2026-08-04 에 바뀌었다 — 규칙 41 참조**(`recv_*`·`stock_short`·`pack_scan_mistake` 는 실수가 아니다). 여기 본문은 중복 서술하지 않는다.

## 규칙 38 — 트랜스퍼 Put away 는 v2 API 에 없다 (⚠️⚠️ 탐색 종결 — 2026-07-31 실측 · 같은 탐색 반복 금지)

Cin7 UI 의 트랜스퍼 문서에는 `Put away` 옵션이 있고, 켜면 라인별 `LOCATION` 컬럼이 생긴다. "이걸 API 로 쓰면 bin 별 미니 트랜스퍼가 필요 없지 않을까"는 **이미 끝까지 탐색했고 답은 없다** (2026-07-31, TR-03259 실측):

- `/stockTransfer/putaway`·`putAway`·`put-away`·`pick`·`stock`·`received`·`receive` → **전부 HTML "Page not found"**
- `/stockTransfer/order` → 정상 JSON 이지만 **라인에 위치 필드 없음**
- 본 문서 응답 헤더에 **`PutAway` 플래그조차 없다** — UI 에서 체크하고 저장해도 API 응답에 반영되지 않는다
- Put away 탭에는 **CSV Import 버튼도 없다** — 수동 대량 입력 우회도 불가

→ **결론: 헤더 `To` 착지 + bin 별 별도 트랜스퍼 문서(규칙 21)가 유일한 API 경로다.** 현재 구조는 우회가 아니라 제약에 맞춘 정공법이다. **같은 탐색을 반복하지 마라.** (cin7-api 스킬 `references/stock-write.md` 에 동일 기록.)

## 규칙 39 — 대형 TR 분할은 효과가 없다 (2026-07-31 실측 계산 — 채택 안 함)

"트랜스퍼를 여러 개로 나눠 보내면 Apply 가 가벼워지지 않을까"에 대한 답. TR-02935(344 라인 / 고유 bin 144 / bin 당 평균 2.4 라인)를 3분할했을 때 총 bin 그룹 수(=Cin7 호출 수):

| 분할 방식 | 총 bin 그룹 수 |
|-----------|---------------|
| 안 나눔 | **144** |
| bin 정렬 3분할 | 146 |
| 브랜드 3분할 | 154 |
| 무작위 3분할 | **217** |

- **한 bin 에 여러 SKU 가 들어가므로, 나누면 bin 그룹이 쪼개져 호출이 오히려 늘어난다.**
- 나눌 거면 **반드시 브랜드 단위**(창고가 브랜드별로 정리돼 bin 이 뭉친다 — 그나마 +10). 그러나 리시빙 때 "이 물건이 어느 TR 것인지" 문제가 새로 생긴다(트럭은 하나, 팔레트는 토론토 픽 순서로 실린다).
- → **청크 자동 반복(규칙 21)이 있으므로 분할 이득 없음. 채택하지 않는다.**

## 규칙 40 — 트랜스퍼 착지는 창고만 지정한다 (⚠️ 2026-07-31 사용자 결정 — 집결 bin 폐기)

앞으로 창고간 트랜스퍼의 `To` 는 집결 bin(EZ010101)이 아니라 **창고(`Asung - Edmonton`)만 지정**한다 — 규칙 21 착지 지점의 **(a) 케이스가 표준**이 된다.

- **이유 ①**: 집결 bin 에 재고가 쌓이면 `asung_bin_stock` → `wms_sku_bins` 스냅샷을 오염시킨다(라스트 로케이션이 집결 bin 으로 기록되는 경로가 사라짐).
- **이유 ②**: "집결 bin 에 남은 게 미이동분인지 원래 둘 물건인지" 헷갈리는 문제가 사라진다. (a) 는 잔량이 **"bin 없는 재고"** 로 남아 그 자체가 미정리 신호다(규칙 20 트랜스퍼 예외 ⑤와 합치).
- ⚠️ **(a) 케이스의 완료 후 bin 이동은 실전 미검증** — API 실측(규칙 21: From=창고 GUID 로 "bin 없는 재고"를 꺼냄, TR-03260 1건)은 됐지만 **실전 Apply 경험은 전부 (b)였다. 다음 트랜스퍼가 첫 검증이다 — dry-run 을 먼저 확인할 것**(백로그 「검증 대기」).
- **풋어웨이 마무리 방식**: 라스트 로케이션이 **없으면 지정하고, 있으면 그대로 둔다.**

## 규칙 41 — 픽·팩 discrepancy: 작업자 실수 vs 재고 불일치는 다른 것이다 (⚠️ 2026-08-04 사용자 결정)

현장 사실: 선반에 5개뿐이면 픽커는 6개를 못 뽑는다 — 이건 실수가 아니라 **Cin7 재고(6)와 실물(5)의 불일치**다. 마찬가지로 "픽커가 7개를 가져옴"과 "팩커가 한 번 더 스캔함"은 다른 사람의 다른 사건이다. 이 구분이 없으면 정확도 지표가 거짓말을 하고, 재고 불일치는 영영 보정되지 않는다.

- **부족은 선반 앞의 사람이 선언한다**: 픽커 `⚠ Not enough stock`(1차) / 팩커는 선반 확인 후 보조 선언. 선언 = `wms_discrepancies` 에 `reason='stock_short'`, `source='picking'|'packing'`, **`responsible=null`**, `declared_by=선언자`(시각=created_at) — 토글(재클릭 취소), ~~진입 시 미해결 행으로 복원~~ → ⚠️⚠️ **2026-08-11 정정: 진입 시 복원(loadStockFlags)은 "미해결(resolved_at null)"이 아니라 "비무효화(voided_at null)" 행 기준이다.**
- ⚠️⚠️ **resolve 는 선언 취소가 아니다 — loadStockFlags 오독 실사고 (2026-08-07 발생 · 2026-08-11 수정, SO-14090/PRO00123)**: 픽커가 15:34 선언 → 매니저가 15:54 resolve(Cin7 Fixed) → 19:15 팩 완료가 선언을 못 보고 `short_after_pack` 에 **responsible=픽커로 부당 집계**(disc id 370 — voided 처리). 원인 = packer `loadStockFlags` 의 `.is("resolved_at",null)`: **매니저가 빨리 처리할수록 픽커가 벌을 받는 역인센티브** — 이 규칙이 스스로 경고한 "정직한 기록을 벌주면 기록 자체가 사라진다"의 실현이었다. **수정 = picker·packer 양쪽 loadStockFlags 를 `.is("voided_at",null)` 로**: 선언은 **사실**이고, resolve 는 "매니저가 Cin7 을 고쳤다"지 선언이 취소된 게 아니다(취소는 delete 라 행 자체가 없다) — voided(롤백 무효화)만 제외하면 같은 오더 재작업에도 정확하다. ⚠️ **picker 쪽 영향이 팩커보다 넓었다(3갈래)**: ① `finish()` 의 short_pick 부당 집계(같은 구조) ② `p_short_refresh`/`p_short_delete` 정리 어긋남 ③ 마찰 모달의 "선언 라인 제외" 오판정(불필요한 강한 마찰). ⚠️⚠️ **`image_mismatch` 의 loadImageFlags 는 같은 `.is("resolved_at",null)` 인데 그건 옳다 — 고치지 말 것**: image_mismatch 의 resolve = "리포트 처리 완료"(눌린 상태 소멸이 맞음 — 토글 복원) / stock_short 의 resolve = "Cin7 고침"(선언 사실은 존속). **같은 조건식이 한쪽에선 버그고 한쪽에선 옳은 이유가 이 의미 차이다** — 다음에 image_mismatch 를 "같은 버그"로 보고 고치면 resolve 된 리포트가 눌린 상태로 부활하는 새 버그가 된다. ⚠️ 토글 취소 delete 의 `resolved_at is null` 조건(양 파일)도 그대로 — "해소된 감사기록은 지우지 않는다"는 옳은 조건이다(resolved 선언 재클릭 시 0행 delete + 거짓 "cancelled" toast 엣지는 백로그).
- ⚠️⚠️ **선언하지 않은 부족은 실수다 — 규칙 유지 (2026-08-11 사용자 결정 · SO-14455)**: 같은 SKU 가 `short_pick`(19:48) → `short_after_pack`(20:06, responsible=팩커 시점 픽커)으로 두 번 기록된 데 대한 "이중 계산 아니냐" 질문에 — **"규칙을 유지한다. 안 그러면 실수와 실제 인벤토리 틀어짐을 구분할 방법이 없다."** 선언은 사람만 할 수 있는 판단이다 — 그게 없으면 시스템은 "선반에 없었다"와 "덜 뽑았다"를 구분할 수 없다. **해결책은 코드가 아니라 작업자 교육** — 선언하면 실수가 아니고 안 하면 실수가 된다는 인과가 명확히 전달돼야 한다. ⚠️ 위 resolve 소실 실사고가 여기 직결된다 — 그동안 "선언해도 매니저가 처리하면 실수로 잡히던" 경험이 쌓였을 수 있으니 **고쳐졌다는 것을 작업자에게 알려야 선언 문화가 회복된다** (세션 문서 12장).
- **⚠️ 선언은 실수를 지우는 것이 아니라 재분류다.** 주문 수량은 그대로(여전히 부족 출고), 차이는 discrepancy 큐에 남아 **매니저가 Cin7 에서 수동 조정 → "Cin7 Fixed"** — 규칙 20 리시빙 차이 처리와 같은 구조(자동 조정 없음). **남용 방지가 이 구조 자체다**: 선언해도 기록은 남고, 매니저가 bin 을 확인하는 단계에서 걸러진다.
- **초과는 실물을 셀 수 있는 팩커가 라인별로 구분한다**(완료 시 2택 모달): `Picker brought extra`(실물이 정말 많음)→`over_pick` responsible=picker+반납 / `I scanned twice`(실물은 정확)→`pack_scan_mistake` **선해소 insert**(responsible=null — 감사 기록만, 실수 집계 제외).
  - ⚠️ **왜 바꿨나 — 기존 초과 처리의 두 결함**(2026-08-04 이전): ① 초과 confirm 이 **전 라인 일괄 1회**였다. 초과 라인이 여러 개면 OK/Cancel 하나로 전부 같은 판정이 되어 "이 라인은 픽커가 정말 더 가져왔고 저 라인은 내 스캔 실수" 를 **나눌 수 없었다**. ② `Cancel`(=스캔 실수) 은 **아무것도 기록하지 않았다** → 사후에 "실수였는지 그냥 취소였는지" 구별이 불가능. → **라인별 2택 모달**(promise 기반)로 교체하고 두 갈래 **모두** 행을 남긴다.
  - ⚠️⚠️ **`pack_scan_mistake` 를 실수 집계에 넣지 않는 것은 타협이 아니라 설계다.** 넣으면 팩커가 정직하게 "내가 두 번 스캔했다" 를 고르지 않고 픽커 탓(`over_pick`)으로 떠넘긴다 — **정직한 기록을 벌주면 기록 자체가 사라진다.** `recv_off_po` 를 리시버 실수에서 뺀 판단과 같은 논리이며, 새 자백형 reason 을 추가할 때도 같은 기준으로 판단할 것.
- **`responsible` 은 실수 귀속 전용 컬럼이다** — Stats mistake tally 가 이걸로 센다. stock_short/pack_scan_mistake 에 responsible 을 넣지 말 것(선언자는 `declared_by`). `recv_over/recv_short/recv_off_po` 도 실수 집계에서 제외(공급사/실물 사실 — off-PO 확인 소홀 리뷰는 admin Receiving 승인 게이트가 담당).
- **short_pick 의 픽커 이름은 새 컬럼이 아니라 `pick_task_id` 조인으로 표시한다 (2026-08-13 설계 확정 — (가') 새 컬럼안 폐기)**: 근거 = 마이그레이션 0 · 픽 완료 RPC 무접촉(검증된 경로) · **과거 16건 소급 표시**(새 컬럼은 백필 불가라 과거 0건) · responsible 무접촉이라 Stats 집계 무영향 — ⚠️ **새 컬럼이 이기는 시나리오가 하나도 없었다.** 의미 차이(스냅샷 vs 현재 담당자)는 롤백 시 discrepancy 가 voided 되므로 창이 좁다. 표시(admin Discrepancy 탭) = 회색 "picked by {name}"(completed_by 우선→assigned_to 폴백) / Map 에 없으면 "picker unknown — batch removed"(롤백으로 task 삭제 — `_srcGone` 과 같은 판정 원리). **분기 순서 고정: declared_by → responsible → pick_task_id → "—"** — stock_short 는 declared_by 가 있어 1분기에서 걸리므로 회색으로 안 내려간다(순서가 그것을 보장). FK 없음이라 임베드 불가 — `.in` 일괄 조회(schema.md 2026-08-13 보강 참조).
  - [실측 2026-08-13] **`pick_task_id` 커버리지 경계**: 08-06 13:22 UTC 이전 = 전량 NULL(53건) / 08-07 01:56 UTC 이후 = 100%(16건) — **경계 겹침 0**, "부분 커버리지"가 아니라 "그 시점부터 채워지기 시작했다". 커밋 로그는 08-05 picker.html 첫 기입으로 보이나 데이터는 08-06 RPC 시점과 맞는다(미해결 — 설계 판단에는 무영향: 08-07 이후 100% 가 데이터로 확인됨). 📌 **교훈: 커버리지 23% 만 보고 "경로가 반쪽"이라 단정하지 말고 시점 분포를 볼 것** — 봤더니 깨끗한 경계였다. 비율은 시점 축을 숨긴다.
- 구현 지도는 `references/frontend.md` 「2026-08-04」 · 스키마는 `supabase/migrations/20260804000000_disc_stock_short.sql`(declared_by + 규칙 29 유니크 정착). ⚠️ **배포 순서: SQL 먼저, 프론트 나중**(규칙 23) — 컬럼 없이 선언 insert 가 실패한다.
- ⚠️⚠️ **`reason` 에는 2026-08-06 부터 CHECK 제약이 있다** (`20260806000000_receipts_uq_disc_reports_checks.sql` — 9개 값: short_pick·short_after_pack·over_pick·resolved_pack_recovery·stock_short·pack_scan_mistake·recv_over·recv_short·recv_off_po). **새 reason(자백형 포함)을 추가하려면 CHECK 를 바꾸는 마이그레이션이 코드보다 먼저 나가야 한다** — 안 나가면 새 분류의 첫 insert 가 400(23514) 으로 죽고, EF 리시빙 선기록 실패면 **Apply 가 통째로 막힌다**(규칙 27 R12). `wms_reports.kind` 도 같은 날부터 CHECK 4개 값(규칙 14) — 동일 절차. **커밋 훅이 이걸 자동으로 잡는다**(2026-08-06): `scripts/check-class-values.sh`(pre-commit, description 검사와 같은 지점)가 staged 코드의 reason/kind 리터럴을 마이그레이션 CHECK 목록과 대조 — 출처는 하드코딩이 아니라 `supabase/migrations/*.sql` 파싱이며, 같은 제약을 재정의하는 마이그레이션이 여러 개면 **파일명 정렬상 마지막 정의가 이긴다**(DB 적용 순서와 동일). CHECK 에 없는 값이 코드에 있으면 커밋 차단, CHECK 에만 있고 코드에 없는 값은 경고만(폐기 후보). 마이그레이션이 제약을 언급하는데 파서가 값 목록을 못 뽑으면 **모르면 멈춤**(낡은 목록 폴백 없이 실패). ⚠️ 정규식 한계 — 변수·함수 인자로 흘러가는 값과 테이블 참조에서 ±30줄 넘게 떨어진 조립은 못 잡는다(한 줄 삼항·`kindDb="…"` 대입은 잡음). **훅 통과 ≠ 보장** — 새 분류를 변수로 넣을 땐 여전히 사람이 마이그레이션 선행을 확인할 것.
- ⚠️ **2026-08-04 배포 — 현장 검증 기록이 없다**(코드 경로만 확인). "동작한다"고 쓰기 전에 백로그 「검증 대기」의 확인 항목을 실물에서 볼 것.
- ⬜ 백로그: packer `overScans` 메모리 전용(Hold/새로고침 시 초과 표시 소실 — 판정 "결과"는 기록됨) · 위 현장 검증 — 둘 다 「백로그 / 미해결」에 등록됨.

## 규칙 43 — Cin7 On Hold 감지 → WMS 보류 (⚠️ 2026-08-12 · 현장 미검증)

> 규칙 42 는 **결번** — "규칙 42 계열(근거의 출처)"이 기록 규칙의 비공식 번호로 여러 문서에 굳어 있어 충돌을 피했다.

**목적: 실수로 오더가 진행되는 것을 막는 안전장치.** 자주 쓰는 기능이 아니다 — 평소엔 존재감이 없고, 필요할 때 확실히 막는다. 릴리즈 후 WMS 작업이 끝날 때까지 `AdditionalAttribute1` 은 안 바뀌는 것이 정상이고, 드물게 보류가 필요하면 Cin7 에서 `On Hold` 로 바꾼다(해소되면 `2.Release to WMS` 로 되돌림).

> 📌 **설계 판단 6가지의 근거 표([결정])는 `docs/sessions/2026-08-12-hold-and-postgrest-cap.md` 5장이 정본** — 근거 없이 규칙만 남으면 "왜 보류는 자동인데 재개는 수동이지?" 같은 질문에서 되돌려진다. 아래 각 항목에 근거를 인라인으로도 남겼다.

- **감지 = hello 폴링의 Updated 트리거**: 유입 오더(already_exists)의 `wms_orders.cin7_updated`(유입 시점 Updated)와 목록의 현재 `Updated` 를 비교(0콜) — 다르면 상세 재조회로 판정. ⚠️ Updated 는 신호가 아니라 **트리거**(판정은 상세만 — 무관한 수정은 헛읽기 1회, 누락 없음). ⚠️ `wms_polled_sales`(미유입 전용)와 별개. 종전 갭("유입 후 변경 → WMS 모름")이 이걸로 닫혔다 — 정정은 `references/edge-function.md` 폴링 절.
- **보류 트리거는 `On Hold` 하나뿐** — "2.Release 가 아닌 전부"로 잡으면 정상 완료 오더(3.Finalized 등)가 전부 보류가 돼 기능이 무력해진다. **예상 밖 값 = `hold_state='unexpected'`**: 보류로 처리하지도 무시하지도 않는다 — admin 에 **원문 그대로** 알림(숨김·차단 없음, 매니저 판단). WMS 종착(closed)·voided 는 어떤 값이 와도 무시.
- **보류 동작 = "현재 단계는 마치되 다음 단계로 넘어가지 않는다"**: 대기 풀(picker pending·pending wave 카드·packer poolNew·fulfillment 보드)에서 **완전히 숨김**(라벨을 달아 무시하게 하는 것보다 안 보이는 게 확실하다) / **진행 중(내 배치·held)은 끝까지 허용** — 실물이 토트에 있는데 화면이 사라지면 되돌릴 근거도 절차도 없다. 완료 직후 "ON HOLD — 다음 단계로 안 넘어감" 안내(`notifyIfHeld`). wave 는 멤버 하나라도 보류면 **시작 전 카드 전체 숨김**(부분 시작 불가 — unwave 로 정리).
- ⚠️⚠️ **정정 (2026-08-12 당일 — SO-14592 실측): 작업 화면은 ~~picker·packer·fulfillment 셋~~ → 넷, `manager.html`(Order Splitting) 포함.** 첫 배포 직후 On Hold 오더(pending 단계)가 감지·admin 표시는 정상인데 **Splitting 목록에 그대로 보였다** — pending 오더는 픽 배치가 없어 picker 에 애초에 안 나오고, **pending 의 유일한 출구가 분할 화면**이라 여기를 안 막으면 보류가 무력화된다. 수정: `loadOrders` 필터(Split·Group 이 같은 배열 — 한 곳으로 둘 다) + **분할 확정·wave 생성 직전 `holdBelt` 서버 재확인**(첫 쓰기 앞 — 미리보기는 실물이 없어 버려도 손실 0: "진행 중 유지" 원칙은 토트에 실물이 담긴 경우를 위한 것이라 예외가 아니라 정확한 적용. "보류됨"과 "확인 실패"는 alert 문구 구분 — 매니저 대응이 다르다). 📌 **왜 놓쳤나 — 교훈**: 첫 설계에서 "작업 화면"을 픽·팩·풀필먼트라는 **화면 이름으로 나열**했고, 단계별로 **"이 상태의 오더가 다음으로 가는 경로가 무엇인가"를 세어보지 않았다**(pending→분할, picking→팩, packing→풀필, packed→Finalize — 이렇게 셌으면 분할 화면이 첫 줄에 나온다). **다음에 비슷한 게이트를 만들 때는 화면이 아니라 상태 전이 경로를 전수하라.**
- **Finalize 서버 재확인 벨트가 마지막 방벽** — 픽·팩이 끝났어도 출고 직전에 `hold_state` 를 서버 재조회해 on_hold 면 전체 차단(pack progress 벨트와 같은 지점·같은 원칙 — 확인 실패도 차단). unexpected 는 경고 후 진행 허용(차단하면 정상 오더가 갇힌다 — 사용자 결정).
- **재개는 수동만 — 비대칭이 의도다**(막는 건 자동=빨라야, 푸는 건 수동=신중해야. 보류됐던 오더는 문제가 있었던 것이라 사람이 한 번 봐야 한다): Cin7 복귀를 폴링이 보면 `hold_releasable_at` 표시만. admin "Re-check & resume" → **hello EF `?action=hold_recheck`** 가 **Cin7 을 재확인(1콜)한 뒤에만 해제** — 안 그러면 다음 폴링이 다시 보류로 되돌려 두 시스템이 싸운다. 업무 원칙 = **"Cin7 을 먼저 풀고, 그걸 인지한 매니저가 허가한다"**. `unexpected` 는 Cin7 정상 복귀 시 **자동 해소**(아무것도 안 멈췄으므로 — on_hold 와 비대칭 의도) · 강제 dismiss 없음(WMS 에서 알림만 끄면 Cin7 불일치가 숨는다 — 사용자 결정).
- ⚠️⚠️ **hold_recheck 는 레포 첫 서버측 사용자 권한 게이트**(anon 401 · `role='admin' || perms 'apply'` — staff-create 의 `/auth/v1/user` 패턴 이식). 배경 실측은 규칙 8 각주. **2026-08-13 부터 게이트는 `_shared/authgate.ts` 공용**(receiving 확대와 함께 추출) + **⚠️ active 검사 신설** — 종전엔 active 를 안 읽어 비활성 admin 세션이 통과했다(백로그 「보안」 참조).
- **캡 굶주림 없음(self-draining)**: 판정 후 `cin7_updated` 갱신으로 처리된 오더는 후보에서 자동 이탈(SO-14106 의 영구 잔류와 반대 구조) · 정렬 최신 우선 · `HOLD_CHECK_MAX=10` · 잘린 수는 `hold_check_deferred`(여러 회차 연속 >0 이면 캡 재검토). `cin7_updated is null` 행도 후보(비교 불가 행이 영원히 안 빠지게 — 사용자 지시. 2026-08-12 실측은 757건 전부 채워짐/null 0). ⚠️ **캡 재검토 조건에 실제 도달 (2026-08-14 dry-run 실측)**: `hold_checked` 10(캡 도달) · **`hold_check_deferred` 24** — 5분마다 10건씩이라 후보 34건 소진에 3회차(15분). 실해는 없다(`hold_detected` 0 — 실제 보류 없음). ⚠️ **후보가 34건이나 쌓인 이유 미확인** — `cin7_updated` 가 목록의 Updated 와 안 맞는 오더가 그만큼 있다는 뜻. ⬜ 조사: 자연 이월인가·self-draining 이 안 도는가 → 캡 상향 판단.
- 저장 = `wms_orders` 4컬럼(`hold_state/hold_progress/hold_detected_at/hold_releasable_at`, `20260812000000_wms_orders_hold.sql`) — status 는 무접촉(직교 플래그. 세 화면이 이미 wms_orders 임베드라 조인 추가 0). admin Status 탭 보류 목록은 **WMS 단계 표시 필수**(극단 케이스는 기존 Rollback 으로 — 강제 중단 도구는 안 만든다, 사용자 결정 F).

## 현재 진행 상태 (2026-08-04 기준)

**전 기능 LIVE — wms.asung.ca. 리시빙 PO 경로 실전 성공. 트랜스퍼 창고간 Apply = 청크 v3 + checkpoint repair 로 TR-03144 완주(2026-07-31). 배터리 최적화 완료. 리시빙 동시 작업 정식 지원. ⚠️ fulfillment 스캔 배정은 배포됐으나 실전 미검증(규칙 36). 트랜스퍼 착지는 앞으로 창고만 지정(규칙 40 — (a) 케이스 실전은 미검증). ⚠️ 2026-08-04 배포분(규칙 41 픽·팩 선언/초과 2택 · 규칙 20 Status 조회 · **풋어웨이 bin 단위 완료 + admin Apply 주황 경고·Awaiting putaway**)도 **현장 미검증** — 백로그 「검증 대기」. ⚠️⚠️ **2026-08-05 배포 4건(완료 확인 마찰 모달 — SO-14129 · 리스트뷰 행 탭+available 칩 · 리시빙 기대치 인보이스 전환 · receiver 리포트 3종)도 현장 미검증** — 백로그 「검증 대기」 맨 위. 그중 **인보이스 전환의 Advanced 경로 + 첫 Apply 가 가장 중요**하다(재고·Cin7 반영이 걸린 유일한 건 — 아직 안 받은 PO 로 검증할 것, PO-01068 은 이미 Apply 됨).

**2026-08-05 세션 — 배포 4건 · 커밋 `b426275`·`d64ebff`·`70cf91d`·`9c97618` (⚠️ 전부 현장 미검증 — 백로그 「검증 대기」 맨 위)**
- ✅ **SO-14129 원인 확정 + 완료 확인 마찰 모달** (규칙 9 · `wms-confirm-modal.js` 신규 공용 모듈): **물리 탭 2회(footer `Complete pack` 오탭 → native confirm `OK` 오탭)만으로 스캔 0건 60줄 오더가 완료된다 — 조건·타이밍 불필요, 상시 재현**([실측]). ~~H1 스캐너 CR 이 confirm 을 승인~~ 은 **안드로이드 태블릿 실측 반증**(스캐너는 읽었으나 팝업 무반응 · 접미는 CR 뿐 → Tab 후보도 사망). 대응은 **하드 차단이 아니라 마찰 모달**(사용자 결정). `20260805000000_completed_by_pack_link.sql`(completed_by · pack_task_id/pick_task_id). 조사 기록은 `docs/incidents/2026-08-04-so14129.md`
  - ⚠️⚠️ **조사 과정에서 두 번 헛짚었고 원인이 같은 종류다 → 「기록 규칙」에 2항목 승격**(2026-08-05 사용자 결정 — **규칙 번호로는 올리지 않았다**): "근거의 출처를 표시한다"(일반적 동작 **설명**이 사고 당시 **관찰**로 잘못 승격돼 하루치 조사가 헛돌았다 — 규칙 27 R11 과 같은 계열) · "UI·입력 동작은 코드 읽기로 결론내지 않는다"(재포커스 코드가 전 지점에 있었지만 진짜 원인은 **인접 버튼 오탭** — 실물 1회가 코드 조사 4시간보다 값쌌다). 규칙 17·규칙 27 R11 에 상호참조 한 줄씩.
- ✅ **리스트뷰 정보 접근성** (규칙 9 · `references/frontend.md` 「2026-08-05 — 리스트뷰」): packer available 칩(`wms_sku_bins` 일괄 1요청) + picker/packer 행 탭 → 임시 싱글뷰(`viewOverride`) + `← Back to list`
- ✅ **리시빙 기대치를 인보이스 기준으로** (규칙 20 개정 · Apply 게이트 invBlock 전환 · `20260805100000_receiving_expected_invoice.sql` 의 `expected_source`/`cin7_type`): 오더 라인 기준이 만들던 **가짜 `recv_short` 제거**([실측] PO-01068 Advanced — Order 92줄 vs Invoice 77줄). ⚠️⚠️ **Simple 만 확인됐다 — Advanced 경로와 첫 Apply 가 미검증이고 이게 오늘 배포분 중 가장 중요하다**(bin 이동 캡 `min(received, expected)` 의 근거가 바뀌었다). **아직 안 받은 PO 로 검증할 것**(PO-01068 은 이미 Apply 됨)
- ✅ **문서 정합성 정리 (2026-08-05 후반)**: description 감축 1017→**722자**(여유 302 — 별건 작업이었던 백로그 항목 해소) · SO-14129 조사 기록 정정(H1 반증 · "alert" 관찰 취소) · `cin7-api` ↔ `asung-apps-script` **Cin7 Script Property 키 이름 드리프트 통일**(`CIN7_APPLICATION_KEY` — 실호출 1회 실패의 원인, ⚠️ Script Properties 실물 확인은 미실시) · 내일 후보 5건 백로그 등록
- ✅ receiver recvView 싱글뷰 ⚑Barcode changed/⚑Box barcode/⚑Image differs — picker/packer 와 같은 성격(매니저 알림만, Cin7 쓰기·bcMap 수정 없음), `receipt_id`+`po_number` 귀속(`20260805200000_reports_receiving.sql`), `source='receiver'`. **receiver 전용 구현**(사용자 결정 — 공용 모듈 추출은 검증된 픽·팩 코드를 건드려 보류) · **factor 리포트 제외**(사용자 결정 — 바코드만). admin `REPORT_KIND` box_barcode + Order 열 `order_number||po_number`. ⚠️ **SQL 먼저 배포**(규칙 23), ⚠️ **현장 미검증**
- ⬜ 공용 리포트 모듈(wms-reports.js) 추출 — wave 귀속 버그(규칙 14) 수정과 묶어 별도 작업(백로그)

**2026-08-04 세션 (폴링 EF saleList 유입 누락 — 규칙 12 실사고 2건)**
- ✅ **429 백오프 + 회차 조기 종료**: saleList 페이지 순회가 429 즉시 throw 로 죽던 것 → 공용 **`_shared/cin7.ts`**(receiving 의 `cin7()` 추출 — 동작 동일 diff 증명) 백오프 후, 소진 시 throw 없이 조기 종료 + `rate_limited(+at_page)` 노출. ⚠️ `_shared` 변경 시 **hello·receiving 둘 다 재배포**. ⚠️ receiving 은 import 교체만(동작 불변) — **재배포 시 Apply dry-run 으로 확인할 것**
- ✅ **상세조회 최신 오더번호 우선(내림차순)**: 오름차순 + MAX_DETAIL 캡 + "비대상은 저장 안 됨 → 매 회차 fresh 잔류" 가 합쳐져 최신 오더가 영구 굶주림(SO-14106). 규칙 20 오름차순 함정의 두 번째 사례
- ✅ **진단 필드 확장**: `list_total/list_fetched/truncated/oldest·newest_scanned/rate_limited/detail_capped_orders` + `skipped_detail` 에 `skip_picked` 포함 — "안 들어온다" 진단 순서는 규칙 12
- ✅ 실측: 스캔 범위는 무죄(`list_total` 140) · `Status=ORDERED` 도 정상 유입 · **Advanced Sale 정상 처리**(SO-14023 라인 15개 일치, Type 필터 불필요)

**2026-08-04 세션 후반 (픽·팩 실수 vs 재고 불일치 구분 — 규칙 41 신설)**
- ✅ picker/packer `⚠ Not enough stock` 선언(stock_short·declared_by) + 팩커 초과 라인별 2택 모달(over_pick / pack_scan_mistake 선해소) + admin 카테고리 필터·선언자 표시 + Stats `NOT_MISTAKE`(recv_* 포함 제외 — 그간 리시버가 부당 집계됨). ⚠️ **배포됐으나 현장 미검증** — 백로그 「검증 대기」
- ✅ **schema.md 정정: `wms_discrepancies.note` 컬럼은 실물에 없다**(문서만 있었음 — 규칙 29 또 한 사례)
- ⬜ **마이그레이션 2건이 원격 히스토리에 없다 (2026-08-04 실측)** — `supabase migration list --linked` 결과 `20260802000000_wms_order_date`·`20260804000000_disc_stock_short` 둘 다 `remote` 가 **빈 값**이다. 그런데 **컬럼은 원격에 실재한다**(REST 프로브: `order_date`·`declared_by` 는 200, 없는 컬럼은 42703 — 대조군으로 확인) → 컬럼이 **마이그레이션 밖 경로로 먼저 적용**됐고 파일은 사후 기록이라는 뜻이다(스킬 상단 「DB 스키마 변경 절차」가 금지하는 드리프트 — 이번엔 응급 수정의 잔재).
  - ⬜ **사람이 `supabase db push`** — 기능 배포가 아니라 **히스토리 정렬**이 목적이다. 안 하면 새 환경·`db reset` 에서 `order_date` 컬럼이 없어 **오더 유입이 죽고**, `uq_disc_receipt_sku` 가 부분 유니크로 되돌아가 **리시빙 discrepancy 가 다시 조용히 사라진다**(규칙 29 재발).
  - ✅ **둘 다 멱등이라 이미 적용된 원격에 다시 실행해도 안전**하다(확인함): `add column if not exists` · `drop index if exists` + `create unique index if not exists`.

**2026-08-04 세션 마지막 (풋어웨이 완료 입도 — 번호 규칙 없음 · `references/frontend.md` 「풋어웨이 완료 입도」)**
- ✅ **`putaway_done` 이 PO 에서 거의 항상 false 였던 원인 = 코드가 아니라 입도.** 완료 표시가 라인별 `togglePlaced()` 하나뿐이었다. 실측: TR-02935 344/344·TR-03144 327/327(둘 다 `updated_at` distinct_sec 222·215 → **작업자가 실제로 하나씩 누른 것 — "수동 SQL 일괄 UPDATE" 가설은 반증됐다**) vs PO-01069 0/26·PO-01073 0/85. **5~6라인은 누르고 11라인 이상은 아무도 안 누른다** — 작업자는 **bin 단위로 움직인다**(한 자리에 서서 다 놓고 이동)
- ✅ **receiver.html: bin 그룹 헤더 `Place all in this bin`**(클릭이 라인 수 → bin 수). 저장은 기존 라인 단위 경로 그대로(`queueWrite`+`.select()` 1행 — 규칙 24) · **동시 8개 풀**(규칙 34) · **실패해도 로컬 유지 + `NOT SAVED` 표시**(규칙 24 파생 원칙) · `placingBin` 중복 실행 차단. 완료 요약의 `Not yet placed` 는 SKU 나열 → `12 lines not placed in 4 bins`
- ✅ **admin.html: Apply 버튼 주황 경고**(`putaway_bin` 있고 `putaway_done=false` 인 라인 있으면 — 배지·confirm·Review 배너·History) + **「Awaiting putaway」 섹션**(`Put away →` 딥링크). ⚠️ **비활성화하지 않는다** — 관행 정착 전 하드 게이트는 모든 Apply 를 멈추고 작업자가 안 놓고 눌러 통과시켜 **지표가 더 거짓이 된다**(규칙 41 `pack_scan_mistake`·`recv_off_po` 와 같은 논리 — 정직한 기록을 벌주면 기록이 사라진다). 재검토는 백로그
- ✅ **`ensureReceiptOpen()`** — Apply 된 receipt 를 열어둔 화면의 풋어웨이 쓰기 차단(규칙 27 R5 부분 완화). ⚠️ **규칙 28 의 `ensureMine()` 은 리시빙에 못 쓴다**(`wms_receipts` 에 `assigned_to` 없음 + 나눠 받기가 규칙 24 기능) — 규칙 28 항목 참조
- 📌 **번호 규칙(42)으로 승격하지 않음** (사용자 결정) — UI 입도 문제라 "모르면 사고가 나는 것"이 아니다. 기준은 「기록 규칙」에 남겼다. **description 압축은 별건**(백로그)
- ⬜ **오늘 배포분 전부 실물 미검증** — 백로그 「검증 대기」

**2026-08-02 세션 (인쇄물 3건 — 규칙 15 갱신 · `references/frontend.md` 「2026-08-02」)**
- ✅ **픽리스트 인쇄 공용화 + picker·packer 재인쇄**: manager 안에 있던 HTML·CSS·JsBarcode 를 **`wms-picklist.js`**(신규 파일 — 형식의 단일 출처)로 추출, picker/packer 헤더에 **🖨 Print**. 종이를 잃으면 손 쓸 방법이 없던 문제(픽리스트가 소유권을 보증 — 규칙 22/28). ⚠️ **바코드 값 = `batch_label`**(웨이브는 wave label) — 스캔 재진입 키라 다른 값을 넣으면 인쇄물로 화면에 못 들어온다. ⚠️ `window.open` 은 **클릭 핸들러 안에서 먼저**(await 뒤면 팝업차단)
- ✅ **픽리스트 Order Date**(현장 요청): `wms_orders.order_date` 신설(`20260802000000_wms_order_date.sql`) + 폴링 EF `hello` 매핑(`d.OrderDate || c.OrderDate` 앞 10자). ⚠️ **컬럼이 EF 보다 먼저**(없으면 헤더 insert 실패 = 유입 전면 중단). **신규 유입분부터만 차고, 값 없으면 줄/열 생략**이라 옛 오더도 깔끔히 찍힌다
- ✅ **팩킹 유닛 라벨을 식별자만으로**(`P1` · `B3 on P1`) — **`wms-packing.js`**(신규, 라벨의 단일 출처). `SO-13849+-P1` 의 `+` 는 표시가 아니라 **생성 단계 버그**였다(`addUnit` 이 "외 여러 건" 접두사를 DB `wms_pallets.label` 에 저장) → 표시에서 자르지 않고 생성을 고쳤다. 번호는 **"개수+1" → "이미 쓰인 최대 번호+1"**(중간 유닛 삭제 후 중복 방지) + `unitCode()` 옛 라벨 호환 계층(마이그레이션 없음 — 라벨은 표시 문자열이고 유닛의 키는 `id`)
- ✅ **팩킹리스트 오더 소계 캡션 상시 표시 + CSV `Order` 열**: 캡션의 역할을 "혼합 유닛의 구분선" 에서 **"표의 신원"** 으로 재정의(표 한 장만 떼어 봐도 누구 물건인지 알아야 한다) → 4경로 문구 통일(fulfillment 유닛별·스토어별 종합·admin Print·PDF). CSV 는 정렬·필터로 행이 흩어져 캡션만으로 부족 → **행마다 오더번호**를 싣고 7열로 정렬
- ✅ 스토어별 종합 팩킹리스트 혼합 팔렛 표기(`also contains` 오더 목록 · 유닛 지도 · 최상위 유닛 그룹핑)

**2026-07-31 세션 (Apply 청크 v1→v3 — 규칙 30-2·R10 해소 + 규칙 38~40)**
- ✅ **EF Apply 청크 처리**: 상한 도달 시 정상 종료(`done:false, groups_remaining, lines_moved/lines_total`) + **매 회차 apply_note 갱신**(`groups_remaining(N):` 계약 표식 — buildApplyPlan 재개 게이트·admin 공유) + `applied_at` 은 done:true 회차에만. 429 는 백오프 재시도(상한 2회) 후 회차 조기 종료(failed_moves 제외), 그룹 간 sleep 300→150ms — 규칙 21 청크 절
- ✅ **청크 v2 — 이중 가드로 재조정**: 1차(`APPLY_MAX_GROUPS=30`)는 배포 후에도 **첫 회차조차 완주 실패**(TR-03144 실측 — `exported_base` 210→225→250 전진, `apply_note` 는 null 지속) → **12 로 인하 + `APPLY_TIME_BUDGET_MS=20000`**(요청 시작 t0 기준·Cin7 POST 앞 판정·먼저 걸리는 쪽) + `stopped_by:"groups"|"time"` 기록 + **종료부 불사**(receipt PATCH 실패에도 응답 반환, `note_saved:false`). 원칙: **회차는 반드시 완주해야 한다 — 완주하지 못하면 기록이 안 남아 원인 추적이 불가능하다.**
- ✅ **admin 자동 반복**: done:false → 자동 재호출(회차 사이 dry-run 없음), 진행률 배너/버튼(EF 응답 필드 그대로), Stop 버튼(회차 경계 중단 — 체크포인트까지 안전·`Continue apply` 로 재개), 무한루프 가드(`groups_moved===0` 중단 + 회차 상한 20), beforeunload·재진입 차단 반복 전체 유지
- ✅ **청크 v3 — 실패 그룹이 미처리 그룹을 가로막지 않게 (배포 완료)**: v2 배포 후 TR-03144 실측 `CHUNK - 0 group(s) moved, 3 failed · stopped_by=time` — 실패 3그룹(400 응답 느림)이 plan 앞자리에서 매 회차 20초를 소진해 46개 미처리 그룹이 영구 정지 + `groups_moved===0` 가드가 자동 반복도 중단. → **①미시도 우선 정렬 ②연속 3회 실패 bin 격리(`permanently_failed`, `Retry failed bins`+`retry_failed=1` 로 해제) ③실패 시도 시간 상한 6초** + 계약 마커 2개 추가(`permanently_failed(N):`·`fail_counts:{...}`) + admin 버튼 우선순위(`Continue apply` > `Retry failed bins`)·가드 정교화(`groups_tried===0` 2연속만 중단, 상한 30) — 규칙 21 청크 절 v3 항목
- ✅ **checkpoint repair(목적지 되읽기 회복) + R10 실측 확인**: TR-03144 격리 10 bin/25 라인 수동 확인 결과 **전부 목표 bin 에 이미 도착** — 원인은 타임아웃이 Cin7 POST 와 markExported PATCH 사이를 끊은 것(죽은 회차 수와 격리 bin 수 거의 일치). `Available quantity … is 0` 400 패턴에만 `/ref/productavailability` **OnHand** 되읽기로 `exported_base` 자동 회복(`checkpoint_repaired: N`) — 규칙 21 ④·규칙 27 R10 실측 확인 항목. **근본 원인은 v3 완주 보장으로 해소, 이 경로는 잔여물 정리용.**
- ✅ **TR-03144 완주로 트랜스퍼 청크 실전 검증 종료**(자동 반복·격리·checkpoint repair 동작 확인)
- ✅ **PO 경로 이식 (2026-07-31 후반)**: 청크·체크포인트(⚠️ 의미 = "문서에 실은 양")·실패 수집/격리 + **authorize 게이트**(1회 제약 — 모든 bin 이 실린 마지막 회차에만, 미완이면 DRAFT 유지 + admin `Cin7 DRAFT` 배지) + 공용 `chunkGuard()` 추출(트랜스퍼 동작 불변). ⬜ 실전 검증: **작은 PO 로 commit 먼저**, PO-01070 은 dry-run — 백로그 6번
- ✅ **Put away API 탐색 종결(규칙 38)** — TR-03259 실측: v2 API 는 UI 의 라인별 Put away 를 노출하지 않는다. bin 별 별도 트랜스퍼가 유일한 경로 — 같은 탐색 반복 금지. cin7-api `stock-write.md` 에도 기록.
- ✅ **TR 분할 무익 확정(규칙 39)** — TR-02935 3분할 계산: 144 → 146/154/217 그룹으로 오히려 증가. 채택 안 함.
- ✅ **트랜스퍼 착지 정책 변경(규칙 40, 사용자 결정)** — 집결 bin(EZ010101) 폐기, 창고만 지정. ⬜ (a) 케이스 실전 검증은 다음 트랜스퍼(dry-run 먼저).

**2026-07-30 세션 (규칙 35~37)**
- ✅ **풋어웨이 진입 프리즈 수정**(직렬 await 제거 → 백그라운드 큐) — 규칙 34
- ✅ **admin Apply 버튼 상태 머신**(Checking…/Applying…/✓ Applied/⚠ Partial/Apply failed, 배너·beforeunload 는 commit 구간만, 플래그 기반 재진입 차단, rAF 150ms 타임아웃) — 규칙 35. ✅ **매니저 2명 동시 Apply — 2026-08-06 서버 in-flight 잠금으로 해소(PO·트랜스퍼 공통)**(규칙 27 R4)
- ✅ **`image_mismatch` 리포트**(picker·packer 싱글뷰 ⚑Image differs 토글, `wms_reports.kind` 세 번째 값 — CHECK 제약 없음 실물 확인) — 규칙 14. ⚠️ **발견: 기존 두 kind 는 wave 모드에서 오더 귀속이 틀린다**(`task.order_id` 고정) → 백로그
- ✅ **admin Stats 확장**(리시빙·트랜스퍼·풋어웨이·discrepancy, Throughput by worker 통합, 근무시간 기준 소요) — 규칙 37
- ✅ **admin LIVE NOW 전 화면 확장**(리시빙 `stage:"receiving"|"putaway"` 재-track·트랜스퍼·풋어웨이·fulfillment presence 합류, 미상 screen 은 Picking 폴백 금지 → `Other`) — 규칙 24 · `references/frontend.md` 「admin LIVE NOW 전 화면 확장」
- ⚠️ **fulfillment 스캔 배정(2026-07-29 배포) 실전 검증 미완** — 규칙 36

**2026-07-28~29 세션 (규칙 29~33)**
- ✅ **discrepancy 유니크 인덱스 수정**(부분 → 전체) — `on_conflict` 42P10 으로 **리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않았음**을 발견·해소. SQL `supabase/wms_disc_uq_fix.sql`. ⬜ **같은 내용을 새 마이그레이션으로 담아 로컬·원격 정렬**(사람이 `db push`). — 규칙 29
- ✅ **TR-02935 종료** — 4회 Apply(124 라인 이동) + 나머지는 Cin7 수동 처리, 초과/부족은 ST-00794/00795 재고 조정. 착지·수량 실측은 규칙 30-1.
- ⬜ **Apply 회차당 그룹 상한 미구현** — 144 그룹은 1회에 안 끝나고 타임아웃 시 `applied_at`·`apply_note` 가 둘 다 null. 규칙 30-2 (최우선 백로그)
- ⬜ **Apply 대기 중 수동 이동 경고 문구**(admin) 미구현 — 규칙 30-3
- ⚠️ **`exported_base` 수동 UPDATE 로 receipt 을 닫은 이력이 있다**(TR-02935) — 다시 하지 말 것. 규칙 30-4
- ⚠️ **원가 0 재고 재평가 = 미해결**(Non-zero 0 + Zero stock 재입력은 상계되지 않고 재고가 2배가 된다) — 규칙 31
- 📌 bin 재고 대조 리포트 확정(Stock Level Report + Bin 컬럼) — 규칙 32 · ⬜ bin↔bin 이동 화면은 설계만 — 규칙 33

**픽 소유권 가드 (2026-07-28 세션 — 규칙 28)**
- ✅ picker.html·packer.html: 쓰기 직전(`saveLine`/Complete/Hold) + `visibilitychange`·`focus` 에서 `assigned_to` 재확인 → 아니면 **프리즈**(입력·버튼 비활성 + 리로드 전용 모달, **로컬 수량 flush 안 함**). 타이머 0 유지(규칙 22). wave 는 `wms_waves` 행 기준. ⬜ 원자화(claim_seq)는 백로그.

**리시빙 동시 작업 (2026-07-27 세션 — 규칙 24~27) · 커밋 4개**
- ✅ **L1 라인 단위 저장**(`unconfirmed`+`writeChain`, `.select()` 1행 판정) / **Hold·finish 의 전체 배열 덮어쓰기 제거** — 함께 받던 사람 작업이 되돌아가던 근본 원인 해결
- ✅ **L3 완료 요약 서버 재조회**(`serverChecks`/`preFinish`/`mergeServerRows`) — 남이 받은 물량이 short 로 뜨던 오표시 해결
- ✅ **L4 presence 배지**("🟢 also here", `wms-presence` 재사용, batch 필드 없음 — admin 오표시 방지). 타이머 0 유지(규칙 22)
- ✅ **bcMap·수량 핸들러 id 기반화**(규칙 25) — dropLine 왕복 창의 엉뚱한 SKU 가산 제거
- ✅ **채운 라인 아래로 정렬**(규칙 26, `isFilled`/`sortedIdx`) — autoAdvance 는 `sortedIdx(false)` 로 동선 유지
- ✅ `printReceivingList` 오타 수정 — `receipt.source` → **`source_type`**(트랜스퍼가 PO 로 인쇄되던 문제)
- ⬜ **미해결 위험 R1·R3·R5·R10 + RLS 창고 스코프 — 규칙 27 참조** (R4 는 2026-08-06 in-flight 잠금으로 PO·트랜스퍼 모두 해소 — ⚠️ 현장 미검증 · ~~EF 권한~~ 은 2026-08-13 서버측 게이트로 해소 — 규칙 27 「EF 권한」). R1 은 현재 팀 규칙(SKU 분담)으로 운영 중

**리시빙 (2026-07-24 세션 — PO 경로 완결)**
- ✅ **Cin7 stock received 3대 제약 실측 확정 & EF 반영**: 문서당 bin 1개(bin별 분할 POST) / 같은 SKU+bin 중복 병합 / **authorize=POST(PUT 405)**. 오래 헤맨 "Lines is invalid" 원인 = 여러 bin 한번에 → 해결. (규칙 21)
- ✅ **PO Apply to Cin7 실전 성공** — DRAFT(bin별) → authorize 자동까지. (PO-00965 검증)
- ✅ 빈 지정 스캔+드롭다운(빈자리 포함, EF action=bins) / 정렬 4종 / Zone→Bay sticky 점프 / Change 버튼 / 모바일 터치 / bayOfBin 파서 (규칙 20)
- ✅ admin **Review 버튼**(읽기요약+Reopen) / **Apply 권한**(perms `apply`, staff-admin 체크박스) / Resume-applied 필터 / **중복 receipt 방지**(한 PO=receipt 1개)
- ✅ 라스트빈 "no last bin" 근본 규명(sticky first_seen=7/6 한계, 버그 아님)
- ✅ **트랜스퍼 창고간 실측 완료 + EF 반영** (규칙 21): 완료=PUT COMPLETED·~~수량 초과 허용~~(⚠️ **2026-07-28 정정: 틀린 기록 — `TransferQuantity` 변경은 무시된다.** 규칙 21 정정 항목)·착지는 (a)bin 없이 창고 or (b)집결 bin 두 경우 → **From=det.To 로 통일**해 bin 이동. 워크플로는 **PO 와 동일**(받기→풋어웨이→Apply)로 확정.
- ✅ **차이 처리 정책 확립 + 구현**: 실물대로 Cin7 → 차이는 discrepancy 큐 → 매니저가 Cin7 수동 adjustment (규칙 20)
- ✅ **리시빙 리스트 프린트**(문서 바코드·라스트빈 정렬·체크박스) / **held_by Hold 이어가기** / **픽리스트 Reference**(규칙 23)

**배터리 최적화 (2026-07-24) — 규칙 22**
- ✅ picker/packer **heartbeat 전면 제거** → **스캔 이어받기**로 대체. admin BATCH ACTIVITY presence 기반(active/away). realtime presence·LIVE NOW 유지. reaper 는 느슨한 백업.

**백엔드 — 완료**
- ✅ 스키마: 운영 + 복제 2 + 신규(`wms_reports`·`wms_rollback_log`·`wms_waves`·**리시빙 `wms_receipts`/`wms_receipt_lines`**) + 컬럼추가(`perms`+**`apply`**·`fulfillment_type`/`finalized_by`/`finalized_at`·`note`·pick_tasks `wave_id`/`tote_no`·**`wms_orders.mgr_reviewed`**·**`wms_sku_bins.last_seen`**) — `references/schema.md`
- ✅ `wms_health_check()`(불변식 12검사) — 규칙 19. ✅ wave(`wms_waves.sql`) — 규칙 18. ✅ BQ→Supabase 동기화(`WmsSync.gs`). ✅ 자동 폴링 pg_cron `wms-poll-orders`. ✅ Edge Function `receiving` 배포(bin분할·authorize POST) — `references/edge-function.md`

**인증/권한 — 완료**
- ✅ 개인계정 Auth + `wms-auth.js`. RLS + auth_all. 세부권한 perms(split/admin/staff/stock/**apply**). 매니저 지정 완료.

**프론트엔드 — 완료 (7화면 + 리시빙 receiver.html)**
- ✅ 기본 7화면 + 영어화 + 로고 + Health 탭 + wave 모드. ✅ receiver.html(규칙 20). ✅ **헤더 규칙: ☰ Menu 는 유저이름 바로 옆**(전 화면).

**스키마 SQL — 전부 baseline 에 포함됨 (2026-07-26)**
예전에 하나씩 실행하던 `.sql` 파일들 — `wms_rollback_log`·`wms_reports`·`wms_schedule_polling`·`wms_staff_perms`·`wms_fulfillment_stats`·`wms_waves`·`wms_healthcheck`·`wms_receipts`+`wms_receipts_apply`·`wms_orders_review`·`wms_held_by`·`wms_disc_receiving`·`wms_order_reference` — 은 **모두 `supabase/migrations/20260101000000_baseline.sql` 에 흡수됐고 repo 에서 삭제됐다.**

- ✅ **실행할 것 없음.** 위 목록은 이력용. 다시 실행하지 말 것.
- 확인됨: `held_by`(pick/pack/waves) · `wms_orders.reference` · 리시빙 discrepancy 컬럼(`receipt_id` 등) 전부 baseline 에 존재.
- 예전의 "순서 의존"(`wms_waves.sql`→`wms_healthcheck.sql`) 도 baseline 안에서 이미 해결 — 신경 쓸 필요 없음.
- **앞으로의 스키마 변경은 새 마이그레이션만** — 위 「DB 스키마 변경 절차」. pg_cron 스케줄은 예외로 `supabase/ops/cron.sql` 에 기록(마이그레이션 아님).

## 백로그 / 미해결

📌 **여기가 백로그의 단일 목록이다** — 규칙 본문에 "백로그" 라고만 적고 여기에 안 올리면 잊힌다. 새 항목은 규칙 번호를 달아 아래 분류 중 하나에 넣을 것.

📌 **우선순위 (2026-08-13 저녁 확정 · 2026-08-14 갱신 — 원장 앞의 4건 전부 해소)**: ~~EF 게이트~~(✅ — 「보안」) → ~~Health 12검사 자동 실행~~(✅ 2026-08-14 — 「신규 기능」) → ~~Cin7 void 감지~~(✅ 2026-08-14 — 「신규 기능」) → ~~packer donePick 근본 수정~~(✅ 2026-08-14 — 캡 표 각주) → ~~"잘린 모수" 전수조사~~(✅ 2026-08-14 — 캡 표 아래 항목) → 🆕 ~~이미지 직결 EF~~(✅ 2026-08-14 저녁 — 계획에 없던 삽입 건, 실사고 대응 · 「상품 이미지 파이프라인」 절) → **재고 원장 shadow mode**(다음 차례). 근거는 원문 유지: 앞의 것들은 **"지금 틀리거나 뚫려 있는 것"** 이고 원장은 새로 짓는 것 — 기반이 새는 상태에서 층을 올리면 나중에 둘 다 의심하게 된다. 📌 **2026-08-14 마감: 우선순위 5건 + 계획에 없던 이미지 파이프라인까지 08-13~14 이틀에 전부 닫혔다.** 다음은 원장 — 선행 3건(FIFO 확정·Supabase 유료·Cin7 month-to-month)은 이미 해소(「원장 선행」). ⬜ 착수 시 첫 조사 = **Cin7 API 가 입고 레이어별 원가를 노출하는지**(「원장 선행」 ①의 기존 ⬜ 항목과 동일 — 중복 등록 아님).

### 리시빙 Apply — 최우선 (2026-07-31 갱신)

1. ~~Apply 회차당 처리 그룹 상한 (규칙 30-2)~~ — ✅ **2026-07-31 v2 구현 → v3 배포 → TR-03144 로 실전 검증 완료**: v1(상한 30 만)은 첫 회차 미완주(apply_note null), v2(그룹 12 + 시간 20초)는 실패 그룹이 예산을 선점(`CHUNK - 0 group(s) moved, 3 failed`), **v3(미시도 우선·격리 3회·실패 6초)로 완주** — 규칙 21 청크 절. 격리 10 bin/25 라인은 수동 확인 결과 전부 이미 목표 bin 도착(POST↔PATCH 사이 타임아웃 잔여물) → **checkpoint repair 로 자동 회복 추가**(규칙 21 ④·규칙 27 R10).
2. ~~**트랜스퍼 (a) 케이스 첫 실전 Apply** — (a)(창고 GUID, bin 없이 착지)의 완료 후 bin 이동은 실전 경험이 없다~~ — ✅ **2026-08-10 완주** (TR-03259: (a) 창고 착지 · 176그룹/321라인 · `ALL GROUPS DONE · 319/321 lines` · applied_at 09:26:48 · `checkpoint_repaired` 0회 — 세션 문서 `docs/sessions/2026-08-10-transfer-parallel-and-clamp.md` 2장. 잔량 정리는 문서 8장의 사람 몫 목록).
3. **Apply 대기 중 수동 이동 경고 (규칙 30-3)** — admin Receiving 의 Apply 대기 항목에 경고 문구 + 운영 규칙 명문화.
4. **`apply_note` 정규식 파싱을 컬럼으로** — 지금 EF 와 admin.html **양쪽이 같은 포맷을 파싱**한다(드리프트 위험). 계약 표식이 **4개로 늘었다**(2026-07-31 v3): `failed_moves(N):` + `groups_remaining(N):`(청크 미완) + `permanently_failed(N):`(격리) + `fail_counts:{...}`(연속 실패 카운트). `wms_receipts.failed_move_count`/`groups_remaining`/`fail_counts`(또는 jsonb 하나) 컬럼으로 승격.
5. **admin.html 배너가 EF 캡 규칙을 JS 로 중복 계산** — 같은 판정을 두 곳에서 하지 말고 EF 응답 필드를 그대로 표시하도록.
6. ~~PO 경로에는 체크포인트도 청크 상한도 없다~~ — ✅ **2026-07-31 이식** (규칙 21 PO 이식 절 · 규칙 27 R10): 전체 throw 제거(수집 후 계속) + `exported_base` 체크포인트(⚠️ PO 의미 = "문서에 실은 양") + 청크 이중 가드(공용 `chunkGuard()` — 트랜스퍼와 같은 상수·판정) + 실패 격리 + **authorize 게이트(미처리·실패·격리·스킵 있으면 DRAFT 유지, 모든 bin 이 실린 마지막 회차에 1회만)**. ~~⬜ 실전 검증 대기~~ → ✅ **2026-08-10 실전 검증** — PO-01121(Simple, 61라인/10 bin 그룹 1회차 완주 · authorize 게이트 정상 1회 성공 — 세션 문서 2장). ⬜ **PO 되읽기 회복(트랜스퍼 ④ checkpoint repair 상당)은 미적용** — "POST 후 체크포인트 누락" 잔여물은 `Cannot add duplicate value` 400 으로 시끄럽게 드러나므로(조용한 이중 계상 없음) 실측에서 필요성이 확인되면 별도 검토.
7. ~~discrepancy 유니크 인덱스 수정을 마이그레이션으로~~ — ✅ **2026-08-04 해소**: `supabase/migrations/20260804000000_disc_stock_short.sql` 이 `uq_disc_receipt_sku` 를 WHERE 없는 전체 유니크로 **멱등 재생성**해 담았다(원격엔 이미 응급 적용돼 있었고, 이걸 담지 않으면 새 환경·`db reset` 에서 부분 유니크로 되돌아가 `on_conflict` 42P10 이 재발한다 — 규칙 29). ⬜ **남은 것은 사람이 `supabase db push`** — 그리고 이건 이 마이그레이션만의 문제가 아니다: **2026-08-04 실측 `migration list --linked` 결과 `20260802000000`·`20260804000000` 두 건 모두 원격 히스토리에 없다**(컬럼은 실재 — 마이그레이션 밖 경로로 적용된 드리프트). 둘 다 멱등이라 재실행 안전. **push 의 목적은 기능이 아니라 히스토리 정렬** — 안 하면 `db reset`/새 환경에서 `order_date` 부재로 오더 유입이 죽고 유니크가 부분으로 되돌아간다.
8. **리시빙 discrepancy Health 검사** — `short_no_disc` 는 픽킹 전용이라 규칙 29 의 사고를 못 잡았다(규칙 19). ⚠️ 같은 공백이 하나 더: **`wms_receipts`/`wms_receipt_lines` 는 Health 무검증**이라 R3(중복 receipt)·R4(이중 Apply)도 지금은 검사에 안 걸린다(`references/frontend.md` 「Health」).
9. **`wms_receipt_lines.putaway_bin` ↔ `asung_bin_stock` 대조 Health 검사** — 하루 지연 스냅샷이라 실시간 용도는 아님(규칙 32).
10. **R13 Discrepancy 큐 방치 시 재고 불일치가 계속 남는다** — ~~에이징 알림·리포트 없음~~ → 🟡 **2026-08-11 표시 부분 해소**: admin Discrepancy·Reports 탭에 경과시간 색 3단계(<24h 회색/1~3일 주황/3일+ 빨강) + 기간 요약의 `(N open)` 병기 + 주별 추세(`references/frontend.md` 「Discrepancy 탭 + Stats」절). **능동 알림(푸시·이메일)은 여전히 없다** — 매니저가 탭을 열어야 보인다(잔여 항목). ⚠️ 규칙 29 로 **큐 자체가 비어 있던 기간**이 있었으므로 과거분은 큐로 복원되지 않는다.
11. **R10 bin 루프 비트랜잭션** — 트랜스퍼는 부분 실패 수집 + 재Apply 로 운영 가능하지만 원자성은 아니다. ✅ **"POST↔PATCH 사이" 잔여물은 checkpoint repair 가 자동 회복**(2026-07-31, 규칙 21 ④) — 단 v3 이후에도 `checkpoint_repaired` 가 계속 나오면 다른 원인 신호(규칙 27 R10).
12. ~~**매니저 2명 동시 Apply (규칙 27 R4 · 규칙 35)**~~ → **✅ 2026-08-06 해소 — PO·트랜스퍼 공통** in-flight 잠금(`apply_lock_at/by`, 규칙 21). 🟡 **2026-08-10 부분 검증** — 같은 계정 반복 클릭에서 이중 이동 0회(진행 숫자가 단조 감소만 — 세션 문서 2장). **다른 계정 동시 클릭은 미검증** — 단 아래 하향으로 능동 시험은 하지 않는다. 📌 ~~**검증 방법(2026-08-11 확정 — 세션 문서 9장)**: ⚠️ **트랜스퍼로 할 것**(역방향으로 되돌릴 수 있다 — PO stock received 는 되돌리기가 번거롭다) · A 가 OK 후 **20초 안에** B 가 OK(90초 후엔 만료 탈취라 판정 불가) · B 계정에 `perms.apply` 필요.~~ → 🟡 **2026-08-13 관찰 대기로 하향(사용자 결정 — 능동 시험 안 함 · 회차 경계 45초를 관찰 대기로 내린 18번과 같은 처리, 검증 방법 원문은 재발 시의 절차로 취소선 보존)**. 하향 근거 셋: ① **테스트 자체가 위험을 만든다** — 일부러 이중 이동을 유도하는 시험이라 잠금이 안 작동하면 재고가 실제로 틀어진다("트랜스퍼면 되돌릴 수 있다"가 종전 근거였으나 **"되돌릴 수 있음" ≠ "만들어도 됨"**) ② **잠금 자체는 이미 작동 확인** — 08-10 반복 클릭 이중 이동 0회, 다른 계정이라고 코드 경로가 달라지지 않는다(`apply_lock_by` 값만 다름) ③ **재고 카운트가 안전망** — 팀이 자주 세므로 이중 이동이 생겨도 발견된다. ⚠️ **확률은 0이 아니다 — "낮다"로만 적지 않는다**: Apply 는 5분 규모라(2026-08-12 트랜스퍼 실측 각 5분) 응답이 느리면 사람은 다시 누른다(08-10 반복 클릭이 그 증거) — 매니저 둘 이상이면 "Apply 안 됐나?" 하고 다른 사람이 누르는 상황이 실제로 있다. ⚠️ **트랜스퍼는 duplicate 400 방어가 없어 잠금이 뚫리면 진짜 이중 이동이다**(PO 는 Cin7 이 중복을 거부해준다 — 08-06 잠금 확장의 이유). **재발 의심(이중 이동·재고 어긋남)이 생기면 그때 코드부터 볼 것.** 코드 대신 할 것 = 매니저 안내 **"Apply 는 한 사람만 · 느려도 다시 누르지 말 것"**(08-11 선언 문화 안내와 같은 성격 — 코드보다 실효가 크다) · ⬜ 전달 여부 미확인.
13. **엔드포인트 폴백 — `/purchase` 400 이면 `/advanced-purchase` 재시도 + `cin7_type` 기록** (2026-08-05 후보). Apply 게이트·`poRaw()` 가 `wms_receipts.cin7_type` 으로 엔드포인트를 고르는데, 값이 틀리거나 비면 400 으로 죽는다 → 400 을 만나면 반대쪽으로 1회 재시도하고 성공한 쪽을 `cin7_type` 에 되쓴다(자기치유). ⚠️ **급하지 않다 — `cin7_type` 이 실제로 채워짐이 [실측] 확인됐다**(PO-01077 = `'Simple Purchase'`). 구형 receipt(`cin7_type` NULL)만 폴백이 필요하고 그건 전부 Simple 이라 현행 `/purchase` 기본값으로 맞는다. **먼저 할 것은 위 「검증 대기」의 Advanced 첫 Apply** — 그게 이 폴백이 필요한지 자체를 결정한다.
14. ~~⚠️ **초과 클램프 — 정책은 확정, 선행조건이 남았다** (2026-08-05)~~ — ✅ **2026-08-10 구현·배포·회귀 검증 완료** (규칙 20 ① 개정문이 정본 · 커밋 `34fbecf`). **선행조건 4개의 해소 경위·판단은 세션 문서 5장으로 대체**(`docs/sessions/2026-08-10-transfer-parallel-and-clamp.md`): ① Apply 성공 = invoice 기준 8회 실측 ② 트랜스퍼 캡과는 **중복이 아니라 별개** — 수식 쌍둥이지만 성격이 다르다(물리 강제 vs 정책 선택) · expected 0 처리가 정반대라 그대로 복사 금지, 헬퍼 추출은 보류(검증 직후의 병렬 배치 코드를 흔들지 않는다 — 5-4) ③ `exported_base` = 클램프값(markExported 가 move_base 기준 — 자동) ④ ~~expected 0 = 공장 백오더 → 클램프 제외·받은 대로(5-1)~~ — ⚠️⚠️ **2026-08-12 정반대로 반전**(전제 오류 — 백오더는 물건만 따로 오지 않는다. 실사고 PO-01027 400. 규칙 20 ① 정정이 정본). 부수 확정: "마지막 bin 부터"는 구현 불가능했다(채움 시각 미기록) → **마지막 PO 라인부터**(5-3 — 📌 정책을 정할 때 "그 순서를 실제로 알 수 있는가"를 먼저 확인). ⬜ **"자르는 동작" 자체는 실전 미검증** — 「검증 대기」의 초과 클램프 항목 참조(로컬 스위트 `po_clamp_test.ts` 9케이스가 유일한 사전 검증).
15. ~~**Invoice First 게이트 fail-closed 전환 판단**~~ → **✅ 2026-08-06 전환 완료** (규칙 21 정정 항목 참조). 전환 조건이던 관찰은 폴백 배포(v30)+PO-01076 Apply 성공으로 충족. ✅ **2026-08-10 AUTHORISED 통과 회귀 확인** — PO-01121: `PATH=simple` · `invoice check: AUTHORISED` · 10 bin 그룹 1회차 완주 · `stock received AUTHORISED` (세션 문서 2장).
16. ~~**Apply 병렬화 / bin 배치 분리** — 측정 후 판단~~ — ✅ **2026-08-10 배포·실전 검증** (`TRANSFER_PARALLEL_BATCH = 4` — 규칙 21 병렬 배치 항목 · TR-03738 로 5/5 확인). **"측정 후 판단"의 답 = 세션 문서 3-2**: 순차 4건 31.5초 vs 동시 4건 8.1초 = **3.9배**, TR 번호 역전 = 큐잉 없음. "같은 SKU 그룹 분리"도 배치 구성의 defer 로 구현됨. TR 분할이 대안이 아니라는 판단(규칙 39)은 세션에서 재확인(호출 수 = bin 그룹 수 — 무분할 144 vs 3분할 217). ~~⬜ 176그룹급 실전 관찰은 「검증 대기」 참조~~ → ✅ **2026-08-12 닫힘**(규칙 21 「실전 검증 닫힘」).
17. ~~⚠️⚠️ **`hello` 폴링 비대상 기억 테이블**~~ — ✅ **2026-08-11 구현·배포·검증 완료** (회차당 콜 52→2~3 · 유입 지연 0 — 세션 문서 2·8장, herd 관찰 잔여는 「검증 대기」). 설계 판단은 **(가)+(나) 결합**으로 확정: `Updated` 를 변경 트리거로(실측 SO-14516 — 릴리즈 시 목록에서 Updated 만 바뀐다, `AdditionalAttribute1` 은 목록에 없음) + **TTL 1시간 순수 보험**(신호가 실패해도 조용한 영구 누락이 구조적으로 불가능). `wms_polled_sales`(마이그레이션 `20260811000000`) · 스킵 = Updated **정확 문자열 일치**(파싱 금지 — .29Z/.290Z 오판) + TTL 내 · **기록은 "상세조회 성공+비대상 판정"일 때만·commit 만**(429/실패 스킵은 절대 기록 안 됨 — 구조적 보장) · 킬 스위치 `POLL_MEMORY_TTL_MS=0` · 진단 `skipped_unchanged`/`memory_ttl_expired`/`memory_rows`/`detail_rate_limited` 추가(기존 필드 무변). 상세는 `references/edge-function.md` 「확인했으나 비대상 기억 스킵」 절(⚠️ 릴리즈-회차 경합 = 누락 아닌 ≤5분 지연 명시 포함).
18. 🟡 **회차 경계 45초 공백 — 관찰 대기로 하향 (2026-08-12 · 원관측 2026-08-10 세션 문서 3-5·7장 2번)** — **2026-08-12 Cin7 API Log 실측에서 경계 10초**(18:18:38 배치 POST → 18:18:48 새 회차 GET), 45초는 재현되지 않았다. 하향 근거 둘: ① 어제 표본은 **회차 경계 1개**뿐 ② ⚠️ **어제 관측은 폴링 수정(52콜→2~3, 17번) 전** — 폴링 버스트가 60/60 창을 먹던 시기라 45초가 그 간섭이었을 수 있다. **재현되면 그때** F12 Network 로 조사(절차 유지): `receiving` 요청 자체가 45초면 EF/네트워크 · 요청은 짧은데 다음 요청까지 비면 admin · 그 사이를 Supabase 조회가 채우면 `loadReceiving()`(유력 후보 = admin 의 900ms 뒤 재조회). 원기록 보존: EF 밖 판정(`booted` 19ms + 같은 초 첫 Cin7 콜 = EF 준비 0초 · admin 의 의도적 대기는 900ms 뿐 — grep 확인) · "176그룹이면 회차 22번×45초=16분" 우려는 10초 실측 기준 4분 미만으로 축소.
19. **회차마다 동일 `?TaskID=` GET 이 2번, 같은 초에** — 30회차면 30콜 낭비. 2026-08-10 하드 alert 의 발원도 이 GET (세션 문서 7장 3번).
20. **`_shared/cin7.ts` 429 백오프가 60초 창에 구조적으로 부족** — `1500*(attempt+1)`·상한 2회 = 총 4.5초. 60콜을 10~20초에 소진하면 남은 ~40초는 전부 429 인데 4.5초 기다리고 throw 한다. ⚠️ 공용 파일 — 고치면 `hello`·`receiving` 둘 다 재배포 (세션 문서 7장 4번).
21. **회차 throw 시 `apply_note` 미갱신** — 종료부가 실행되지 않아 진행분이 화면에서 **되돌아가 보인다**(2026-08-10 실제 171→164→171 발생). 체크포인트는 멀쩡 — 매니저가 "날아갔다"고 오해한다 (세션 문서 7장 5번).
22. **`RETRY of a partial apply from ?`** — 타임스탬프가 `?` 로 찍히는 표시 결함 (세션 문서 7장 6번).
23. **인보이스 폴백 공백** — 인보이스가 실재하는데 폴백으로 빠진 receipt 는 `expected_source='order'` 로 기록되어(receiver.html startPo) 클램프를 받지 않는다. 안전한 방향이지만 **그 상황의 빈도는 확인된 바 없다** (세션 문서 7장 12번).
24. **`hello` 상세조회 429 경로의 `await sleep(60000)` 구조 (2026-08-11 별건 — 사용자 결정: 이번에 고치지 않음)** — 회차를 60초 통째로 막으면서 그 오더를 건너뛰기까지 한다. 기억 스킵(17번)으로 상세조회가 50→0~1건이 되어 발생 확률이 크게 줄었지만 구조는 그대로다. **`detail_rate_limited` 로 빈도를 먼저 관측한 뒤 판단**(2026-08-11 도입 — 종전엔 이 스킵이 어디에도 안 남아 fresh 51 vs detail_fetched 50 의 1 차이로만 흔적이 보였다).
25. **폴링 TTL 흩기 — 필요 없을 수 있음 (2026-08-11 관찰 대기)** — 배포 직후 첫 commit 회차에 일괄 기록된 9건이 1시간 뒤 **동시에** 만료되는 herd(그 회차만 detail 9, 나머지 0~3). 자연히 흩어지는 중(`memory_ttl_expired` 9→1)이고 최악이 회차당 9콜(한도 60 대비 미미) — **며칠 관찰 후에도 뭉쳐 있으면** TTL 55~65분 무작위화 검토 (세션 문서 2장).

- ~~⚠️⚠️ **Rollback 탭이 Finalize 단계를 모델링하지 않는다 (2026-08-12 실사고 — 버튼 차단 응급 처방만 배포, 근본 미수정)** — stage 판정(admin.html loadRollback)이 fulfillment 여부를 **pallet_items 행 존재 하나로만** 가린다(2026-07-20~23 커밋 — Finalize 개념·`finalized_at`·`fulfillment_type` 은 07-21 에 들어왔는데 판정이 안 따라갔다). Direct pack 은 정의상 팔렛에 안 올리므로 pallet_items 0행 → closed 인데 "Pack complete"/**Undo Pack 으로 오판**. ⚠️ **실사고 SO-13893**: 07-30 18:56 finalize(direct) → 19:20 Undo Pack → **status='picking' + finalized_at 잔존**인 어중간한 상태로 2주 방치. 노출 규모 = closed+finalized_at+팔렛 없음 **513건**(Finalized 164 중 Direct 115 라 대부분이 direct 경로). ⚠️ **doRollback("fulfillment") 도 반쪽 결함** — 팔렛만 지우고 status·finalized_at 무접촉(`// order stays ready_to_close` 주석이 Finalize 이전 세계의 증거) → packing_list 오더의 Undo Fulfillment 도 표시만 맞고 실행하면 finalize 가 안 풀린다. **응급 조치(2026-08-12)** = closed 오더의 Undo Pack 버튼 비활성(사유 문구 표시 — 회색 버튼만 두지 않는다) + 오더/배치 단위 서버 재확인 벨트(로드 후 finalize 경합 창 차단) — **버튼 차단이지 근본 수정이 아니다.** 근본 = "Finalized" 단계 신설(status/finalized_at 을 판정 최상단에) 인데 **설계 판단 필요**: 무엇을 되돌리나 · Cin7 은 이미 3.Finalized 인데 그건 어떻게 · direct 와 packing_list 가 다르다.~~ → ✅ **2026-08-13 근본 수정 완료(아래 항목이 정본 — 실행 한 바퀴도 같은 날 통과, SO-11896).** 유지되는 사실: ⊘ Void 는 정당 경로라 그대로(SO-13364·SO-13333 이 그 경로로 종결) · [실측] 세 오더(SO-13893·13364·13333) 전부 Cin7 에서는 정상 출고 — 실질 피해 없음 · 발견 경위는 세션 문서 `2026-08-12-hold-and-postgrest-cap.md` 6장.
- ✅ **Rollback Finalize 단계 모델링 (2026-08-13 근본 수정 · 같은 날 실행 한 바퀴 통과 — SO-11896)**: 판정 최상단에 `isFinalized = status==='closed' && finalized_at 있음` 신설(**팔렛 유무 무관** — packing_list 도 같은 오판이었다) → stage "Finalized" / action "finalize" / "↩ Undo Finalize"(Worker 열 = finalized_by). closed 인데 finalized_at null(통계 컬럼 없던 시절의 status-only 폴백 finalize)은 이 분기에 안 걸리고 기존 체인으로 떨어진다 — 유지된 응급 차단·벨트가 막고, 경로는 ⊘ Void 뿐. [실측 2026-08-13] 노출 **540건**(direct 538 / packing_list 2 — 08-12 의 513건에서 증가) · 어중간 상태 잔재(활성 status + finalized_at) **0건**(정리 불필요).
  - **`doRollback("finalize")`**: 팔렛 먼저 삭제 → **status 플립 마지막** (⚠️ 순서가 중요 — 중간 실패 시 closed 유지라 재실행이 잔여분을 완주한다. 역순이면 ready_to_close 오더가 스테일 팔렛을 단 채 fulfillment 보드에 뜬다) · `status→ready_to_close` + `finalized_at/finalized_by/fulfillment_type` null 을 **CAS**(`.eq("status","closed")` + `.select()` 행수 판정 — 규칙 24, 0행=경합 중단)로. [실측] status CHECK 6값에 `ready_to_close` 포함(pg_constraint 확인) — 제약 위반 없음.
  - **voidDisc 없음** — finalize 는 discrepancy 를 만들지 않고 픽·팩 작업을 되돌리지 않으므로 그 단계들의 disc 는 살아있는 게 맞다(규칙 41 화이트리스트 원칙).
  - ⚠️ **Cin7 무접촉**(이미 3.Finalized · 매니저가 Cin7 에서 직접 — 불가역 외부 쓰기를 늘리지 않는다는 기존 결정). confirm 첫 줄("Cin7 stays at 3.Finalized — WMS only") + 실행 후 안내(rollbackDone notes 경유 alert).
  - **fulfillment 분기에 closed 벨트 신설** — 종전엔 pack 분기에만 있었다. ⚠️ 반쪽 결함의 정확한 메커니즘(2026-08-13 조사 확정): 팔렛만 지우고 closed 잔존 → fulfillment 보드의 `.neq("status","closed")` **한 줄**에 걸려 **재-finalize 가 영구 불가**.
  - 팔렛 삭제는 **`deleteFulfillmentRows` 로 추출**해 fulfillment/finalize 가 공유(동작 동일 리팩터) — ⚠️ **빈 유닛만**(아이템 0 + 자식 0) 지운다. `wms_pallets` 는 unit_type 으로 팔렛/박스 구분·parent_id 로 계층 — 새로 짜면 공유 유닛의 남의 오더 물건이 사라지거나 고아 박스가 생긴다.
  - **08-12 응급 차단(packBlocked·배치 차단·pack 벨트) 전부 유지** — 판정이 다시 어긋날 때의 마지막 방어선(사용자 지시). 이제 여기 오는 closed 는 레거시(finalized_at null)뿐.
  - `STAGE.finalize=["finalized","pack_complete"]` — Undo Finalize 가 팔렛까지 지우므로 착지가 pack_complete("fulfilled" 로 적으면 로그가 실제 착지와 어긋난다).
  - ~~⬜ **실행 한 바퀴 미검증**: Undo Finalize 실행 → ⚠️ **Cin7 안내 alert 이 실제로 뜨는지**(notes 경유라 rollbackDone 이 표시해야 한다 — 안 뜨면 두 시스템이 갈라진 걸 매니저가 모른다) → 보드 재등장(Ready to close) → 재-finalize → 로그 finalized→pack_complete.~~ → ✅ **2026-08-13 통과 (SO-11896)** — [실측] 4단계 전부 화면 확인: ① confirm 4줄 표시 — 첫 줄 "Cin7 stays at 3.Finalized — this changes the WMS only" ② **실행 후 alert 표시 — notes 경유가 정상 작동**(이 항목의 핵심 우려였다): "SO-11896 rollback done (finalize). ⚠ Cin7 is still 3.Finalized … back on the fulfillment board as Ready to close." ③ fulfillment 보드 재등장 — ready_to_close 로 목록에 나타남(`.neq("status","closed")` 통과) ④ 재-finalize 성공 — "Direct pack — no pallet/box" 로 정확히 분류 · Rollback 목록에 Finalized 로 복귀하며 Worker 가 새 finalized_by(재실행자)로 갱신 · closed 총수 676→677. 📌 판정 정합성 부수 확인: finalized_at 없는 오더(SO-13697·SO-13849)는 Rollback 에서 "Pack complete", fulfillment 보드에서 ready_to_close — **두 화면이 같은 사실을 말한다.**
- **doBatchRollback pick 에 closed 벨트 없음 (2026-08-13 신규)** — 배치 단위 Reset Pick 은 표시로만 차단된다(loadRollback 배치 행의 "Finalized — undo finalize first"). 로드↔실행 사이 finalize 경합 창이 남는다. pack 분기와 같은 형태의 벨트 추가가 근본(2026-08-13 doBatchRollback 무접촉 지시로 미룸).
- **packing_list 인데 팔렛이 없는 finalize 오더 2건 (2026-08-13 관찰 — ⬜ 재발 시 조사, 지금 단정 금지)** — SO-14417·SO-14412, 둘 다 Changmo Ku, finalized_at 이 밀리초까지 동일(2026-08-10 15:43:12.247) · updated_at = finalized_at(= finalize 후 아무것도 실행 안 됨) · wms_pallets 행도 0. 즉 Undo Fulfillment 흔적이 아니라 **처음부터 팔렛 없이 packing_list 로 finalize** 됐다. fulfillment 화면에서 `fulfillment_type` 이 실물과 어긋나게 기록될 수 있다는 신호 — 단 2건·한 시점이라 그날의 특수 상황일 가능성.
- ⚠️ **packer 대기열 쿼리 근본 수정 (2026-08-12 SO-14532 응급 처치의 후속)** — 응급 처방(내림차순+LIMIT 1000)은 잘리는 쪽을 "오래된 것"으로 바꿨을 뿐 캡 자체는 남아 있다. 근본: donePick 을 `wms_orders!inner(status)` 로 **안 닫힌 오더의 완료 픽만**(닫힌 오더의 완료 픽 제외 — 결과가 수십 건 규모로 영구 유지) + allPack 의 완료 팩 기간 제한(진행·pending 은 전량). ⚠️ **!inner 전환은 임베드 형태가 바뀌어 검증이 필요해 응급 커밋에서 하지 않았다**(사용자 지시 — 창고 대기 중). 미팩 백로그가 1000건에 근접하면(비현실적이지만) 응급 처방도 뚫린다.
- **Rollback finalize 토글 라벨의 숫자 (2026-08-12 저녁 — 표시 문제, 작업 안 막힘)** — `Hide finalized (640)` 의 N 은 count-head **총수**인데 펼쳐도 목록엔 closed **최근 200**(캡 위험 #7 사양)만 있다 — 매니저가 "640이라더니 왜 200개만?" 하고 헷갈릴 수 있다. 펼친 상태 캡션(`Latest 200 of 640 listed …`)이 설명하고는 있지만, 버튼 숫자를 표시 건수 기준으로 바꿀지 · `640 (200 listed)` 형태로 합칠지 판단(저녁 문서 F절 1번).

### 동시 작업 원자화
- ⚠️ **completed wave + 멤버 0 잔재 (2026-08-11 실물 확보 — wave id 21/W-0806-4)** — 08-06 테스트 조작이 만든 상태를 발견·삭제했다(규칙 20 「지우지 않는다 원칙의 예외 사례」). **조작으로 가능하면 운영에서도 가능하다** — 픽 RPC 원자화(`wms_complete_pick`) 이후 재발하는지 관찰, 재발하면 unwave/롤백 경로 조사 (세션 문서 11장).
- **같은 SKU 다중 픽커 / 같은 라인 동시 스캔 (R1)** — PostgREST 조건부 UPDATE(CAS) 또는 RPC 증분.
- **`claim_seq`(A→B→A 스테일 화면) — 규칙 28 후속.** 현재 가드는 best-effort. R1 CAS 와 같은 패턴이라 함께 처리.
- **리시빙에 복귀 시점 감지 미적용 (규칙 28 · 2026-08-04)** — `ensureReceiptOpen()` 은 **쓰기 직전에만** 확인한다. picker/packer 의 `visibilitychange`/`focus` 훅(규칙 28 이 "실질적으로 가장 중요"하다고 적은 경로 — 태블릿 두고 나갔다 복귀)은 리시빙에 없어서, Apply 된 receipt 를 열어둔 화면은 **첫 탭을 누를 때까지** 아무것도 모른다. 손실은 작다(그 탭 하나가 거부되고 목록으로 나간다) — 우선순위 낮음.

### 원장 선행 (재고 원장 착수 전 판단 — `docs/design/2026-08-06-inventory-ledger-principles.md`)
- ✅ **선행조건 3건 전부 해소 (사용자 확인 2026-08-13)**: ① **원가 모델 = FIFO 확정**(Cin7 이 FIFO). ⚠️ 함의: 입고 레이어별(수량+단가+입고순서) 보관 + 출고 시 오래된 레이어부터 소진 — 가중평균보다 복잡하지만 **Cin7 과 숫자가 맞는 것이 shadow mode 3자 대조의 전제**다. ⬜ 남은 조사: Cin7 API 가 입고 레이어별 원가를 노출하는지 ② Supabase **유료 업그레이드 완료** ③ Cin7 계약 = **month-to-month, 제약 없음** — ⚠️ 종전 기록("Cin7 갱신 시점이 실제 마스터 스케줄 제약일 수 있다" — 08-07 리포트)은 **사실이 아니었다.** 오히려 shadow mode 를 충분히 오래 돌려볼 여유가 있다는 뜻이고, 되돌리기 어려운 작업이라 그 여유가 자산이다. ⚠️ 착수 순서는 백로그 머리의 우선순위(2026-08-13) — 원장은 마지막.
- ⚠️ **stale stock_short 처리가 픽·팩 비대칭이다 (2026-08-06 사용자 지시로 명시)** — **픽은 delete**(`wms_complete_pick` ⑤ · 종전 finish() 도 delete), **팩은 resolve**(`wms_complete_pack` — resolved_by/at 기록). 비대칭이며 **delete 쪽은 원장 원칙 1번("고치지 않고 추가")과 어긋난다** — 선언했다가 채워진 사실 자체가 지워져 사후 설명이 불가능해진다. **원장 착수 전에 통일 판단 필요**(resolve 로 통일이 원칙 정합적 — 단 admin Discrepancy 큐 표시·선언 토글 복원 로직(`loadStockFlags` 가 미해결 행만 읽음)과의 상호작용을 확인하고 별건으로).

### 리포트·통계
- ~~⚠️ **wave 모드 리포트 오더 귀속 버그 (규칙 14)**~~ — ✅ **2026-08-11 수정 완료** (규칙 14 wave 귀속 항목이 정본). 종전 기록 유지: wave 에서 `wrong_location`·`barcode_mismatch` 가 대표 오더에 고정 귀속돼 B 오더 라인의 리포트가 A 에 붙었고, 매니저가 A 에서 그 SKU 를 못 찾아 리포트를 오작동으로 여기는 신뢰 침식이었다. **수정 = picker `reportIssue` 에 `lineOrder(l)` 적용**(`order_id`/`order_number` 짝 + `!o.id` 가드 — image_mismatch 와 동일 형태·동일 toast). ⚠️⚠️ **정정 — 종전 "범위: picker + packer(`barcode_mismatch`)" 중 packer 는 틀린 표기였다**: pack task 는 오더당 1개라 packer 화면의 모든 라인이 같은 오더 소속이고, packer 에는 wave 분기도 `_orderId` 도 없다(2026-08-11 코드 대조 — packer 의 barcode_mismatch 는 이미 자기 파일의 image_mismatch 와 동일 형태). **같은 의심으로 같은 조사를 반복하지 말 것.** ⚠️ 수정 전에 쌓인 잘못된 행은 소급 정정 불가 — 2026-08-11 이후 행부터 옳다. ⬜ 현장 확인은 wave 2오더 배치에서 두 번째 오더 라인 리포트 1건(아래 「검증 대기」 아님 — 다음 wave 픽에서 가볍게).
- **공용 리포트 모듈 `wms-reports.js` 추출** (2026-08-05 후보) — ⚑ 리포트 로직이 지금 **4곳에 복제**돼 있다: picker(3 kind)·packer(2)·receiver(3, 2026-08-05 신규)·admin(표시). receiver 를 만들 때 **의도적으로 복제**했다(사용자 결정 — 검증된 픽·팩 코드를 건드리지 않기 위해). 이제 4번째가 생겼으니 `wms-picklist.js`·`wms-packing.js`·`wms-confirm-modal.js` 와 같은 **단일 출처** 패턴으로 뺄 시점이다. ~~⚠️ 위 wave 귀속 버그 수정과 반드시 묶을 것~~ → **2026-08-11 갱신: 귀속 버그가 먼저 수정됐다**(위 항목) — "추출이 버그를 이식한다" 위험은 해소. 추출 시 **수정된 형태(`lineOrder(l)` 짝 귀속 + `!o.id` 가드)를 단일 출처로 옮길 것.** ⚠️ 추출은 픽·팩의 검증된 경로를 건드리므로 **동작 동일성 diff 를 먼저 증명**할 것(`_shared/cin7.ts` 추출 때와 같은 절차).
- ~~⚠️ **`started_at` 덮어쓰기 — avg time 왜곡**~~ — ✅ **①(스캔 이어받기)·②(Hold→재개)는 2026-08-11 수정 완료** (규칙 37 「avg time·min/line 의 신뢰 한계」가 정본 — SO-14464-1 원인은 담당자 **증언**으로 ② 확정, 행 증거 없음). 수정 = 4곳 SET 에서 started_at 제거 + only-if-null backfill(`ensureStartedAt`/`ensureStartedAtPack`). ⬜ **잔여 ③ wave 멤버 과대**(`startWave` 일괄 기록 → 멤버 전원 dur ≈ wave 전체) — wave 시간을 멤버에 배분할지의 설계 결정 필요. ⚠️ 수정 후 avg 는 Hold 대기 포함(과대 방향 — dur 24h 캡이 밤샘 Hold 를 제외하는 안전장치 겸 통계 공백, 규칙 37).
- **스캔 타임스탬프 기반 순수 작업시간 (규칙 37)** — 현재 소요시간은 근무시간 경과라 "열어두고 다른 일 한 시간"이 포함된다. 스캔 이벤트 타임스탬프 집계가 필요. ~~⚠️ 위 started_at 덮어쓰기 항목과 연결 — `picked_at` 이 픽 라인에 실제로 채워지는지부터 확인할 것(2026-08-11 실측: SO-14464-1 은 전 행 null 이었다 — 채워지지 않으면 이 항목의 전제가 무너진다).~~ → ⚠️⚠️ **2026-08-13 실측 종결: `picked_at` 은 죽은 컬럼 확정** — `wms_pick_task_lines` **19,375행 전량 null**(oldest 2026-07-21 13:50 ~ newest 2026-08-13 14:50 — 부분 커버리지도 시점 경계도 없음, 어느 코드도 안 채운다). **이 항목의 전제가 무너졌다** — 살리려면 픽/팩 저장 경로에 스캔 시점 기록을 먼저 넣어야 한다(별건 선행 작업 — 검증된 저장 경로를 건드리므로 동작 동일성 증명 필요). 같은 컬럼으로 다시 확인하지 말 것.
- **근무시간 계산에 공휴일 미반영 (규칙 37)** — `WORK_DAYS`(월–금)만 본다.
- **근무시간 상수가 실제와 맞는지 확인 (규칙 37)** — `WORK_HOURS`(09–17)·`WORK_DAYS`(월–금)는 추정 상수다. 두 창고의 실제 근무시간과 대조 후 조정할 것.
- **packer `overScans` 가 메모리 전용 (규칙 41)** — Hold 하거나 새로고침하면 **초과 표시가 사라진다**(판정 "결과" 인 `over_pick`/`pack_scan_mistake` 행은 남는다). 서버 저장이 맞다(규칙 5 — 상태를 localStorage 에 두지 말 것). 지금은 초과가 한 세션 안에서 처리되는 게 보통이라 우선순위 낮음.
- ~~**Stats 「Mistakes by worker」 수정 (2026-08-12 저녁 — ⬜ 수정 내용 미확정)** — 사용자가 남은 작업으로 지목했으나 **구체 내용은 다음 세션에서 사용자에게 확인 후 확정**(저녁 문서 F절 2번·G절). 내용이 정해지기 전에 추측으로 구현하지 말 것.~~ → ✅ **2026-08-13 닫음 — 조사·화면 실측 결과 고칠 것이 없음이 확정.** ① 화면 실물 열은 4개(WORKER/TOTAL MISTAKES/SHORT AFTER PACK/OVER-PICK) — **short_pick 열은 애초에 렌더되지 않는다**(집계 객체 `mistakes[...]` 에 키만 있고 `renderMistakes` 가 안 그린다). ⚠️ 코드 조각만 보고 "죽은 열이 서 있다"고 판단했다가 스크린샷에서 틀린 것이 드러났다 — **화면 판단은 화면을 볼 것**(규칙 42 계열 "UI 는 코드 읽기로 결론내지 않는다"와 같은 계열). ② 사용자가 지목했던 문제("실수 안 했는데 재고 부족으로 실수 집계")는 이미 3중으로 해소돼 있다: 선언(stock_short)=NOT_MISTAKE 제외 · resolve 후=2026-08-11 voided_at 수정 · 미선언(short_pick)=responsible null 이라 `if(!d.responsible)return` 탈락. ③ 잔재 확인 쿼리 0건(선언이 먼저 있는데 short_after_pack 이 살아 있는 행 — SO-14090 이 유일했고 voided 처리 완료). ⚠️ 남아 있던 실제 문제(중복 행·이름 누락)는 Stats 가 아니라 **Discrepancy 탭**의 것이었고 2026-08-13 별도 처리(short_pick 픽커 회색 참고 표시).
- **done 목록 LIMIT 500 → 1000 (2026-08-11)** — 1000 으로 올리기로 했으나 500 으로 구현됐다. discrepancy 월 ~450건 기준 500 은 한 달치 — 잘림 표기("showing first N of M")가 있어 급하지 않음 (세션 문서 10장).
- ⚠️ **요약·추세 쿼리의 PostgREST 1000행 캡 — 예고된 만기 (2026-08-11)** — PostgREST 는 요청하지 않아도 1000행에서 자르고, 잘리면 추세 숫자가 **조용히** 틀린다(표기 "trend counts the first N of M rows" 는 이미 있음). 실측 규모: `wms_discrepancies` 3주 324건(월 ~450) · `wms_reports` 3주 93건 → **discrepancy 는 약 두 달 뒤 1 year/All 기간에서 걸린다.** 그때 서버 집계(뷰/RPC) 또는 페이지 누적으로 전환 판단.
- **resolved 된 stock_short 선언 재클릭 시 거짓 "cancelled" toast (규칙 41 · 2026-08-11 관찰)** — 토글 취소 delete 는 `resolved_at is null` 조건이라 resolved 행에서 **0행 삭제**(감사기록 보존 — 옳은 동작)인데, 코드가 무조건 로컬 플래그를 지우고 "cancelled" toast 를 낸다 → 다음 reload 에서 칩이 되살아난다. resolved 선언은 사실상 취소 불가가 맞으므로 **동작은 옳고 메시지만 거짓** — 좁은 UX 엣지(0행이면 "already resolved — cannot cancel" 안내가 정답). loadStockFlags 수정(규칙 41 실사고 항목)과 함께 발견했으나 1040 무접촉 지시 범위 밖이라 여기만 남긴다.
- ⚠️ **관찰 대기 3건 (2026-08-13 — 원인 미확정, 단정하지 말 것 · 규칙 42 계열)**: ① **Finalized 탭 This week 숫자 요동** — 같은 날 몇 시간 사이 182 → 87 → 192. 오늘 출고 진행 중이라 증가는 자연스러우나 **87 이 설명되지 않는다** — 재발 시 F12 Network 로 조사(응답 원문 대조). ② **Status BATCH ACTIVITY 에 활성 오더 목록 밖 배치가 보인다**(SO-13262-1 등 — 아침 SQL 활성 36건에 없던 오더): 배치는 살아 있는데 오더는 활성 4상태가 아닌 상태 — 어떤 경로로 생기는지 미확인. ③ **Elapsed 의 ageOver 판정이 달력 60일 가정** — `workMinutes` 의 60일 캡이 달력인지 근무일인지 미확인. 어긋나면 극단 지체가 "—" 로 위장된다(현재 최장 17일이라 발생 조건 아님). 안전한 형태 = `ageOver = !!imported_at && ageMin==null`(캡 원인 무관 — 판정을 캡 정의에서 분리).
- **풋어웨이 하드 게이트 재검토 (2026-08-04 · `references/frontend.md` 「풋어웨이 완료 입도」)** — 지금 admin Apply 는 미배치 라인이 있어도 **주황 경고만** 하고 막지 않는다. **관행이 정착한 뒤**(bin 일괄 버튼이 실제로 눌리는지 몇 주 관찰) 차단으로 올릴지 판단할 것. ⚠️ 지금 막으면 모든 Apply 가 멈추고 작업자가 안 놓고 눌러 통과시켜 **지표가 더 거짓이 된다** — 판단 근거는 규칙 41 의 "정직한 기록을 벌주면 기록이 사라진다".
- **admin Finalized 재출력에는 `⚠ Unassigned` 표가 없다 (규칙 15 · 2026-08-02)** — fulfillment 화면 전용이다. Finalize 이후엔 pack task 재집계가 필요해 그때 범위 밖으로 뒀다. 상세는 `references/frontend.md` 「admin.html Finalized 재출력 3종」.

### 검증 대기 (배포됐으나 실전 미확인)

- ⚠️ **product-images EF (2026-08-14 저녁 — 「상품 이미지 파이프라인」 절이 정본)** — 첫 성공은 실측 완료(148페이지·3분 32초·updated 6·Health warn 소멸). ⬜ 남은 확인: ① **cron 자동 회차**(12:30 UTC — `wms_image_sync_runs` 에 mode CRON 행이 생기는지. ⚠️ **2026-08-15 의 12:30 슬롯은 쿨다운 20h 에 걸려 SKIPPED cooldown 예상**(첫 성공이 08-14 저녁) — **08-16 부터 정상이니 놀라지 말 것**) ② **재시도 슬롯(13:30)이 SKIPPED cooldown 으로 no-op** 하는지 ③ 다음날 사이클(6:30 재적재가 BQ 값으로 되돌림 → EF 가 다시 덮음 — 그 사이 BQ 값 표시는 정상) ④ `force=1` 의 authgate 통과(admin 계정 — 시크릿 없는 401 만 실측됨).

- ⚠️ **2026-08-14 배포분 (Health 자동 실행 · Cin7 void 감지 · !inner 근본 수정 · "잘린 모수" 3건 · 리시빙 진행도)** — 저녁 확인분(2026-08-14) 반영: ~~① Health cron 실동~~(✅ 간접 확인 — `image_sync_stale` 이 `last_ok_at` 을 잡았다 = 스냅샷 cron 이 돌고 있다) ~~② Cin7 void 실전~~(✅ SO-13993 첫 실전 탐지 — 「신규 기능」 void 항목의 실측이 정본) ~~③ packer 기능 한 바퀴~~(✅ 픽 완료 → 팩 대기열 정상 — 하루 출고 49건 정상 완료로 확인). ⬜ 남은 것: ④ Receiving 진행도 정확성(진행 중 receipt 의 수치가 Review 모달 라인 합과 일치하는지) ⑤ 창고별 로컬 시각(TR-03548 에드먼턴이 토론토 PO 보다 2시간 이르게 표시되는지) ⑥ ⬜ **`--line-2` CSS 변수 존재 미확인** — admin Empty 태그가 `var(--line-2,#eef1f6)` 를 쓴다. fallback 이 있어 안전하지만 정의 여부를 확인 안 했다 — 배포 후 태그가 이상하면 여기부터. ⚠️ 어제분 「Apply dry-run 이 admin 계정으로 통과하는지(hasApply 의 `||` 판정)」도 아직 열려 있다 — 다음 리시빙 완료 때.

- ⚠️⚠️ **Cin7 On Hold 감지 → 보류 (2026-08-12 구현 — ⬜ 배포 전 · 규칙 43)** — 배포 순서: **SQL(`20260812000000_wms_orders_hold.sql`) 먼저** → `supabase functions deploy hello` → 프론트 4파일 push(컬럼 없이 프론트가 먼저 나가면 임베드 select 가 400). 확인할 것: ① **anon 키로 hold_recheck 호출 → 401** (`curl -H "Authorization: Bearer <anon>" "...functions/v1/hello?action=hold_recheck&order_id=1"` — **이 게이트가 안 되면 기능 전체가 무의미하다**) + apply 권한 계정 → 통과, 무권한 로그인 → 403 ② 픽 대기 오더를 Cin7 On Hold → ≤5분 내 picker 목록에서 사라짐(진단 `hold_detected 1`) ③ 픽 진행 중 보류 → 완료는 되고 완료 시 ON HOLD 안내 + packer 대기열에 안 뜸 ④ Cin7 을 2.Release 복귀 → admin 에 "resumable" 표시(자동 복귀 안 됨 확인) ⑤ 매니저 Re-check & resume → 복귀(픽커 목록 재등장) ⑥ Cin7 이 아직 On Hold 인데 재개 시도 → 차단 + 값 표시 ⑦ **회귀: 정상 오더가 실수로 사라지지 않는지** — 배포 전후 picker/packer/fulfillment 목록 건수 비교(hold_state 전부 null 이므로 동일해야 함) + 폴링 진단 `hold_checked` 평시 0~2 · `hold_check_deferred` 0 ⑧ 예상 밖 값(예 Backordered 로 변경) → 화면 유지 + admin 에 원문 표시, Cin7 정상 복귀 시 자동 소멸 ⑨ **manager(Order Splitting — 2026-08-12 당일 누락 정정분)**: On Hold 오더가 PENDING ORDERS 목록(Split·Group 두 탭)에서 사라지는지(SO-14592 재현 케이스) + 오더 선택 후 보류시키고 분할 확정 → `holdBelt` 차단 alert("ON HOLD — cannot send to picking") + 아무것도 생성 안 됨 + wave 생성도 동일.

- ~~⚠️⚠️ **폴링 "확인했으나 비대상" 기억 (⬜ 배포 전)**~~ — ✅ **2026-08-11 배포 + 양방향 검증 완료** (세션 문서 `docs/sessions/2026-08-11-polling-and-stats.md` 2·8장): 회차당 콜 **52 → 2~3**(94% 감소) · `detail_fetched` 50 → 0~1 · 안 바뀐 오더 스킵(11/12) · **릴리즈 → 다음 회차 유입 지연 0**(SO-14521) · 기억 행 자동 삭제·신규 자동 등록 확인 · `errors`/`detail_rate_limited` 0. ⚠️ **관찰 잔여 — 동기화된 무리(herd)**: 배포 직후 일괄 기록된 9건이 1시간 뒤 동시 만료(그 회차만 detail 9) — 자연히 흩어지는 중(`memory_ttl_expired` 9→1), **한 시점만 보고 "절감이 사라졌다" 판단 금지**(실제로 그렇게 오판했다가 5분 뒤 재측정으로 정정 — 세션 문서 7장). 판정 순서·킬 스위치는 `references/edge-function.md` 폴링 절이 정본.
- 🟡 **WMS 체감 지연 (2026-08-11 — 원인 미확정)** — 재현 없음. Cin7 키 분리와 폴링 수정이 그 사이에 있어 **어느 것이 효과였는지 구분 불가**(그날의 일시적 부하였을 수도). 재발 시 그때 파야 한다 — 지금 원인을 적으면 추정이 사실로 굳는다.
- ⚠️ **2026-08-11 결함 수정 3건 — 자연 발생 검증** (세션 문서 9장): ① **wave 리포트 귀속** — 오더 2개+ wave 에서 **두 번째 오더 라인**에 ⚑ → admin Reports 에 그 오더로 뜨는지(⚠️ 1오더 wave·비-wave 로는 안 드러난다) ② **stock_short 선언 복원** — 선언 → 매니저 resolve → 팩 완료 시 `short_after_pack` 미생성 · picker 는 선언→Hold→resolve→재개 시 칩 유지 ③ ~~**started_at 보존** — Hold 재개·이어받기 후 완료가 라인 수 대비 말이 되는 시간인지. **또 2분짜리가 나오면 실패.**~~ → ✅ **2026-08-13 검증 통과**: 매니저가 실제로 한 아이템 남기고 Hold → 재개 → 완료를 거쳐 배치 소요시간 확인. [실측] 같은 날 완료된 픽 배치 **20개 전부** 라인 수에 비례하는 정상 값(33~36라인 = 16~38분 · 라인당 0.5~1.2분) — 종전 68라인 2분 같은 **이상치 0건**. ⚠️ Hold 를 거친 배치 자체는 특정하지 못했다(매니저 수행·배치 미기록) — 유력 후보는 SO-14661-3(33라인 38.8분 = 1.18분/라인, 같은 오더 -2 가 34라인 26분인데 더 오래 걸렸다)이지만 작업자 차이일 수도 있어 단정하지 않는다. **판정 근거는 "이상치 부재"이며 그것으로 충분하다**(실패 조건이 "또 2분짜리가 나오면"이었다).

- ⚠️⚠️ **Advanced PO 2단 Apply (2026-08-07 · 규칙 20·21 Advanced 절 · cin7-api 13)** — 1차 실전(PO-01094)에서 **stage1 승인 건너뜀 실사고**(규칙 21 Advanced 절 실사고 항목 — 부재 증명 결함, 존재 증명으로 재설계·⬜ 수정판 배포 대기). ⚠️⚠️ **실사고 2호(I&R 그룹 분리 — 규칙 21 Advanced 절)로 복구 절차가 바뀌었다**: PO-01094 의 32줄은 **잘못된 그룹**(TaskID 44e2f761…, 빈 DRAFT 인보이스 딸림)에 AUTHORISED 로 들어가 있다. **복구 = ① caleb 이 Cin7 에서 직접 정리**(그 그룹의 32줄 + 빈 DRAFT 인보이스 — WMS 정리 코드는 만들지 않음, 사용자 결정) **② 수정판 배포 ③ 재Apply**. 정리 **전에** Apply 하면 외부 그룹 가드가 중단시키는 것이 정상 동작(메시지에 조치 포함). 정리 후 기대: dry-run 에 `Target I&R group: cf791a11… (invoice 63467)` → 실행 로그 `PATH=advanced` → 타깃 그룹 delta 재전송 → 승인 → stage2 단일 POST(모두 타깃 TaskID). Simple 회귀·정정 경로 실측 등 기존 확인 항목 유지. 확인 순서: ⓪ 응답 첫 줄 `PATH=advanced` + `stock tasks on Cin7: [...]` 원문 상태 로그(이게 Status 실제 문자열의 첫 실측이 된다 — `stock-write.md` 10번에 기록할 것) ① stage1 존재 증명 통과·`stage2 IRREVERSIBLE CALL`·put-away 되읽기 통과 순서 확인, Cin7 화면에서 bin 배치 + PO Status RECEIVED ② ~~Simple 회귀~~ ✅ **2026-08-10 확인** — PO-01121: `PATH=simple (cin7_type='Simple Purchase')` · 10 bin 그룹 1회차 완주 · authorize 성공(세션 문서 2장) ③ stage2 만 실패 시 admin "⚠ Applied (N bins failed)"+'Retry failed bins' 재개 확인(ALL-OR-NOTHING 문구 포함) ④ put-away authorize 형태는 이번이 첫 실측 ⑤ ⚠️ **"잘못 놓인 bin 은 stockTransfer 로 정정" 실측** — X-b 위험 평가의 근거인데 미확인. 오배치 발생 시 bin↔bin 이동 1건으로 확정, 안 되면 X-b 재평가. ⚠️ 배포는 **커밋 후에**(미커밋 워킹트리 배포가 이번 사고 조사에서 "어느 코드가 나갔는지" 를 흐렸다 — 규칙 21 부수 교훈). ✅ **2026-08-13 정상 경로 첫 완주 — PO-01128 (Advanced 회귀 통과)**: 종전 확인(2026-08-12 PO-01027)은 Simple→Advanced 전환 + exported_base 19줄 리셋 후 재Apply 한 **복구 케이스**였다 — PO-01128 이 전환·복구 없는 **정상 경로 Advanced PO 의 첫 완주**다. [실측 Cin7 화면] `Advanced purchase #PO-01128` · Status `Received` · I&R 그룹 `#0` 하나뿐 · `1 task`(그룹·TaskID 분리 없음 = **실사고 2호 재발 없음**) · 인보이스 2337334 전액 일치(16,405.40/16,405.40) · `Stock receiving 08/12/2026` · 빈 DRAFT 인보이스 없음(실사고 2호의 지문 부재). 잔여 미확인은 ③(stage2 만 실패 시 재개)·⑤(stockTransfer 정정)뿐 — 발생 조건이 와야 확인 가능한 항목이라 열어 둔다.
- ~~⚠️⚠️ **리로드 복원 URL — 배포 전 · 계정 2개 소유권 차단 테스트 통과 전 push 금지**~~ — ✅ **2026-08-10 배포 + 소유권 차단 4경로 실측 통과** (세션 문서 2장 표): ① B 계정이 A 의 `?batch=` URL 로 진입 → **차단** + 목록 이탈 + toast(`That batch is now assigned to … — re-scan the pick list to take it over`) ② **F5 신규 로드 → 재진입 + 수량 보존**(이 기능의 목적 그 자체) ③ 뒤로가기→앞으로(`pageshow`) 재진입 ④ Hold → Resume 재진입 + 수량 보존. **배포 가드를 앞질러 나가 있던 유일한 항목이 이걸로 정상화됐다.** ⬜ 잔여 소확인: wave·pack 변형 각각의 재진입 / `chrome://discards` Discard 복귀 / Hold·완료 후 URL 비워짐. ~~이미지 lazy 의 "리로드 빈도 감소"는 미검증 가설~~ → ✅ **2026-08-11 닫힘** — 작업자 확인: "스크롤 중 리프레시·튕김 현상 사라졌다"(세션 문서 8장). 코드로 증명 불가한 항목이라 **직접 질문이 유일한 판정**이었다.
- ⚠️⚠️ **Hold RPC `wms_hold_pick`/`wms_hold_pack` (2026-08-07 · 규칙 9·18·23·28)** — ✅ **2026-08-10 배포 + 단일 픽 경로 부분 검증**: Hold → 목록 "Resume your held" 배지 → 재진입 시 스캔 수량 보존 (세션 문서 2장). ⬜ **남은 확인**(아래 목록 중 단일 픽 Hold→Resume 외 전부 — 특히 wave Hold·팩 Hold·음성 프로브): ① 프로덕션 음성 프로브(`p_task_id:-1` 그리고 픽은 `p_wave_id:-1` 도 → `{held:false, worker:"이름"}` 무기록 · anon 은 permission denied) ② 단일 픽 Hold → 목록에 "Resume your held" 노출 → **다른 계정**으로 이어받기(라인 수량 보존) ③ 팩 Hold → 재개 ④ **wave Hold**(wave 행·멤버 전부 pending+held_by 를 SQL 로 확인) → wave 재개 ⑤ Hold 실패 alert 문구가 실물 태블릿에서 읽히는지(HOLD FAILED — NOT held) ⑥ 재탭(응답 유실 흉내는 어려우니 이미 held 인 상태에서 뒤로가기 없이 Hold 재시도) → "Already held" + 목록 복귀. — 로컬 테스트 12케이스는 있으나 ⬜ 현장 미검증. 확인할 것: ① 프로덕션 음성 프로브(단일 `p_task_id:-1` **그리고 wave `p_wave_id:-1`** → `{completed:false, worker:"이름"}` — wave 모드 배선+auth 유도를 한 번에 · 모드 배타 예외) ② 배포 전 **잔재 감사 SQL**(completed wave + 미완 멤버 — 과거 2단 쓰기 잔재 실재 여부) ③ 단일 픽 정상·부족 완료 회귀 ④ ⚠️ **wave 픽 완료**(2오더 그룹 — short 의 오더별 귀속 + 멤버·wave 동시 completed 를 SQL 로 확인) ⑤ 선언(stock_short) 갱신/stale delete ⑥ 이름 드리프트 프리즈 문구.
- ⚠️⚠️ **팩 완료 RPC `wms_complete_pack` (2026-08-06 8단계 · 규칙 9)** — 로컬 테스트 8케이스는 있으나 ⬜ 현장 미검증. 확인할 것: ① 프로덕션 음성 프로브(남의/없는 태스크 → `{completed:false}` · 불량 reason → 예외 — 안 씀이 설계 보장) ② **테스트 오더 양성 프로브**(`{completed:true}` + 전후 SQL 덤프 diff — 절차는 배포 보고) ③ 정상 완료 회귀(초과 2택·선언·회복 갈래 포함) ④ CAS 실패 시 라인 미변경 ⑤ 전 라인 stock_short 선언 완료 ⑥ 60줄 소요시간(순차 60요청 → 1 RPC) ⑦ 이름 드리프트 프리즈 문구.
- ⚠️⚠️ **2026-08-05 배포 4건 — 전부 현장 미검증** (커밋 `b426275`·`d64ebff`·`70cf91d`·`9c97618`).
  가장 중요한 것은 **인보이스 기준 기대치의 Advanced 경로 + 첫 Apply** 다(재고·Cin7 반영이 걸린 유일한 건).
  1. **완료 확인 마찰 모달 (`b426275` · 규칙 9 · SO-14129)** — ✅ 확인됨: 모달이 뜨는 것 · 표시 중 스캔 차단.
     ⬜ **미확인**: **장갑 낀 손으로 숫자 입력**(창고 실사용 조건 — 못 치면 작업이 멈춘다) ·
     **부족 50% 경계**(티어 2 전환이 실제 오더에서 옳은 쪽으로 갈리는지) ·
     **picker 경로**(`Complete as incomplete` — 지금까지 본 것은 packer 뿐).
  2. **리스트뷰 행 탭 + packer available 칩 (`d64ebff`)** — ✅ 확인됨: 행 탭 → 싱글뷰 전환.
     ⬜ **미확인**: **`← Back` 의 스크롤 복원**(탭한 행으로 돌아가는지 — 60줄에서만 드러난다) ·
     **뷰 선호(`view`) 유지**(Back 없이 완료/Hold 로 나간 뒤 다음 배치가 선호 뷰로 열리는지) ·
     **wave 모드**(`_orderId` 라인이 섞인 리스트에서 행 탭).
  3. ⚠️⚠️ **인보이스 기준 기대치 (`70cf91d` · 규칙 20 개정)** — ✅ 확인됨: **Simple PO 경로** ·
     ✅ **2026-08-10 추가 확인**(세션 문서 2장): **첫 Apply 포함 누적 8회** — `expected_source='invoice'`
     receipt 8건 중 7건 기 Apply 성공 + PO-01121(61/61) · `expected_source='invoice'` 실제 기록도 같은 실측.
     ~~⬜ **미확인**: **Advanced 경로**(`invoiceBlock()` 의 배열[0] 분기 —
     PO-01068 이 Advanced 인데 이미 Apply 돼 재사용 불가)~~ → ✅ **2026-08-12 PO-01027 로 확인**
     (Simple→Advanced 전환 PO 재Apply 완주 — Target I&R group 1개 유도 · stage1 delta · stage2 전량 put-away.
     세션 문서 8장. ~~⬜ `Target I&R group` 표시 항목을 검증 대기에서 닫을지는 다음 Advanced 정상 케이스 후 판단~~
     → ✅ **2026-08-13 닫음** — 그 "다음 Advanced 정상 케이스"가 왔다: PO-01128(전환·복구 없는 정상 경로 완주,
     아래 Advanced PO 2단 Apply 항목의 PO-01128 실측 참조)) ·
     ⬜ 인보이스 폴백 경고 토스트가 실물에서 보이는지는 여전히 미확인.
  4. **receiver 리포트 3종 (`9c97618` · 규칙 14)** — ⬜ **전부 미확인**. 최소 확인:
     **admin Reports 탭에 스캔한 바코드 값이 실제로 보이는지**(`box_barcode` 의 note 가 본체다 —
     안 보이면 매니저가 Cin7 에 반영할 수 없어 기능이 무의미하다) · `receipt_id`+`po_number` 귀속으로
     Order 열이 PO 번호를 표시하는지 · 이미지 토글 복원(`receiptId|sku` 키).

- ⚠️ **fulfillment 스캔 배정 (규칙 36)** — `Move all` 기본값 · 포커스 정책 · 오프라인 롤백 · **기존 DnD/탭 경로 회귀** · 태블릿 sticky 오프셋. 현장 검증 전에는 "동작한다"고 기록하지 말 것.
- ~~⚠️ **트랜스퍼 (a) 케이스**(창고 착지·bin 없음)~~ — ✅ **2026-08-10 완주** (TR-03259 — 위 「리시빙 Apply」 2번·세션 문서 2장).
- ⚠️⚠️ **초과 클램프 "자르는 동작" 첫 실전 (2026-08-10 배포 · 규칙 20 ① · 세션 문서 7장 11번)** — ✅ **부분 확인(2026-08-12 PO-01027): 자르는 동작 자체는 실전 정상 작동**(CRO71965 writes 12 of 24 — 인보이스에 있는 SKU 는 제대로 잘림). → ✅ **재Apply 완주(2026-08-12 후반, 반전 배포 후)**: 10 bin 그룹 전량 · `CRO85684·CRO85716 NOT ON INVOICE - writes 0` · Apply 성공(세션 문서 8장). ⬜ 남은 것 = **정상 초과 케이스**(전환·복구 없이 처음부터 클램프만 발동하는 회차) 1회 — **다음 초과 리시빙에서**: dry-run `1b) CAPPED` 스텝 + `capped_to_invoice[]` 확인 → commit 후 Cin7 stock received 수량 = 인보이스 수량 · `exported_base` = 클램프값 · apply_note `CAPPED to invoice quantity`. ⚠️ **매니저가 Cin7 수동 조정을 하지 않으면 창고 실물과 Cin7 이 계속 어긋난다 — 이 정책의 유일한 실패 지점**(discrepancy 큐 에이징 알림(위 「리시빙 Apply」 10번)의 우선순위가 이 배포로 올라갔다).
- ~~**병렬 배치 176그룹급 실전 관찰 (세션 문서 7장 10번)** — 대형 트랜스퍼에서 `CHUNK - N group(s) moved` 가 **8 근처면 설계대로**. **4 이하면** 파티션이 매 회차 전체 그룹을 도는 오버헤드를 의심할 것(종전엔 가드에 걸리면 루프를 빠져나갔다).~~ → ✅ **2026-08-12 닫힘** (Cin7 API Log 실측 — **규칙 21 병렬 배치 「실전 검증 닫힘」 항목이 정본**: 같은 초 4건 발사 · 회차당 12그룹 상한 달성 · TR 번호 역전 = 큐잉 없음). 176그룹급 다회차는 안 겪었으나 충분하다고 판단해 닫는다(사용자 결정 · 저녁 문서 B절) — N 판정 기준(8 근처/4 이하)은 취소선 원문에 남긴다.
- ⚠️ **풋어웨이 진입 성능 태블릿 실물 확인 (규칙 34)** — 직렬 await 제거 수정은 유선에서만 확인했다. 태블릿 Wi-Fi(RTT 150~400ms)에서 진입 즉시 전환·백그라운드 저장 완료를 실물로 확인할 것(`?debug=perf`).
- ⚠️ **픽·팩 재고 부족 선언 / 초과 2택 모달 (규칙 41, 2026-08-04 배포 · 2026-08-05 재확인: 여전히 미검증)** — **현장 검증 기록이 없다.** 확인할 것: 픽커 선언 → 팩커 화면 칩(`Stock short — declared by {picker}`) 표시 · 선언 후 수량을 채운 라인의 stale claim 해소 · 라인별 2택 모달이 초과 라인 **여러 개**에서 각각 뜨는지 · admin Discrepancy 카테고리 필터·Stats tally 에서 `stock_short`/`pack_scan_mistake` 가 실수로 안 잡히는지. **현장에서 보기 전에는 "동작한다"고 기록하지 말 것.**
- ⚠️ **PO 목록 Status 기반 조회 (규칙 20 개정, 2026-08-04 배포)** — 확인된 것은 **EF 응답 수준까지**다(`scanned {INVOICED:73, RECEIVING:5}` · 973행→78행 · 대상 8건 동일 — 배포 전후 diff). **receiver.html 로 실제 PO 를 받아 완료까지 가는 흐름은 이 세션에서 확인하지 않았다** — 특히 `truncated`/`totals` 진단 필드가 `pos` 소비 경로를 깨지 않는지, 부분입고(RECEIVING) PO 가 목록에 남는지.
- ⚠️⚠️ **풋어웨이 bin 단위 완료 + admin 경고 (2026-08-04 배포 · 2026-08-05 재확인: 여전히 미검증, `references/frontend.md` 「풋어웨이 완료 입도」)** — **실물 확인 전혀 없음.** 확인할 것: ①`Place all in this bin` 일괄 **적용과 해제**(재클릭 confirm) ②**20줄 이상 bin 의 반응 속도**(낙관적 렌더 + 동시 8개 풀이 태블릿 Wi-Fi 에서 실제로 안 멈추는지) ③오프라인/순단에서 **`NOT SAVED` 표시 → 완료 flush 가 되찾는지** ④**admin 주황 버튼이 Apply 상태 머신(규칙 35)과 충돌하지 않는지 — 특히 실패 후 5초 뒤 초록이 아니라 `wait` 복구로 다시 주황이 되는지** ⑤「Awaiting putaway」의 `Put away →` 딥링크 이동.
- ⚠️ **`_shared/cin7.ts` 추출 후 `receiving` 재배포 확인 (규칙 12, 2026-08-04)** — `hello` 와 공유하는 파일로 바뀌었고 receiving 은 import 교체뿐(동작 불변 diff 확인)이지만, **재배포 후 Apply dry-run 으로 한 번 확인**할 것. ⚠️ `_shared` 를 고치면 **hello·receiving 둘 다 재배포**.

### 신규 기능
- 🆕 **BQ CSV 이미지 경로는 여전히 수동이다 (2026-08-14 · ⬜ 2026-08-15 결정 예정)** — WMS 는 `product-images` EF 가 매일 덮으므로 영향이 없지만, **Customer Portal 등 다른 앱은 BQ 를 본다**(「상품 이미지 파이프라인」 절). CSV 3단계(다운로드→업로드→GAS 실행)는 앞의 둘이 손이라 트리거를 붙여도 반쪽이고, ⚠️ GAS 트리거는 20/20 으로 꽉 차 있다. ⬜ 후보: ① GAS SystemMonitor 에 "`asung_product_images.updated_at` 이 N일 초과" 검사 추가(기존 모니터 루프라 트리거 0 · 알림이 밖으로 나간다) ② 캘린더 월 1회 반복(코드 0줄) ③ EF 가 BQ 에도 쓰기(서비스 계정 인증 필요 — 새 설계). ⚠️ 판단 기준은 **"포털 사진이 실무에서 얼마나 중요한가" — 미확인.**
- 🆕 **`image_sync_stale` 48h 를 조일 값어치 (2026-08-14)** — 하루 1회 실행인데 48h 기준이면 **두 번 연속 실패해야** 경고가 뜬다. 운영 안착 후 26~30h 로 조이는 것 검토(지금은 첫 실행 확인 단계라 그대로 둔다).
- ~~🆕 **Health 12검사 자동 실행 (2026-08-13 · 우선순위 1위 — 백로그 머리 참조)**: `wms_health_check()` 12검사는 만들어 뒀으나 **사람이 admin Health 탭을 눌러야 돈다**(규칙 19). 08-07 리포트가 지적한 그대로이고, **08-02~03 에 20시간 자동화 정지가 실제로 있었다 — 원인이 점검 장치 자체여서 알림도 안 울렸다.** → pg_cron 에 하나 추가: 매일 `wms_health_check()` 실행 → fail_count > 0 이면 알림.~~ → ✅ **2026-08-14 완료 — 스냅샷·이력·배지 전환 + PUBLIC 회수** (마이그레이션 2건 + cron.sql 잡 3 + admin.html):
  - [실측 2026-08-14] `wms_health_check()` 실행 **1,271ms · shared hit 70,550**(explain analyze). ⚠️ admin 부팅마다 `refreshHealthBadge()` 가 이걸 통째로 돌고 있었다 — `finalize_recon` 이 closed 오더 전체를 스캔하므로 오더가 쌓일수록 계속 느려진다.
  - `wms_health_runs` 이력 + `wms_health_snapshot()` 신설(`20260814000000_health_snapshot.sql`) · pg_cron **1시간 주기**(사용자 결정) · 90일 보존 정리는 함수 안에서(`wms_reap_stale_claims` 패턴 — 별도 정리 잡 없음). ⚠️ **CTE `materialized` 필수** — select 리스트에서 r 을 집계와 서브쿼리 양쪽에서 참조하므로 inline 되면 검사가 2회 실행(1.27초 → 2.5초). PG12+ 에서 1회 실행 강제.
  - 배지는 `wms_health_runs` 최신 1행만 읽고, Health 탭은 라이브 RPC 유지(+ 마지막 스냅샷 시각 표시 — 자동 실행 생존을 사람이 보는 창). ⚠️ **조용한 무시 제거가 이 작업의 실질**: 종전 `catch(e){}` 라 RPC 가 죽으면 배지가 그냥 안 떠서 "이상 없음"과 "검사 자체가 죽음"이 구분 안 됐다 → 스냅샷 없음·3시간+ stale·조회 실패는 **회색 "?" 배지**(08-02~03 20시간 정지가 알림 없이 지나간 사고의 처방).
  - [실측] 12검사 전부 fail_count 0 — 자동화하기 좋은 타이밍이었다. ⚠️ **검사 수 정정 경위 (2026-08-13 당일)**: 처음 "38검사"로 적었다 — 08-07 리포트의 숫자를 **검증 없이 옮긴 것**이 원인. [실측 2026-08-13] `select count(*) from wms_health_check();` → **12**(규칙 19 의 기존 서술이 맞다). 리포트의 38 은 다른 것을 센 것으로 보인다(GAS SystemMonitor 쪽 가능성 — 미확인). 📌 리포트·요약 문서의 숫자도 실측 등급이 아니다 — 옮기기 전에 세어 볼 것. 📌 **자동 테스트를 새로 만드는 것보다 이것이 먼저다 (2026-08-13 판단)**: 이 프로젝트의 결함은 대부분 "코드가 틀렸다"가 아니라 **"전제가 틀렸다"** 여서 테스트가 못 잡는다(08-13 발견 결함 5건 중 테스트로 잡히는 것 0건). 게다가 테스트 코드도 Claude 가 쓰므로 같은 틀린 전제가 테스트에도 들어간다 — **이미 만든 12검사를 살리는 것이 비용 대비 효과가 크다.** ⚠️ 단 **재고 원장에는 자동 테스트가 필요하다** — 원가 계산은 논리가 복잡하고 틀리면 회계가 틀어진다. (📌 이 문단은 1차 갱신 때 void 항목 꼬리에 잘못 붙었던 것을 3차에서 제자리로 옮김.)
  - 🆕 **`wms_health_check()` 의 PUBLIC EXECUTE 회수**(`20260814010000`) — [실측] proacl 이 `{=X/postgres, postgres=X/postgres, authenticated=X/postgres, service_role=X/postgres}`: ① `=X/postgres`(사용자명 없이 =) = **PUBLIC 에 EXECUTE 가 있다** → anon 은 PUBLIC 경유로 실행 ② **anon 항목 자체가 없다** → baseline 의 GRANT ALL 을 근거로 `from anon` 만 쓰면 아무것도 회수하지 못한 채 조용히 통과했을 것이다 — **규칙 29 의 또 한 사례**. (sample 에 오더번호·SKU 가 실리고 SECURITY DEFINER 라 RLS 도 우회했다.)
  - ⬜ 미검증: 정시 cron 이 실제로 도는지(`wms_health_runs` 2행째).
- ~~**Cin7 void 감지 (2026-08-13 우선순위 — 백로그 머리 참조)**: Cin7 에서 오더를 void 해도 WMS 가 모른다.~~ → ✅ **2026-08-14 완료 (커밋 `6a46a15` — 규칙 43 과 같은 뿌리·별도 감지 루프)**: 실사고 SO-14015 — 07-31 유입 → **08-04 15:30 Cin7 void** → WMS 는 ready_to_close 로 **9일 방치**(08-13 지체 목록 59h 빨강으로 사람이 발견) → 08-13 15:57 매니저 수동 ⊘ Void(⚠️ 당시 CombinedPickingStatus='PICKING' — 실물이 토트에 있었을 가능성이 높다).
  - [실측 2026-08-14 GAS] void 된 sale 은 `saleList?OrderStatus=AUTHORISED` 에서 **빠진다**(Total 0). 무필터엔 남고 Status·QuoteStatus·OrderStatus·CreditNoteStatus·RestockStatus 가 모두 VOIDED. ⚠️ 판정은 **`Status='VOIDED'`** 만 — CombinedPickingStatus 는 갈린다(SO-14613 NOT PICKED / SO-14015 PICKING). ⚠️ saleList 응답에 AdditionalAttribute1 이 **없다** · 키 이름은 **SaleID**(ID 아님).
  - 감지 = hold 와 구조가 다르다: "값이 바뀐 행"이 아니라 **"있던 행이 없어짐"**. WMS 활성 오더 − 이번 회차 목록 = 사라짐 후보 → 확정 조회. ⚠️ 대조 기준은 **skip_picked 이전의 전체 candidates** — notPicked 로 대조하면 Cin7 이 먼저 픽한 오더가 전부 오탐.
  - ⚠️ **연속 2회차 완충**(사용자 결정): 1회차 부재는 기록만(`cin7_gone_missing_since`), 2회차만 확정 조회, 재등장 시 자동 해제 — "없다"가 진짜 void 인지 목록 누락인지 구분할 방법이 없고 오판의 대가(작업자가 멀쩡한 오더를 멈춤)가 크다. ⚠️ truncated/rate_limited/**Total 미보고** 회차는 전면 스킵(fail-safe).
  - 확정 조회(saleList Search) 4분기: Status=VOIDED→`cin7_void_state='voided'` / OrderStatus=AUTHORISED→목록 누락 글리치 해제(⚠️ 무필터 Search 엔 FULFILLED 도 있으므로 OrderStatus 로 가른다) / Search 에도 없음→`gone_other`+**NOT_IN_CIN7**(무한 재시도 금지 — 언더스코어 = Cin7 원문 아님 표식) / 그 외→`gone_other`(표시만).
  - 화면: 안 잡은 배치는 대기 풀 숨김 · **진행 중은 빨간 배너**(숨기면 실물이 토트에 남는다 — 중단 여부는 작업자가 아니라 매니저가 정한다) · **status 무접촉, voided 전환은 ⊘ Void 수동만**(감지는 자동·처분은 수동 — 규칙 43 비대칭 원칙. admin Status 탭에 처리 대기 카드 + ⊘ Void 바로가기). Cin7 콜 추가 0(활성 오더 Supabase 1콜만 — existingSaleIds 는 목록의 SaleID 로 조회하므로 "목록에 없는 오더"가 구조적으로 안 나온다).
  - [검증] dry-run `void_active` 35 · `candidates_new` 0 · `skipped_unsafe` false. ~~⬜ 실전 미검증: 실제 void 발생 시 5~10분 내 감지.~~ → ✅ **배포 당일 첫 실전 탐지 (2026-08-14 저녁 — SO-13993 을 `gone_other` 로)**: `cin7_gone_status` = **CLOSED**(voided 가 아니라 다른 종착) · `cin7_gone_missing_since` 17:25(1회차 부재 기록) → 2회차 확정 조회 — **연속 2회차 완충이 실제로 작동했다.** 📌 이 오더는 08-13 지체 목록에서 **336시간(14일) 방치**로 빨강이던 그 건이다 — Cin7 에서는 이미 종결됐는데 WMS 만 ready_to_close 로 붙들고 있었다(SO-14015 의 void 9일 방치와 같은 계열의 **다른 종착**). ⚠️ gone_other 라 화면에서 숨기지도 막지도 않는다 — 설계대로다(처분은 매니저 ⊘ Void 수동). 같은 날 오탐 0(활성 오더 대조 `candidates_new` 0). 📌 **배포 당일에 실전 성과가 나왔다 — 어제였다면 아무도 몰랐다.**
  - ⬜ **진단 `void_cleared` 가 두 의미를 합친다 (2026-08-14 관찰)**: ① 목록 재등장(정상 복귀 — un-void 포함) ② 확정 조회에서 OrderStatus=AUTHORISED(목록 누락 **글리치**였다). ⚠️ ②가 계속 >0 이면 **폴링 목록에 구멍이 있다는 신호**인데 합쳐져 있어 구분이 안 된다 — 진단 필드 분리 후보(급하지 않음 — 실해 없음).
- ⚠️ **오프라인 대응 — 판단 정정 기록 (2026-08-13)**: 08-07 리포트가 "없는 기능 중 하나만 고르라면 이것"으로 꼽았다(매일 작업에 영향). 그런데 6일간 미착수이고, 2026-08-13 에 Claude 가 "지금 인터넷 문제 없으니 미루자"고 권했다 — ⚠️ **그 판단은 6일 전 자기 문서를 근거로 반박되지 않은 채 통과됐다. 기록해 둔다.** 선행: **풋어웨이의 `NOT SAVED` → 완료 flush 회복이 이미 구현돼 있으나 미검증**이다(「검증 대기」 풋어웨이 bin 단위 완료 항목의 ③) — **새로 만들기 전에 있는 것부터 검증할 것.** 이후 ① Service Worker(화면만이라도) ② IndexedDB 큐(⚠️ **이미 잡은 배치의 스캔만** — 배치 claim 을 오프라인에서 하면 CAS 의 "서버가 진실" 전제(규칙 28)가 무너진다) ③ 로컬 우선 DB 순. ⬜ 실제로 와이파이 약한 자리에서 멈춘다는 현장 보고가 지금도 있는지 확인이 먼저.
- ~~**Order Trace — CCTV 조회용 (2026-08-13 후보 · 규칙 9/37 계열)**~~ → ✅ **2026-08-13 구현·검증 완료 (커밋 `e01565e` — admin 9번째 탭 `Trace`)**: 손님 미수령 연락 → 어느 분할 배치를 누가 언제 어느 창고에서 작업했는지로 CCTV 시간·장소 특정. ⚠️ 후보 시점의 "`wms_staff.perms` 게이트" 구상은 **안 만들었다** — admin.html 전체가 `requirePerm:"admin"` 이라 탭 추가만으로 매니저 한정이 성립(perms 게이트는 탭 단위가 아니라 화면 단위 — 2026-08-13 조사). 검색 2경로 = 오더번호 `.eq` 정확 일치(Rollback void 박스 패턴 재사용) / **손님명 ilike — admin 첫 ilike 선례**(`%`/`_` 이스케이프 · 최근 30 + `count:"exact"` 총수 캡션 — "잘린 모수" 계열 표시 관례). 상세 = 병렬 3왕복: ① `wms_pick_tasks` + 픽라인 임베드 + `wms_pack_tasks`(`uq_packtasks_pick` 유니크 — 픽 배치와 1:1) + 팩라인 ② `wms_order_lines` **sbAll 전량**(⚠️ 라인 ~1000개 오더가 실재해 캡 경계) ③ discrepancy order_id 귀속(배치 귀속은 pick/pack_task_id · 08-06 이전 NULL 링크·롤백분은 "batch unknown" 블록).
  - ⚠️⚠️ **라인 테이블에 SKU 컬럼이 없다** — `wms_pick_task_lines`/`wms_pack_task_lines` 에는 `order_line_id` 뿐이고 SKU·상품명·bin 은 `wms_order_lines` 조인으로만 나온다. **픽↔팩 라인 매칭도 order_line_id**(SKU 매칭 금지 — 같은 base_sku 가 여러 order_line 일 수 있다). 📌 이걸 모르고 설계했다가 조사에서 잡혔다 — 다음에 라인을 다룰 때 같은 함정. [실측 2026-08-13] `(task_id, order_line_id)` 중복 0행 — 태스크 내 1:1 성립(픽·팩 양쪽, 단 DB 유니크 제약은 없음).
  - 시각 = **토론토 로컬** + 에드먼턴 오더는 EDM 병기(Intl timeZone 변환 — 오프셋 하드코딩 없음). ⚠️ **소요는 달력 경과** — 같은 날 지체 지표(규칙 37)는 근무시간 자로 통일했지만 **CCTV 는 벽시계**이므로 여기만 의도적 예외.
  - 배치 정렬 자연수(`trBatchCmp`) — ⚠️ **baCmp 직접 호출 금지**: `baSort` 전역(정렬 키·방향)이 새어 들어온다. batch 키 로직만 복제(주석에 출처 명시).
  - ⚠️ **한계 = 배치 단위가 상한** — `picked_at` 죽은 컬럼(19,375행 전량 null) + [실측 2026-08-13] `verified_at` 도 팩 완료 RPC 가 `v_now` 하나로 전 라인 일괄 기록(`20260806150000:90`) → **라인 시각은 픽·팩 양쪽 다 없다.**
  - ~~⬜ **실전 미사용**~~ → ✅ **2026-08-13 실전 통과** — 화면 조회·표시가 실전에서 정상 작동 확인. ⚠️ 단 **"CCTV 30분 구간이 실용적인가"는 별개로 열려 있다** — 실제 클레임 대응에서 그 구간으로 영상을 찾을 수 있는지는 여전히 관측 대상이며, **그것이 아래 「picked_at 살리기」 착수 여부의 근거다.**
- **picked_at 살리기 — 개별 SKU 스캔 시각 (2026-08-13 · 규칙 37 「순수 작업시간」과 Order Trace 의 공통 선행)**: ⚠️ 비용이 크다 — ① 완료 시점 일괄 기록은 무의미(전부 같은 시각) → **스캔 시점** 기록이어야 한다 ② 스캔마다 서버 쓰기 = 왕복 급증(대형 배치 수백 스캔) ③ 대안(로컬 배열 → 완료 시 일괄 저장)은 왕복 불변이나 **클라이언트 시각** — 태블릿 시계가 틀리면 CCTV 대조에 치명적 ④ **검증된 픽 경로(8단계 RPC 원자화)를 건드린다 — 동작 동일성 증명 선행**(규칙 9). Order Trace 정밀도와 순수 작업시간 집계 둘 다 이것에 걸려 있다.
- **admin 1-B — ORDER STATUS/WORK BATCHES 카드 클릭 → 오더 목록 (2026-08-13 보류)**: 구현하지 않았다. BATCH ACTIVITY 의 Phase·State 필터가 상당 부분 대체했으므로 **사용해본 뒤 여전히 필요한지 판단**. 연결 고리는 준비돼 있다(`.stat.link` CSS 정의 + orderStats 배열의 미사용 status 키 `s` — data-st 로 살리면 됨).
- **Finalize 시 Cin7 `3.Finalized` 자동 업데이트 (2026-08-12 검토 — 보류)** — 기술적으로 가능하나 **되돌릴 수 없는 Cin7 쓰기가 는다.** 지금은 사람이 보는 단계가 마지막 안전망이라 자동화하지 않는다(세션 문서 11장 — Rollback Finalize 미모델링과 얽혀 있어 그쪽 설계가 선행).
- **Cin7 bin↔bin 이동 화면 — 규칙 33**(A 자유 이동 → B 풋어웨이 큐. `wms_bin_moves` 감사 테이블 필요, `wms_sku_bins` 에 쓰지 말 것).
- **원가 0 재고 재평가 방법 확정 — 규칙 31**(미해결. 1 SKU 로 2단계 후보를 끝까지 실측).
- **박스 라벨에 스토어명 인쇄** — 스캔 배정으로 "박스=오더 하나"가 정착되면 가능. 프랜차이즈 창고가 박스를 열어보지 않고 스토어별 재분배할 수 있다(fulfillment 스캔 배정의 후속, 2026-07-29).

### 문서·스킬 유지

- ~~⚠️⚠️ **`asung-wms` frontmatter description 압축 — 1017 / 1024 자, 여유 7자**~~ — ✅ **2026-08-05 완료: 722자 / 여유 302자.** 무엇을 뺐는지와 왜 그것을 골랐는지는 위 「이 스킬 문서를 갱신할 때」 · CLAUDE.md 7절. 요약: 키워드 9개 제거(중복 2 · 과도하게 일반적 2 · 해소된 함정어 2 · 구현 내부 이름 3) + 열거 1개 압축 + ⚠️ 불변식 9→4. **본문에서 빠진 사실은 없다.** 검사 `scripts/check-skill-desc.sh`.
- **`shopify-tracking` description = 855자 / 여유 169자** (2026-08-05 실측 — 이제 6개 스킬 중 가장 빡빡하다). 그 스킬에 키워드를 더할 때는 같은 압축 순서를 적용할 것.
- ⬜ **CLAUDE.md 에 "커밋 메시지 Co-Authored-By 금지" 명문화 (2026-08-13 미완)**: Claude Code 가 커밋 메시지에 자동으로 붙이는데, 채팅과 Claude Code 는 별개 세션이라 **프롬프트마다 수동 지시가 필요했다**(2026-08-13 하루 종일 반복). CLAUDE.md 커밋 규칙 절에 넣으면 영구 해결 — 아직 확인·추가 안 함.

### 캡 위험 전수조사 (2026-08-12 — PostgREST 1000행, 규칙 20 캡 함정 절·check-caps.sh 와 연동)

미수정 지점엔 코드에 `// caps-ok: TODO(캡 위험 #n — 미수정, …)` 부착 — **caps-ok 는 "검토 끝"이 아니다.** 추적: `grep -rn "caps-ok: TODO" *.html supabase/functions | wc -l`.

| # | 위치 | 상태 |
|---|---|---|
| 1 | fulfillment 완료 팩(보드 원천) | ✅ **근본 수정(2026-08-14 — `wms_orders!inner` 안 닫힌 오더만, packer 와 같은 커밋 `de4a5f2`)**. desc+LIMIT 은 이중 안전 유지. (종전 응급: 내림차순+LIMIT — 998/1000 에서 2건 전) |
| 2 | admin `wms_pick_tasks` 배치 카운트 | ✅ 근본 수정(2026-08-12 1단계 — count-head 4콜·행 0개. 종전 1000+ 과소 표시였으므로 수정 후 증가가 정상) |
| 3 | admin `wms_pack_tasks` 배치 카운트 | ✅ 근본 수정(동일 커밋 — completed 는 카드가 안 써 아예 미조회) |
| 4 | admin Finalized 팔렛 배지 pallet_items | ✅ 수정(.in 300오더 + range 페이지네이션 — 발견 시 이미 2517/1000) |
| 5 | admin Stats 기간 조회 6곳(픽/팩/disc/reports/recvStats 2곳) | ✅ 근본 수정(2026-08-12 4단계 — `sbAll` 페이지 누적으로 기간 전량. **종전 1 year/All 은 1000+ 로 지표 과소였으므로 수정 후 장기 기간 숫자 증가가 정상.** 임베드 라인은 최상위 행에 실려 페이지와 함께 온전 — 라인·유닛 합계도 캡 무관. 서버 집계 뷰/RPC 는 불채택: 펼침 목록이 행 자체를 쓰므로 전량 행이 필요) |
| 6 | manager Splitting `pending+voided` 오름차순 | ✅ 근본 수정(2026-08-12 5단계 — 쿼리 분리: pending 전량(활성 풀·캡 무관) + **voided 최근 50 사양**(전량 아님 — 사용자 확정: "목록은 최근 N, 전체는 검색으로") + ⊘ 버튼 라벨 = count-head 총수. 핵심 = "잘려서 안 보임(총수 모름)"→"정해서 안 보여줌(총수 표시)") |
| 7 | admin Rollback 대상 목록(closed 포함·오름차순) | ✅ 근본 수정(2026-08-12 5단계 — 활성 3상태 전량 + **closed 최근 200 사양**(updated_at desc, 총수 count-head 캡션) 병합 후 order_number 재정렬. **다운스트림 4쿼리(picks/packs/pallet_items/pick_task_lines `.in`)도 sbAll** — #4 실측(오더 300개=2517행)이 근거: `.in` 이라도 행 수는 오더당 배수라 잘리면 stage 판정이 조용히 얕아진다) |
| 8 | admin open 큐 2곳(reports·discrepancies) | ✅ 근본 수정(2026-08-12 3단계 — `sbAll` range 페이지 누적으로 전량. 실측 11·15건이라 지금은 1왕복 그대로 = 예방. 미해결 큐는 잘리면 처리 누락이라 전량 정확성이 목적) |
| 9 | admin 요약·추세 쿼리 | 잘림 표기 있음("trend counts the first N of M") — 기존 백로그 「예고된 만기」 |
| 10 | receiving EF receipt_lines(문서당) | 여유 — 문서 라인 수 bound(실측 최대 344). 1000라인+ 문서만 이론상 위험 |
| 11 | receiver 빈 지정 드롭다운 폴백 `wms_sku_bins.eq("warehouse")` | ✅ 근본 수정(2026-08-12 2단계 — RPC `wms_warehouse_bins` jsonb 단일 값·1왕복. **실측 8105/7371행 = 캡 8배 초과, 발견 시 이미 잘린 상태**(1481개 중 최대 1000개·누락 bin 미정의) — "실해 제한적" 판단은 실측 전 과소평가였다. 뷰는 기각: distinct 1481 > 1000, 규칙 20 원리) |

~~3호(packer donePick·allPack)는 2026-08-12 응급 수정 완료. 근본 수정(!inner 안 닫힌 오더만)은 「동시 작업 원자화」 위 packer 항목.~~ → ✅ **2026-08-14 근본 수정 (커밋 `de4a5f2` — donePick·allPack·fulfillment #1 같은 커밋)**: [실측 2026-08-14] 완료 픽 **1,140행 — 이미 캡 초과**(140건이 창 밖) · 안 닫힌 오더 소속은 **13행**(98.9% 감소 — 행수가 활성 오더 규모로 유계라 캡이 구조적으로 무관) · `wms_pack_tasks` 도 **1,135행**. 창 밖으로 밀린 활성분은 아직 0이었으나 오래 방치된 미팩 배치 하나면 밀린다 — ⚠️ **allPack 이 밀리면 claimedPickIds·held 보호가 함께 사라져 그 픽이 poolNew 에 재등장 = 이중 팩 가능성**(이 수정이 그 경로를 닫는다). desc+limit(1000) 은 이중 안전으로 유지. 🆕 **레포 첫 `!inner` 실사용** — [실측] 문법 통과(error null · to-one 임베드는 여전히 객체라 소비 코드 무변). ⚠️ **임베드를 select 에서 아예 빼면 같은 필터가 400 으로 거부된다**(실측 — 시끄럽게 죽어서 차라리 안전). ⚠️ 그러나 **임베드는 있는데 !inner 만 빠지면 조용히 틀린다**: 부모 행이 남고 임베드가 null → `inWh(null)` 이 acc="both" 작업자에게 true → 고객명 없는 카드가 쏟아진다.

- ⬜ **훅의 `.in(ids)` 구멍 (2026-08-12 5단계에서 실물 확인)** — 식별자 `.in` 통과 규칙은 "행 수 = 항목당 배수"를 못 본다: ids 300개면 결과가 수천 행일 수 있다(#4 실측: 오더 300개 → pallet_items 2517행. 롤백 다운스트림 4쿼리가 같은 모양이었고 잘리면 stage 판정이 조용히 얕아진다 — 5단계에서 sbAll 로 수정). **`.in` + 배수 테이블(pallet_items·*_task_lines 등) 조합을 볼 때마다 물을 것** — 훅 규칙 자체의 개선(자동 감지)은 오탐 비용 대비 판단 필요, 별건.

- ⚠️⚠️ **"잘린 모수" 계열 — 명시적 LIMIT 이 집계 숫자로 샌다 (2026-08-13 하루 3건 연속 — 패턴으로 기록, 규칙 20 캡 계열)**: ① Rollback finalize 토글 — 버튼 640(총수) vs 목록 200 ② Status ORDER STATUS 의 Finalized 카드 — limit 40 에 잘린 배열 길이(40 초과 시 항상 "40") ③ Finalized 탭 — closed 최근 300 고정이라 **All 인데 카드가 정확히 300**(657 중 357 누락 — MIX 카드 4개가 전부 잘린 모수의 숫자). 📌 **공통 구조 = "표시용 LIMIT 이 집계 모수로 새어 들어간다."** 캡 전수조사(#1~#11)는 PostgREST 1000행 캡(암묵)을 찾았지만 **명시적 LIMIT 이 숫자로 새는 것은 그 조사의 대상이 아니었다 — 훅도 caps-ok 도 안 잡는다**(LIMIT 이 있으면 훅은 통과). ~~⬜ 같은 모양을 계속 찾을 것~~ → ✅ **2026-08-14 전수조사 완료 (커밋 `c9ed52c` — 6화면 전부 훑음 · 결함 2건 + 디테일 1건, 전부 수정)**: ① **Finalized "N of M not yet reviewed"** — 분모가 리뷰완료 200 잘림을 그대로 썼다([실측] closed 703 · 리뷰완료 671 → 분모에서 약 471건 누락, 실제 "32 of 703"이 "32 of ~232"로 표시) → **분자·분모 둘 다 count-head**(rangeOr — FINALIZED 카드와 같은 모수·기간. 분자만 배열로 두면 두 경로가 어긋난다). 배포 후 705 확인 ② **Receiving 탭 전체가 `wms_receipts` limit(60) 배열 위에 있었다** — ⚠️ updated_at desc 라 **오래된 것부터 잘리는데 awaiting putaway 는 오래 방치될수록 문제인 지표**고, 60 밖 completed 미Apply 는 Apply 화면에서 사라져 Cin7 반영이 영영 안 된다 → **work**(미적용 전량 sbAll) + **placed**(applied 인데 미풋어웨이 라인 잔존 — !inner) + **recent**(최근 60, history 표시 전용) 3집합 재편([실측] 37/60 — 예방 수정. 📌 placed 는 (a)안 스케치가 놓친 집합 — "Cin7 applied" 태그(08-04)가 바로 이 상태이고 "Apply 끝난 것 최근 N"에 맡기면 늙는 순간 사라진다) ③ **Reports·Disc sum 쿼리에 정렬이 없었다** — 1000 도달 시 "first N of M" 표기가 전제하는 정렬이 실제로 없고 추세 바도 왜곡 → 정렬 추가([실측] 188·379 — 여유. 모수 count-head 분리는 추세가 전량 행을 필요로 해 #9 유지). 🆕 문법 실측: **`not.is.true`**(null·false 둘 다 잡는다 — count 30·error null) · **!inner + dotted 필터 4스택**(error null). 📌 **점검 질문(다음에 이 패턴을 찾을 때)**: "이 화면 숫자의 모수가 목록 LIMIT 이 걸린 배열인가, 서버가 센 총수인가?" — 전수조사는 끝났지만 새 화면·새 숫자마다 물을 것.
- ✅ **admin Finalized 탭도 같은 패턴으로 재편 (2026-08-13 사용자 결정 — "목록은 리뷰 기준")**: 종전 "closed 최근 300 고정 + 클라이언트 기간 필터"는 All 에서도 340건을 조용히 누락시켰다([실측 2026-08-13] closed **657건** — 미리뷰 **16** · 리뷰 완료 **641**, All 인데 카드가 정확히 300). 재편 = **미리뷰 전량(sbAll — 리뷰 대기 큐, 잘리면 처리 누락) + 리뷰 완료 최근 200**(#6·#7 과 같은 "전량 + 최근 N" 패턴, 총수 캡션). **카드 4개는 count-head 서버 집계로 목록과 독립** — 기간은 `coalesce(finalized_at, updated_at)` 의 서버 `or(and(),and())` 표현이라 목록의 클라이언트 inRange 와 같은 기준. 레거시 `fulfillment_type` null 은 **분모 제외 + 캡션 명시**(count-head 는 행이 없어 팔렛 폴백 분류가 불가능 — 폴백은 목록 행에만 남는다). rate 분모를 total→기록분(pk+dr)으로 바꾼 것이 종전보다 정직하다.

### 보안 (2026-08-12 발견 · 2026-08-13 게이트 확대 완료 — 규칙 8 각주의 실측이 근거)
- ~~⚠️⚠️ **EF 서버측 권한 게이트 확대** — 기존 EF(특히 receiving apply — 되돌릴 수 없는 Cin7 쓰기)는 anon JWT 로 호출 가능(규칙 8 각주 실측). hold_recheck 의 게이트(`/auth/v1/user` → wms_staff 권한)를 같은 패턴으로 이식할 것. ⚠️ 아래 "레포 비공개 전환"과 같은 뿌리 — 키가 공개인 한 클라이언트 게이트는 장식이다.~~ → ✅ **2026-08-13 확대 완료 (커밋 `c76729b` — 규칙 8 각주 백로그 해소)**: **`_shared/authgate.ts` 신설** — `verifyCaller(req)` → `{email,name,role,perms,active} | null` + `hasApply(staff)`. hold_recheck·staff-create 에 두 벌 복제돼 있던 것을 추출(**세 번째 복제를 만들지 않는다** — `_shared/cin7.ts` 추출 전례와 같은 판단 · ⚠️ 바꾸면 hello·receiving 둘 다 재배포). **receiving 2단 게이트**: read 5종(pos·po·bins·transfers·transfer) = 로그인한 active 직원 / **`action=apply` 는 dry-run·commit 둘 다** admin·'apply' 승격(사용자 결정 — 발주 계획 SKU·수량·bin 노출 차단, admin.html 만 호출하므로 깨질 호출자 0). ⚠️⚠️ **hasApply = `role==='admin' || perms.includes('apply')` — `||` 필수**: [실측] Caleb 의 perms 는 `["split","admin","staff"]` 로 apply 가 없고 role='admin' 으로만 통과한다 — perms 만 보면 admin 이 막힌다. **hold_recheck 도 authgate 로 교체 + ⚠️ active 검사 신설** — 종전 `select=name,role,perms` 로 active 를 안 읽어 **비활성화된 admin 의 살아 있는 세션이 통과했다**(staff-create 는 검사했다 — 두 게이트가 갈라져 있었다). [실측] 전원 active=true 라 현재 무영향 = 안전한 타이밍. **구현 판단 2건(실측 근거)**: ① **이메일 lowercase 안 함** — `wms-auth.js:170` 이 원문 `.eq` 하는 것이 기존 불변식. 정규화하면 mixed-case 계정이 로그인은 되는데 게이트만 막히는 회귀 ② **active 판정은 `!== false`**(`=== true` 아님) — null 행이 로그인은 되는데 게이트에서 막히는 어긋남 방지. authgate 의 wms_staff 조회 실패는 throw → 기존 catch 500 = **fail-closed**. **[검증 통과 2026-08-13]** ① 폴링 무회귀(헤더 없이 정상 응답 · list_total 93 · rate_limited false) ② receiving anon → 401 ③ receiver.html read 5종 정상(작업자 Joyce Chang·admin 둘 다) ④ hold_recheck anon → 401(authgate 교체 회귀 없음). ⬜ **미검증**: Apply dry-run 이 admin 계정으로 통과하는지(hasApply 의 `||` 판정) · hold_recheck 실제 재개(보류 오더 발생 시).
- **레포 비공개 전환 검토 — ⚠️ 위 게이트 항목에서 분리 (2026-08-13 정정)**: 종전 기록이 "같은 뿌리 — 둘 중 하나만으로는 불완전"으로 묶어 놨는데 **그것이 착수를 미뤘다.** 정정: **anon 키는 F12 로 보인다 — 레포 비공개는 근본 방어가 아니다.** 게이트만으로 실질 방어가 성립하고(2026-08-13 완료), 레포 비공개는 **로직 노출을 줄이는 별개 항목**이다. `asungtrading/asung-wms` 는 PUBLIC(Pages 무료 배포 때문 — 환경 상수 표) — 전환 시 Pages 유료화 또는 배포 방식 변경 필요(08-13 GitHub Pages 502 장애와 묶어 검토할 값어치).
- 🆕 **hello 폴링 경로 무인증 개방 (2026-08-13 · ⬜ 미착수)** — [실측] `config.toml:416-418` 에서 hello 는 **verify_jwt=false** 이고, cron.job 실물 확인 결과 `wms-poll-orders` 가 Authorization 에 **Bearer 접두어 없는 anon 키**를 넣어 부른다(그 헤더는 사실상 아무 역할을 안 한다). → ⚠️ **헤더 없이 아무나 `hello?commit=1` 을 호출할 수 있다**(2026-08-13 curl 로 실측 — 정상 응답). 재고 불가역 쓰기는 아니지만 **호출당 Cin7 GET 수십 회를 유발하는 429 남용 벡터**다. ⚠️ 게이트를 넣으면 오더 유입이 전면 중단된다 — **cron 호출 형태를 Bearer 로 바꾸는 것이 선행.** 급하지 않음(표적이 될 규모가 아님).
- **applied_by 서버 유도 (2026-08-13 · 작은 것)** — 여전히 쿼리스트링 `&by=<name>` (위조 가능 — 규칙 27 「EF 권한」 잔존분). 게이트가 생겨 이제 hold_recheck 의 `by: s.name` 처럼 **`caller.name` 으로 대체 가능**해졌다.
- **프론트 401 처리 (2026-08-13 · 작은 것)** — receiver.html `efGet`·admin.html `hdrs` 의 anon 폴백(`||WMS_CONFIG.SUPABASE_ANON_KEY`)은 게이트 후 **100% 401 이라 실패를 지연시키는 죽은 코드**다. 제안: 폴백 제거 + 401 이면 "Session expired — sign in again" 후 reload. 발생 빈도는 낮음(getSession 자동 갱신) — **401 toast 가 목격되면 착수.**

### 정리 필요 (데이터)
- 🆕 **테스트 오더 SO-14742 정리 여부 ⬜ (2026-08-14 20:35 유입 — 마지막 유입 건)** — ⚠️ 정리하지 않으면 **월요일에 작업자가 픽하려 할 수 있다.** [관찰 — 2026-08-14 하루 결산(참고 기록)] 출고 49건 정상 완료 · 하루 끝 활성 = picking 1(이 테스트 오더) + ready_to_close 1(SO-13993 — gone_other·CLOSED, 「신규 기능」 void 항목의 첫 실전 탐지 건) 뿐.
- **SO-13893 어중간 상태 (2026-08-12 발견)** — 07-30 finalize(direct) 후 Undo Pack 오판 실행으로 status='picking'+finalized_at 잔존 2주. **Cin7 정상 출고 확인됨 → `closed` 로 정합성 회복이 방향**(세션 문서 11장 — 위 「Rollback 이 Finalize 단계를 모델링하지 않는다」 참조). ✅ [실측 2026-08-13] 어중간 상태 전수 쿼리(활성 status + finalized_at) **0건** — 이미 정리돼 있었다(누가·언제 되돌렸는지는 미확인). 재등장하면 그때 다시 본다.
- **PO-01027 수동 조정 3건 (2026-08-12 재Apply 성공 후 잔여 — recv_over 큐에 있음)** — `CRO85684` 78 · `CRO85716` 60 (NOT ON INVOICE — 전량) · `CRO71965` 12 (클램프 초과분). **물건은 창고에 있고 Cin7 에는 없다** — 매니저 Cin7 수동 조정이 유일한 반영 경로(규칙 20 ③).
- TR-02935(수동 처리분) · 테스트로 만든 TR-03260(3개씩 완료됨)·TR-03261·TR-03267(수량 실측용) 재고 조정.
- **2026-08-10 세션분은 세션 문서 8장이 목록의 정본** (`docs/sessions/2026-08-10-transfer-parallel-and-clamp.md` — ANN04401/ASSH40608 감산 · ASSH40615 실물 카운트 선행 · 유령 discrepancy 281/282 · PO-01094 잔재 · 테스트 계정 · `PARALLEL PROBE` TR 8건은 상쇄 완료 등).

### GAS — System_Automation (2026-08-10 세션 문서 6·7장)
- **죽은 폴백 제거** — `|| getProp('CIN7_API_KEY')` 3곳(`InvoiceLineProbe.js` 의 `apsProbe` · `Wmstrasferwritetest.js:43` · `WmsPoStockWriteTest.js:40`). `getProp` 은 없는 키에 **throw** 라 `||` 오른쪽은 도달 불가 — `apsProbe` 는 순서가 반대(`CIN7_API_KEY` 먼저)라 **실행 즉시 죽는다.** Script Properties 에 `CIN7_API_KEY` 는 존재하지 않음(확인 완료).
- **`ccm_runDailySync` 2026-08-10 04:26 실패** — 58.7초 사망(평소 115~168초 · 직전 6일 전부 Completed). 수동 재실행 성공 → 코드/데이터가 아니라 **그 시간대 조건**. 실행 로그 확인 필요.
- **GAS 편집기 드리프트** — `clasp pull` 로 `apsProbe`(InvoiceLineProbe.js 에 추가)·`WmsAdvPoStockProbe.js`(신규)가 로컬·GitHub 에 없던 것이 드러났다(08-07 Advanced 조사 때 편집기 직접 작성 추정). **편집기에서 만들면 pull·커밋까지** — 버스팩터. 참고: Cin7 키 분리(`Asung GAS`)와 키 보유처 전수 목록은 세션 문서 6장(키 로테이션 때 그 목록이 자산이다).
- 🆕 **GAS 폴더 두 개가 같은 scriptId (2026-08-13 관찰 · ⬜ 정리 필요)** — [실측] `~/asung/gas-system-automation` 과 `~/asung/asung-ops/gas/System_Automation` 의 `.clasp.json` scriptId 가 동일(`1K891Nbg…`). 같은 프로젝트의 두 복사본이므로 **어느 쪽에서 `clasp push` 하느냐에 따라 서로를 덮어쓸 수 있다**(위 「GAS 편집기 드리프트」와 같은 계열). 부수 확인: 두 폴더 모두 `functions/v1` grep 0건 — **GAS 는 EF 를 호출하지 않는다**(EF 게이트 확대가 GAS 를 깨지 않음의 확정 근거).

### 그 외 (기존)

- ⚠️ **스크롤 튕김 — ✅ 2026-08-07 판별 진행 + 후보 수정 구현 (배포·검증 대기)**. 2026-08-07 작업자 청취로 **모달 없이, 스크롤 중간에서** 리프레시됨이 확인 — ②(규칙 28 프리즈)가 아니라 ① 계열(리로드)의 지문. 단 세부 원인은 `pageshow` 가 아니라 **탭 폐기/렌더러 OOM 복구로 추정**(둘 다 `persisted=false` 신규 로드 — 규칙 16 항목의 2026-08-07 재검토). **당시 이 항목이 지목한 후보 수정(`?batch=` URL 복원 — localStorage 아님) 그대로 구현됨**(규칙 9) + 이미지 lazy(OOM 원인 후보 완화 — 미검증 가설). 잔여 판정은 검증 대기 항목(배포 며칠 뒤 작업자 재청취).
- **리시빙 PO**: partial 상태 Cin7 draft 누적(현재 최종완료 때 일괄). Apply 자동 실행 전환(매니저 게이트→작업자 완료 시, 신뢰 쌓이면). Advanced Purchase 상세 라인 실측. 라스트빈 movements 백필(선택).
- **유령 bin 정리**: 숫자만/오타 bin 은 Cin7 삭제 후 sync 로 자연 소멸.
- **리시빙 동시 작업 미해결분 — 규칙 27 이 전체 목록** (위 「리시빙 Apply」·「동시 작업 원자화」에 안 담긴 것): **R3 `wms_receipts.cin7_purchase_id` 유니크**(중복 0건 확인, 분할 입고는 새 PO 라 걸어도 안전 — 새 마이그레이션) · ~~R4 Apply 최종 PATCH 에 `applied_at is null`~~(✅ 2026-08-06 in-flight 잠금으로 PO·트랜스퍼 해소 — 규칙 27 R4) · R5 Complete↔Apply 창 · RLS 창고 스코프 · ~~EF 호출자/perms 서버 검증~~(✅ 2026-08-13 `_shared/authgate.ts` — 백로그 「보안」 · 잔여 applied_by `&by=` 서버 유도도 그쪽) · 🆕 **backBtn 빈 receipt 정리**(2026-08-14 방치 4건 후속 — 규칙 24 「receipt 방치」 항목 참조: 나갈 때 "이 세션에서 만든 + 작업 흔적 4가지 전부 0"이면 confirm 후 삭제. receiver 1429행 "무해" 주석 정정 동반 — 그 판단이 목록 점유 부작용을 계산에 안 넣었다).
- **`startWave` 가 wave 행의 `held_by` 를 정리하지 않는다 (규칙 18·23 · 2026-08-07 발견)** — 멤버 task 는 `held_by:null` 로 정리하는데 wave 행 UPDATE 에는 빠져 있다(picker.html `startWave`). "내가 Hold → 남이 claim → 무작업 Back" 뒤 wave 가 pending 인데 held_by=나 로 남아 **"Resume your held" 섹션에 잘못 떠 보이는 표시성 스테일**(실해 없음 — holdCasFailed 의 "내 Hold" 오판 케이스도 그 시점 실상(pending·미배정·라인 보존)과 결과가 같다). 수정은 `startWave` 의 wave UPDATE 에 `held_by:null` 한 필드 — 단 검증된 claim 경로라 별건으로.
- **인덱스 기반 bcMap 잔존**: picker.html·packer.html(규칙 25). 지금은 splice 를 안 해 안전 — 라인 삭제 기능 추가 시 반드시 id 기반으로 먼저 전환.
- ~~**Cin7 병행 케이스 C 자동감지**: 유입 후 Cin7 상태 변경 감지.~~ → ✅ **2026-08-12 해소** (규칙 43 — Updated 트리거 · On Hold 보류 · unexpected 알림). 잔여: needs_review 자동 전환은 범위 밖. ~~voided~~ → ✅ **void 감지는 2026-08-14 해소** — 단 "같은 감지 루프에 분기"가 아니라 **별도 루프**였다(void 는 목록에서 빠져 Updated 트리거가 못 본다 — 실측. 「신규 기능」 void 항목 참조 · 전환은 ⊘ Void 수동).
- **GAS scannable_barcodes 근본수정**: base 라인에 형제변형(-12) 바코드 포함(현재 bcMap 병합 우회).
- 진단 로그(EF SENT) 유지 중 — 안정화 후 제거 가능.
- `wms_drop_locations` 비어있음.
- RLS 세분화(쓰기/해소=매니저만) — auth_all로 충분하나 운영 강화 시.
- is_selling 이상치 청소: CAN94629/-12·RSK53280/-12(변형 No로)·EBI00001~4(Cin7 수정 후 청소쿼리).
- 알림(작업완료 clean/flagged) 미구현. 미사용 SA `wms-edge-bq` 삭제 가능. private repo+$4/mo 고려.
- 스캔 오류음 추가강화(풀스크린 빨강 플래시 등)·팔렛/박스 완료 잠금 — 현장 피드백 대기.

## 개발 워크플로우 노트

- **환경 = WSL2 Ubuntu + bash.** 이전 기록의 PowerShell 예시(`Invoke-RestMethod`, `cd ~\asung-wms`)는 낡았다.
- Edge Function 배포: `cd ~/asung/asung-wms && supabase functions deploy hello` (Docker 불필요, "Docker not running" 경고 무시).
- 함수 호출(bash + 진짜 curl):
  ```bash
  curl -s "https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/hello?commit=1" \
    -H "Authorization: Bearer $ANON" | jq .
  # POST 바디는 파일로 넘기면 이스케이프 사고 없음
  curl -s -X POST ".../functions/v1/receiving" \
    -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
    --data @/tmp/body.json | jq .
  ```
- anon key로 호출(Authorization Bearer). service_role은 Edge Function 내부에서만(자동주입).
- 현재 함수명은 연습 함수 `hello`를 재활용 중(나중에 제대로 된 이름으로 새 함수 분리 가능).
- 집·회사 동등개발: 각 컴퓨터 CLI 설치 + `git clone`. **작업 후 `git push` 습관.** Supabase 클라우드(테이블·데이터·secrets·배포함수)는 어디서든 접근, 로컬 코드만 git 동기화 필요.
- ⚠️ **`core.hooksPath` 는 머신 로컬 설정이다 — 클론한 머신마다 1회 (2026-08-12 집 PC 에서 실감)**: 회사에서 설정해도 집에는 없고, 안 하면 **커밋 훅(check-caps.sh 등)이 아무 경고 없이 통째로 안 돈다.**
  ```bash
  cd ~/asung/asung-wms && git config core.hooksPath scripts/hooks
  bash scripts/test-caps-hook.sh   # 9/9 PASS 확인
  ```
  ⚠️ **레포를 헷갈리지 말 것** — `scripts/hooks` 가 없는 레포(예: GAS)에 걸면 그 레포의 훅이 조용히 전부 꺼진다(2026-08-12 실제 발생, `git config --unset core.hooksPath` 로 되돌림). 확인: `git config core.hooksPath` → `scripts/hooks`. 훅 자체 테스트의 마지막 두 케이스가 중요: 「레포 전체 클린」(기존 27곳에 caps-ok 부착 — 파일을 건드려도 커밋이 안 막힘) · 「사유 없는 caps-ok 거부」(예외 남발 차단). 설치 절차 원문: CLAUDE.md 7절 「hook 설치」.

## 참조 파일

- `references/schema.md` — 14개 테이블(+`wms_waves`) + `wms_staff` 전체 컬럼·enum·인덱스, 복제 2테이블, `wms_health_check()` 함수, RLS
- `references/edge-function.md` — Edge Function 1~3단계 코드 구조, assembleLine 로직, 폴링/dedup/저장
- `references/sync-gas.md` — WmsSync.gs 구조, BQ 소스 쿼리, warehouse/zone 정규화 함수
- `references/frontend.md` — 8화면 구조(manager Split/Group·admin Health/Receiving 탭·picker wave 모드·**receiver 동시 작업 구현 지도**), wms-auth.js 로그인 모듈, RLS, 배포, 영어화·로고, 개발 워크플로우
