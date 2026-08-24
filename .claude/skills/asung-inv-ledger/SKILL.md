---
name: asung-inv-ledger
description: >
  Asung Trading 재고 원장(IMS 두 번째 모듈)을 다룰 때 먼저 읽으세요.
  Cin7 재고를 대체할 자체 장부 — 사건을 쌓아 잔고를 계산합니다.
  "원장", "inv_ledger", "재고 원장", "shadow", "shadow 모드", "기초 스냅샷",
  "inv_snapshot", "inv_compare", "inv_sync_state", "대조", "Movements",
  "ProductAvailability", "StockOnHand", "차감 시점", "Ship 차감", "Allocated",
  "IN_TRANSIT", "운송 중", "조립", "FinishedGoods", "번들", "AutoAssembly",
  "Adjustment", "ExistingStockLines", "NewStockLines", "CreditNotes Restock",
  "StockReceived Lines Date", "DepartureDate", "CompletionDate", "seq_hint",
  "line_ref", "FIFO", "원가 레이어" 등이 나오면 추측하지 말고
  이 스킬의 확정 사실·이벤트 규칙·함정을 확인하세요.
  ⚠️Adjustment는 증감분이 아니라 조정 후 수량, ⚠️NewStockLines는 규칙이 다름,
  ⚠️재고는 Ship에 빠짐(픽·팩은 Allocated), ⚠️StockOnHand는 수량이 아니라 평가액,
  ⚠️같은 날은 유입 먼저 — 어기면 원장 전체가 반대로 쌓이거나 잔고가 음수가 됩니다.
---

# Asung Trading 재고 원장 스킬

WMS 다음 모듈. **설계 정본은 레포의 `docs/design/ledger-design.md`** — 이 스킬은 그 요약과
실측 근거, 그리고 반복해서 틀렸던 지점들이다.

관련 스킬: `asung-wms`(같은 레포·DB), `cin7-api`(엔드포인트·파라미터)

---

## 1. 무엇을 만드는가

"지금 몇 개"를 저장하지 않고 **"무슨 일이 있었다"만 쌓는다.** 잔고는 더해서 구한다.

- **1단계 범위**: 수량만 · 창고 단위 · shadow(어디에도 안 씀)
- **기준은 Cin7 문서.** WMS 는 보조 — WMS 미경유 사건이 월 수백 건이라 WMS 기준은 처음부터 구멍
- 원가(amount)·자리(bin)는 **값만 저장하고 계산엔 안 씀** — 나중에 소급 불가라 지금부터 담는다

**진행 상태 (2026-08-20 — ⑤ 가동)**: 테이블 **5개**(`inv_conflicts` 포함) + 스냅샷 EF
(`inv-snapshot`) + 수집 EF(`inv-collect` — ②-a 전량 축 3종·②-b 증분 축 3종) 배포 · 현재
**`@2026-08-19.1`**(페이싱 1200ms·`Retry-After` 백오프 + `inv_conflicts` 변경 감지).
⚠️⚠️ **쓰기가 켜졌다 — `commit=1` 금지는 해제됐다.** ③ 검증에서 ⑤ 가동까지 2026-08-20 저녁~밤에
한 번에 넘어갔다(경위 정본: `docs/sessions/2026-08-20-ledger-go-live.md` · 설계 정본: 4부
「⑤ 쓰기 가동」).

- ✅ **④ 기초 스냅샷 완료** — `snapshot_key 2026-08-20-initial` ·
  `taken_at 2026-08-20T23:42:47.855Z` · **13,844행**(토론토 7,523 / 에드먼튼 6,321) · 44초 ·
  `truncated`·`rate_limited` false · `unexpected_warehouses []`. **8/22 예정을 8/20 로 앞당겼다**
  (창고가 멈춘 시각이면 조건이 같다).
- ✅ **커서 seed 완료** — `transfer=TR-01327` · `adjustment=ST-00646` · `assembly=FG-00128` /
  증분 축 3종(`sale`·`purchase`·`creditnote`)은 스냅샷 `taken_at`.
- ✅ **가동 첫날 정상 (2026-08-21 — 설계 4부 「가동 첫날 검증」이 정본)**: 6잡 전부 `last_run_at`
  갱신 · 커서 전진(`transfer` `TR-01327`→`TR-03974`, 밤사이 2,647건 소화) ·
  ⭐ **첫 실물 대조 통과**(`ST-01233` 파손 조정 3 SKU — Cin7 Variance 와 `qty_delta` 정확 일치,
  bin 까지. **Cin7 은 절대값·원장은 증감분 — 변환이 옳다**) ·
  `since` 실동작(`TR-03539` — 오늘 적용됐지만 사건 날짜 8/4 라 정확히 제외: 갱신 축과 사건 날짜의
  독립이 실물로) · 트랜스퍼 4행 구조 실동작(TR-04166~70 각 4행·합계 0) ·
  📌 `TR-01327` seed 판단 적중(`TR-03539` 는 버려진 게 아니라 실제 적용 대상이었다 —
  「되돌릴 수 있는 쪽을 고른다」의 값어치).
  ⚠️ **대기 중**: `TR-03975`·`03976`(IN TRANSIT · `hold_intransit_before_since`) — **도착하면
  「since 경계 아티팩트」 첫 실물**(1·2행이 걸러져 IN_TRANSIT 음수) — 그때 원장 확인.
  ⚠️ **검증 범위 정직하게**: 대조는 조정 1건뿐 — 판매 45·발주 2건 미대조 · `inv_conflicts` 아직 빈 상태.
  **전량 대조는 ⑥의 일이다.**
- ✅ **pg_cron 6잡 등록**(jobid 6~11 · 소스별 분리 · `hello` 와 분을 어긋나게) —
  기록은 `supabase/ops/cron.sql`.
  ⚠️ **[2026-08-21 정정] purchase 는 `7-52/15` → `8-53/15`** — 최초 등록값 7·22·37·52 가
  `transfer`(`2-57/5` = 2·7·12·…·57)의 **부분집합**이라 4회 실행이 전부 동시였다(둘 다
  `inv-collect`·같은 WMS 키 → 합산 분당 ~100콜 = 한도 60의 1.7배). `alter_job` 으로 변경 완료 ·
  **현재 겹침 0**. `hello` 와는 처음부터 6잡 전부 안 겹쳤다.
  📌 **분 어긋내기는 「폴링과」가 아니라 「서로」까지 봐야 한다** — 잡이 늘면 쌍은 제곱으로 늘고,
  눈으로는 못 센다. **분 집합을 전수 계산할 것.**

**⑤ 진입 게이트 — 6개 전부 통과** (**정본은 설계 4부** 「commit=1 을 켜기 전에 닫아야 하는 것」):
```
☑1 CardID · 👁2 adv_no_putaway(관찰) · ☑3 재등장 전제 ·
🟡4 ON CONFLICT(코드 완료 — ⚠️ 실동작 미검증, 원장이 비어 있어 첫 회차 insert_skipped=0) ·
☑5 캡·페이싱 · ☑6 커서 seed
```
⇒ **단계는 ⑥ shadow 대조로 넘어간다.**
- ✅ **⑥ shadow 대조 가동 (2026-08-24 · 마이그레이션 `20260824130759` · cron 잡 12·13 등록 ·
  정본은 설계 4부 「⑥ shadow 대조 가동」)**: Cin7 현재고 = `inv-snapshot ?key=auto-compare` 재사용
  (리터럴일 때만 `YYYY-MM-DD-compare` 자동 생성 — `-initial` 은 여전히 수동만) · 대조 =
  RPC `inv_compare_run(p_key)`(DB 전용 — 기준선+사건 합 FULL JOIN compare 스냅샷, SKU×창고) ·
  verdict 최소 규칙(match 카운트만/IN_TRANSIT explained/나머지 unknown — **missing_event·
  calc_error 는 자동 판정 금지, 사람이 unknown 닫으며 기록**) · `inv_compare` 는 **diff≠0 만** ·
  `inv_compare_runs` 에 카운트+샘플+**cursors**(타이밍 차이 재확인 근거) · 보존 = compare 14일
  (**`-initial` 불가침 코드 강제**)·runs 90일. [로컬 검증] 테스트 6케이스 + 회귀(팩9·픽12) 통과.
  ⭐ [실측 2026-08-24 BMA15710] **Cin7 도 운송 중을 ON HAND 에서 빼고 별도 컬럼으로 관리** —
  IN_TRANSIT 합성 창고와 같은 모델. 원장 대조 토론토 910·에드먼튼 16·IN_TRANSIT 204 완전 일치
  = 스냅샷+사건 누적의 첫 증명. `inv-snapshot` 은 OnHand 만 읽으므로 **IN_TRANSIT 짝 없음이 정상**.
  ✅ **첫 회차 실측**: `compared_pairs 13,836 · match 13,835 · explained 316 · unknown 1`.
  ⚠️ **카운트 관계 — 셋을 더하지 말 것**: `compared_pairs = match + unknown` 이고
  **explained(IN_TRANSIT)는 pairs 밖의 별도 집계**다(RPC 의 `filter (warehouse <> 'IN_TRANSIT')`).
  첫 회차에서 13,835+316+1=14,152 로 배타 합산해 "정합이 안 맞는다"고 오독했다.
  ⚠️ 15분 간격(스냅샷 21분 → 대조 36분)은 **설계의 핵심**이다 — 아래 오탐 (b).

- ⚠️⚠️ **⑥의 첫 수확 = 비재고 SKU 가 재고로 쌓이던 결함 (`FINAL-SALE` · 2026-08-24)**:
  unknown 1건 = `FINAL-SALE`(원장 −34 · Cin7 0 · `SO-15097`). Cin7 `Type=Non-inventory`
  (파손품을 adjustment 로 뺀 뒤 판매하는 껍데기 SKU — Cin7 은 재고를 안 움직인다)인데
  판매 수집이 재고 사건으로 쌓았다. ⚠️ **`IsService` 와 `Type=Non-inventory` 는 다른 축**이라
  (cin7-api 스킬 15번) `IsService=false` 인 이 SKU 가 기존 필터의 **틈에 빠졌다**.
  ✅ **처방**: `inv_sku_types` 캐시(EF `inv-sku-types` · cron 일 1회 — ⚠️ **cron 은 아직 미등록**,
  아래 「검증 대기」 항목) + 수집 게이트.
  · 게이트는 **`makeSink` push 진입부 한 곳**(since 필터 앞) — 6소스가 전부 그 지점을 지난다
    (배출구 = 공유 루프 2곳뿐) ⇒ **새 소스도 자동 적용**
  · 판정은 **「테이블에 있으면 차단」** — `product_type`·`is_service` **값을 보지 않는다**
    (로드가 `select=sku,refreshed_at`. 비-Stock 만 저장하는 것이 계약이므로 행의 존재가 곧 판정)
  · ⚠️ **캐시 미스는 fail-open(통과 + 경고)** — 원장은 shadow, **대조가 안전망**이다.
    차단은 정상 재고 수집까지 멈춘다. 경고 3분기(EMPTY·STALE·UNREADABLE) → `non_stock_gate`
  · ⚠️ **저장 범위 계약: Stock 은 넣지 않는다** — 넣으면 1,000행 캡에서 조용히 잘리고
    **잘린 비재고 SKU 가 게이트를 통과**한다. 마이그레이션 주석 + **800행 근접 경보** + `caps-ok`
  · **테스트 8케이스** `scripts/test-invcollect-gate.mjs` — 원본에서 `makeSink` 를 **실행 시마다
    원문 추출**해 검증(구현이 바뀌면 테스트가 따라온다). 정적 검사가 **세 번째 배출구를 잡는다**
  · 정정은 **상쇄 행**(`source='manual'`·`event_type='manual_reversal'`) — ⚠️ **물리 삭제 금지.
    append-only 의 첫 위반이 「사소한 1건」인 것이 가장 위험**하다
  📌 [실측] 비-Stock 45건(`Non Inventory` 2 + `Service` 43). `is_service` 는 **전 행 false** —
  `productList` 응답에 그 필드가 없어 기본값일 뿐 판정에 안 쓰인다(**정리 후보**).

- ⚠️⚠️ **대조를 잘못 돌리면 오탐이 난다 — 같은 날 3회차 실측(unknown 1 → 134 → 165, 진짜는 1건)**:
  **(a)** 같은 키로 재촬영하면 `ignore-duplicates` 라 **첫 값이 남는다**(`wrote: 5` 로 끝나고
  13,800행은 아침 값). 재촬영은 **다른 키**로.
  **(b)** 낡은 스냅샷에 최신 원장을 맞추면 그사이 판매가 원장에만 반영돼 **134건이 어긋난 것처럼**
  보인다([실측] 차이가 당일 판매 사건과 정확히 일치 — 원장은 맞고 기준이 낡았다).
  ⇒ **자동화가 준비된 것을 수동으로 급히 돌리지 말 것.** cron 15분 간격이 이걸 구조적으로 막는다.
  **(c)** ⚠️ **스냅샷이 조용히 불완전할 수 있다 — 최우선 미해결.** [실측] 밤 회차가 목록 21,877
  (아침 22,079) · 22페이지(23) · 13,787행 — `truncated:false`·`rate_limited:false` 인데
  **Cin7 이 애초에 적게 줬다**. `list_total == received_rows` 라 **all-or-nothing 가드가 구조적으로
  못 잡는다**. [실증] `AS93125` 토론토 2,662개가 그 스냅샷에만 없었다.
  ⚠️ **기준선(`-initial`)이 이렇게 찍히면 원장 전체가 잘못된 출발점을 갖고, 어느 대조에서도
  드러나지 않는다.** ⬜ 처방 미구현 = **직전 회차 대비 `list_total`·행 수 급감 검사**.
- 👁2 는 **관찰 대기**(WMS 는 put-away 없이 Apply 하지 않아 우리 시스템이 만들 수 없는 상태.
  ⚠️ Advanced 기본값을 켜면 게이트로 복귀) · 🟡4 만 **실동작 미검증**으로 남는다.

- ⬜⬜ **검증 대기 — `inv-sku-types` cron 이 등록돼 있지 않다 (2026-08-24 발견 · 미해결)**
  [실측 2026-08-24 `cron.job` 전체] 12(inv-snapshot-compare)·13(inv-compare-run)·14(wms-auto-hold)
  — **`inv-sku-types` 는 없다.** ⑥ 세션이 "잡 14"로 문서화했으나 등록되지 않았다(발견 경위:
  WMS 자동 Hold 의 실물 jobid 가 14 였고, **12·13 다음이 14 라는 사실 자체가 미등록의 증거**였다
  — jobid 는 시퀀스라 unschedule 해도 재사용되지 않는다).
  ⚠️ **영향**: 비재고 SKU 캐시(`inv_sku_types`)가 갱신되지 않는다 → 마지막 수동 실행에서 48h 뒤부터
  `inv-collect` 응답 `non_stock_gate.warnings` 에 `cache STALE`. 게이트는 옛 목록으로 계속
  작동하므로 즉시 사고는 아니나 **새 비재고 SKU 를 못 막는다**(FINAL-SALE 계열이 다시 쌓이고,
  ⑥ 대조가 unknown 으로 잡아줄 뿐 — 그것이 원래 이 캐시를 만든 이유다).
  ⇒ **등록 = `supabase/ops/cron.sql` 의 해당 절 `cron.schedule` 을 실서버에서 실행**하고,
  **받은 jobid 를 그 파일에 반영**할 것(미리 적은 번호는 추정 — 같은 파일 헤더의 교훈).
  📌 이 항목은 「세션당 조용한 결함 발견」으로 계상됐다(2026-08-24 · 2건 중 ②) —
  경위 정본은 `docs/sessions/2026-08-24-hold-tracking.md`.

⚠️⚠️ **`since=<스냅샷 날짜>` 는 매 호출에 필요하다 — cron URL 6줄에 `since=2026-08-20` 이 박혀 있다.**
코드가 `occurred_on > since`(**엄격히 큼**)를 쓰므로 8/20 전체가 제외된다 — 그날 낮 사건은 스냅샷에
이미 녹아 있다. `since=2026-08-19` 로 하면 8/20 낮이 **이중 계상**된다.
📌 **스냅샷을 다시 찍으면 cron 6잡의 `since` 를 손으로 갱신할 것**(테이블 영속화 대신 URL 을 고른 대가).

⚠️ **`TIME_BUDGET_MS=120초` 안에 6종을 다 돌 수 없다**(첫 소스가 예산을 소진 → 나머지는
`aborted: "time budget exhausted before this source"`) → **소스별 cron 분리로 해결했다**.
📌 **시간 가드에 걸린 것은 페이싱 실패가 아니다** — 페이싱 판정 기준은 `rate_limited` 다.

⚠️ **회차 소요는 「후보 수 ÷ 캡」으로 추정하면 틀린다 — 가르는 것은 「상세를 봐야 하는가」다.**
[실측 2026-08-20 가동] `adjustment` 는 후보 586건이 **한 회차에 끝났다**(`detail_fetched: 0` —
`skip_since` 가 목록 레벨에서 판정된다) · `transfer` 는 두 날짜를 봐야 해서 캡 40에 걸린다
(`detail_capped_remaining: 1,787`, 5회차에 214건 전진).

⚠️ **`precision_skipped` 가 「목록은 많은데 후보가 0」을 설명한다** — `UpdatedSince` 는 날짜 단위라
겹치게 받고(커서 − 1일) 커서 **시각** 이전 갱신분을 우리 쪽에서 다시 거른다. [실측] 발주 88 =
45(서비스 전용) + **43(precision)** · 판매 273 = **179(precision)** + 78(미출하) + 16(void).
📌 **검증 커맨드에 이 필드를 넣을 것** — 없으면 「왜 안 들어왔지」를 추적할 수 없다.

📌 **cron 검증은 결과물로만 한다** — `cron.job_run_details` 의 `succeeded` 는 아무것도 보장하지
않는다(HTTP 요청을 띄운 것까지만 본다). 유일한 증거는 `inv_sync_state.last_run_at` 갱신 +
`last_cursor` 전진이다.
⚠️ **원장 쓰기 뒤 `insert_skipped ≠ 0` 은 정상**(재수집) · `conflicts_detected ≠ 0` 이면
`select * from inv_conflicts order by detected_at desc`. **첫 회차는 원장이 비어 `insert_skipped` 0** —
두 번째 회차부터 의미가 있다. ⚠️ `R.written` 의미가 「시도 행수」 → **「실삽입 행수」**로 바뀌었다.
(~~CardID 재수집 안정성~~ 은 2026-08-18 저녁 PO-01117 실측으로 닫힘 — Convert 를 통과해도 유지.)
⚠️ **PA 블록은 `DRAFT` 로 생성 → 승인되면 `AUTHORISED`.** [실측] PO-01117 은 Convert 직후 DRAFT,
**다음 날 아침 AUTHORISED** — 화면이 먼저 바뀌고 API 가 따라온다(**지연 확정**, 2026-08-19).
⇒ `putaway:DRAFT` 는 오류가 아니라 진행 중 상태고, 원장은 다음 회차에 기표한다(유실 아님).

---

## 2. ⚠️ 반복해서 틀렸던 것 (가장 중요)

| 함정 | 진실 |
|---|---|
| `Adjustment` 가 증감분? | **아니다. 조정 후 목표 수량.** 증감 = `Adjustment − QuantityOnHand` |
| `NewStockLines` 도 같은 규칙? | **아니다.** `Quantity` 가 그대로 증가분. 섞으면 원장이 통째로 틀림 |
| `StockOnHand` 가 수량? | **아니다. 평가액.** 원장 기준값은 `OnHand` |
| 재고가 픽/팩에 빠지나? | **아니다. Ship 시점.** 픽·팩·Finalize 는 `Allocated` 일 뿐 |
| 문서 번호로 순서를 정하면? | **안 된다.** 접두어가 달라 비교 무의미. **유입(+) 먼저, 유출(−) 나중** |
| `Bin=null` 행이 창고 집계행? | **아니다.** 빈 미지정 재고 자리. 99.8%가 0이고, 0이 아닌 14행은 진짜 재고 |
| UOM SKU 도 재고가 있나? | 평소 없다(`OnHand=0`·`Available` 만 파생). 다만 **구조상 가질 수는 있다** |
| `ProductID` 가 라인 식별자? | 상품 ID 다. 같은 SKU 두 줄이면 겹침. **다만 실무상 안 겹쳐서 line_ref 로 씀** (⚠️ 판매 예외 — 5절) |
| 발주 블록 `Status` 는 DRAFT 만 제외? | **아니다 — 그리고 어느 배열의 상태를 보느냐가 먼저다(08-18).** 화이트리스트 = **PA 축 기준 `AUTHORISED` 만** + 미지값 경고. ~~SR 기준 AUTHORISED·`""` 통과(08-17)~~ 는 폐기 — 빈 문자열 예외의 근거 PO-01128 은 빈 상태가 **SR 블록**이었다(PA 는 AUTHORISED 84줄). SR 상태로 거른 "−90행 유령 재고 차단" 판정도 무효(실재 입고를 지운 것) |
| 발주 라인 수량은 나중에 바뀔 수 있는가? | **그렇다(2026-08-19).** PO 를 닫으려면 인보이스 수량과 정확히 같아야 해서 **PO 수량을 인보이스 수량으로 채운다** — [실측] PO-01117 PA `CAN01620` **168→192**(`CardID`·bin·문서번호 전부 동일, 수량만). 차액은 **stock adjustment 로 되돌아온다**(`ST-01220` −24/+24) — 한 입고가 `po_in`+`adjustment` **두 소스에 걸친 사건**이 된다. ⚠️ 유니크 키가 같아 `DO NOTHING` 이면 새 수량이 조용히 버려진다(설계 정본 4부 3번) |
| 발주 입고는 `StockReceived` 를 읽으면 되나? | **아니다(2026-08-18 확정).** Advanced = **`PutAway`** / Simple = `StockReceived`. SR 은 ① `LocationID` 가 null 이거나 창고 GUID 라 **bin 이 구조적으로 없다** ② `Status` 가 stock receiving 단계의 **워크플로 상태**라 재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED · PO-01131 SR=NOT AVAILABLE/PA=AUTHORISED 3,570u). SR·PA 는 같은 입고의 두 표현 — 둘 다 읽으면 두 배 |
| 목록 `StockReceivedStatus` 로 후보를 좁히면? | **안 된다.** 상세 블록 상태와 **상관이 없다**(양방향 불일치 — PO-01131 목록 AUTHORISED/상세 NOT AVAILABLE ↔ PO-00848 반대). 표본 6건 중 4건(12,552u)이 실재 입고인데 문서째 유실됐다. 판정 권한은 상세 한 곳 — 목록 값은 분포만 센다 |
| 트랜스퍼도 bin 을 가져오는가? | **가져올 수 있다 — 다만 현재 코드는 안 읽는다(2026-08-19 정정).** bin 은 **라인이 아니라 헤더**에 있다: `FromLocation`/`ToLocation` 이 **`"창고: bin"` 문자열**([실측] TR-02645 `"Asung - Edmonton: EZ01Pallet03"`→`"Asung Trading Inc.: F0300PALLET01"` · 목록·상세 양쪽). **문서 하나 = bin 하나 → bin 하나**라 라인에 없는 게 정상(WMS 도 Apply 시 출발 bin 별로 문서를 쪼갠다). 현재는 `From`/`To` GUID 만 `resolveLoc` 에 넘겨 창고만 해석 → `bins=[""]`. **창고 단위는 지금도 정확** · 자리 단위 때 `": "` 파싱+매핑 대조로 고친다. ⚠️ `Lines[].ProductCustomField1/2` 는 상품 마스터 필드 — 쓰지 말 것(TR-02644 null). ⚠️ ~~"라인에 bin 필드가 없다=데이터 없음"~~ 은 오판이었다(응답 한 부분만 보고 판단 — 발주 SR/PA 와 같은 실수) |
| `saleCreditNoteList` 행은 CN 단위? | **아니다. sale 단위.** 목록 `RestockStatus` 로 거르면 같은 오더의 AUTHORISED CN 이 유실 — 판정은 상세 `CreditNotes[]` 순회 한 곳만 |
| `Restock[]` 이 비면 DRAFT? | **아니다.** AUTHORISED+빈 배열 실재(표본 하나 CR-00024 의 일반화였다) — 판정은 배열 실제 길이로 |
| `UpdatedSince` 로 받으면 그 기간 이벤트만? | **아니다. 갱신 축과 이벤트 날짜는 분리** — 8월 갱신 문서가 4월 이벤트를 품는다. **`since=`(이벤트 필터)가 스냅샷 경계 방어 — 쓰기 켤 때 필수.** `from_since` 는 커서 씨앗으로 딴 것 — 혼동 금지 |
| `SR=[""]` 빈 상태 블록을 이상 신호로 볼 것인가? | **아니다. Convert 를 거친 문서의 정상 흔적**(라인이 PA 로 옮겨간 뒤 껍데기만 남는다 — PO-01117 실측: Convert 직후 SR 0줄·PA 51줄, CardID 동일) |

### 조사 자체에서 반복된 실패 (같은 실수 반복 금지)

- **1페이지만 받고 판정** — `/transactions` 30일이 6,451행인데 1,000행만 보고 "86% 미대응"이라 오판.
  전량 받으니 **87% 일치**로 정반대였다. **Total 과 수신 행 수를 항상 대조할 것**
- **정렬 가정** — 목록 앞쪽 1,000행이 전부 UOM 집계행이라 "빈 지정 0%"로 오판
- **파라미터 이름 추측** — `stockadjustment?ID=` 로 400. 문서엔 `TaskID` 로 적혀 있었다
- **대조군 없이 판정** — Cin7 은 모르는 파라미터를 조용히 무시한다.
  존재하지 않는 이름(`ZzzNotARealParam`)을 같이 던져 "무시" 기준선을 만들 것
- **표본 하나에서 규칙을 만들었다** (2026-08-17) — 명세 전제 4개 중 3개가 실측에서 깨졌다
  (발주 블록 상태 어휘 · CN 행 단위 · 빈 Restock). **블랙리스트는 처음 보는 값을 조용히
  통과시킨다 → 화이트리스트 + 미지값 경고가 정답**
- **응답 필드명을 추측했다** (2026-08-17) — `updated_since_req`·`srs_counts`·`advanced_count`
  전부 오답(실제 `updated_since_requested`·`sr_block_status_counts`·`advanced_docs`).
  **`jq 'keys'` 로 먼저 확인할 것** — 위 「파라미터 이름 추측」과 같은 계열
- ⚠️ **응답의 한 부분만 보고 「없다」고 결론내지 말 것 — 이틀 만에 두 번 반복했다.**
  ① 2026-08-18 발주: `StockReceived` 라인만 보고 「Advanced 는 bin 을 못 얻는다」 →
     실제로는 `PutAway` 블록에 있었다.
  ② 2026-08-19 트랜스퍼: `Lines[]` 와 dry 의 `bins=[""]` 만 보고 「트랜스퍼는 bin 이 없다」 →
     실제로는 헤더 `FromLocation`/`ToLocation` 에 `"창고: bin"` 문자열로 있었다.
  📌 **점검 질문**: 라인에 없으면 **헤더·다른 블록·다른 엔드포인트**에는? 그리고
  **화면에 보이는데 API 에 없어 보이면 API 를 덜 본 것이다.**
  ⚠️ 둘 다 **Caleb 이 화면을 보고 지적해서** 잡혔다 — dry 숫자만으로는 두 번 다 못 잡았다

---

## 3. 이벤트 8종 — 어디서 무엇을 읽나

| 사건 | 출처 | 부호 | 날짜 |
|---|---|---|---|
| 판매 출고 | `sale` → `Fulfilments[].Pick.Lines` | − | `Ship.Lines[].ShipmentDate` |
| 반품 입고 | `sale` → `CreditNotes[].Restock` | + | `CreditNoteDate` |
| 발주 입고 | Advanced → **`PutAway[].Lines`** / Simple → `StockReceived.Lines` (08-18) | + | **`Lines[].Date`** |
| 이동 출발 | `stockTransfer` → `Lines[].TransferQuantity` | − | `DepartureDate` |
| 이동 도착 | 같은 문서 | + | `CompletionDate` |
| 조정 기존 | `stockadjustment` → `ExistingStockLines` | `Adjustment − QuantityOnHand` | `EffectiveDate` |
| 조정 신규 | `stockadjustment` → `NewStockLines` | `+Quantity` | `EffectiveDate` |
| 조립 | `finishedGoods` → `PickLines`(−) + 헤더(+) | 양방향 | 오더 생성 시점 |

**원가만 바뀌는 6종**(`* Cost Change`)은 `Quantity=0` — 수량 원장에서 무시.

### 문서별 함정

- **발주 (2026-08-18 재설계 확정 — `@2026-08-18.1` 반영)**: 축은 목록 `Type` 으로 가른다 —
  **Advanced = `PutAway`**(bin 있음·확정 반영) / **Simple = `StockReceived`**(객체 하나 · bin 있음
  — PO-00874). SR 을 쓰면 안 되는 이유 둘: ① SR 라인의 `LocationID` 는 null 이거나 **창고
  GUID** 라 bin 이 구조적으로 없다 ② SR `Status` 는 stock receiving 단계의 **워크플로 상태**지
  재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED 62줄 `FULLY RECEIVED` · PO-01131
  SR=NOT AVAILABLE/PA=AUTHORISED 3,570u · PO-01128 SR=""/PA=AUTHORISED 84줄). SR·PA 는 같은
  입고의 두 표현(15건 srLines==paLines) — **둘 다 읽으면 정확히 두 배**.
  블록 화이트리스트: **통과는 두 축 모두 AUTHORISED 만** + 미지값 경고(~~빈 문자열 통과~~ 는
  근거 소멸로 삭제). **PA 축의 알려진 어휘 = `AUTHORISED`·`VOIDED`·`DRAFT`**(08-18 · Convert
  직후 PA 는 DRAFT 로 생성 — PO-01117) — ⚠️ 어휘와 통과 기준은 다르다: DRAFT 는 경고 없이
  건너뛰는 정상 상태일 뿐 기표되지 않는다. 목록 `StockReceivedStatus` 게이트 없음(위 함정 표).
  Advanced 인데 PA 없음 = 행 미기표 + 보고, 커서는 안 멈춘다(~~재등장 전제 미확인~~ →
  **08-19 실측으로 닫힘 — PA 승인 후 +51행 재등장**. 정본 4부 체크리스트 ☑3).
  ⚠️ `Type` 은 가변이지만 **Convert 는 사람이 누르는 명시적 동작 — 시간 아님(PO-01117 31분 무변)**.
  ~~"Apply 후 ~10분 자동 전환(12/12)"~~ 은 Convert 가 보통 빨리 눌렸던 것의 오인.
  `simple_docs: 0` 도 `> 0` 도 정상이고, 전환이 `LastUpdatedDate` 를 올려 **모든 PO 가
  UpdatedSince 에 최소 두 번 잡힌다**. ~~"최근 40건 전부 Advanced — Simple 분기 미실행"(08-17)~~ 은 닫혔다:
  목록 게이트 제거 후 `simple_docs: 7` 실행·정상 동작(SR NOT AVAILABLE 올바르게 배제).
  [실측 08-18 dry 전/후] rows 383→643(+68%) · UNMAPPED 소멸 · bin 실제 선반으로
  ✅ **Simple 분기가 실제로 행을 만들었다 (08-19 PO-01112)** — 종전엔 `simple_docs > 0` 이어도 SR 이
  전부 `NOT AVAILABLE` 이라 걸러졌을 뿐 **Simple 축이 행을 만든 적은 없었다**. PO-01112 Apply 로
  `sr_block_status_counts={AUTHORISED:1, NOT AVAILABLE:5}` → **102행**(같은 창 727→829).
  ⇒ Simple=SR 축 결정이 실동작으로 검증됐다. 📌 이 증가는 코드가 아니라 **데이터 변화**다
  (`candidates`·`docs_processed` 는 20 으로 동일한데 행만 늘어 감지 로직을 의심했다 — 확인은
  `wms_receipts.applied_at` 조회. **행 수가 늘면 코드보다 그날의 입고를 먼저 볼 것**)
- **발주 날짜**: `OrderDate`·`InvoiceDate`·`LastUpdatedDate` 전부 어긋남. 우연히 맞는 경우가 있어
  **한 건만 보고 판단 금지**
- **반품**: `RestockStatus='AUTHORISED'` 일 때만 재고 복귀. `DRAFT` 는 금액만.
  한 오더에 크레딧 노트가 **여러 개** 붙을 수 있음.
  ⚠️ 정정(08-17): **AUTHORISED 인데 `Restock[]` 빈 배열 실재** — 판정은 배열 길이로.
  목록 행은 **sale 단위** — 목록에서 `RestockStatus` 로 거르지 말 것(같은 오더의 승인 CN 유실).
  원장 doc_number = **CreditNoteNumber**(오더번호면 다중 CN 이 유니크 키를 깬다)
- **이동**: 한 문서가 원장 4행(출발창고− / IN_TRANSIT+ / IN_TRANSIT− / 도착창고+).
  미완료면 출발만. **97%가 같은 창고 안 자리 이동** — 창고 단위로는 ±0이지만 **두 줄 다 기록**.
  ⚠️ **빈 이동의 `DepartureDate` 결손은 구조적이다**(Cin7 WMS 모바일 빈 이동이 만든다 —
  실측 15건 · 우리 WMS 에 빈 이동 기능이 없어 **계속 발생**). 대체 규칙: **같은 창고 →
  `LastModifiedOn` 으로 대체 + raw 에 대체 사실 기록**(창고 잔고 ±0 이라 무영향) /
  **다른 창고 → hold**(잔고가 움직이는데 시점 불명 = 진짜 이상)
- **조립**: 오더 생성 시점에 실제로 재고가 움직인다. 출고는 배송 때 — 그 사이 번들이 재고로 존재(0~15일).
  물리적 이동이 아니라 **재분류**라 실사 때 장부와 선반이 달라 보임.
  ⚠️ 조립 없이 팔리는 경우도 있다(조정으로 재고를 잡아둔 것 — 3건 확인).
  ⚠️ 필드 실측(2026-08-17): `sku` 출처는 **`ProductCode`**(PickLines·헤더 둘 다 — SKU 필드가
  없다) · `doc_number` = **`AssemblyNumber`**(목록 배열 키는 **`FinishedGoods`**) ·
  날짜 = `CompletionDate`(FG-00110 = 2026-08-06 — `Date`/`CompletionDate`/`WIPDate` 세 값 동일 ·
  재고 이동일과 일치) · `Status='COMPLETED'` 만(120건 중 VOIDED 77)

---

## 4. 수집 경로

### 문서 목록 축으로 수집한다 (`/transactions` 아님)

⚠️ **`/transactions` 는 탐지 축으로 쓸 수 없다** — 창고내 이동의 94%가 회계 분개를 안 만든다.
금액 이동이 없어서다. 실측: 창고내 분개있음 123 / 없음 1,882 · 창고간 23 / 4.

### 목록별 증분 가능 여부 (실측)

| 목록 | Total | 증분 |
|---|---|---|
| `saleList` | 14,752 | ✅ `UpdatedSince` |
| `purchaseList` | 1,155 | ✅ `UpdatedSince` |
| `saleCreditNoteList` | 3,583 | ✅ `UpdatedSince` |
| `stockadjustmentList` | 1,201 | ❌ 전량 2p |
| `stockTransferList` | 3,977 | ❌ 전량 4p |
| `finishedGoodsList` | 120 | ❌ 전량 1p |

날짜 축 없는 셋은 **매번 전량 받아 우리 쪽에서 날짜로 거른다.** 하루 10페이지 안팎.

**전량 셋의 커서 하한(`?from_cursor=` — 2026-08-17)**: 저장된 커서가 없을 때의 시야 하한 —
그 번호 이하 문서는 후보에서 아예 제외(스냅샷에 녹아 있어 볼 이유가 없다).
⚠️ 근거 사고: `DepartureDate` 없는 2025-11 초기 트랜스퍼 **TR-00012~76 40건이
hold_missing_date 로 상세 캡 40을 정확히 소진**해 뒤 ~3,000건을 한 건도 못 봤다.
**`since` 로는 못 푼다 — 커서 정지가 필터보다 먼저다.** ⚠️ 하한은 "옛 데이터를 안 보는 것"이지
**이상 감지를 끄는 것이 아니다** — 하한 이후의 날짜 결손·DRAFT 는 여전히 커서를 막는다.

⚠️⚠️ **`from_cursor` 형식·함정 (2026-08-24 규명 — 두 번 헤맸다)**:
- **형식 2종**: bare `from_cursor=TR-03900`(②-a 전량 축 3종 전부에 같은 하한) 또는
  `from_cursor=transfer:TR-03900,adjustment:ST-01150,assembly:FG-00110`(소스별).
- ⚠️ **②-a(조정·이동·조립) 전용이다** — 판매·발주·반품(②-b 시각 커서)은 이 파라미터를
  **아예 읽지 않는다**(그쪽 씨앗은 `from_since=YYYY-MM-DD`).
- 📌 **[2026-08-21 실측 재구성] `from_cursor=TR-03538` 이 "조용히 무시"였던 이유 — 에러가
  아니라 무시가 맞고, 두 겹이었다**: ① 판매 등 ②-b 에는 참조 코드 자체가 없다(구조적 무시)
  ② ②-a 에서도 **state 커서가 있으면 param 은 무시**(`floor 우선순위 state → param` —
  `from_cursor_param_ignored` 로 표시만 된다). ⑤ 가동 후에는 state 가 항상 있으므로
  **from_cursor 는 사실상 죽은 파라미터다** — 커서를 옮기려면 `inv_sync_state.last_cursor`
  를 직접 고치는 것뿐(쓰기 — dry 로는 불가).
- ⚠️ **[2026-08-24 실측] 시각 문자열을 넣으면 콜론이 형식 구분자와 충돌한다** —
  `from_cursor=2026-08-21T00:00:00` → `2026-08-21T00` 이 소스 키로 오파싱 →
  400 `"from_cursor: unknown source '2026-08-21T00'"`. 시각 커서 소스를 겨냥할 파라미터가
  아니다(위 ②-a 전용).
- ⇒ **커서를 무시하고 특정 창을 강제 조회하는 무해 파라미터는 없다**(2026-08-24 확인) —
  지나간 문서의 게이트 검증은 실데이터 재조회가 아니라 **로컬 테스트**로 한다
  (`scripts/test-invcollect-gate.mjs` — makeSink 를 원문 추출해 node 모의, 8케이스).

**증분 셋의 날짜 커서 규칙 (2026-08-17 구현 확정)**: `UpdatedSince = last_cursor − 1일`
(겹침 수신 — 중복은 유니크 키 흡수) · 문서 상태로 커서 안 멈춤(갱신되면 재등장) ·
⚠️ **캡 회차만 커서 = 마지막 처리 문서의 Updated**(오름차순 처리 전제 — 회차 시작 시각으로
옮기면 캡 밖 후보가 영영 유실. 판매는 캡 초과가 일상) · ⚠️ 커서는 시각 전체 정밀도로 저장하고
**거르기도 우리 쪽 전체 정밀도로**(날짜 절단이 "매 회차 같은 40건 반복·삽입 0행·정상 응답"의
완전히 조용한 정체를 만든다 — dry 로는 재현 불가) · ⚠️ **`since=<스냅샷 날짜>`(이벤트 필터)는
쓰기 켤 때 필수** — 갱신 축과 이벤트 날짜가 분리라 과거 이벤트가 스냅샷과 이중 계상된다.

### `Movements` 는 검증용

`product?ID=…&IncludeMovements=true` 로 SKU 단위 전체 이력. **부호가 이미 들어 있고 완전하다**
(3건 전수: 누적 = 현재 `OnHand`). 그런데 **날짜 필터가 없고**(후보 7종+대조군 전부 무시)
**SKU 단위 조회**라 수집엔 못 쓴다. → **대조·검산 축**으로 쓴다.

`Movements` Type 어휘 14종 = 수량 8종 + 원가 6종. 필드: `TaskID·Type·Date·Number·Quantity·Amount·Location(빈 포함)·FromTo`

---

## 5. 스키마 (배포 완료)

`inv_ledger` · `inv_snapshot` · `inv_compare` · `inv_sync_state`

### `inv_ledger` 핵심

- **append-only** — `authenticated` 는 INSERT+SELECT 만(`wms_rollback_archive` 선례). `anon` 전부 회수
- 유니크: `(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)`
  - ⚠️ `bin` 은 **NOT NULL DEFAULT `''`** — 부분 유니크 금지 규칙(29) 때문
  - ⚠️ `sku` 를 넣은 이유: `line_ref` 가 흔들려도 **조용한 누락 대신 가시적 이중 계상**이 되게
- `seq_hint` — **1=유입 / 2=유출**. 같은 날 정렬용
- `warehouse` — **Cin7 원문 그대로** + `IN_TRANSIT`(언더스코어 = Cin7 원문 아님 표시)
- `line_ref` = **`ProductID`** (WMS 의 `cin7_po_line_id` 선례) — ⚠️⚠️ ~~판매만 예외~~ →
  **예외 둘(08-18): 판매·발주.** 규칙의 정본은 설계 문서 2부 「중복 방지」 소스별 표
  ("소스마다 가장 안정적인 라인 식별자" — 통일보다 정확성 우선). **판매 예외:
  `<fulfilment TaskID>:<ProductID>`** (2026-08-17 · 의도적 이탈). 유니크 키에 **occurred_on 이
  없어서**, 분할 출하(같은 SKU·같은 bin·날짜만 다름)의 두 행이 키가 완전히 같아져 두 번째
  출고가 조용히 사라진다. **"스킬대로 ProductID 로 되돌리자"는 제안이 나오면 이 줄이 근거다 —
  되돌리면 분할 출하가 뭉개진다.** fulfilment 식별자는 TaskID(GUID — 재수집에도 안정 · 배열
  인덱스 금지). [실측] TaskID 폴백 발동 0회. ~~발주의 진짜 라인 식별자 CardID 는 raw 원문에만~~
  → 08-18 부터 발주의 line_ref 자체가 CardID 다(아래).
  ⚠️ **발주는 `CardID` 로 확정(2026-08-18 · `@2026-08-18.1`)** — 같은 SKU 가 여러 빈으로 쪼개지고
  같은 빈·같은 SKU 가 날짜만 달리 두 줄인 사례 실측(PO-00944 KUZ77036). `ProductID` 는 유일성
  94/97 · 109/110 으로 부족, `CardID` 는 97/97 · 110/110. [실측] `.7` dry `merged_lines: 5`
  (가설이던 뭉개짐이 실재) → `.1` 에서 **0**. ✅ CardID 의 재수집 안정성은 **닫힘(08-18 저녁
  PO-01117)** — Convert(SR→PA)를 통과해도 51줄 전부 CardID·LocationID·순서 유지, 재생성 아님
- `raw` = **그 행을 만든 라인 원본 + 계산에 쓴 머리말 + 우리가 적용한 계산 규칙**.
  문서 전체 금지(344라인 트랜스퍼면 수천 벌 중복)
- ⚠️ `qty_delta` 에 CHECK 없음 — **소수 수량이 실재**(5.25개 · ×0.25)

### 기초 스냅샷

`ref/productavailability` 전량 22,133행 · 23페이지 · 1분. 페이지 상한 없음.

**스냅샷 조건**: 자리 지정된 것은 자리별로, **자리 없이 떠 있는 재고(`Bin=null` & `OnHand≠0`)도 담는다.**
자리 있는 것만 담으면 11건이 통째로 누락된다.

✅ **실촬영 완료 (2026-08-20)** — `snapshot_key 2026-08-20-initial` ·
`taken_at 2026-08-20T23:42:47.855Z`(19:42:47 토론토) · **13,844행**(토론토 7,523 / 에드먼튼 6,321) ·
44초 · `truncated` false · `rate_limited` false · `unexpected_warehouses []`.
낮 dry 리허설은 41초·13,871행 — **27행 차이는 그사이 5시간의 실제 재고 변동**이다(정상).
📌 DB 검증 일치. `bins` 만 SQL 쪽이 1씩 많은데(506→507 · 1467→1468) **빈 문자열 bin 이 `distinct` 에
세어진 것**이지 불일치가 아니다.

⚠️ **`key` 파라미터가 필수다** — 자동 생성을 하지 않으며 **dry 에도 요구**한다. 인증은 `inv-collect` 와
같은 `WMS_CRON_SECRET`.

⚠️ **자리 미상 재고가 기준선에 포함된다 — 알고 시작하는 위험.** `null_bin_nonzero` **15건**
(토론토 1,421개 · 에드먼튼 6개). 최대는 **`AS00879BLA` 1,200개 · $12,065** · `AIA*` 7종은 전부
6개·$0.0831 로 같은 패턴(샘플·디스플레이 추정) · `SUN31504` 159개는 원가 $0.
⇒ 원장은 그대로 기록하고 **⑥ 대조에서 드러난다.**
📌 **`null_bin_nonzero` 에 샘플 상한은 없다**(코드 확인 — `nullBinNonzero` 는 조건 없이 `push`,
`slice` 없음). 15건이 전량이다.

---

## 6. 창고

`ref/location` 2,676행 · **`ParentID` 없는 것이 창고**(2단 트리, 재귀 불필요) · 창고 3개

| Cin7 | WMS `warehouse` | WMS `location` |
|---|---|---|
| `Asung Trading Inc.` | `toronto` | 같음 |
| `Asung - Edmonton` | `edmonton` | 같음 |
| `Production Facility` | 없음 | — |

- `wms_orders.location` 은 **Cin7 표기 그대로** → 매핑 불필요
- `wms_receipts`·`wms_waves` 는 `warehouse` 만 → **2줄 매핑 필요**
- ⚠️ `Production Facility` 는 삭제 불가한 시스템 창고, 미사용(재고 0 전수 확인).
  **제외하되 `OnHand>0` 이 나타나면 경고할 것**

---

## 7. 재고 조회 규칙 (`ref/productavailability`)

- ⚠️ `Sku` 는 **전방 부분일치** — `ANN04350` 요청에 `ANN04350-12` 도 온다. **정확일치로 재필터**
- ⚠️ `Bin=null` 행과 빈행을 **합산하면 이중 계산**
- ⚠️ UOM SKU 는 `OnHand=0` · `Available>0`(파생값) — 원장 대상 아님
- `StockOnHand ÷ OnHand` = 단가. 빈마다 다르다(68%) → **FIFO 구조**. 초기 단가로 쓸 수 있으나
  **레이어 구조는 여기서 못 얻는다**
- `InTransit` 필드는 창고이동과 무관 — `OnOrder` 와 같은 값(발주 잔량)

---

## 8. 알고 시작하는 위험

- **원가 0 재고** — 조정으로 새로 잡을 때 `UnitCost=0` 이 들어온다. 원가 단계에서 공짜 재고
- **원본 데이터 오류** — `AMP41108-12` 의 `UOM="6"`(SKU 접미어와 불일치).
  ⚠️ **SKU 접미사 파싱 금지**. 원장은 원본 오류를 그대로 물려받는다
- **전체 합계 검산 경로 없음** — SKU 단위는 `Movements` 누적으로 되지만, 창고 총계는 화면 리포트뿐
- **수동 단계** — 매니저의 `2.Release to WMS`(`sale` 의 `AdditionalAttributes.AdditionalAttribute1`).
  주 5일이라 월요일에 몰린다. 재고와 무관하나 대조 때 설명이 필요
- **주말·공휴일** — 재고가 안 움직이는 게 정상. 온타리오와 앨버타의 공휴일이 다르다

---

## 9. 작업 방식

- 조사·판단 먼저 → Caleb 확인 → 구현. **한 번에 한 단계**
- git·SQL·EF 배포·Cin7 호출은 **Caleb 이 직접**. 프로덕션 직접 요청 금지
- 마이그레이션은 항상 새 파일. baseline 수정 금지. `supabase db reset` 으로 로컬 재생 검증 후 push
- 커밋 메시지에 `Co-Authored-By` 금지
- GAS 프로브가 표준 조사 도구 — EF 구현 전에 항상 실측
