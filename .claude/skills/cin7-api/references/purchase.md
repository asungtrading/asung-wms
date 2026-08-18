# Purchase 엔드포인트 레퍼런스

## Purchase List — GET /purchaseList

발주 목록 빠른 조회. Simple/Advanced PO 모두 포함.

### ⚠️ 필터·페이징 실측 (2026-07-28 — WMS 리시빙 PO 목록. 추측 금지)

Asung 계정 실측(당시 `InvoiceStatus=PAID` Total **825**). "최신 PO 가 목록에 안 뜬다"로 여러 번 헤맨 항목들:

| 항목 | 실측 결과 |
|------|-----------|
| **`InvoiceStatus`** | **단일 값만 받는다** — `AUTHORISED` 와 `PAID` 를 **각각 호출해 ID 로 dedup 병합**해야 한다. 실측: PO-01081(InvoiceStatus=**PAID**, 입고 전)이 AUTHORISED 단일 조회에서 **Total 0** 으로 아예 안 나왔다. Invoice First 워크플로에서 PAID 는 승인 **이후** 단계라 리시빙 자격을 잃지 않는다. |
| **`Limit`** | **`Limit=1000` 이 동작한다.** page1 에 825건 전부(PO-00004~PO-01081), page2 는 0건. 기본 100 으로 3페이지(=300건)만 읽으면 **최신 PO 를 통째로 못 읽는다.** |
| **기본 정렬** | **PO 번호 오름차순** — page1 = PO-00004…, **최신 PO 는 마지막 페이지**(Limit=100 이면 PO-01081 이 Page 9). ⚠️ "최근 것부터 온다"고 가정하면 안 된다. |
| **`UpdatedSince`** | 동작은 한다(30일 124건 / 60일 249 / 90일 331). ⚠️ **하지만 최신성을 보장하지 못한다** — 지불 처리로 **옛 PO 가 갱신**되므로 60일 창의 page1 도 PO-00004 부터 시작한다. 날짜 창 + 페이지 상한 조합은 최신 PO 누락으로 이어진다. |
| ~~**`RestockReceivedStatus`**~~ | ⚠️⚠️ **이 행은 틀린 기록이었다 — 2026-08-04 정정.** 아래 「파라미터 이름 오타」 절 참조. |
| **`Status`** | **복합 문자열**("RECEIVED / CREDITED") 가능 → 정확 일치 말고 `includes` 로 검사. |
| **`Type`** | `"Service"`(운송·관세 — 물건 없음) 존재 → 리시빙 목록에서 제외. |

### ⚠️⚠️ 정정 — 파라미터 이름 오타였다 (2026-08-04)

7/28 에 *"Cin7 이 `StockReceivedStatus` 서버 필터를 무시한다(`NOT AVAILABLE`·`DRAFT` 모두 Total 825 = 무필터와 동일)"* 로 적었다. **틀렸다.** 실제로 보낸 파라미터 이름은 **존재하지 않는 `RestockReceivedStatus`** 였고(위 파라미터 표의 오래된 항목명을 그대로 베꼈다) Cin7 이 **모르는 파라미터를 조용히 무시**한 것이다.

2026-08-04 실측 — 같은 계정, 같은 시점:

| 보낸 것 | Total |
|---|---|
| `StockReceivedStatus=NOT AVAILABLE` | **585 — 동작한다** |
| `RestockReceivedStatus=NOT AVAILABLE` | 877 (= 무필터, 무시됨) |

이 오기록 때문에 **"서버 필터는 불가능하다" 는 결론이 일주일간 유지**되며 전량 조회 + 클라이언트 필터 구조를 계속 짊어졌다.

📌 **교훈 — 파라미터가 무시되는 것처럼 보이면 이름 오타를 먼저 의심하라.** Cin7 은 모르는 파라미터를 조용히 무시하므로 응답만으로는 **"오타" 와 "미지원" 이 구별되지 않는다**(둘 다 무필터와 같은 Total). 검증 순서:
1. 이 `references/` 의 정확한 스펠링과 대조한다(⚠️ 아래 파라미터 표는 apib 원문 표기이고, 실제 응답 필드명은 `StockReceivedStatus` 다 — **표의 이름과 응답의 이름이 다를 수 있다**).
2. **동작을 아는 파라미터**(`Status=INVOICED` 등)를 같이 보내 배선이 살아 있음을 확인한다.
3. 그래도 Total 이 안 변하면 그때 "미지원" 으로 기록한다.

**HTTP 200 은 파라미터를 받아들였다는 뜻이 아니다** — 쓰기 쪽의 "검증은 되읽기로"(`stock-write.md` 2절, 완료 PUT 의 `TransferQuantity` 무시) 와 같은 계열의 함정이다.

### 서버 필터 실측 표 (2026-08-04 — 전체 PO 1,129건 시점)

| 파라미터 | 결과 |
|---|---|
| `Status=INVOICED` | Total **73 — 동작** |
| `Status=RECEIVING` | Total **5 — 동작** |
| `Status=INVOICED,RECEIVING` / `INVOICED\|RECEIVING` | Total **0 — 여러 값 동시 요청 불가** → 상태별 개별 호출 + `ID` 기준 dedup |
| `StockReceivedStatus=NOT AVAILABLE` | Total **585 — 동작** |
| `Type=Simple Purchase` / `Advanced Purchase` / `Service Purchase` | 585 그대로 — **무시됨** → Service 제외는 클라이언트에서 |
| `InvoiceStatus=PAID` | 877 |
| `InvoiceStatus=PAID` + `Status=INVOICED` | **1** (AND 로 결합된다) |

**전체 PO 1,129건의 `Status` 분포**: COMPLETED 768 · RECEIVED 95 · VOIDED 89 · INVOICED 24 · ORDERING 8 · **RECEIVED / CREDITED 6** · CREDITED 4 · ORDERED 3 · RECEIVING 2 · **COMPLETED / CREDIT NOTE CLOSED 1**
⚠️ **복합 상태가 실재한다** → 클라이언트 제외 검사는 반드시 `includes` 로 할 것(정확 일치는 새는 원인).

📌 **`InvoiceStatus` 로 좁히지 말고 `Status` 로 좁혀라 (WMS 리시빙에서 얻은 교훈).** `InvoiceStatus=PAID` 는 창업 이후 지불을 마친 **모든** PO(877건)를 돌려주는데 그중 리시빙 대상은 **0건**이었다 — 전량을 긁어 클라이언트에서 버리는 구조라 PO 가 쌓이면 언젠가 페이지 상한에 닿고, **기본 정렬이 오름차순이라 잘리는 쪽은 항상 최신 PO** 다. `Status` 는 문서가 완료되면 `COMPLETED` 로 빠지므로 **데이터가 쌓여도 조회량이 늘지 않는다.** 실측 전환 효과: **973행 → 78행**(대상 8건은 동일 — 배포 전후 diff 로 확인).

⚠️ **`Limit` 을 바꿀 때 조기 종료 조건도 같은 상수로 바꿀 것** — 마지막 페이지 판정은 `items.length < Limit` 이다. 요청 Limit(100)보다 **큰 값**으로 비교하면(`< 1000`) 꽉 찬 페이지도 "마지막"으로 보여 **첫 페이지에서 루프가 끊긴다**. 두 곳에 상수를 따로 쓰지 말고 하나(`PO_PAGE_LIMIT`)를 공유한다.

📌 **상한에 걸린 사실은 응답에 진단 필드로 노출할 것** — WMS EF 는 `scanned`(상태별 가져온 행 수 예 `{AUTHORISED:n, PAID:825}`) + `truncated`(더 있는데 못 읽음) 를 싣는다. 이게 없어서 "왜 안 뜨는가"에 왕복이 여러 번 걸렸다.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `Search` | string | OrderNumber, Supplier, InvoiceNumber에서 검색 |
| `UpdatedSince` | DateTime | 이 날짜 이후 수정된 건 (ISO 8601) |
| `UpdatedUntil` | DateTime | 이 날짜 이전 수정된 건 |
| `RequiredBy` | DateTime | RequiredBy가 이 날짜 이전인 건 |
| `OrderStatus` | string | DRAFT, AUTHORISED, VOIDED, NOT AVAILABLE |
| `RestockReceivedStatus` | string | ⚠️ **apib 원문 표기이지만 서버가 무시한다** — 실제로 동작하는 이름은 **`StockReceivedStatus`**(응답 필드명과 같다). 위 정정 절 참조. |
| `StockReceivedStatus` | string | 입고 상태 필터 — **동작 확인됨**(`NOT AVAILABLE`/`AUTHORISED`). 값은 응답의 `StockReceivedStatus` 와 같은 어휘. |
| `InvoiceStatus` | string | 인보이스 상태 필터 — **단일 값만**(AUTHORISED/PAID 는 2회 호출 병합) |
| `Status` | string | 전체 Purchase 상태 (아래 참고) — **단일 값만**(콤마·파이프로 여러 값 = Total 0) |

### Purchase 상태 목록
`DRAFT`, `VOIDED`, `ORDERING`, `ORDERED`, `RECEIVING`, `RECEIVED`, `INVOICED`, `CREDITED`, `COMPLETED`, `PARTIALLY INVOICED`

### 응답 구조
```json
{
  "Total": 50,
  "Page": 1,
  "PurchaseList": [
    {
      "ID": "guid",
      "OrderNumber": "PO-00026",
      "Status": "COMPLETED",
      "OrderDate": "2024-01-15T00:00:00",
      "InvoiceDate": "2024-01-20T00:00:00",
      "Supplier": "공급업체명",
      "SupplierID": "guid",
      "InvoiceNumber": "INV-SUP-001",
      "InvoiceAmount": 5000.00,
      "PaidAmount": 5000.00,
      "RequiredBy": "2024-02-01T00:00:00",
      "OrderStatus": "AUTHORISED",
      "StockReceivedStatus": "AUTHORISED",
      "InvoiceStatus": "AUTHORISED",
      "Type": "Simple Purchase",
      "LastUpdatedDate": "2024-01-20T00:00:00"
    }
  ]
}
```

---

## Purchase 상세 — GET /purchase (Simple)

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `ID` | Guid | **필수** — PurchaseList에서 얻은 ID |

### 응답 핵심 필드
```json
{
  "ID": "guid",
  "Supplier": "공급업체명",
  "OrderNumber": "PO-00026",
  "Status": "COMPLETED",
  "OrderDate": "2024-01-15T00:00:00",
  "Lines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "Name": "제품명",
      "Quantity": 100,
      "Price": 12.00,
      "Total": 1200.00,
      "ReceivedQuantity": 100,
      "InvoicedQuantity": 100
    }
  ]
}
```

⚠️⚠️ **정정 (2026-08-05 실측 덤프)** — 위 샘플의 **`InvoicedQuantity` 필드는 실계정 Order.Lines 응답에 없다**(apib 원문 표기일 뿐). 인보이스 수량이 필요하면 아래 「인보이스 블록 실측」의 `Invoice.Lines` 를 읽을 것 — Order 라인에서 읽으려 하지 말 것.

---

## ⚠️ 인보이스 블록 실측 (2026-08-05, GAS 직접 호출 — WMS 리시빙 기대치 전환의 근거)

PO 상세 응답 안에 인보이스가 **이미 들어 있다** — `/purchase/invoice` 추가 호출 불필요.

| | Simple `GET /purchase?ID=` | Advanced `GET /advanced-purchase?ID=` |
|---|---|---|
| `d.Invoice` | **객체** | **배열** (실측 len=1 — 다중 인보이스는 미실측) |
| 접근 | `d.Invoice` | `d.Invoice[0]` |

공용 접근자 (WMS EF `invoiceBlock()` — 타입 분기를 새로 만들지 말 것):
```javascript
const invBlock = Array.isArray(d.Invoice) ? d.Invoice[0] : d.Invoice;
```

- Advanced `Invoice[0]` keys: `TaskID, InvoicingAndReceivingNumber, InvoiceDate, InvoiceDueDate, InvoiceNumber, Status, CurrencyRate, Lines, AdditionalCharges, Payments, TotalBeforeTax, Tax, Total, Paid`
- Simple `Invoice` keys: `InvoiceDate, InvoiceDueDate, InvoiceNumber, Status, Lines, …`
- **라인 필드 (양쪽 동일): `SKU` · `Quantity` · `Price` · `Total` · `NonInventory`** — SKU 표기는 Order.Lines 와 동일
- `AdditionalCharges` 는 별도 배열 — Discount 류가 `Lines` 에 섞이지 않는다
- ⚠️⚠️ **`GET /purchase/invoice` 는 Advanced PO 에서 400** — `"deprecated and does not support Advanced Purchase"`. Simple 에선 동작하지만 deprecated 명시 — 신규 코드는 상세 응답의 Invoice 블록을 쓸 것 (WMS Apply 게이트도 2026-08-05 전환).
- 실측 예 **PO-01068 (Advanced)**: Order.Lines **92줄** / Invoice[0].Lines **77줄** — 빠진 15줄은 공장 백오더. `ORS11021` 오더 360 → 인보이스 **264** (수량도 다르다). 오더 라인으로 기대치를 잡으면 이 차이가 전부 가짜 discrepancy 가 된다.
- ⚠️ **리시빙 대상 PO 에 Advanced 가 실재한다**(PO-01068) — "Asung 발주는 전부 Simple" 로 가정하지 말 것.

---

## Advanced Purchase — GET /advanced-purchase

Advanced PO (복수 입고/인보이스)의 경우 별도 엔드포인트 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `ID` | Guid | **필수** — PurchaseList에서 얻은 ID (Type이 "Advanced Purchase"인 경우) |

**주의**: `PurchaseList`의 `Type` 필드로 Simple/Advanced 구분 후 적절한 엔드포인트 호출.

### ⚠️ 입고 블록 실측 — `PutAway` 가 확정 축 (2026-08-18 · 원장 수집 재설계의 근거)

Advanced 상세 응답의 입고는 **`StockReceived`(창고 도착)와 `PutAway`(선반 배치) 두 배열**이고,
둘은 **같은 입고의 두 표현**이다(15건 표본 srLines==paLines — 둘 다 읽으면 정확히 두 배).
**bin 이 있는 쪽은 `PutAway` 뿐** — SR 라인의 `LocationID` 는 null 이거나 **창고 GUID** 다
(SKILL.md 주의 13 ①의 쓰기 실측과 교차 검증). SR 의 `Status` 는 stock receiving 단계의
워크플로 상태라 재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED · 62줄 FULLY RECEIVED).

- **블록 필드**: `TaskID` · `InvoicingAndReceivingNumber` · `Status` · `Lines`
- **라인 필드**: `Date` · `Quantity` · `ProductID` · `SKU` · `Name` · `Location` · `LocationID` ·
  `Received` · `BatchSN` · `SupplierSKU` · `ExpiryDate` · `CardID` · 상품 치수/커스텀필드
- ⚠️ **SR 라인에만 `NonInventory` 가 있고 PA 라인엔 없다**(실측)
- ⚠️ **블록은 receiving 횟수가 아니라 I&R 그룹 단위다** — PO-00703: 화면 stock receiving 2건 ·
  API 블록 1개(분할 입고는 `Lines[].Date` 로 갈린다). SKILL.md 13번의 "TaskID = I&R 그룹" 과 동일 구조
- ⚠️ `CardID` = 라인 고유 식별자(같은 SKU 의 빈 분할·날짜 분리에도 유일 — PO-00944 실측
  97/97·110/110. `ProductID` 는 94/97 로 부족)
- `InventoryMovements` 는 **수량 축이 아니다** — `Quantity`·`LocationID` 가 없고 COGS·상품
  치수·커스텀필드뿐. 원가 레이어 작업에는 쓸 수 있다

### 목록(purchaseList) 응답 필드 보강 (2026-08-18)

- `CombinedReceivingStatus` — 실측 어휘: `FULLY RECEIVED` · `PARTIALLY RECEIVED` ·
  `NOT RECEIVED` · `NOT AVAILABLE`. ⚠️ 관측만 했고 **게이트로는 쓰지 않는다**
- ⚠️ 목록 `StockReceivedStatus` 는 상세 블록의 `Status` 와 **양방향으로 어긋난다**(상관없음 —
  PO-01131 목록 AUTHORISED/상세 NOT AVAILABLE ↔ PO-00848 반대). 후보 게이트로 쓰면 실재 입고가
  문서째 사라진다(표본 4건 12,552u)
- ⚠️ `Type` 은 **가변**이다 — Simple 로 발행된 PO 가 입고 후(대개 Apply 후 ~10분) Advanced 로
  전환된다(실측 12/12). 전환이 `LastUpdatedDate` 를 갱신한다

---

## Apps Script 예시 — Simple/Advanced 자동 감지 (PurchaseHistory.gs 패턴)

```javascript
function fetchPurchaseDetail(purchaseId, purchaseType) {
  const endpoint = purchaseType === 'Advanced Purchase' 
    ? 'advanced-purchase' 
    : 'purchase';
  
  Utilities.sleep(200);
  return cin7Get(endpoint, { ID: purchaseId });
}

function fetchAllPurchases(updatedSince) {
  const list = fetchAllPages('purchaseList', {
    UpdatedSince: updatedSince,
    Status: 'COMPLETED'
  });
  
  const results = [];
  for (const po of list) {
    const detail = fetchPurchaseDetail(po.ID, po.Type);
    for (const line of (detail.Lines || [])) {
      results.push({
        po_number: po.OrderNumber,
        supplier: po.Supplier,
        order_date: po.OrderDate,
        sku: line.SKU,
        product_name: line.Name,
        quantity: line.Quantity,
        unit_cost: line.Price
      });
    }
  }
  return results;
}
```
