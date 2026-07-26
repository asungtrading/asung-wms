# Product 엔드포인트 레퍼런스

## Product Availability — GET /ref/productavailability

재고 현황 조회. OnHand, Available, OnOrder, InTransit 포함.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 ProductID로 조회 |
| `Name` | string | 제품명 시작 문자 필터 |
| `Sku` | string | 특정 SKU 조회 |
| `Location` | string | 특정 Location 이름으로 필터 (빈 문자열 = 전체) |
| `Batch` | string | 배치/시리얼 번호 필터 |
| `Category` | string | 카테고리명 필터 |

### 응답 구조
```json
{
  "Total": 500,
  "Page": 1,
  "ProductAvailabilityList": [
    {
      "ID": "guid",
      "SKU": "PROD-001",
      "Name": "제품명",
      "Barcode": null,
      "Location": "Toronto Warehouse",
      "Bin": "A0101",
      "OnHand": 100,
      "Allocated": 10,
      "Available": 90,
      "OnOrder": 50,
      "StockOnHand": 100,
      "InTransit": 20,
      "NextDeliveryDate": "2024-02-01T00:00:00"
    }
  ]
}
```

### 필드 설명
| 필드 | 설명 |
|------|------|
| `OnHand` | 실제 창고에 있는 수량 |
| `Allocated` | 판매 오더에 배정된 수량 |
| `Available` | OnHand - Allocated (실제 판매 가능 수량) |
| `OnOrder` | 발주 진행 중 수량 (아직 입고 안 됨) |
| `InTransit` | 브랜치 이전 중인 수량 |
| `NextDeliveryDate` | 다음 입고 예정일 |

---

## Apps Script 예시 — 재고 부족 SKU 감지

```javascript
function getLowStockSkus(threshold) {
  const allStock = fetchAllPages('ref/productavailability', {
    Location: '' // 전체 Location
  });
  
  return allStock.filter(item => item.Available <= threshold && item.Available >= 0);
}
```

## Apps Script 예시 — 특정 SKU 재고 확인

```javascript
function getSkuAvailability(sku) {
  const data = cin7Get('ref/productavailability', { Sku: sku });
  return data.ProductAvailabilityList || [];
  // 여러 Location에 나눠져 있으면 배열로 여러 개 반환됨
}
```
