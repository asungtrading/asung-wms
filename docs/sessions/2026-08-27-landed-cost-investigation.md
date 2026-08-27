# 2026-08-27 — 원가(landed cost) 조사: Cin7 이 COGS 를 만드는 방식

⑤ 원가 단계 착수 전 조사. **구현은 하지 않았다** — 이 문서는 조사 결과와 설계 판단이다.

⚠️ **다시 조사하지 말 것.** 아래는 전부 GAS 프로브 실측이고 산술이 소수점 6자리까지 닫혔다.
표본 6건(`PO-00943` · `PO-01130` · `PO-00799` · `PO-01085` · `PO-00853` · `PO-00005` 계열).

방향 정본: `docs/design/ims-principles.md` — **Cin7 없이 독립 작동**이 전제다.
이 문서가 기술하는 것은 **「Cin7 이 지금 어떻게 하는가」**이지 「우리가 어떻게 할 것인가」가 아니다.
shadow 단계의 원칙은 **Cin7 과 같은 값을 담는 것**이다(§7).

---

## 1. 엔드포인트

```
GET /ExternalApi/v2/advanced-purchase?ID=<purchaseList 의 ID>
```

⚠️ **`/purchase` 는 Advanced·Service Purchase 를 지원하지 않는다** —
`"This endpoint is deprecated and does not support Advanced Purchase and Service Purchase"`.
⚠️ 파라미터는 **`ID`** 다. `TaskID` 는 `"Purchase Task with specified ID not found"`.

**응답 최상위 키** (실측)
```
ID, SupplierID, Supplier, Contact, Phone, InventoryAccount, BlindReceipt, Approach,
BillingAddress, ShippingAddress, BaseCurrency, SupplierCurrency, TaxRule, TaxCalculation,
Terms, RequiredBy, Location, Note, OrderNumber, Type, CombinedInvoiceStatus,
CombinedReceivingStatus, CombinedPaymentStatus, IsServiceOnly, OrderDate, Status,
RelatedDropShipSaleTask, CurrencyRate, LastUpdatedDate,
Order, StockReceived, PutAway, Invoice, CreditNote, ManualJournals,
AdditionalAttributes, Attachments, InventoryMovements
```

⚠️ **`Invoice`·`StockReceived`·`PutAway` 는 배열이다.** `[0]` 만 보면 틀린다 —
`PO-01130` 은 Invoice 2 · SR 2 · PutAway 2 였고, `[0]` 만 보다가 숫자가 안 닫혀 헤맸다.

---

## 2. ⭐ `InventoryMovements` 가 원가의 원천

**수량 장부가 아니라 가치 장부다.** 필드는 `TaskID · ProductID · Date · COGS` + 제품 속성뿐 —
**수량도 SKU 도 bin 도 없다.**

「이 제품에 이 날짜로 재고 가치가 얼마 늘었다」만 말한다.

### 행이 여러 벌인 이유 — 비용 종류마다 한 벌

`PO-00853` (35개 제품):
```
6/15 · 6/16   35행   상품가        합 31,699.72   ← 입고일(SR 날짜와 일치)
6/12          35행   통관비 배분    합     90.00   ← service 인보이스 날짜
              ─────
              70행                    31,789.72
```

⇒ **`IM 행 수 = 제품 수 × (1 + 비용 건수)`**.
⚠️ 비용 행은 **SR 이 없는 날짜**에 뜬다(입고보다 앞설 수 있다).

---

## 3. ⭐⭐ 산술 — 전부 실측 검산(소수점 6자리)

### 3-a. 상품가

```
Stock in Transit(MJ, IsSystem=true) = Invoice.Total × Invoice.CurrencyRate
라인 COGS                            = Invoice 라인 Total × CurrencyRate
```

| PO | 검산 |
|---|---|
| `PO-00943` | 17,897.05 × 1.42358 = **25,477.88** = MJ ✅ |
| `PO-00799` | (14,221.22 − 335) × 1.37488 = **19,091.89** = MJ ✅ |
| `PO-00853` | 22,718.44 × 1.39533 = **31,699.72** = MJ ✅ |
| `PO-01085` | 34,883.74 × 1.40131 = **48,882.93** = MJ ✅ |
| `PO-01130` | 152.17 + 11,304.84 = **11,457.01** = COGS 합 ✅ (인보이스 2건, 환율 각각) |

⚠️⚠️ **환율은 `Invoice[].CurrencyRate` 다 — 헤더 `CurrencyRate` 가 아니다.**
`PO-01130` 은 회차별로 **1.40275 / 1.39342** 로 갈렸다. 헤더 값(1.39342)만 쓰면 틀린다.

### 3-b. 비용 배분 — **금액 비례** (수량·무게 아님)

```
분모 = Invoice.Lines 총합 (⚠️ AdditionalCharges 반영 **전**)
라인 배분액 = 비용 × (라인 Total ÷ 분모)
```

| 검산 | 계산 | IM 실측 |
|---|---|---|
| `PO-00799` `BIG02001` | 91.25 × (473.76 ÷ 13,886.22) = **3.113201** | 3.113201 ✅ |
| `PO-00853` `AMP41248` | 90 × (868.68 ÷ 28,503.19) = **2.742893** | 2.742892 ✅ |
| `PO-00853` `AMP41248` 상품 | (868.68÷28,503.19) × 22,718.44 × 1.39533 = **966.0994** | 966.0993572 ✅ |
| `PO-01085` `AMP41340` | (1,182.48÷45,793.32) × 34,883.74 × 1.40131 = **1,262.2603** | 1,262.2603349 ✅ |

📌 `ProductWeight` 필드가 있는데도 **무게는 쓰지 않는다.**
📌 Caleb 의 실무 감각(「금액과 수량이 혼합되어야」)과 **Cin7 동작이 다르다** — 혼합 배분은
하드 플립 후에 바꿀 후보다(§7 3단계).

---

## 4. ⚠️ 비용이 들어오는 **두 경로** — `Account` 가 재고 여부를 가른다

### 경로 ①: `Invoice[].AdditionalCharges`

서플라이어 인보이스에 얹힌 줄. **계정에 따라 재고에 들어가거나 안 들어간다.**

| 항목 | `Account` | 재고로? | 표본 |
|---|---|---|---|
| Discount (Volume DC, **음수**) | `_59_` | ✅ | `PO-01085` −10,909.58 · `PO-00853` −5,784.75 · `PO-00010` −612.61 |
| Rounding | `_59_` | ✅ | `PO-00003` |
| **Freight Purchase** | **`_95_`** | ❌ | `PO-00799` 335 · `PO-00005` 826.66 |
| **Commission** | **`_95_`** | ❌ | `PO-00005` 638.43 |

⇒ **`_59_` = 재고 계정**(MJ 의 `Debit` 이 항상 `_59_`). 그 외는 손익으로 빠진다.

⚠️ **`Order.AdditionalCharges` 에는 `Account` 필드가 없다.** 같은 비용이 두 곳에 있지만
계정 정보는 **`Invoice` 쪽에만** 있다 ⇒ **원가 판정은 반드시 `Invoice[].AdditionalCharges` 로.**

### 경로 ②: `ManualJournals` 의 `IsSystem=false` 줄

**Service Purchase 문서가 merge 된 흔적**이다. 항상 `Debit=_59_` ⇒ **항상 재고에 들어간다.**

```
SYS   {Reference:"Stock in Transit", IsSystem:true}   ← 상품가 (Cin7 생성)
SYS   {Reference:"Inventory discrepancy correction"}  ← CN 정정 (Cin7 생성)
⭐USER {Reference:"16667", Amount:90, IsSystem:false}  ← 통관사 인보이스
```

### ⚠️ 그래서 같은 성격의 비용이 갈린다 — 확인 필요

```
서플라이어 인보이스의 Freight   → _95_ → 비용 처리  ❌ 재고 안 들어감
포워더·통관사 인보이스(경로 ②)  → _59_ → 재고       ✅
```

`PO-00799` 기준 **460.58 CAD(재고 원가의 2.4%)** 가 그렇게 빠졌다.
⚠️ **의도인지 데이터로는 알 수 없다** — 회계 판단 영역. 6개월 간격 두 표본에서 같은 동작이므로
실수가 아니라 **패턴**이다. ⬜ **회계 담당자 확인 대기.**

---

## 5. ⭐ Service Purchase — 별개 문서, 단방향 연결

`Type = "Service Purchase"` · `IsServiceOnly = true` · **`InventoryMovements` 0건**
(자기 자신은 재고를 안 움직인다). 최근 100건 중 **7건**.

공급자: BBE Customs Brokers · CBSA · Showtime Freight Services

### 연결은 한 방향뿐

```
Service Purchase 문서
    │  ⚠️ 자기가 어느 PO 에 붙었는지 **모른다** (연결 필드 없음 · RelatedDropShipSaleTask=null)
    ▼
Advanced PO 의 ManualJournals[].Reference = service 인보이스 번호   ← 유일한 다리(문자열)
    ▼
InventoryMovements 의 배분된 COGS 행
```

⇒ ⚠️⚠️ **원가 수집은 반드시 Advanced PO 축에서.** Service Purchase 를 따로 수집하면
어디에 붙일지 알 수 없다.
📌 다행히 **`Reference` 를 볼 필요조차 없다** — IM 에 이미 배분된 값이 있다. `Reference` 는
사람이 추적할 때만 쓴다.

### 금액 관계 — **MJ 금액 = service 인보이스의 세전액**

| service 인보이스 | 붙은 PO | MJ | ×1.13 | 인보이스 |
|---|---|---|---|---|
| 16667 | PO-00853 | 90.00 | 101.70 | 101.70 ✅ |
| 16608 | PO-00799 | 91.25 | 103.11 | 103.11 ✅ |
| 16101 | PO-00005 | 83.75 (3줄 합) | 94.64 | 94.64 ✅ |
| 16104 | PO-00009 | 80.00 (2줄 합) | 90.40 | 90.40 ✅ |

⇒ **HST 13% 는 재고 원가에 안 들어간다**(매입세액).
⇒ **한 service 인보이스가 한 PO 안에서 여러 MJ 줄로 쪼개질 수 있다.**

⚠️ **그리고 여러 PO 에 걸칠 수 있다**: CBSA `10039192301744` 는 인보이스 7,376.42 인데
`PO-00005` 에 붙은 것은 **4,207.55** 뿐이다(나머지는 다른 PO). 관세는 컨테이너 단위라 자연스럽다.

---

## 6. ⭐ 원가를 원장 행에 잇는 경로 — **사슬이 완성됐다**

```
InventoryMovements   제품 × 날짜 × COGS
        ↕  (ProductID, Date) 로 매칭 — [실측] 1:1
StockReceived.Lines  제품 × 날짜 × 수량
        ↕
PutAway.Lines        + Location/LocationID(bin) + **CardID**
                                                     ↕
원장 발주 행          line_ref = CardID · bin
```

**[실측 `PO-00853`]** SR 35 = PA 35 = IM(상품) 35 · **bin 분할 0건 · PA날짜≠SR날짜 0건 ·
수량 불일치 0건**. IM 만 있는 키 35건 = 비용 행(6/12).

### 계산식

```
단위원가     = IM.COGS ÷ SR.Quantity          (같은 ProductID·Date)
원장 행 원가 = 단위원가 × PutAway 라인.Quantity  (bin·CardID 단위)
```

⚠️ **`PO-00853` 은 bin 분할 0건인 「깨끗한」 표본이다.** `inv-collect` 주석의 실측대로
**PA 는 같은 SKU 를 빈 단위로 쪼개 여러 줄로 담을 수 있다** — 그때는 수량 비례로 나눈다.
공식은 그대로 성립한다.

⚠️⚠️ **bin 은 `PutAway` 에만 있다.** `StockReceived.Lines` 의 `Location` 은 **전부 null** 이다.
[2026-08-27] 그것을 보고 「원가는 bin 을 모른다」고 결론냈다가 **Caleb 이 Cin7 Put away 화면을
보여줘서** 정정됐다 — 「화면에 보이는데 API 에 없어 보이면 API 를 덜 본 것」의 재현이다.

---

## 7. ⭐ 설계 판단 — **(가) Cin7 그대로 담는다** [Caleb 확정 2026-08-27]

비용 사건을 어떻게 담을 것인가:

| | 방식 | 판정 |
|---|---|---|
| **(가)** | 비용을 **별도 사건**으로, **Cin7 이 준 날짜 그대로** | ✅ **채택** |
| (나) | 입고 사건에 합쳐 입고일로 끌어옴 | ❌ |

**근거**
- shadow 단계의 원칙은 **「Cin7 과 같은 값을 담는다」** — (나)는 날짜가 달라 대조가 어긋난다
- ⭐ **되돌릴 수 없다**: 합쳐버리면 원본이 사라진다. (가)→(나)는 나중에 가능하지만 역은 불가능
- ⭐ **Cin7 도 append 형태다** — 기존 상품 COGS 를 고쳐 쓰지 않고 **새 IM 행을 추가**한다
  ([실측 `PO-00799`] 5/25 상품 651.3631 = 라인×환율 그대로, 비용은 5/21 에 별도 행 3.1132)
  ⇒ **원장의 append-only 와 구조가 같다.** 소급 정정을 어떻게 할지 고민할 필요가 없다

### ⚠️ 다만 날짜가 과거로 찍힌다

```
PO-00799  비용 날짜 5/21 · 입고 5/25 · LastUpdated 6/25
PO-00943  비용 날짜 6/27 · 입고 6/29 · LastUpdated 8/20
PO-00853  비용 날짜 6/12 · 입고 6/15·16 · LastUpdated 7/21
```

비용은 **한 달 뒤에 입력**되는데 날짜는 **인보이스 날짜로 소급**된다.
📌 스킬의 **「`UpdatedSince` 와 이벤트 날짜는 독립 축」**이 그대로 적용된다 — 문서는 갱신 축으로
다시 오지만 **사건 날짜는 이미 지난 기간**이다. ⚠️ **`since` 필터가 그것을 버릴 수 있다.**

---

## 8. ⬜ 남은 것

| | |
|---|---|
| ⬜ **freight 계정 정책** | `_95_` 로 빠지는 것이 의도인지 회계 확인 (§4) |
| ⬜ **`since` 경계** | 소급된 비용 사건이 `since` 에 걸려 유실되지 않는가 (§7) |
| ⬜ **bin 분할 PO 실측** | `PO-00853` 은 분할 0건 — 분할되는 표본으로 수량 비례 검증 필요 |
| ⬜ **Simple Purchase** | 조사는 전부 Advanced 였다. Simple 은 축이 다르다(`StockReceived`) |
| ⬜ **CN 의 원가 영향** | `PO-01130` 의 "Inventory discrepancy correction" 175.74 — 순증 0 이었으나 일반 규칙 미확인 |
| 👁 **MJ Status** | `AUTHORISED`/`DRAFT`/`NOT AVAILABLE` 셋 다 관측. **DRAFT 여도 COGS 는 나온다**(`PO-01085`) ⇒ MJ status 로 게이트를 걸면 안 된다 |
| ⬜ **FIFO 레이어** | 이번 범위 밖. 담는 방식만 정했고 계산은 다음 단계 |

---

## 9. 📌 조사 중 틀렸던 것 (기록 규칙)

1. **`/purchase?ID=`** 로 시작했다 — Advanced 미지원. 에러 본문을 안 찍게 짜서 한 번 더 헤맸다
   ⇒ **프로브는 처음부터 에러 본문을 찍게 짤 것.**
2. **`Invoice[0]`·`StockReceived[0]` 만 봤다** — 배열인데 첫 원소만 보고 「숫자가 안 닫힌다」고 했다.
   `PO-01130` 의 8/18 미스터리가 그것이었다.
3. **「`AdditionalCharges` 는 landed cost 와 무관」** — 앞선 두 PO 가 우연히 비었을 뿐이었다.
4. **「MJ 합계 = COGS 합계」** — `PO-00943` 표본 하나로 만든 규칙이 `PO-01130` 에서 바로 깨졌다.
   ⇒ **표본 하나로 규칙을 만들지 말 것**의 실사례.
5. **「원가는 bin 을 모른다」** — `StockReceived` 만 보고 내린 결론. bin 은 `PutAway` 에 있었다.
   **Caleb 이 화면을 보여줘서** 정정됐다(§6).
6. **스캔 프로브가 `Order.AdditionalCharges` 를 섞어 세서** `Account: undefined` 3건을
   「⚠️ 재고 아님」으로 오탐했다. 그 배열에는 `Account` 필드 자체가 없다.
7. **`OrderBy=OrderDate desc` 가 무시됐다** — 2025년 10~11월 PO 가 나왔다. 파라미터를 추측했다.

📌 관통하는 패턴: **응답의 일부만 보고 「없다」고 결론냈다**(2·3·5). 스킬에 이미 있는 항목인데
같은 세션에서 세 번 반복했다.
