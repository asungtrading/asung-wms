# 2026-08-10 세션 기록 — 트랜스퍼 속도 · 병렬화 · 소유권 검증

> 이 문서는 `.claude/skills/asung-wms/SKILL.md` 및 `references/edge-function.md` 에 병합할 원본이다.
> 항목마다 **[실측] / [결정] / [정정] / [미해결]** 등급을 표시한다 — 근거의 출처를 흐리지 않기 위함(규칙 42 계열).

---

## 1. 배포된 것 (2건, 둘 다 `receiving` EF)

### 1-1. 트랜스퍼 그룹 간 페이싱 150ms → 1200ms
- 커밋: `fix(receiving): pace transfer bin-move groups at 1200ms for Cin7 60/60 rate limit`
- 상수 `TRANSFER_GROUP_SLEEP_MS` 신설(기존 매직넘버 3곳 치환: already-at-destination / failedMoves push 뒤 / markExported 뒤)
- ⚠️ **checkpoint repair 안쪽 라인 루프의 `sleep(150)` 은 그대로 둔다** — 중첩 루프라 올리면 라인 7개 그룹이 8.4초를 검증에만 써 실패 예산(6초)이 터진다
- ⚠️ PO 경로 `sleep(400)` 2곳, 조회 `sleep(250)`·페이지네이션 `sleep(300)` 무변
- **효과**: 하드 alert 로 죽던 것이 백오프로 흡수되어 전진. 다만 **속도 개선은 아니었다**(아래 3-1 참조)

### 1-2. 병렬 배치 도입 `TRANSFER_PARALLEL_BATCH = 4`
- 커밋: `feat(receiving): parallel batch (4) for transfer bin moves - 3.9x measured`
- 구조: **파티션 → 미시도 병렬 배치(4) → 실패 이력 순차**
  - `fireGroup(it)` — POST 1건 + 성공 시 즉시 `markExported`. 절대 throw 하지 않음
  - `settleGroup(it, info, prevFails)` — 429 / checkpoint repair / failCounts·failedMoves (종전 catch 본문 이동)
- **지켜야 할 것들**:
  - ⚠️ `Promise.allSettled` — `Promise.all` 금지(한 건의 거부가 나머지 3건 결과를 버린다)
  - ⚠️ 한 배치 안에 **같은 `base_sku` 금지** — 출발지가 같은 착지 재고 한 곳이라 동시에 빼면 `Available quantity … is 0`. 겹치면 다음 배치 선두로 defer(첫 그룹은 항상 들어가므로 무한 루프 없음)
  - ⚠️ `chunkGuard` 는 **배치 단위 · 발사 직전에만** — 배치 중간에 걸리면 반쯤 발사된 배치가 생긴다
  - ⚠️ **실패 이력 그룹(prevFails>0)은 배치에 넣지 않는다** — `APPLY_FAIL_BUDGET_MS` 회계가 그룹 단위이고, 격리 전까지 최대 3개뿐이라 병렬 이득이 없다
  - ⚠️ checkpoint repair(`binOnHand` 되읽기)는 배치 발사가 **전부 끝난 뒤 순차로만** — 배치 안에서 중첩되면 예산이 터진다
  - ⚠️ **`a += await f()` 금지** — await 앞에서 `a` 를 읽으므로 배치 4건이 동시에 돌면 lost update 가 난다. `const n = await f(); a += n;` 형태로. (구현 중 실제로 발견해 수정. `linesMovedNew` 가 실제보다 작게 찍히는 결함이었다.)
- **상수 무변**: `APPLY_MAX_GROUPS(12)` · `APPLY_TIME_BUDGET_MS(20000)` · `APPLY_FAIL_BUDGET_MS(6000)` · `APPLY_QUARANTINE_FAILS(3)` · `APPLY_LOCK_STALE_MS(90000)`
  - ⚠️ **시간 예산 20초는 잠금 만료 90초와 "4.5배" 관계로 묶여 있다.** 한쪽만 올리면 회차가 도는 중에 다른 Apply 가 잠금을 만료 탈취해 **재고가 이중 이동**한다. 20초의 유래 자체는 코드 어디에도 적혀 있지 않다(EF 한도 역산이 아니다) — [미해결]

### 1-3. PO Apply 초과 클램프 (백로그 14번 — 해소)
- 커밋: `feat(receiving): PO Apply 초과 클램프 …`
- 신규 파일 **`po_clamp.ts`**(순수 함수 `applyPoInvoiceClamp`) + **`po_clamp_test.ts`**(9케이스)
  - ⚠️ `index.ts` 가 최상위 `Deno.serve` 라 **테스트가 import 하면 서버가 뜬다** → 순수 함수 분리가 필수였다. 앞으로 계산 로직을 테스트하려면 같은 패턴을 쓸 것
- **동작**: `buddget = SKU 별 expected_base 합` 을 `planLines`(라인 id 순)로 소진 → `move_base` = `min(received, 잔량)`. `qty_units = move / factor` (정수 아니면 **throw** — fail-loud)
- **적용 조건**: `rcpt.expected_source === 'invoice'` 뿐. 구형 `'order'` 는 무클램프
- **`exported_base` 는 자동으로 클램프값이 된다** — `markExported` 가 `move_base` 를 기준으로 배분하기 때문. 트랜스퍼가 이미 검증한 경로
- **discrepancy 무변경** — `recv_over` 는 `lines` 의 received vs expected 에서 독립 산출된다(`move_base` 와 무관)
- **가시성 4겹**: dry-run `1b) CAPPED` 스텝 · plan `capped_to_invoice[]` · `apply_note` 의 `CAPPED to invoice quantity` · admin 모달 ⚠ Capped 블록
- ⚠️ **`budget` 은 `received 0` 라인의 expected 도 포함**한다(전체 인보이스 합). discrepancy 의 `bySku`(rb>0 필터)와 다른 집계다 — 빠뜨리면 **과잉 클램프**가 된다
- ⚠️ **알려진 엣지**: "같은 SKU 의 한 라인은 초과 · 다른 라인은 전혀 안 받음" 이면 `recv_over` 표시량과 클램프 컷 양이 다를 수 있다(클램프가 더 관대 = 안전 방향). 기존 동작이라 손대지 않았다
- 📌 **`admin.html` 도 함께 배포해야 한다**(GitHub Pages `git push`). EF 만 배포하면 `capped_to_invoice` 가 있어도 모달에 안 뜬다

**📌 이미 레포에 반영된 문서** — Claude Code 가 같은 커밋에서 갱신했다. 병합 시 중복하지 말 것:
- `SKILL.md` 규칙 20 ① — **정정 형식**(종전 문장 취소선 + "API 제약이 아니라 **정책으로** 자른다" 명시)
- `references/edge-function.md` `buildApplyPlan` po 절

---

## 2. 검증 완료 — 「검증 대기」에서 내릴 것

| 항목 | 결과 | 근거 |
|---|---|---|
| **트랜스퍼 (a) 케이스 첫 실전 Apply** | ✅ 완주 | TR-03259, 176그룹/321라인, `applied_at` 2026-08-10 09:26:48 토론토, `ALL GROUPS DONE · 319/321 lines`, `checkpoint_repaired` 0회 |
| **소유권 차단 (리로드 복원)** | ✅ 4경로 전부 통과 | 아래 표 |
| **Hold RPC (`wms_hold_pick`) 단일 픽 경로** | ✅ 부분 검증 | Hold → Resume 배지 → 재진입 시 스캔 수량 보존 |
| **Apply in-flight 잠금** | 🟡 부분 검증 | 같은 계정 반복 클릭에서 이중 이동 0회(숫자가 단조 감소만). **다른 계정 동시 클릭은 미검증** |
| **병렬 배치** | ✅ 실전 검증 | TR-03738(5그룹) — 4건 동시 + 1건, `5/5 lines exported` |
| **Simple PO Apply 회귀** (fail-closed 게이트 + 폴백) | ✅ | PO-01121 — `PATH=simple (cin7_type='Simple Purchase')` · `invoice check: AUTHORISED` · 10 bin 그룹 1회차 완주 · `stock received AUTHORISED` |
| **초과 클램프 회귀** | ✅ 자르지 않음 | PO-01121 — 61라인 전부 `received == expected` 인 receipt 로 `61/61 lines exported`, `CAPPED` 문구 없음. **`buildApplyPlan` PO 분기를 통째로 바꿨는데 한 줄도 틀어지지 않았다** |
| **인보이스 기준 기대치** | ✅ 8회 | `expected_source='invoice'` receipt 8건 중 7건이 이미 Apply 성공(2026-08-10 실측) + PO-01121 로 8건 |

⬜ **초과 클램프의 "자르는 동작" 자체는 실전 미검증** — `expected_source='invoice'` 인 미적용 receipt 가 PO-01121 하나뿐이었고 61라인 전부 일치였다. **로컬 스위트 9케이스가 유일한 사전 검증 근거.** 다음 초과 리시빙이 첫 실전 → dry-run 에서 `1b) CAPPED` 스텝과 `capped_to_invoice[]` 를 반드시 확인할 것

### 소유권 차단 4경로 [실측]
| 경로 | 결과 |
|---|---|
| B 계정이 A 의 `?batch=` URL 로 진입 | **차단** + 목록으로 이탈 + toast `That batch is now assigned to Caleb Chang — re-scan the pick list to take it over` |
| **F5 (신규 로드)** | 재진입 + 수량 보존 ← **이 기능을 만든 목적 그 자체** |
| 뒤로가기 → 앞으로 (`pageshow`) | 재진입 |
| Hold → Resume | 재진입 + 수량 보존 |

- 배포 가드("계정 2개 테스트 통과 전 push 금지")를 앞질러 프로덕션에 나가 있던 유일한 항목이 이걸로 정상화됐다
- ⬜ **이미지 lazy 의 "리로드 빈도 감소"는 코드로 증명 불가** — 며칠 뒤 작업자에게 "스크롤 중 리프레시가 아직 있는지" 직접 물어야 판정된다

---

## 3. 실측 데이터 — 새로 확정된 사실

### 3-1. ⚠️⚠️ 트랜스퍼 Apply 의 진짜 병목은 한도가 아니라 **Cin7 POST 지연**이다
- **[실측] POST 1건 = 6~9초** (평균 7.9초, 표본 5). Cin7 API Log 의 요청 시각과 응답 `LastModifiedOn` 차이로 교차 확인(요청 09:24:47 → `LastModifiedOn` 09:24:53)
- 그래서 순차 실행이면 **176그룹 = 21분**. 한도가 무한이어도 이 시간이 나온다
- 우리가 쓰던 콜은 **분당 9콜** — 한도 60의 **15%**
- 📌 **교훈: "한도 60/60" 을 보고 "이론상 4분" 이라 계산한 것은 콜당 지연을 0 으로 놓은 것이었다.** 처리량 산정에 지연을 빼면 안 된다

### 3-2. [실측] Cin7 은 동시 쓰기를 병렬 처리한다 — 3.9배
GAS 프로브 `Cin7ParallelProbe`(측정 후 삭제)로 에드먼튼 실재고 4 SKU × 1개를 임시 bin 왕복:
- **순차 4건 = 31.5초** (건별 9212 / 6138 / 8604 / 6993 ms)
- **동시 4건(`UrlFetchApp.fetchAll`) = 8.1초** — 단건 소요와 사실상 동일
- **교차 증거**: TR 번호가 요청 순서와 어긋나게 배정(요청 PAL→SSU→TWA→TDX, 번호 03735·03734·03736·**03733**) = 큐잉 없음
- ⚠️ **N=6, N=8 은 측정하지 않았다.** 4 가 유일하게 측정된 안전점이다
- ⚠️ **측정 설계 주의**: "출발지 4 → 목적지 1" 로 재면 목적지 bin 잠금 때문에 직렬로 보일 수 있다. 실제 Apply 와 같은 **"출발지 1 → 목적지 4, SKU 전부 다름"** 으로 재야 한다

### 3-3. [실측] Cin7 한도는 **Application 키 단위**로 적용된다
- Cin7 공식 KB 확인. 계정당 API Application 을 여러 개 만들 수 있고 개수 상한은 문서에 없다
- 화면에 `make.com`(Disabled·0콜) · `Easy Insight` · `Data Management` 가 이미 등록돼 있었다
- ⬜ **과금 미확정** — KB 는 "Cin7 Core API 는 integration 애드온을 요구한다"까지만 말하고 "키마다 별도 과금"인지는 명시하지 않는다. 구독에는 `1 x Integration` 인데 앱은 3개였다. **확정 증거는 `inventory.dearsystems.com/MySubscription` 의 `Integration` 수량이 1인지 2인지**

### 3-4. ⚠️⚠️ [실측] `hello` 폴링 1회 = Cin7 **52콜**, 5분마다 → 하루 약 15,000콜
dry-run 실측(2026-08-10):
```
pages_scanned 2 · list_total 147 · after_skip_picked 110
already_exists 59 · fresh_candidates 51 · detail_fetched 50 · detail_capped false
```
- **구조적 낭비**: 비대상(`2.Release to WMS` 아님) 오더는 **저장되지 않아 매 회차 fresh 에 잔류** → 5분마다 같은 51건의 상세를 다시 읽는다
- 상세 50건 × 250ms ≈ **25초 동안 60/60 창을 통째로 소진**하는 버스트
- Cin7 API Log 에서 `/v2/sale?ID=` GET 이 **초당 2건** 페이스로 나가는 것이 육안 확인됨
- Cin7 전체 하루 호출은 **26,251콜** — 폴링이 절반 이상으로 추정
- **이것이 429 의 진짜 원인이다.** 평균은 여유로운데 순간이 겹친다

### 3-5. [실측] 회차 경계에 **45초 공백**이 있다 — EF 밖이다
TR-03738 타임라인(Cin7 Log + Supabase EF Log 대조):
```
15:05:18  EF booted (19ms) · 같은 초에 첫 Cin7 GET
15:05:24  PUT (트랜스퍼 완료)
15:05:28~29  POST × 4  ← 배치 1, 1초 안에 (병렬 확인)
   ↓ 약 45초 공백 (Cin7 콜 없음)
15:06:14  EF booted (19ms) · 같은 초에 첫 Cin7 GET
15:06:20  POST × 1  ← 배치 2
```
- **`booted` 시각과 첫 Cin7 콜 시각이 같다** → EF 준비 시간은 사실상 0. 콜드스타트도 아니다(19~20ms)
- `admin.html` 에 45초짜리 지연 없음(회차 사이 유일한 의도적 대기는 900ms) — [실측] grep 확인
- 남은 후보: ① 1회차 응답 반환 후 EF 종료 지연(`shutdown` 로그가 15:08:36~38 로 한참 뒤) ② admin 의 900ms 뒤 `loadReceiving()` 목록 재조회가 무거움(**가장 유력**) ③ 브라우저·네트워크
- **176그룹이면 회차 22번 × 45초 = 16분** — 병렬화 이득을 그대로 먹는다. **다음 타깃**
- ⚠️ 표본이 회차 경계 1개뿐이다. 아침 TR-03259 에서 관측한 100초와 자릿수는 비슷하다

### 3-6. Cin7 API Log 라는 진단 도구가 있다
`Integration → API → (앱) → Log`. **보관 5일.** 요청·응답 본문까지 열람 가능
- ⚠️ **429 로 거부된 요청은 이 로그에 남지 않는 것으로 보인다** — 콜이 하나도 없는 공백 구간이 있는데 표시는 전부 `Success` 였다. **"Success 만 있다"를 "429 가 없었다"의 근거로 쓰면 안 된다**
- 📌 오늘 오전에는 이 도구를 모른 채 스크린샷 시각과 EF 응답으로 추정했다. 처음부터 여기 다 있었다

---

## 4. [정정] 이 세션에서 틀렸던 판단들

> 규칙 42(근거의 출처 표시) 계열. 같은 실수를 반복하지 않기 위해 남긴다.

| 주장 | 실제 | 원인 |
|---|---|---|
| "한도 60이면 이론상 4분" | 21분 | **콜당 지연을 0 으로 놓은 계산** |
| "N=12 로 뛰었다, 4배 개선" | 그 2분간 6회차가 돌았다. 회차당 그룹 수는 사실상 그대로 | 스크린샷 2장 사이를 1회차로 단정 |
| "admin 무한루프 가드가 멈춘 것" | alert 에 `round limit (30) reached` 라고 적혀 있었다 | **화면에 이유가 있는데 추정을 앞세움** |
| "EF 진입→첫 콜까지 7.5초" | 0초(`booted` 로그로 반증) | t0 역산이 다른 가정 위에 있었음 |
| "폴링 먼저 안 고치면 429 가 더 난다" | 병렬화는 총 소요를 줄여 **겹칠 횟수도 줄인다**. 순서를 강제할 근거 약함 | 한쪽(순간 사용량)만 봄 |
| "회차당 8그룹, 1회차 완주" | 1회차는 배치 1개(4그룹)에서 시간 가드 | 완료 PUT(6~9초)이 예산을 먹는 것을 누락 |

⬜ **[미해결] 1회차가 왜 배치 1개로 끝났는지는 아직 설명되지 않았다** — t0 역산이 `booted` 로그와 모순된다

---

## 5. [결정]

> ⚠️ **백로그 14번은 이 세션에서 구현·배포·회귀 검증까지 완료됐다.** 아래는 그 과정에서 확정된 판단들 — 백로그 14번 항목 자체는 **완료로 처리**하고, 판단 내용은 규칙 20 개정문(이미 레포 반영)과 이 절을 근거로 남긴다.

### 5-1. 선행조건 ④ 확정 — expected 0 라인
**expected 0 라인은 클램프 예외 — 받은 만큼 그대로 반영한다.**
- 근거: 인보이스에 없는 오더 라인 = **공장 백오더**. "잘못 온 것"이 아니라 **정상적으로 늦게 온 것**이라 초과와 성격이 다르다. 클램프는 "인보이스보다 많이 왔다"를 다루는 장치이고 expected 0 은 그 대상이 아니다. 규칙 20 의 `rb≤0` 만 건너뛰는 현행 동작과도 충돌하지 않는다

### 5-2. 선행조건 ② 닫힘 — 중복이 아니라 별개다
- [실측] `Math.min` 은 파일에 **817줄 한 곳뿐**이고, 그 캡의 예산(`left`)은 **`expected_base` 합계**(807줄)에서 온다
- PO 경로(654줄)는 캡이 아예 없다: `pending_base = exported_already >= qty_base ? 0 : qty_base`
- 즉 **수식은 같지만 성격이 다르다**:
  - **트랜스퍼 캡 = 물리적 강제** — 초과분은 Cin7 에 존재하지 않아 쏘면 400
  - **PO 클램프 = 정책 선택** — Cin7 PO stock received 는 초과를 허용하는 게 실측 사실(규칙 20 ①)
- ⚠️ **그대로 복사하면 안 된다**: 트랜스퍼는 `expected 0 → 전량 제외`(맞다, Cin7 이 안 갖고 있으니), PO 는 **5-1 결정에 따라 통과**. **정반대 동작**
- 💡 권고(구현 시 확정): 공용 헬퍼로 뽑되 **`expected 0` 처리를 인자로 가른다** — 차이가 코드에 명시적으로 드러난다. 별개 구현으로 두면 한쪽만 고쳐지는 결함 위험
- 💡 [실측] **"bin 감산은 마지막 bin 부터"는 이미 구현돼 있다** — SKU 단위 `budget` 을 `planLines` 순서대로 소진(818줄). ⬜ 단 `planLines` 정렬이 실제 bin 배치 순서인지는 미확인

### 5-3. ⚠️ "마지막 bin 부터"는 구현 불가능했다 → **"마지막 PO 라인부터"**
- [실측] **작업자가 bin 을 채운 시각은 어느 컬럼에도 기록되지 않는다.** `updated_at` 은 bin 변경·승인에도 갱신되는 최종 수정 시각이라 부적격
- `planLines` 순서 = `wms_receipt_lines` id 순 = `startPo` 가 PO 라인 배열을 일괄 insert 한 순서 = PO/인보이스 라인 순서
- 그래서 **id 역순으로 잘린다**(= 마지막 PO 라인부터). 결정론적이고 트랜스퍼 캡과 일관된다
- ⚠️ 정책 문구를 그대로 두면 나중에 **"시간 순서대로 잘린다"고 오해**한다 → 코드 주석·SKILL.md·edge-function.md 4곳에 정정 반영 완료
- 진짜 시간 순서가 필요하면 `first_received_at` 컬럼 신설이 선행(범위 증가 — 지금은 안 만든다)
- 📌 **교훈: 정책을 정할 때 "그 순서를 실제로 알 수 있는가"를 먼저 확인한다.** 2026-08-05 에 "마지막 bin 부터"로 확정했지만 그 정보가 시스템에 없었다

### 5-4. 헬퍼 추출 보류 — 내 권고를 뒤집은 판단
- 제안했던 "공용 헬퍼 + expected 0 처리를 인자로 가르기"는 **트랜스퍼 캡 루프를 고쳐야** 하는데, 그건 같은 날 배포·검증을 막 끝낸 병렬 배치와 인접 코드다
- **검증 직후의 코드를 리팩터링으로 다시 흔들지 않는다** → 별개 블록 + **양쪽에 상호 참조 주석**("수식 쌍둥이 — 한쪽 수정 시 반대쪽 확인, expected 0 처리는 의도된 정반대")
- 헬퍼 추출은 트랜스퍼 경로가 다음에 열릴 때 별건으로

### 5-5. 규칙 39 재확인 — 대형 TR 분할은 답이 아니다
호출 수 = **bin 그룹 수**이지 라인 수가 아니다. 나누면 같은 bin 이 여러 트랜스퍼에 걸쳐 그룹이 오히려 는다(TR-02935 실측: 무분할 144 → 무작위 3분할 217).

---

## 6. 설정 변경 — Cin7 API 키 분리

- 새 Application **`Asung GAS`** 발급 → `System_Automation` Script Properties 의 `CIN7_APPLICATION_KEY` 교체
- **검증**: `ccm_runDailySync` 수동 실행 성공(200 이 아니라 잡 완주가 근거 — 규칙 29)
- [실측] **`CIN7_APPLICATION_KEY` 를 보유한 곳은 `System_Automation` 이 유일**하다 — Apps Script 전 프로젝트(Asung_AgentReports · Customer Purchase Data · Shopify Customer Login Tracker · Tradeshow · Warehousemapsync · PenguJ8 · Shopify(AS) Reorder Proxy · BarcodeLogger) Script Properties 확인 + 각 프로젝트 `api-auth` grep 확인. **하드코딩 키 없음** — 전부 `getProp()` 경유
- 📌 이 목록 자체가 자산이다. 키 로테이션 때 같은 목록이 필요하다
- **현재 예산 배분**: 새 키 = GAS / 기존 키 = Supabase EF(`hello` 폴링 + `receiving` Apply)
- ⚠️ **폴링과 Apply 는 여전히 같은 키를 나눠 쓴다.** Supabase secrets 는 프로젝트 전체 공유라 `CIN7_APPLICATION_KEY` 를 바꾸면 두 함수가 같이 옮겨간다. 진짜 분리는 `_shared/cin7.ts` 수정이 필요(별건)
- ⬜ **BigQuery 는 Cin7 키를 갖지 않는다** — 쿼리 엔진이라 외부 REST 호출 경로가 없다. 흐름은 항상 `Cin7 → GAS → BQ`
- 💡 **존재 증명으로 확인하는 법**: 모든 콜은 Cin7 Application 목록 중 하나에 잡힌다. 앱별 `LAST DAY` 합이 전체 총합과 맞으면 숨은 소비자가 없다는 뜻

---

## 7. 새 백로그 항목

### 최우선
1. ⚠️⚠️ **`hello` 폴링 비대상 기억 테이블** — 5분 52콜 → 평시 3~5콜. 예: `wms_polled_sales(cin7_sale_id, last_status, checked_at)` 를 dedup 에 추가(`already_exists` 와 같은 패턴)
   - **설계 판단 1개**: 비대상이던 오더가 나중에 `2.Release to WMS` 로 바뀌면 어떻게 다시 잡나 — (가) TTL 재확인(단순, 콜 조금 남음) (나) saleList 갱신 신호로 무효화(콜 최소, 신호 실재 여부 실측 필요). **매니저가 authorize→릴리즈로 바꾸는 실제 리듬**에 달렸다
   - ⚠️ 폴링은 오더 유입의 생명선이다. 잘못 고치면 오더가 **조용히** 안 들어온다 → dry-run 진단 필드로 전후 비교 필수
2. **회차 경계 45초** — 3-5 참조. 다음 리시빙 때 **F12 Network 탭**을 켜두고 Apply. 판정: `receiving` 요청 자체가 45초면 EF/네트워크 · 요청은 짧은데 다음 요청까지 비면 admin · 그 사이를 Supabase 조회가 채우면 `loadReceiving()`

### 그 외
3. **중복 GET** — 회차마다 동일한 `?TaskID=` GET 이 2번, 같은 초에 나간다. 30회차면 30콜 낭비. 오늘 하드 alert 를 낸 것도 이 GET
4. **`_shared/cin7.ts` 429 백오프가 60초 창에 구조적으로 부족** — `1500 * (attempt+1)`, `attempt < 2` = **총 4.5초**. 60콜을 10~20초에 소진하면 남은 40초는 전부 429인데 4.5초 기다리고 throw 한다. ⚠️ 공용 파일이라 `hello`·`receiving` 둘 다 재배포 필요
5. **회차 throw 시 `apply_note` 미갱신** — 종료부가 실행되지 않아 진행분이 **화면에서 되돌아가 보인다**(오늘 171→164→171 로 실제 발생). 체크포인트는 멀쩡한데 매니저는 "날아갔다"고 오해한다
6. **`RETRY of a partial apply from ?`** — 타임스탬프가 `?` 로 찍히는 표시 결함
7. **죽은 폴백 제거** — `|| getProp('CIN7_API_KEY')` 3곳(`InvoiceLineProbe.js` 의 `apsProbe`, `Wmstrasferwritetest.js:43`, `WmsPoStockWriteTest.js:40`). `getProp` 은 값이 없으면 **throw** 하므로 `||` 오른쪽은 도달 불가능하다. `apsProbe` 는 순서가 반대(`CIN7_API_KEY` 가 먼저)라 **실행 즉시 죽는다**. Script Properties 에 `CIN7_API_KEY` 는 존재하지 않음(확인 완료)
8. **`ccm_runDailySync` 2026-08-10 04:26 AM 실패** — 58.7초에서 죽음(평소 115~168초, 직전 6일 전부 Completed). 수동 재실행은 성공 → 코드/데이터가 아니라 **그 시간대 조건**. 실행 로그 확인 필요
9. **GAS 편집기 드리프트** — `clasp pull` 로 `apsProbe`(InvoiceLineProbe.js 에 추가됨) + `WmsAdvPoStockProbe.js`(신규)가 로컬·GitHub 에 없던 것이 드러났다. 08-07 Advanced PO 조사 때 편집기에서 직접 만든 것으로 보인다. **편집기에서 만들면 pull·커밋까지 해야 한다** — 버스팩터 문제
10. **병렬화 실전 관찰** — 176그룹급에서 `CHUNK - N group(s) moved` 가 8 근처면 설계대로. **4 이하면** 파티션이 매 회차 전체 그룹을 도는 오버헤드를 의심할 것(종전엔 가드에 걸리면 거기서 빠져나갔다)
11. **초과 클램프 첫 실전** — 다음 초과 리시빙에서 dry-run `1b) CAPPED` · `capped_to_invoice[]` · Cin7 stock received 수량 = 인보이스 수량 · `exported_base` = 클램프값 확인. ⚠️ **매니저가 Cin7 수동 조정을 하지 않으면 창고 실물과 Cin7 이 계속 어긋난다 — 이 정책의 유일한 실패 지점이다.** discrepancy 큐 에이징 알림(백로그 10번)의 우선순위가 이 배포로 올라갔다
12. **인보이스 폴백 공백** — 인보이스가 실재하는데 폴백으로 빠진 receipt 는 `expected_source='order'` 로 기록되어(receiver.html:655) 클램프를 받지 않는다. 안전한 방향이지만 **그 상황의 빈도는 확인된 바 없다**

---

## 8. 사람이 해야 할 미정리 데이터

| 대상 | 내용 |
|---|---|
| `ANN04401` | 에드먼튼 **−1** 감산. Cin7 에 bin 없는 재고 1(= 부족분), 실물은 EF010102 에 34 |
| `ASSH40608` | 에드먼튼 **−2** 감산(같은 구조로 추정 — 화면 확인 필요) |
| `ASSH40615` | ⚠️ **EU070101 실물 카운트가 먼저.** 4개면 토론토 C040504 → 에드먼튼 EU070101 트랜스퍼 2(조정보다 트랜스퍼 — 원가 계층 보존). 2개면 작업자 오카운트이므로 **조정 없이 discrepancy 무효 처리** |
| discrepancy 큐 | TR-03259 기록은 2건. `recv_off_po`(ASSH40615)가 들어 있는지 확인 — 큐가 유일한 보정 지시서다 |
| 유령 discrepancy | id 281·282 정리 |
| PO-01094 | 잘못된 I&R 그룹 잔재(32줄 + 빈 DRAFT 인보이스) Cin7 정리 여부 확인 |
| 테스트 계정 | 소유권 테스트용 계정 비활성화 |
| 프로브 잔재 | `PARALLEL PROBE` reference 로 TR 8건(03729~03736). 재고는 상쇄돼 영향 없음 |
| 검증 트랜스퍼 | TR-03738 재고는 역방향 트랜스퍼로 원상복구 완료 |
| PO-01121 | ✅ Apply 완료(Simple, 61/61) — 조치 불필요. 기록용 |
| PO-01082 | Imperial Dax — Apply 대기 중 |
| git | `gas-system-automation` push 필요 (`asung-wms` 는 클램프 커밋 시 push 완료) |
| Cin7 구독 | `MySubscription` 의 `Integration` 수량 확인(1 인지 2 인지 = 과금 확정) |

---

## 9. 이 세션의 작업 방식에서 배운 것

- 📌 **화면에 답이 적혀 있으면 그것을 먼저 읽는다.** `round limit (30) reached` 를 두고 "무한루프 가드"라고 추정했다
- 📌 **처리량 계산에 지연(latency)을 빼면 안 된다.** "한도 60/60 → 이론상 4분" 이 세 번의 잘못된 예측을 낳았다
- 📌 **진단 도구를 먼저 찾는다.** Cin7 API Log 가 있는 줄 모르고 오전 내내 스크린샷 시각으로 추정했다
- 📌 **측정 설계가 결론을 바꾼다.** 병렬성 프로브를 "목적지 1개로 모으기"로 짰으면 목적지 잠금 때문에 "직렬"이라는 반대 결론이 나올 수 있었다
- 📌 **순차→병렬 전환 시 `a += await f()` 를 전수 점검한다.** 순차일 땐 없던 lost update 가 생긴다
- 📌 **정책을 확정할 때 "그 정보가 시스템에 있는가"를 먼저 확인한다.** "마지막 bin 부터"는 채움 시각이 없어 구현 불가능했다(5-3)
- 📌 **커밋 메시지 관례를 확인할 때 `git log --oneline` 은 무용하다** — 트레일러·본문이 안 보인다. `git log --format='%s%n%b'` 를 써야 한다. (오늘 `--oneline` 을 제시했고 확인이 안 됐다)
- 📌 **되돌릴 수 없는 쓰기를 바꾸는 변경은 "자르는 기준이 맞다"가 먼저다.** 클램프는 기준(expected)이 인보이스임을 확인한 뒤에만 안전하다 — 기준이 틀리면 정상 수량이 잘리고 되돌릴 수 없다
