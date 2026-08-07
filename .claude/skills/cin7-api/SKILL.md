---
name: cin7-api
description: >
  Cin7 Core (DEAR Inventory) API v2 연동 코드를 작성할 때 반드시 이 스킬을 사용하세요.
  Google Apps Script 또는 BigQuery 파이프라인에서 Cin7 데이터를 가져오거나 자동화할 때 트리거됩니다.
  "Cin7", "DEAR", "판매 데이터 가져오기", "발주 데이터", "고객 구매 이력", "재고 조정", "브랜치 트랜스퍼",
  "ProductAvailability", "SaleList", "PurchaseList", "StockAdjustment", "StockTransfer",
  "PO 생성", "발주 생성", "DRAFT 발주", "드래프트 오더", "Cin7에 쓰기", "purchase POST",
  "Fixed Price", "고정 단가", "product-suppliers", "빈 트랜스퍼", "bin GUID",
  "stock received 쓰기", "purchase/stock", "리시빙 반영", "Invoice First",
  "ref/location", "Bins", "purchaseList 필터", "InvoiceStatus", "PAID",
  "StockReceivedStatus", "OrderStatus", "Status 필터", "파라미터 무시",
  "429", "rate limit", "백오프",
  "재평가", "Stock Revaluation", "Stock Level Report", "bin 재고 리포트",
  "Movement Details" 등의
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

⚠️⚠️ **Script Property 이름은 `CIN7_APPLICATION_KEY` 다 — 2026-08-05 정정.**
이 문서는 `CIN7_API_KEY` 로 적혀 있었고, `asung-apps-script` 스킬은 `CIN7_APPLICATION_KEY` 로
적혀 있었다. **두 스킬이 갈라져 있어 2026-08-05 실호출이 한 번 실패**했다(폴백으로 진행).
`CIN7_APPLICATION_KEY` 로 통일한 근거는 **문서 4 : 1**:
`asung-apps-script/SKILL.md` 규칙 1 표준 키 목록 · `shopify-tracking/references/customer-master.md`
(⚠️ "`CIN7_API_KEY` 아님" 이라고 **명시**) · `asung-wms/SKILL.md` 환경 상수 ·
`asung-wms/references/edge-function.md`(Supabase secret 이 같은 이름으로 **실동작 중**) 대(對)
이 문서 한 곳. ⚠️ **단 GAS Script Properties 실물은 이번에 열어보지 않았다** — 헤더 이름
(`api-auth-applicationkey`)과 Script Property 키 이름은 별개이고, 확증은 Script Properties 화면뿐이다.
**호출이 `401/403` 이면 이름을 의심하고 Script Properties 를 먼저 열어 확인할 것**(`getProp` 은
없는 키에 `Missing Script Property: …` 를 throw 하므로 증상이 분명하다).

```javascript
// Config.gs의 getProp() 사용 — API Key를 코드에 직접 쓰지 말 것
const BASE_URL = 'https://inventory.dearsystems.com/ExternalApi/v2/';

function getCin7Headers() {
  return {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    // ⚠️ CIN7_API_KEY 가 아니다 (위 정정 참조)
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
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
| **트랜스퍼/입고 쓰기 (bin GUID 필수)** | `POST /stockTransfer`, `POST /purchase/stock`, `PUT /stockTransfer`(완료 — ⚠️수량 변경 무시) | `references/stock-write.md` |
| **bin GUID 조회** | `GET /ref/location` → 창고 행 `Bins[]` | `references/stock-write.md` 5절 |
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
   - ⚠️⚠️ **쓰기 검증은 HTTP 200 이 아니라 GET 으로 되읽은 값으로 한다 (2026-07-28 원칙).** Cin7 은 요청을 **200 으로 받고 조용히 무시**하는 경우가 있다 — 창고간 트랜스퍼 완료 PUT 의 `TransferQuantity` 변경이 그렇다(TR-03267: 요청 4 → 저장 2, 요청 2 → 저장 4, 양방향 무시). 이 때문에 "수량 초과 완료 허용"이라는 **틀린 기록**이 한동안 남아 있었다 — 정정 내용은 `references/stock-write.md` 2절.
1. **List vs Detail 패턴**: `*List` 엔드포인트는 요약 정보만 반환. 라인 아이템이 필요하면 TaskID/SaleID로 상세 엔드포인트를 별도 호출해야 함.
2. **응답 배열 키 이름**: 엔드포인트마다 다름. `SaleList`, `PurchaseList`, `StockAdjustmentList`, `StockTransferList`, `ProductAvailabilityList`, `CustomerList` 등.
3. **Rate Limit**: 루프에서 `Utilities.sleep(300)` 추가 권장. ⚠️ **sleep 만으로는 부족하다** — 여러 프로세스가 같은 계정을 쓰면 429 가 그래도 온다. 429 처리 원칙은 아래 11번.
4. **날짜 필터**: `UpdatedSince`, `CreatedSince` 등은 UTC 기준 ISO 8601.
5. **Simple vs Advanced**: Sale/Purchase 모두 Simple/Advanced 타입 존재. Advanced는 여러 Invoice/Fulfilment 가질 수 있음.
6. **bin GUID 는 `/ref/location` 최상위 창고 행의 `Bins[]` 에서** — 응답은 Total 2678 에 `Limit 500` 으로 잘리지만 `Bins[]` 는 창고 행 하나에 전부 들어있다(에드먼튼 628 · 토론토 2047). ⚠️ child-location 행의 `Name` 은 bin 이름이 아니다(바코드류). `references/stock-write.md` 5절.
7. **`purchaseList` 필터는 직관과 다르다** — `InvoiceStatus`·`Status` 모두 **단일 값만**(콤마·파이프로 여러 값 = Total 0 → 상태별 개별 호출 + `ID` dedup) · `Limit=1000` 동작 · **기본 정렬이 PO 번호 오름차순이라 최신 PO 가 마지막 페이지**(잘리면 항상 최신부터 누락) · `UpdatedSince` 는 최신성 보장 못함 · `Type` 은 무시됨 · **`StockReceivedStatus` 는 동작한다**(⚠️ 아래 12번 — 종전 "무시됨" 기록은 파라미터 **이름 오타**였다). **좁힐 땐 `InvoiceStatus` 가 아니라 `Status` 로** — 실측 973행→78행. 실측 표는 `references/purchase.md`.
   - **`saleList` 는 `OrderStatus`(승인 상태)와 `Status`(진행 상태)가 독립된 축이다** — `OrderStatus=AUTHORISED` 인 오더의 `Status` 는 `ORDERED` 로 남는 게 정상(Simple·Advanced 공통). Advanced Sale 도 라인 구조가 같아 **`Type` 필터는 불필요**. `references/sale.md`.
8. **화면으로만 되는 작업**(재고 재평가·bin 재고 리포트)은 `references/stock.md` 하단 「Cin7 UI 실측 노트」. ⚠️ **원가 0 재고 재평가는 방법 미확정**(Non-zero 0 + Zero stock 재입력은 상계되지 않고 재고가 2배가 된다).
9. ⚠️⚠️ **트랜스퍼 Put away 는 v2 API 에 없다 (2026-07-31 TR-03259 실측 — 탐색 종결).** UI 의 라인별 Put away/LOCATION 은 API 로 노출되지 않는다(`/stockTransfer/putaway` 등 전부 404, 본 문서에 `PutAway` 플래그도 없음, CSV Import 도 없음) → **헤더 `To` 착지 + bin 별 별도 트랜스퍼가 유일한 경로. 같은 탐색을 반복하지 말 것.** `references/stock-write.md` 「Put away」절.
10. **쓰기 되읽기 검증·bin 단위 재고 확인은 `/ref/productavailability`** — 판정은 **OnHand**(Available 은 판매 배정 차감이라 오판) · SKU/창고/Bin 정확 일치 · `Total > 반환 행수` 면 미확인 처리. `references/stock-write.md`.
11. ⚠️ **429 는 일상 전제다 — 페이지 순회에서 즉시 throw 하지 말 것.** 같은 Cin7 계정을 여러 프로세스(pg_cron 5분 폴링 + GAS 잡들)가 공유하면 429 가 흔하다. 1페이지 성공 후 2페이지 429 에 throw 하면 **회차 전체가 죽고 조용한 부분 스캔이 남는다**(2026-08-04 SO-14100/14106 미유입 실사고). 패턴: **백오프 재시도(1.5s→3s, 상한 2회) → 소진 시 throw 없이 회차 조기 종료 + `rate_limited`/`rate_limited_at_page` 진단 필드 노출.** 429 외 4xx/5xx 는 throw 유지. Asung WMS 는 이 HTTP 레이어를 `supabase/functions/_shared/cin7.ts` 로 공용화해 `hello`·`receiving` 두 Edge Function 이 함께 쓴다 — ⚠️ **그 파일을 고치면 두 함수 모두 재배포**(각 함수는 배포 시점 번들을 쓴다).
12. ⚠️⚠️ **파라미터가 무시되는 것처럼 보이면 이름 오타를 먼저 의심하라 (2026-08-04 교훈).** Cin7 은 **모르는 파라미터를 조용히 무시**하므로 응답만으로 "오타" 와 "미지원" 이 **구별되지 않는다** — 둘 다 무필터와 같은 Total 이다. 실제로 `RestockReceivedStatus`(apib 표기, 존재하지 않는 이름)를 보내고 "서버 필터 불가" 라고 잘못 기록해 **일주일간 전량 조회 + 클라이언트 필터를 짊어졌다**(정답은 `StockReceivedStatus`: 585 vs 877). 검증 순서 = ①`references/` 스펠링 대조(⚠️ apib 파라미터 표기 ≠ 응답 필드명일 수 있다) ②**동작을 아는 파라미터를 같이 보내** 배선 확인 ③그래도 Total 불변이면 "미지원" 기록. **200 은 파라미터를 받아들였다는 뜻이 아니다**(0번의 "검증은 되읽기로" 와 같은 계열).
13. ⚠️⚠️ **Advanced Purchase 는 주소·파라미터·응답 구조가 모두 다르다 — 그리고 쓰기 폴백은 Simple→Advanced 한 방향만 (2026-08-07).** 세 번 밟은 함정의 규칙 승격: ①`GET /purchase/invoice` 가 Advanced 에서 400 deprecated(2026-08-05) ②`POST /purchase/stock` 도 Advanced 에서 400 deprecated — PO-01094 Apply 8개 bin 그룹 전멸(2026-08-07 실측: `"This endpoint is deprecated and does not support Advanced Purchase and Service Purchase"`) ③`purchaseList` 의 `Type` 서버 필터 무시. **Advanced 전용 주소** = `/advanced-purchase/stock`·`/advanced-purchase/invoice`·`/advanced-purchase/put-away`. **식별자** = `TaskID`(=PO GUID) 하나가 아니라 **`PurchaseID`(PO GUID, 필수) + `TaskID`(하위 태스크 GUID — 생략 시 새 태스크 생성)**. **응답** = 단일 문서가 아니라 **태스크 배열**(`StockReceiving`/`Invoice[]`/`PutAway` — 인보이스 블록 객체↔배열과 같은 패턴). ⚠️⚠️ **역방향 폴백 절대 금지 — apib 명문**: *"If POST or PUT methods called for Simple Purchase, this purchase will be converted to Advanced Purchase."* Simple PO 에 advanced 주소로 쓰면 **에러가 아니라 PO 가 조용히 Advanced 로 변환**된다 — 읽기 폴백(400 이면 반대쪽 1회 재시도)을 쓰기에 양방향으로 이식하면 타입 기록이 틀린 Simple PO 가 하나씩 오염된다. 쓰기 폴백은 **`/purchase/stock` 400 deprecated → advanced 재시도** 한 방향만(그 400 은 "이 PO 는 Advanced" 의 확정 신호라 안전 — 반대 방향에는 확정 신호가 존재하지 않는다). ⚠️⚠️ **2026-08-07 프로브 실측 2건 추가**(상세 `references/stock-write.md` Advanced 절): ① **Advanced stock received 에는 bin 을 못 싣는다** — `Lines[].LocationID` 는 200 후 되읽으면 null(선반 지정은 별도 `/advanced-purchase/put-away`, 2단 구조) ② **`DELETE /advanced-purchase/stock` 은 200 을 주지만 태스크를 지우지 않는다**(R11 계열 — 200≠반영. API 로 입고 태스크 제거는 미확인, 지울 수 있다고 가정하고 설계하지 말 것). 프로브 도구는 asung-wms repo `docs/probes/WmsAdvPoStockProbe.gs`. apib 원문이 로컬에 없으면 `curl -sL https://jsapi.apiary.io/apis/dearinventory.apib`(공개 문서 — Advanced stock 16918행·put-away 17347행).
