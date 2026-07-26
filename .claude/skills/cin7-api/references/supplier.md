# Supplier 엔드포인트 레퍼런스

## Supplier — GET /supplier

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 공급업체 ID 조회 |
| `Name` | string | 이름 시작 문자 필터 (startsWith) |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 공급업체 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 포함 여부 (기본값 false) |

### 응답 구조
```json
{
  "Total": 10,
  "Page": 1,
  "SupplierList": [
    {
      "ID": "guid",
      "Name": "공급업체명",
      "Currency": "CAD",
      "PaymentTerm": "30 days",
      "AccountPayable": "800",
      "TaxRule": "BAS Excluded",
      "Discount": 0,
      "Comments": null,
      "TaxNumber": null,
      "Status": "Active",
      "LastModifiedOn": "2024-01-15T06:15:17.237Z",
      "Addresses": [
        {
          "Line1": "123 Supply St",
          "City": "Seoul",
          "Country": "South Korea",
          "Type": "Business",
          "DefaultForType": true
        }
      ],
      "Contacts": [
        {
          "Name": "담당자명",
          "Phone": "02-0000-0000",
          "Email": "supplier@example.com",
          "Default": true,
          "IncludeInEmail": false
        }
      ]
    }
  ]
}
```

---

## Apps Script 예시 — 공급업체 ID-이름 맵 만들기

```javascript
function buildSupplierMap() {
  const suppliers = fetchAllPages('supplier', {});
  // 반환 키: SupplierList
  const map = {};
  for (const s of suppliers) {
    map[s.ID] = s.Name;
  }
  return map;
}
```

**주의**: `fetchAllPages()`에서 `SupplierList` 키를 명시적으로 처리해야 함.
```javascript
// fetchAllPages 내부에서 SupplierList 추가
const items = data.SaleList || data.PurchaseList || data.SupplierList || 
              data.CustomerList || data.StockAdjustmentList || 
              data.StockTransferList || data.ProductAvailabilityList || 
              data.Products || data.Transactions || [];
```
