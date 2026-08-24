# 2026-08-24 — ⑥ shadow 대조 가동 · 첫 수확(FINAL-SALE) · 스냅샷 결손 발견

정본은 설계 문서(`docs/design/ledger-design.md` 「⑥ shadow 대조 가동」)와 스킬
(`asung-inv-ledger`·`cin7-api`)이다. 이 문서는 **이날 무엇이 있었나**의 경위 기록이다.

---

## 요약 — 한 줄

**⑥ 대조를 켜자마자 결함 1건을 잡았고**(비재고 SKU 가 원장에 재고로 쌓이고 있었다),
**그것을 고치는 과정에서 더 큰 미해결 하나를 발견했다**(스냅샷이 조용히 불완전할 수 있다).

---

## ① ⑥ shadow 대조 가동

- `inv_compare`(테이블은 ⑤ 이전부터 있었으나 채우는 코드가 0곳) + **RPC `inv_compare_run(p_key)`**
  + 회차 기록 `inv_compare_runs` 신설 (마이그레이션 `20260824130759`).
- **Cin7 현재고는 `inv-snapshot` 재사용** — 검증된 all-or-nothing 을 재구현하지 않는다.
  cron URL 에 날짜를 박을 수 없어 **`?key=auto-compare` 리터럴일 때만** `YYYY-MM-DD-compare` 자동 생성.
  ⚠️ `-initial` 은 **여전히 수동 명시만** · compare 스냅샷 보존 14일 ·
  **`-initial` 불가침을 코드(`not like '%-initial'`)와 테스트로 강제**.
- ✅ **cron 2잡 등록** — `inv-snapshot-compare`(잡 12 · `21 3 * * *`) →
  `inv-compare-run`(잡 13 · `36 3 * * *`). 분 집합 전수 계산으로 기존 잡과 **겹침 0**.
  ⚠️⚠️ **15분 간격이 설계의 핵심**이다 — 이유는 ③-(b).
  ⚠️ 등록 실물은 `select jobid, jobname, schedule, active from cron.job order by jobid;` 로 확인.

**비교 단위 = 창고. IN_TRANSIT 은 짝 없는 행으로 `explained` 자동 분류.**

⭐ **근거 실측 (BMA15710)**: Cin7 도 운송 중 물량을 **`ON HAND` 에서 빼고 별도 `IN TRANSIT` 컬럼**으로
관리한다(에드먼튼 행 `ON HAND 0 · IN TRANSIT 204`). **원장의 `IN_TRANSIT` 합성 창고와 같은 모델**이라
창고별 수치가 자연히 맞는다.
[원장 대조] 토론토 910(스냅샷 1,137 − 227) · 에드먼튼 16 · IN_TRANSIT 204 — **Cin7 과 SKU 단위 완전 일치.**
📌 **스냅샷+사건 누적이 작동한다는 첫 증명**이다.

**첫 회차: `compared_pairs 13,836 · match 13,835 · explained 316 · unknown 1`**
⚠️ **카운트 관계 — 셋을 더하지 말 것**: `compared_pairs = match + unknown`(13,836 = 13,835 + 1)이고
**`explained`(IN_TRANSIT)는 pairs 밖의 별도 집계**다(RPC 의 `filter (warehouse <> 'IN_TRANSIT')`).
📌 첫 회차에서 `13,835+316+1=14,152` 로 셋을 배타 합산해 "정합이 안 맞는다"고 오독했다 — 같은 오해를
반복하지 않도록 남긴다.

---

## ② ⭐ `FINAL-SALE` — ⑥의 첫 수확

`unknown 1` = **`FINAL-SALE` / Asung Trading Inc. / 원장 −34 / Cin7 0** (출처 `SO-15097` 한 건).
**파손품을 stock adjustment 로 뺀 뒤 손님이 원해 판매할 때 쓰는 껍데기 SKU** 다(Comment 에 실제 상품
코드 · MARGIN 100% = 원가 0). Cin7 은 재고를 0으로 두고 팔아도 안 줄인다.

⚠️⚠️ **원인: `IsService` 와 `Type=Non-inventory` 는 다른 개념이다.**
`IsService` = 서비스(팔되 실물 없음 — 수집이 이미 걸러왔다) / `Type=Non-inventory` = **재고를 추적하지
않는 상품**(걸러지지 않았다). `FINAL-SALE` 은 **`IsService=false` + `Non-inventory`** 라
**기존 필터의 틈에 빠졌다.**

**처방 — 비재고 게이트** (마이그레이션 `20260824140345` · EF `inv-sku-types` · cron `26 3 * * *`
— ⚠️ **[정정 2026-08-24 밤] 이 cron 은 실제로 등록되지 않았다**: `cron.job` 에 없다.
경위·영향은 `docs/sessions/2026-08-24-hold-tracking.md` 앵커 ②):
- 게이트는 **`makeSink` push 진입부 한 곳**(since 필터 앞) — 6소스가 전부 그 지점을 지난다
  (배출구 = 공유 루프 2곳뿐) ⇒ **새 소스도 자동 적용**
- 판정은 **「테이블에 있으면 차단」** — `product_type`·`is_service` **값과 무관**하다
  (로드 쿼리가 `select=sku,refreshed_at`. 비-Stock 만 저장하는 것이 계약)
- ⚠️ **캐시 미스는 fail-open(통과 + 경고)** — 원장은 shadow 이고 **대조가 안전망**이다.
  차단은 정상 재고 수집까지 멈춘다
- ⚠️ **저장 범위 계약: Stock 은 넣지 않는다** — 넣으면 1,000행 캡에서 조용히 잘리고
  **잘린 비재고 SKU 가 게이트를 통과**한다. 마이그레이션 주석 + **800행 근접 경보** + `caps-ok` 사유 주석
  (📌 커밋 훅이 이 조회를 실제로 막아 세워서 나온 결론이다 — 훅이 제 일을 했다)
- **게이트 테스트 8케이스** `scripts/test-invcollect-gate.mjs` — ⚠️ 원본 파일에서 `makeSink` 를
  **실행 시마다 추출**해 검증하므로 구현이 바뀌면 테스트가 따라온다. ⑤~⑦은 정적 검사(배출구 2곳 ·
  `nonStockSkus` 전달 · 폴백 경고) — **세 번째 배출구를 만들면 깨진다**

**정정**: 이미 들어간 −34 는 **상쇄 행**(`source='manual'` · `event_type='manual_reversal'` ·
`line_ref` 에 reversal · raw 에 사유)으로 처리.
⚠️⚠️ **물리 삭제는 하지 않았다** — append-only 의 **첫 위반이 「사소한 1건」인 것이 가장 위험**하다.

📌 [실측] 비-Stock 45건(`Non Inventory` 2 + `Service` 43). `_5_`·`_6_`(DEPRECATED)는 Cin7 이
`Service` 로 분류한다 — 어느 쪽이든 Stock 이 아니라 차단된다.
📌 `is_service` 컬럼은 **전 행 false** — `productList` 응답에 그 필드가 없어 기본값이 저장될 뿐이고
판정에 쓰이지 않는다. ⚠️ 오해를 부르는 컬럼이라 **정리 후보**.

---

## ③ ⚠️ 대조를 잘못 돌리면 생기는 오탐

**같은 날 대조를 세 번 돌렸고 결과가 매번 달랐다. 진짜 발견은 1차 한 건뿐이다.**

| 회차 | unknown | 정체 |
|---|---|---|
| 1차 (스냅샷 직후) | **1** | ⭐ 진짜 결함 (`FINAL-SALE`) |
| 2차 (6시간 뒤) | 134 | ⚠️ **낡은 스냅샷** |
| 3차 (재촬영 직후) | 165 | ⚠️ **불완전 스냅샷** |

### (a) 같은 키로 재촬영하면 첫 값이 남는다
`ignore-duplicates` 라 **당일 첫 스냅샷이 대조 기준**이다. 오후에 `key=auto-compare` 를 다시 부르면
`wrote: 5`(신규 조합만)로 끝나고 **13,800여 행은 아침 값 그대로**다. ⇒ 재촬영은 **다른 키**로.

### (b) ⚠️⚠️ 대조는 스냅샷과 붙어 있어야 한다
아침 13:19 스냅샷에 저녁 원장을 맞추면, 그사이 판매가 **원장에만** 반영돼 **134건이 어긋난 것처럼**
보인다. [실측] `ARD62157` −45 = 원장의 `SO-15102`(당일 판매) 그대로 · `FAN03021` −32 ·
`AS91651` −24 — **차이가 원장 사건과 정확히 일치**했다.
📌 **cron 설계(스냅샷 21분 → 대조 36분)가 이것을 구조적으로 막는다.** 수동 실행이 그 규율을 깼다.
⇒ **자동화가 준비된 것을 수동으로 급히 돌리지 말 것.**

### (c) ⚠️⚠️ 스냅샷이 조용히 불완전할 수 있다 — **최우선 미해결**
```
아침 13:19  Cin7 목록 22,079건 · 23페이지 → 13,829행
밤   15:17  Cin7 목록 21,877건 · 22페이지 → 13,787행   ← 190건 적고 페이지도 1 적다 · 소요 1분44초(평소 43초)
```
⚠️ 응답은 **`truncated: false` · `rate_limited: false`** 였다 — 받은 만큼은 다 받았으니 거짓말이 아니지만
**Cin7 이 애초에 적게 줬다.** `list_total == received_rows` 라 **all-or-nothing 가드가 구조적으로 못 잡는다.**
[실증] `AS93125` 토론토 2,662개가 그 스냅샷에만 없었다 — Cin7 화면에는 그대로 있었고 Movements 에
8/20 이후 사건도 없었다. ⇒ **unknown 165건은 원장 문제가 아니라 스냅샷 결손**이었다.
⚠️ **이번엔 대조용이라 무해했지만, 기준선(`-initial`)이 이렇게 찍혔다면 원장 전체가 잘못된 출발점을 갖는다.**
⬜ **처방 미구현**: 직전 회차 대비 `list_total`·행 수 **급감 검사**(N% 이상 줄면 거부 또는 경고).
📌 다행히 `2026-08-20-initial` 은 정상 촬영됐다(23페이지 22,079건 · 검증 완료).

---

## ④ Cin7 API 실측 (스킬 반영)

- ⚠️ **`productList` 는 `Limit` 을 명시해야 한다** — 기본 100건이라 `Page` 를 아무리 돌려도 같은 100건만
  온다. `Limit=1000` + 페이지네이션으로 5,001건 전량 수신 확인.
  📌 처음에 **「배열 키 이름 문제」로 오진**했다 — 키를 동적으로 찾아내도록 고쳐도 0행이라 그제야
  `Limit` 이 원인임을 알았다. **파라미터가 틀려도 200 이 온다**(조용히 무시 계열).
- ⚠️ **`Type` 값은 `Non Inventory`(공백)** — `Non-inventory` 가 아니다(화면 표기와 다름).
  게이트가 `Type !== 'Stock'` 부정 조건인 것이 이 함정을 비켜간다.
- ⚠️ **`from_cursor` 는 ②-a(번호 커서) 전용 · 형식 `transfer:TR-…`** — **두 겹으로 무시된다**
  (②-b 는 파라미터를 아예 안 읽고, ②-a 도 state 커서가 있으면 param 을 버린다). ⑤ 가동 후에는
  **사실상 죽은 파라미터**. 날짜/시각을 넣으면 무시가 아니라 **400**(콜론이 `source:VALUE` 로 오파싱 —
  `unknown source '2026-08-21T00'`). 📌 커서를 무시하고 강제 조회하는 파라미터가 **없기 때문에**
  게이트 검증을 로컬 테스트로 만들었다.

---

## 다음에 할 것

```
1. ⚠️ 내일 아침 — cron 첫 자동 회차 확인
   · 먼저 스냅샷 행 수(13,800 근처인지) — 결손이면 그 회차 대조는 무효
     select snapshot_key, count(*) from inv_snapshot group by snapshot_key order by 1 desc limit 3;
   · 그다음 대조 결과 (상쇄 행 반영 후 unknown 0 이 첫 정상 확인)
     select * from inv_compare_runs order by ran_at desc limit 1;
2. ⚠️ 스냅샷 급감 검사 구현 (③-c) — 최우선 미해결
3. 검증 대기 4건(라인 시각·2단계 Stats·리시빙 갭 컷·reaper) — asung-wms 스킬 상단
— 별건: WarehouseMap 을 WMS 로 · 브랜치 변경 대응 · hello 250ms ·
  Advanced PO 기본값 실물 검증 · product-images cron 결과물 · asung-ops 이관
```
