---
name: cin7-api
description: >
  Cin7 Core (DEAR Inventory) API v2 연동 코드를 작성할 때 반드시 이 스킬을 사용하세요.
  Google Apps Script 또는 BigQuery 파이프라인에서 Cin7 데이터를 가져오거나 자동화할 때 트리거됩니다.
  "Cin7", "DEAR", "판매 데이터 가져오기", "발주 데이터", "고객 구매 이력", "재고 조정", "브랜치 트랜스퍼",
  "ProductAvailability", "SaleList", "PurchaseList", "StockAdjustment", "StockTransfer",
  "PO 생성", "발주 생성", "DRAFT 발주", "드래프트 오더", "Cin7에 쓰기", "purchase POST",
  "Fixed Price", "고정 단가", "product-suppliers", "빈 트랜스퍼", "bin GUID",
  "stock received 쓰기", "purchase/stock", "리시빙 반영", "Invoice First" 등의
  키워드가 나오면 반드시 이 스킬을 먼저 읽고 코드를 작성하세요. 엔드포인트 URL, 파라미터 이름, 
  응답 구조가 정확히 문서화되어 있으므로 추측으로 코드를 작성하지 마세요.
---

# Cin7 Core API v2 연동 스킬

## 기본 정보

- **Base URL**: `https://inventory.dearsystems.com/ExternalApi/v2/`
- **인증 헤더** (두 개 모두 필수):
  - `api-auth-accountid`: Account ID
  - `api-auth-applicationkey`: API Application Key
- **데이터 포맷**: JSON only
- **날짜 포맷**: ISO 8601 (`2024-01-15T00:00:00` 또는 `2024-01-15`)

## Apps Script 인증 패턴 (Asung 표준)

```javascript
// Config.gs의 getProp() 사용 — API Key를 코드에 직접 쓰지 말 것
const BASE_URL = 'https://inventory.dearsystems.com/ExternalApi/v2/';

function getCin7Headers() {
  return {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_API_KEY'),
    'Content-Type': 'application/json'
  };
}

function cin7Get(endpoint, params) {
  const url = BASE_URL + endpoint + '?' + Object.entries(params)
    .filter(([_, v]) => v !== null && v !== undefined)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');
  
  const response = UrlFetchApp.fetch(url, {
    method: 'GET',
    headers: getCin7Headers(),
    muteHttpExceptions: true
  });
  
  if (response.getResponseCode() !== 200) {
    throw new Error(`Cin7 API Error ${response.getResponseCode()}: ${response.getContentText()}`);
  }
  return JSON.parse(response.getContentText());
}
```

## 페이지네이션 패턴

페이지네이션을 지원하는 엔드포인트: `saleList`, `purchaseList`, `stockadjustmentList`, `stockTakeList`, `stockTransferList`, `product`, `ref/productavailability`

```javascript
function fetchAllPages(endpoint, params) {
  const allItems = [];
  let page = 1;
  
  while (true) {
    const data = cin7Get(endpoint, { ...params, Page: page, Limit: 100 });
    
    // 엔드포인트별 배열 키 이름이 다름 — 아래 엔드포인트 섹션 참고
    const items = data.SaleList || data.PurchaseList || data.StockAdjustmentList || 
                  data.StockTransferList || data.ProductAvailabilityList || data.Product || [];
    
    allItems.push(...items);
    
    if (items.length < 100 || allItems.length >= data.Total) break;
    page++;
    Utilities.sleep(300); // Rate limit 방지
  }
  return allItems;
}
```

---

## 엔드포인트 레퍼런스

상세 파라미터와 응답 구조는 `/references/` 폴더의 각 파일을 참고하세요:

| 목적 | 엔드포인트 | 레퍼런스 파일 |
|------|-----------|-------------|
| 판매 목록 / 상세 | `GET /saleList`, `GET /sale` | `references/sale.md` |
| 발주 목록 / 상세 | `GET /purchaseList`, `GET /purchase` | `references/purchase.md` |
| **DRAFT 발주 생성 (쓰기)** | `POST /purchase` → `POST /purchase/order` (2단계 필수) | `references/purchase-write.md` |
| **공급사 단가(Fixed Price) 갱신 (쓰기)** | `PUT /product-suppliers` (읽기는 `GET /product?IncludeSuppliers=true`) | `references/product-suppliers-write.md` |
| **트랜스퍼/입고 쓰기 (bin GUID 필수)** | `POST /stockTransfer`, `POST /purchase/stock` | `references/stock-write.md` |
| 고객 목록 / 상세 | `GET /customer` | `references/customer.md` |
| 공급업체 목록 / 상세 | `GET /supplier` | `references/supplier.md` |
| 제품 마스터 | `GET /product` | `references/product-master.md` |
| 재고 현황 | `GET /ref/productavailability` | `references/product.md` |
| 재고 조정 | `GET /stockadjustmentList`, `GET /stockadjustment` | `references/stock.md` |
| 브랜치 이전 | `GET /stockTransferList`, `GET /stockTransfer` | `references/stock.md` |
| 회계 트랜잭션 | `GET /transactions` | `references/transactions.md` |
| **전체 엔드포인트 목록** | 모든 v2 엔드포인트 인덱스 + apib 라인 번호 | `references/endpoint-index.md` |

---

## 자주 쓰는 Use Case 패턴

### 1. 고객별 구매 중단 상품 감지 (UpdatedSince 활용)
```javascript
// 최근 N일간 판매 없는 고객-SKU 조합 찾기
const sales = fetchAllPages('saleList', {
  UpdatedSince: new Date(Date.now() - 90 * 86400000).toISOString(),
  CombinedInvoiceStatus: 'AUTHORISED'
});
// 각 SaleID로 /sale 상세 호출하여 라인 아이템 추출
```

### 2. 재고 현황 전체 조회
```javascript
const availability = fetchAllPages('ref/productavailability', {
  Location: 'Toronto Warehouse' // 또는 빈 문자열로 전체
});
// 응답: ProductAvailabilityList[].{ SKU, OnHand, Available, OnOrder, InTransit }
```

### 3. 브랜치 트랜스퍼 완료 건 조회
```javascript
const transfers = fetchAllPages('stockTransferList', {
  Status: 'COMPLETED',
  Search: '' 
});
// 각 TaskID로 /stockTransfer?TaskID={} 호출하여 라인 상세 조회
```

### 4. 재고 조정 이력 조회
```javascript
const adjustments = fetchAllPages('stockadjustmentList', {
  Status: 'COMPLETED'
});
// 각 TaskID로 /stockadjustment?TaskID={} 호출하여 조정 라인 조회
```

---

## 주의사항

0. **쓰기(POST) 작업**: Purchase/Sale 등 데이터를 생성·수정하는 코드는 반드시 `references/purchase-write.md`를, **재고 이동/입고(트랜스퍼·stock received)는 `references/stock-write.md`를(bin은 GUID만·Invoice First 게이트·Date 필수 등 실측 확정)** 먼저 읽을 것. 공식 문서와 실제 동작이 다른 부분(2단계 생성, 환율 자동 물림)이 실측으로 정리되어 있음. 새 write 코드는 항상 DRY_RUN 게이트를 거치고, Status는 DRAFT만 사용 (Authorize는 사람 몫).
1. **List vs Detail 패턴**: `*List` 엔드포인트는 요약 정보만 반환. 라인 아이템이 필요하면 TaskID/SaleID로 상세 엔드포인트를 별도 호출해야 함.
2. **응답 배열 키 이름**: 엔드포인트마다 다름. `SaleList`, `PurchaseList`, `StockAdjustmentList`, `StockTransferList`, `ProductAvailabilityList`, `CustomerList` 등.
3. **Rate Limit**: 루프에서 `Utilities.sleep(300)` 추가 권장.
4. **날짜 필터**: `UpdatedSince`, `CreatedSince` 등은 UTC 기준 ISO 8601.
5. **Simple vs Advanced**: Sale/Purchase 모두 Simple/Advanced 타입 존재. Advanced는 여러 Invoice/Fulfilment 가질 수 있음.
