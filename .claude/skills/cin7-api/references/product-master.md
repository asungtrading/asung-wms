# Product 마스터 엔드포인트 레퍼런스

## Product — GET /product

제품 마스터 데이터. 페이지네이션 지원. 재고 현황은 `/ref/productavailability` 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 Product ID 조회 |
| `Name` | string | 제품명 포함 검색 (contains) |
| `Sku` | string | SKU 포함 검색 (contains) |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 제품 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 포함 여부 (기본값 false) |
| `IncludeBOM` | bool | Bill of Materials 포함 (기본값 false) |
| `IncludeSuppliers` | bool | 공급업체 정보 포함 (기본값 false) |
| `IncludeMovements` | bool | 재고 이동 이력 포함 (기본값 false) |
| `IncludeReorderLevels` | bool | 재주문 레벨 포함 (기본값 false) |
| `IncludeCustomPrices` | bool | 고객별 특수가격 포함 (기본값 false) |

**주의**: `IncludeMovements=true`는 응답이 매우 커질 수 있음. 필요할 때만 사용.

### 응답 구조 (핵심 필드)
```json
{
  "Total": 500,
  "Page": 1,
  "Products": [
    {
      "ID": "guid",
      "SKU": "PROD-001",
      "Name": "제품명",
      "Category": "Hair Care",
      "Brand": "브랜드명",
      "Type": "Stock",
      "Status": "Active",
      "Barcode": "829534000001",
      "UOM": "EA",
      "DefaultLocation": "Toronto Warehouse",
      "AverageCost": 12.50,
      "PriceTier1": 25.00,
      "PriceTier2": 23.00,
      "PriceTiers": {
        "Wholesale": 25.00,
        "Distributor": 23.00
      },
      "MinimumBeforeReorder": 10,
      "ReorderQuantity": 100,
      "Tags": "haircare,popular",
      "PickZones": "Zone1",
      "StockLocator": "A0101",
      "LastModifiedOn": "2024-01-15T00:00:00Z",
      "Suppliers": [],
      "ReorderLevels": []
    }
  ]
}
```

### Suppliers 서브 필드 (IncludeSuppliers=true 시)

> **필드명 실측 확정 (2026-07-10, SKU AS92900 / Intervision China USD).**
> 이전 문서의 `Price` 필드는 존재하지 않음 — 아래가 실제 응답 구조.

```json
"Suppliers": [
  {
    "ProductSupplierID": "guid",
    "SupplierID": "guid",
    "SupplierName": "공급업체명",
    "ProductID": "guid",
    "Cost": 1.0,            // 화면의 LATEST PRICE (최근 매입가)
    "FixedCost": 0.5332,    // 화면의 FIXED PRICE (합의 고정가)
    "PurchaseCost": 0.5332, // FixedCost와 동일 값으로 옴
    "Currency": "USD",      // 공급사 통화
    "LastSupplied": "2025-10-02T00:00:00",
    "DropShip": false,
    "SupplierInventoryCode": null,
    "SupplierProductName": null,
    "SupplierProductURL": null,
    "ProductSupplierOptions": []  // Location별 Lead/Safety/Reorder 설정
  }
]
```

**발주 단가로 쓸 때 폴백:** `FixedCost`(>0) → `Cost`(>0) → 없음(0 처리 + 사람 확인).
DRAFT PO 생성 시 이 값을 라인 Price로 넣음 (Cin7은 API 생성 시 가격 자동채움 안 함 —
`references/purchase-write.md` 참조).
**이 값들을 API로 수정하려면 `references/product-suppliers-write.md` 참조** (PUT 스키마 실측 확정).

### ReorderLevels 서브 필드 (IncludeReorderLevels=true 시)
```json
"ReorderLevels": [
  {
    "LocationID": "guid",
    "Location": "Toronto Warehouse",
    "MinimumBeforeReorder": 20,
    "ReorderQuantity": 100
  }
]
```

---

## Apps Script 예시 — 전체 활성 제품 SKU 목록 가져오기

```javascript
function getAllActiveSkus() {
  const products = fetchAllPages('product', {
    IncludeDeprecated: false
  });
  // 반환 키: Products (복수형, 대문자 P)
  return products.map(p => ({
    id: p.ID,
    sku: p.SKU,
    name: p.Name,
    brand: p.Brand,
    category: p.Category,
    status: p.Status,
    barcode: p.Barcode,
    avgCost: p.AverageCost
  }));
}
```

## Apps Script 예시 — 공급업체별 제품 목록 (purchasing.html 연동용)

```javascript
function getProductsBySupplier(supplierName) {
  const products = fetchAllPages('product', {
    IncludeSuppliers: true,
    IncludeDeprecated: false
  });
  
  return products.filter(p => 
    (p.Suppliers || []).some(s => s.SupplierName === supplierName)
  );
}
```

## Apps Script 예시 — 최근 수정된 제품만 동기화 (BigQuery 증분 업데이트)

```javascript
function syncModifiedProducts(lastSyncDate) {
  return fetchAllPages('product', {
    ModifiedSince: lastSyncDate,  // ISO 8601
    IncludeDeprecated: true       // Deprecated 포함해야 삭제 감지 가능
  });
}
```

---

## 주의사항
- 응답 배열 키: `Products` (대문자 P, 복수형) — `ProductList`가 아님
- `Name` 파라미터는 **contains** 검색 (Customer/Supplier의 startsWith와 다름)
- `AverageCost`는 read-only (FIFO/FEFO 기반 자동 계산)
- **공급사 단가는 `Suppliers[].Cost`(최근가)와 `Suppliers[].FixedCost`(고정가)** — `Price` 필드 아님(실측 확정)
- `PriceTiers` 객체는 실제 PriceTier 이름을 키로 사용 (`Tier 1`, `Wholesale` 등 계정 설정에 따라 다름)

---

## 2026-09-11 표본 실측 (Total 14,677 · 30행 표본 · GAS 프로브 · IMS PO 모듈 ③ 제품 표 설계 근거)

```
배열 키 Products  ·  필드 83개
CostingMethod   30행 전부 FIFO
UOM 빈값        0/30
⭐ Brand·Category·UOM 이 ref/brand·ref/category·ref/unit 의 Name 과 일치 100% · GUID꼴 0건 — 이름 문자열 참조
⭐ 제품이 계정과목을 넷 참조한다 — InventoryAccount · COGSAccount · RevenueAccount · ExpenseAccount (ref/account 의 Code)
📌 HSCode · CountryOfOrigin 칸이 있다
```
⚠️⚠️ **제품이 아닌 항목이 섞여 있다** — SKU 가 `[:[OrderTotalDiscount]:]` · `_1_` · `_10_` · `_10767_` 같은 것들(Type=Service 등).
⭐ Caleb 확인: **`_숫자_` 형식은 우리 제품이 아니다.** 목록이 SKU 순 정렬이라 **앞쪽에 몰려 있다** — 앞 몇 페이지만 보고 판단하면 틀린다.

⬜ **`product?IncludeSuppliers=true` 는 미확인** — 표본 5행이 전부 시스템 항목이라 `Suppliers` 가 0 이었다.
「파라미터가 안 먹는다」와 「표본이 나빴다」가 구별되지 않는다 — 실제 상품 SKU 로 다시 봐야 한다.
(⚠️ 「안 된다」가 아니다. `product-suppliers-write.md` 의 읽기 경로는 이 파라미터를 전제한다.)
