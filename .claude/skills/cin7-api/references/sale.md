# Sale 엔드포인트 레퍼런스

## Sale List — GET /saleList

빠른 판매 목록 조회. 라인 아이템 없음.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100, 최대 100 |
| `Search` | string | OrderNumber, Customer, InvoiceNumber 등에서 검색 |
| `CreatedSince` | DateTime | 이 날짜 이후 생성된 건 (ISO 8601) |
| `UpdatedSince` | DateTime | 이 날짜 이후 수정된 건 (ISO 8601) |
| `UpdatedUntil` | DateTime | 이 날짜 이전 수정된 건 |
| `ShipBy` | DateTime | Ship By 날짜가 이 날짜 이전인 건 |
| `QuoteStatus` | string | DRAFT, AUTHORISED, VOIDED, NOT AVAILABLE |
| `OrderStatus` | string | DRAFT, AUTHORISED, VOIDED, NOT AVAILABLE, AUTH_NO_ALLOC, FULFILLED, CLOSED |
| `CombinedInvoiceStatus` | string | VOIDED, DRAFT, AUTHORISED, NOT AVAILABLE, PAID |
| `CombinedShippingStatus` | string | VOIDED, NOT AVAILABLE, SHIPPED, SHIPPING, NOT SHIPPED, PARTIALLY SHIPPED |
| `Status` | string | 전체 Sale 상태 (아래 상태 목록 참고) |
| `ExternalID` | string | 외부 커스텀 ID로 검색 |
| `OrderLocationID` | Guid | 특정 Location의 오더만 |

### Sale 상태 목록
`DRAFT`, `VOIDED`, `ESTIMATING`, `ESTIMATED`, `ORDERING`, `ORDERED`, `BACKORDERED`, `PICKING`, `PICKED`, `PACKING`, `PACKED`, `SHIPPING`, `INVOICING`, `INVOICED`, `CREDITED`, `COMPLETED`

### ⚠️ `OrderStatus` 와 `Status` 는 다른 축이다 (2026-08-04 실측)

`OrderStatus` = **오더 승인 상태**(DRAFT/AUTHORISED/…) · `Status` = **전체 문서 진행 상태**(ORDERED/PICKING/…). **둘은 독립이다.**

- **승인된 오더를 걸러내려면 `OrderStatus=AUTHORISED` 를 쓴다.** 그 오더의 `Status` 는 여전히 `ORDERED` 로 남아 있는 게 정상이며 — Simple/Advanced 둘 다 그렇다 — `Status` 가 `ORDERED` 라는 이유로 "승인 안 된 오더" 로 판단하면 안 된다. (Asung WMS 폴링 EF 가 `OrderStatus=AUTHORISED` 로 필터하는 이유. "Status 가 ORDERED 라서 안 들어오나?" 는 오해로, 2026-08-04 에 실측으로 배제됐다.)
- **`Type`(Simple/Advanced) 필터는 필요 없다** — Advanced Sale 도 `/sale` 상세의 `Order.Lines[]` 가 동일 구조로 오고 정상 처리된다(SO-14023 Advanced Sale 의 라인 15개가 Cin7 화면과 일치 확인). Advanced 는 Invoice/Fulfilment 를 **여럿** 가질 수 있다는 뜻이고 오더 라인 구조가 다르다는 뜻이 아니다.
- `AdditionalAttributes` 는 `saleList` 에 **없다** → 진행단계(`AdditionalAttribute1`) 판정은 반드시 `/sale` 상세로.

### 응답 구조
```json
{
  "Total": 100,
  "Page": 1,
  "SaleList": [
    {
      "SaleID": "guid",
      "OrderNumber": "SO-00092",
      "Status": "COMPLETED",
      "OrderDate": "2024-01-15T00:00:00",
      "InvoiceDate": "2024-01-15T00:00:00",
      "Customer": "고객명",
      "CustomerID": "guid",
      "InvoiceNumber": "INV-00001",
      "CustomerReference": "고객PO번호",
      "InvoiceAmount": 1000.00,
      "PaidAmount": 1000.00,
      "Updated": "2024-01-15T03:00:00Z",
      "OrderStatus": "AUTHORISED",
      "CombinedInvoiceStatus": "PAID",
      "CombinedShippingStatus": "SHIPPED",
      "Type": "Simple Sale",
      "SourceChannel": null
    }
  ]
}
```

---

## Sale 상세 — GET /sale

라인 아이템, 배송 정보 포함 전체 상세.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `ID` | Guid | **필수** — SaleList에서 얻은 SaleID |
| `CombineAdditionalCharges` | bool | AdditionalCharges를 Lines에 포함 여부 |
| `IncludeProductInfo` | bool | 제품 상세 정보 포함 여부 |

### 응답 구조 (핵심 필드)

⚠️ **아래 블록은 발췌다 — 없는 필드가 "응답에 없다"는 뜻이 아니다.** 실제로 이 발췌에
배송 주소·결제 조건이 빠져 있어 **2026-08-28 에 프로브를 한 번 더 돌려야 했다**
(픽리스트 주소·Terms 작업). 확정분은 바로 아래 「배송 주소·결제 조건」 절에 있다.

```json
{
  "ID": "guid",
  "Customer": "고객명",
  "CustomerID": "guid",
  "Email": "email@example.com",
  "Status": "COMPLETED",
  "OrderDate": "2024-01-15T00:00:00",
  "Lines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "Name": "제품명",
      "Quantity": 10,
      "Price": 25.00,
      "Discount": 0,
      "Tax": 0,
      "Total": 250.00,
      "AverageCost": 12.00
    }
  ],
  "AdditionalCharges": [],
  "Invoice": {
    "InvoiceNumber": "INV-00001",
    "Date": "2024-01-15T00:00:00",
    "TotalAmount": 250.00
  }
}
```

### 배송 주소·결제 조건 — 최상위 6종 (실측 확정 · 이 절이 정본)

📌 **출처: GAS 프로브 2026-08-28 · SO-15505** (아래 값은 그 실물). 추측 아님.
📌 **정본 표시** — 같은 사실이 `asung-wms` 스킬 규칙 1 에도 요약돼 있다(WMS 사용처 관점).
   **필드 사실이 바뀌면 이 절을 고치고 그쪽 요약을 맞출 것** (한쪽만 고치면 갈라진다).

```json
{
  "ShippingAddress": {
    "ID": "2fdf25a9-…",
    "Line1": "611 Wellington Ave", "Line2": "",
    "City": "Windsor", "State": "ON", "Postcode": "N9A5J5", "Country": "CANADA",
    "Company": "", "Contact": "", "ShipToOther": false,
    "DisplayAddressLine1": "611 Wellington Ave",
    "DisplayAddressLine2": "Windsor ON N9A5J5 CANADA"
  },
  "BillingAddress": { "…같은 모양 — 단 ID 없음…": "" },
  "Terms": "C.B.S (Cash Before Shipment)",
  "Contact": "James Javier",
  "Phone": "5192546333",
  "ShippingNotes": "…화면 Shipping notes…"
}
```

- ⭐ **`DisplayAddressLine1`·`DisplayAddressLine2` 는 Cin7 이 인쇄용으로 이미 합쳐둔 두 줄이다
  — 우리가 Line1/City/Postcode 로 조립하지 말 것.** 인쇄물은 이 둘을 그대로 쓴다.
  조립이 필요한 경우(라벨 등)를 위해 하위 필드도 함께 온다.
- ⚠️ **`Terms` 는 sale 의 필드명이다** — customer·supplier 목록의 `PaymentTerm`(customer.md ·
  supplier.md)과 **이름이 다르다.** 섞어 쓰면 조회가 조용히 빈 값을 낸다.
- ⚠️ `BillingAddress` 는 `ShippingAddress` 와 같은 모양이지만 **`ID` 가 없다.**
- 소비처: Asung WMS 픽리스트 주소·Terms(`wms_orders.ship_address` jsonb 원문 · `terms` text —
  `asung-wms` 규칙 23 · `references/schema.md` 2026-08-30 절).

---

## Apps Script 예시 — 고객별 구매 이력 추출

```javascript
function getCustomerSaleHistory(customerName, daysSince) {
  const since = new Date(Date.now() - daysSince * 86400000).toISOString();
  
  // 1단계: SaleList로 해당 고객 판매 목록 가져오기
  const saleList = fetchAllPages('saleList', {
    Search: customerName,
    UpdatedSince: since,
    CombinedInvoiceStatus: 'AUTHORISED'
  });
  
  // 2단계: 각 Sale 상세에서 라인 아이템 추출
  const skuHistory = {};
  
  for (const sale of saleList) {
    if (sale.Customer !== customerName) continue; // Search는 부분 일치이므로 정확히 필터
    
    Utilities.sleep(200);
    const detail = cin7Get('sale', { ID: sale.SaleID });
    
    for (const line of (detail.Lines || [])) {
      if (!skuHistory[line.SKU]) skuHistory[line.SKU] = [];
      skuHistory[line.SKU].push({
        date: sale.OrderDate,
        qty: line.Quantity,
        orderNo: sale.OrderNumber
      });
    }
  }
  
  return skuHistory;
}
```
