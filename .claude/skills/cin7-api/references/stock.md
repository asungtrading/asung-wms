# Stock 엔드포인트 레퍼런스

## Stock Adjustment List — GET /stockadjustmentList

페이지네이션 지원. 목록만 반환 (라인 없음).

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `Status` | string | DRAFT, COMPLETED, VOIDED |

### 응답 구조
```json
{
  "Total": 22,
  "Page": 1,
  "StockAdjustmentList": [
    {
      "TaskID": "guid",
      "EffectiveDate": "2024-01-15T00:00:00",
      "StocktakeNumber": "ST-00001",
      "Status": "COMPLETED",
      "Account": "403",
      "Reference": "",
      "Comment": "메모"
    }
  ]
}
```

---

## Stock Adjustment 상세 — GET /stockadjustment

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `TaskID` | Guid | **필수** — StockAdjustmentList에서 얻은 TaskID |

### 응답 구조 (핵심 필드)
```json
{
  "TaskID": "guid",
  "EffectiveDate": "2024-01-15T00:00:00",
  "StocktakeNumber": "ST-00022",
  "Status": "COMPLETED",
  "ExistingStockLines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "ProductName": "제품명",
      "Quantity": 100,
      "AdjustedQuantity": 95,
      "UnitCost": 12.00,
      "LocationID": "guid",
      "Location": "Toronto Warehouse"
    }
  ],
  "NewStockLines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-002",
      "ProductName": "신규 제품",
      "Quantity": 50,
      "UnitCost": 8.00,
      "LocationID": "guid",
      "Location": "Toronto Warehouse"
    }
  ]
}
```

**주의**: `ExistingStockLines`는 기존에 재고가 있던 제품의 조정, `NewStockLines`는 재고가 0이었던 제품의 신규 입력.

---

## Stock Transfer List — GET /stockTransferList

페이지네이션 지원. Toronto ↔ Edmonton 브랜치 이전 조회에 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `Status` | string | DRAFT, IN TRANSIT, COMPLETED, VOIDED |
| `Search` | string | FromLocation, ToLocation, Status, Number에서 검색 |

### 응답 구조
```json
{
  "Total": 5,
  "Page": 1,
  "StockTransferList": [
    {
      "TaskID": "guid",
      "From": "guid",
      "FromLocation": "Toronto Warehouse",
      "To": "guid",
      "ToLocation": "Edmonton Warehouse",
      "Status": "COMPLETED",
      "Number": "TR-00005",
      "CompletionDate": "2024-01-15T00:00:00",
      "DepartureDate": "2024-01-12T00:00:00",
      "Reference": "",
      "LastModifiedOn": "2024-01-15T00:00:00"
    }
  ]
}
```

---

## Stock Transfer 상세 — GET /stockTransfer

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `TaskID` | Guid | **필수** — StockTransferList에서 얻은 TaskID |

### 응답 구조 (핵심 필드)
```json
{
  "TaskID": "guid",
  "Status": "COMPLETED",
  "FromLocation": "Toronto Warehouse",
  "ToLocation": "Edmonton Warehouse",
  "Number": "TR-00005",
  "DepartureDate": "2024-01-12T00:00:00",
  "CompletionDate": "2024-01-15T00:00:00",
  "Lines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "ProductName": "제품명",
      "QuantityOnHand": 100,
      "QuantityAvailable": 100,
      "TransferQuantity": 20
    }
  ]
}
```

---

## Apps Script 예시 — Edmonton 이전 이력 BigQuery 파이프라인

```javascript
function fetchRecentTransfers(daysSince) {
  // 1단계: 완료된 트랜스퍼 목록
  const transferList = fetchAllPages('stockTransferList', {
    Status: 'COMPLETED',
    Search: 'Edmonton' // ToLocation에 Edmonton 포함된 건
  });
  
  const rows = [];
  
  for (const transfer of transferList) {
    const completionDate = new Date(transfer.CompletionDate);
    const cutoff = new Date(Date.now() - daysSince * 86400000);
    if (completionDate < cutoff) continue;
    
    // 2단계: 각 트랜스퍼 상세 (라인 아이템)
    Utilities.sleep(200);
    const detail = cin7Get('stockTransfer', { TaskID: transfer.TaskID });
    
    for (const line of (detail.Lines || [])) {
      rows.push({
        transfer_number: transfer.Number,
        from_location: transfer.FromLocation,
        to_location: transfer.ToLocation,
        completion_date: transfer.CompletionDate,
        sku: line.SKU,
        product_name: line.ProductName,
        transfer_qty: line.TransferQuantity
      });
    }
  }
  
  return rows;
}
```
