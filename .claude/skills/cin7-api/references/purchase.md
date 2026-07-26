# Purchase 엔드포인트 레퍼런스

## Purchase List — GET /purchaseList

발주 목록 빠른 조회. Simple/Advanced PO 모두 포함.

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
| `RestockReceivedStatus` | string | 입고 상태 필터 |
| `InvoiceStatus` | string | 인보이스 상태 필터 |
| `Status` | string | 전체 Purchase 상태 (아래 참고) |

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

---

## Advanced Purchase — GET /advanced-purchase

Advanced PO (복수 입고/인보이스)의 경우 별도 엔드포인트 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `ID` | Guid | **필수** — PurchaseList에서 얻은 ID (Type이 "Advanced Purchase"인 경우) |

**주의**: `PurchaseList`의 `Type` 필드로 Simple/Advanced 구분 후 적절한 엔드포인트 호출.

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
