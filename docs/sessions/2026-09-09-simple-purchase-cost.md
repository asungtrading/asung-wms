# Simple Purchase 원가 경로 — 조사·구현·검증 (2026-09-09)

구현: EF `inv-cost@2026-09-09.1` · 커밋 `5116361`(경로) + `1c8483e`(입고 전 문서 조용한 스킵)
조사 보고 원문: `/tmp/inv-cost-simple-probe.md`(세션 임시 · 이 문서가 정본을 이어받는다)
관련: `docs/sessions/2026-08-27-landed-cost-investigation.md`(Advanced 경로 정본) ·
`docs/design/ledger-design.md` §「inv-cost 수집 계약」(계약) · `asung-inv-ledger` §아침 점검 ⑥ · `cin7-api` §Simple Purchase 상세

⚠️ 표기: **[실측]** = API 응답·DB 에서 읽은 값 · **[추론]** = 실측을 코드나 흐름에 대입한 판단 · **[Caleb 확인]** = 실무 확인.

---

## 1. 경위

1. 아침 점검 ⑥(원가 누락)에 **`PO-01215`** 가 떴다. 원장에는 47라인 9,192개가 정상으로 들어와 있는데 `inv_cost` 에 행이 **0건**.
2. 회차 로그 `dispositions`: `processed 6 · skip_service 2 · skip_simple_unverified 4`. 경고 문구:
   `"Simple Purchase encountered (e.g. PO-01215) - SR-axis cost path is UNVERIFIED (2026-08-27, no specimen); skipped, verify when one appears"`
3. 코드 확인 — 결함이 아니라 **설계된 스킵**이었다. `listDisposition()` 이 목록 `Type` 에 SIMPLE 이 들어가면 상세 호출 전에 스킵한다. 08-27 에 「표본이 나타나면 검증한다」고 남긴 것(헤더 주석 · 커밋 `590b391` · 조사 문서 253·403행)이 **13일 만에** 나타난 것이다.
4. 표본 특정 — `purchaseList UpdatedSince=2026-09-07` 13건 중 Simple 4건. 그중 실제 결손은 1건(§3).
5. GAS 프로브 3회로 `GET /purchase?ID=` 응답 구조를 실측(§2).
6. 코드 조사(자기검증 (b)(c)의 비교 축 · 환율 · `cost_kind` · 배분) → plan → Caleb 판정 넷(§4) → 구현 → 테스트 24개 → dry 에서 문제 1건(입고 전 문서 4건 격리) → 수정 · 테스트 27개 → 배포 · 검증(§5).

---

## 2. 프로브 결과 — 확정 사실 (표본 `PO-01215` · Simple · USD · 47라인 9,192개)

### 2-a. 응답 구조 [실측]
- **주소**: `GET /purchase?ID=<purchaseList 의 ID>`. Advanced 는 `/advanced-purchase`. ⚠️ Simple 을 `/advanced-purchase` 로 부르면 200 + 빈 껍데기(08-27 inv-collect 실측). POST/PUT 이면 PO 가 Advanced 로 변환된다(`cin7-api` 주의 13).
- **최상위 블록**: `Order`(객체) · `StockReceived`(객체) · `Invoice`(객체) · `CreditNote`(객체) · `ManualJournals`(객체) · `InventoryMovements`(배열 47). ⚠️ **`PutAway` 는 ABSENT.**
- 최상위 스칼라에 `CurrencyRate`(1.37905) · `SupplierCurrency`(USD).

### 2-b. bin 이 SR 라인에 있다 — Advanced 와 정반대 [실측]
- `StockReceived.Lines[]` 키: `Date, Quantity, ProductID, SKU, Name, Location, LocationID, Received, BatchSN, SupplierSKU, ExpiryDate, CardID, …`
- `Location` null **0건** · 18개 bin. Advanced 는 SR `Location` 이 전부 null 이고 bin 이 `PutAway.Lines` 에만 있다.
- 원장 `inv_ledger` 의 `PO-01215` 행 대조: `line_ref` = SR 라인 `CardID` · `bin` = SR 라인 `Location` · `warehouse` = `"Asung Trading Inc."` · `occurred_on` = SR 라인 `Date` · `sku` = SR `SKU`. ⇒ **`inv_cost` 5키가 SR 축으로 그대로 맞는다.** 원장(`inv-collect`)은 이미 Simple 의 SR 축을 읽고 있었고 `inv-cost` 만 스킵하고 있었다 — 결손이 원가 한쪽에만 생긴 이유.
- ⚠️ `ProductCustomField2` 도 bin 처럼 보이지만 상품 마스터 필드다. `Location` 을 쓴다.

### 2-c. 환율과 금액 [실측]
- **`Invoice.CurrencyRate` 는 null.** 환율은 최상위 `CurrencyRate` 뿐(1.37905).
- `InventoryMovements[]` 키: `TaskID, ProductID, Date, COGS, …`(수량·SKU·bin 없음 · Advanced 와 동일). `IM distinct ProductID = 47`(전부 유일) · `SR dates` 단일값.
- ⭐ 검산: `sum(COGS) = 35,957.0601` = `Invoice.TotalBeforeTax 26,073.79 × 1.37905 = 35,957.06` — 소수점까지 일치. ⇒ **COGS 는 환율·할인이 반영된 CAD 확정값.** 우리가 환산·배분 계산을 할 필요가 없다.
- `Invoice.AdditionalCharges`: Co-op 4% `-1086.41` · `Account="_59_"`(재고). `Invoice.Lines` 합 27,160.20 − 1,086.41 = `TotalBeforeTax` 26,073.79. ⇒ **이미 COGS 에 녹아 있다** — 따로 더하면 이중 계상.
- `Tax = 0`(`Zero-rated (Purchase)`). 국내 매입은 HST 13% 만큼 `Total` 과 `TotalBeforeTax` 가 어긋난다(`PO-00967` 전례) — `TotalBeforeTax` 를 쓴다.

### 2-d. I&R 이 없다 — 단일 태스크 구조 [실측]
- `InvoicingAndReceivingNumber`: Invoice · SR · CreditNote · ManualJournals · 최상위 **전부 `none`.** SR/Invoice 블록에 `TaskID` 자체가 없다.
- **`IM[0].TaskID` = PO ID**(Advanced 는 하위 태스크 GUID). ⇒ 회차 개념이 없다.

### 2-e. Order.Lines 는 다른 것 [실측]
- `Order.Lines` 52라인 9,840개 ≠ SR/Invoice 47라인 9,192개 — 백오더 5라인 648개. 오더 축으로 기대치를 잡으면 **전부 가짜 결손**(`PO-01068` Advanced 전례와 같은 계열). Simple 은 오더 라인이 `d.Lines` 가 아니라 `d.Order.Lines` 다.

### 2-f. ManualJournals [실측]
- `ManualJournals.Lines` 는 **배열**(len 1 · 키 `Reference, Amount, Date, Debit, Credit, IsSystem`). `IsSystem = [true]` 하나(Stock in Transit 35,957.06). ⇒ **landed 대상 0건.** 현행 코드(`Array.isArray(det.ManualJournals.Lines)`)가 그대로 읽는다.
- ⚠️ 「운임 없음」이 아니라 **「북키퍼가 아직 `Expense` 로 링크하지 않았다」**다 [Caleb 확인]. 링크되면 `LastUpdatedDate` 갱신 → 재수집 → landed 추가. **소급 입력 구조가 실제로 도는지의 첫 시험**이 된다(⬜).

### 2-g. Service Purchase 는 라인이 없다 [실측 `PO-01268`]
- `Invoice.Lines` · `InventoryMovements` · `ManualJournals.Lines` **전부 빈 배열**, `TotalBeforeTax` 만 있다(695). 목록 `IsServiceOnly` 로 거르는 것이 맞다.
- 최상위 `SupplierCurrency`/`CurrencyRate` = CAD/1.0.

---

## 3. 표본 특정 — Simple 4건 중 진짜 결손은 1건

`purchaseList UpdatedSince=2026-09-07` [실측]:

| PO | Status | SR | Inv | 판정 |
|---|---|---|---|---|
| **PO-01215** | RECEIVED | **AUTHORISED** | AUTHORISED | ⚠️ 입고 완료 · **진짜 결손** |
| PO-01228 | ORDERED | NOT AVAILABLE | DRAFT | 입고 전 · 정상 |
| PO-01231 | INVOICED | NOT AVAILABLE | AUTHORISED | Invoice First · 입고 전 |
| PO-01274 | INVOICED | NOT AVAILABLE | AUTHORISED | Invoice First · 입고 전 |

(dry 시점에는 `PO-01275` 도 같은 입고 전 모양으로 하나 더 있었다.)
재고 수량 축은 영향 없음(원장 수량 정상 · ⑧ bin 대조 깨끗). **원가 층만 비어 있었다.**
⚠️ `PO-01133`(08-28)과 다르다 — 그때는 Convert 하면 다음 회차에 사라지는 자가 치유였다. **Simple 로 완료되면 스스로 사라지지 않고 영구 결손으로 남는다.**

---

## 4. 구현 판정 넷 (Caleb) — 근거와 기각한 안

**전제 — 자기검증 (b)(c) 의 비교 축 (코드 확인)**: (b) 는 라인별 `CardID` 대조가 아니라 **`ProductID` 별 수량 합** 대조(`srQtyByPid` vs `paQtyByPid` · `QTY_EPS 1e-6`), (c) 는 `(ProductID, Date)` 키의 양방향 존재 대조다. `CardID` 는 검증이 아니라 식별(`line_ref`)에만 쓰인다. ⇒ `Invoice.Lines`(`ProductID`·`Quantity` 있음 · `CardID` 없음)로 (b) 의 상대를 바꾸는 것은 **격을 낮추지 않는다.**

1. **(c′) 불일치 → A안 격리(`skip_check_failed`)** — 「IM 의 `(ProductID, Date)` 키 ⊇ SR 키」. PA↔SR 을 그대로 두면 Simple 에서는 SR↔자기 자신 항등식이 되어 검증이 아니게 된다. 이 방향(SR 에 있고 IM 에 없음 = 입고됐는데 COGS 없음)은 현행 `cost_kind` 판정이 못 보던 방향이고 `PO-01215` 결손의 모양 그대로다. 코드에 이 방향을 정상으로 취급하는 곳은 없다(`allocate()` 는 IM 키만 순회하므로 그런 SR 라인은 조용히 행 0개가 된다). 기각: B안(경고+부분 저장) — 부분 저장이 「처리됐다」와 「원가가 다 붙었다」를 갈라놓는다. 기각: 「SR 날짜 단일값」 검사 — Simple 분할 입고 가능성이 미확인이라 정상 문서를 막을 수 있다. 조건: fail 문구에 어긋난 키(`ProductID @ Date`)와 수량을 전부 남긴다.
2. **환율 부재 → 행 저장, 원화 3필드 null** — `Invoice.CurrencyRate` 우선 · 최상위 `CurrencyRate` 폴백 · 둘 다 없으면 **null**(종전 `?? 0` 은 `fx_rate=0` 을 조용히 저장했다 — Advanced 에도 열려 있던 구멍 · 현재 오염 0행). `amount`·`unit_cost` 는 COGS 에서 나와 정확하므로 문서를 버리지 않는다. 조건: `fx_rate_missing` 카운터가 summary 에 실린다(창구 없이 비우면 `fx_rate=0` 과 같은 성질). 기각: 문서 스킵 — 정확한 원가까지 버린다.
3. **소급 경로 → `?recheck_since=YYYY-MM-DD` 신설** — `PO-01215` 는 이미 커서 아래(`LastUpdatedDate 2026-09-08T20:37Z` < 커서 `2026-09-09T04:33Z`)라 평시 회차로는 영영 안 들어온다. `from_since` 는 커서가 있으면 무시되고 정밀도 필터가 커서 아래를 거른다. 신설 파라미터는 목록 `UpdatedSince` 를 그 날짜로 쓰고 정밀도 필터를 그 회차만 끈다. 커서는 뒤로 가지 않는다(비캡 = 회차 시작 시각으로 전진 · 캡 = 제자리). `summary.recheck_since` 에 값이 남는다. 기각: 수동 커서 되감기 — 결함 C·D 계열 사고 지점이고 **되감은 사실이 회차 로그에 남지 않는다**(「사건을 남긴다」 위반).
4. **`raw.axis` · `simple_docs` 추가** — `raw.axis`(`"stock_received"` / `"putaway"`)는 「이 행이 어느 블록에서 왔나」를 되짚는 유일한 수단이고 원가는 소급 재구성이 어려운 축이라 지금 담는다. `simple_docs` 가 없으면 Simple 이 돌았는지 summary 에서 알 수 없다 — 진단 없는 경로는 조용히 죽는다.

**dry 에서 드러난 문제 1건 → `skip_not_received`** (커밋 `1c8483e`): 입고 전 문서 4건(SR=NOT AVAILABLE · 라인 0)이 (b′) 에서 「SR 0 vs INV n」으로 전부 격리·경고됐다. 이것은 불일치가 아니라 「아직 입고 안 됨」이고, 그대로 두면 입고까지 매일 경고 4건(「기준선 3을 외운다」 모양). 조건 **SR 수량 합 0 그리고 IM 0** 이면 경고 없이 `dispositions.skip_not_received` 로만 센다. IM 이 있는데 SR 이 0 이면 빠지지 않고 (b′) 가 격리한다(입고 전에 COGS 가 생긴 이상 상태). 📌 Advanced 는 같은 상황을 `processed`(행 0)로 조용히 넘긴다 — 새 어휘를 둔 이유는 「처리했는데 행 0」과 「처리 대상이 아님」이 다른 상태라서다. Advanced 는 건드리지 않았다(테스트 ㉗ 이 가드).

---

## 5. 검증 결과 (배포 후 · Caleb 실행)

| 항목 | 결과 |
|---|---|
| `PO-01215` 재수집(`?since=2026-08-20&recheck_since=2026-09-07`) | `inv_cost` **47행** · `sum(amount) = 35,957.06` |
| `raw.axis` | `stock_received` |
| `fx_rate` · `currency_orig` | 1.37905 · USD · `amount_orig` 채워짐 |
| bins | 18 |
| 아침 점검 ⑥ | **0행** 복귀(5키 조인 실증) |
| Advanced 회귀 | 6문서 행수·금액 무변(74 / 100 / 36 / 78 / 21 / 1) |
| dispositions | `skip_not_received 4` · `skip_check_failed 0` · `INV/SR qty mismatch` 경고 0 |
| 테스트 | `scripts/test-invcost.mjs` 27개 통과 · `deno check` 통과 |

📌 `amount_orig` 합은 **27,160.20**(할인 전 라인 합)이고 `amount` 합은 35,957.06(할인·환율 반영 CAD)이다. 두 축은 다른 것을 담는다 — 재계산 항등식 `amount = (amount_orig ÷ lines_total_all) × net_total × fx_rate` 로 연결된다.

---

## 6. ⚠️ 내가 틀린 것 (같은 실수 반복 금지)

1. 「(b)(c) 가 라인별 `CardID` 대조일 수 있으니 격을 낮춰야 할지도」 → 실제로는 이미 `ProductID` 합 대조여서 **격 유지로 대체 가능**했다. 근거 없이 걱정했다 — 코드를 먼저 읽었어야 했다.
2. 「`fx_rate` 구멍은 `inv_layer` 와 시점이 겹친다」 → 레이어 스키마에 통화 컬럼이 **아예 없어** 영향 없었다. 확인 전에 긴급도를 올렸다.
3. 「`?recheck=1` 로 소급되는지 확인할 것」 → `inv-cost` 에 그 파라미터가 **없다.** 원장 수집(`inv-collect`) 축의 항목을 잘못 이전했다.
4. `landed` 를 `ManualJournals` 에서 오는 것으로 가정하고 SQL 을 썼다 → 실제로는 `InventoryMovements` 에서 온다(`raw.alloc.mj_user_lines` 12문서 전부 빈 배열).
5. `inv_cost` 에 `created_at` 이 있다고 가정 → 실제 컬럼은 `refreshed_at`.
6. `amount_orig` 를 26,073.79 로 예상 → 실제 27,160.20(할인 전 라인 합).
7. (구현 중) 「SR 0 + IM 있음」이 landed 배분 실패 경로로 드러난다고 단언해 테스트가 깨졌다 → 실제로는 (b′) 가 먼저 잡는다. 결과는 같았지만 경로를 확인 없이 적었다.

---

## 7. 별건 대기 (기록만 · 이번에 처리하지 않음)

1. ⬜ **`PO-01120` `warn_merged_landed` 규명** — 차액 **695** 가 `PO-01268`(Service Purchase) 금액 695 와 정확히 일치. 둘 다 CAD 라 통화 문제가 아니고 「Service 인보이스가 PO 의 goods IM 에 병합됐다」는 가설과 부합 ⇒ 북키퍼의 `Expense` 링크와 같은 축일 가능성 — **[추론] 미확인.**
2. ⬜ **Simple 의 `landed` 경로** — 표본 대기(§2-f).
3. ⬜ **테스트 프로젝트(Asung-IMS) `inv-cost` 정지** — [실측] Cin7 secret 이 없다(`SUPABASE_DB_URL` 하나뿐) ⇒ 배포해도 첫 호출에서 죽는다. `last_run` 09-08 00:33 · `latest_cost_date 2026-09-03` · 922행(운영 1,006). 「운영 변경이 테스트로 흐른다」 원칙에서 이미 갈라져 있다. ⬜ 언제 어떻게 맞출지 미결정.
4. ⬜ **⑦-b `missing_lines_unkeyed` 3 → 0** — [09-09 아침 실측] 0행. 종전 기준선은 `ST-01283` 로 인한 3. ⚠️ 원인 미확인(원장 옛 행 정리 또는 collector 동작 변화). 판정은 ⑫ 가 하므로 영향 없음. 「기준선 3을 외운다」가 실제로 사라진 것이면 ⑦-b 정리(원장 스킬 대기열 1번 남은 항목)의 근거.
5. ⬜ **`inv_layer_cost_add` 0행 · 채우는 함수 미착수** — `PO-01215` 47행이 들어왔으므로 레이어 적재의 **첫 실물 후보**(PO + 원가 쪽 판단).
6. ⚠️ **`x-wms-cron-key` 가 대화에 평문 노출됐다**(`477179e8…`) — 교체 검토 항목. 지금 당장의 위험은 낮으나 기록해 둔다.
