# GAS 웹앱: Shopify Customer Login Tracker

## 개요
- 별도 GAS 프로젝트 (System_Automation과 분리). prefix `LT_`.
- Shopify Custom Pixel + Customer Account UI Extension이 `doPost`로 이벤트 전송 → BQ streaming insert.
- 현재 배포 exec URL은 프로젝트 배포 화면에서 확인 (Custom Pixel/Extension의 ENDPOINT와 반드시 일치해야 함).

## 필수 설정
1. **BigQuery Advanced Service 활성화**: 편집기 좌측 Services → `+` → BigQuery API. (없으면 `BigQuery is not defined` 에러)
2. **웹앱 배포**: 배포 → 새 배포 → 유형 웹 앱 → 실행 계정 = 본인 → 액세스 = **모든 사용자(Anyone)** (외부 Pixel 호출 위함).
3. **수정 후 재배포**: 반드시 "배포 관리 → 편집 → 새 버전 → 배포" (URL 유지). "새 배포"는 URL이 바뀌므로 금지.

## 전체 코드 (Code.gs)

```javascript
// ===== Asung Customer Login / Page-View Tracker (LT_) =====
// Shopify Custom Pixel + Customer Account UI Extension → doPost → BigQuery

const LT_BQ_PROJECT = 'geometric-rock-487814-k4';
const LT_BQ_DATASET = 'Cin7_Customer_Data';
const LT_BQ_TABLE   = 'shopify_customer_login_event';

function lt_getProp_(key) {
  return PropertiesService.getScriptProperties().getProperty(key);
}

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return lt_json_({ ok: false, error: 'no body' });
    }
    const body = JSON.parse(e.postData.contents);

    // (선택) 공유 시크릿 검증 — Script Property LT_SHARED_SECRET 설정 시 활성화
    const expected = lt_getProp_('LT_SHARED_SECRET');
    if (expected && body.secret !== expected) {
      return lt_json_({ ok: false, error: 'unauthorized' });
    }

    const row = {
      customer_id: body.customerId ? String(body.customerId) : null,
      email:       body.email ? String(body.email) : null,
      event_time:  body.eventTime ? String(body.eventTime) : new Date().toISOString(),
      page:        body.page ? String(body.page) : null,
      received_at: new Date().toISOString(),
      event_type:  body.eventType ? String(body.eventType) : null,
      page_url:    body.pageUrl ? String(body.pageUrl) : null,
      page_type:   body.pageType ? String(body.pageType) : null,
      page_title:  body.pageTitle ? String(body.pageTitle) : null,
      client_id:   body.clientId ? String(body.clientId) : null,
      referrer:    body.referrer ? String(body.referrer) : null,
      // product_view 이벤트 필드 (2026-07)
      product_sku:   body.productSku ? String(body.productSku) : null,
      product_title: body.productTitle ? String(body.productTitle) : null,
      product_brand: body.productBrand ? String(body.productBrand) : null,
      product_price: body.productPrice ? String(body.productPrice) : null,
      product_id:    body.productId ? String(body.productId) : null,
    };

    lt_insertRow_(row);
    return lt_json_({ ok: true });
  } catch (err) {
    console.error('LT doPost error: ' + err);
    return lt_json_({ ok: false, error: String(err) });
  }
}

function doGet() {
  return lt_json_({ ok: true, service: 'asung-login-tracker' });
}

function lt_insertRow_(row) {
  const request = {
    rows: [{ insertId: Utilities.getUuid(), json: row }],
  };
  const res = BigQuery.Tabledata.insertAll(
    request, LT_BQ_PROJECT, LT_BQ_DATASET, LT_BQ_TABLE
  );
  if (res.insertErrors && res.insertErrors.length) {
    throw new Error('BQ insert error: ' + JSON.stringify(res.insertErrors));
  }
}

function lt_json_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// 테스트용 (드롭다운 실행). 끝에 _ 없으면 실행 목록에 뜸.
function lt_test() {
  lt_insertRow_({
    customer_id: 'gid://shopify/Customer/TEST',
    email: 'test@asung.ca',
    event_time: new Date().toISOString(),
    page: 'test',
    received_at: new Date().toISOString(),
    event_type: 'test',
    page_url: 'https://asung.ca/test',
    page_type: 'home',
    page_title: 'Test',
    client_id: 'test-client',
    referrer: null,
  });
  console.log('test insert done');
}
```

## GAS 함수 이름 관례
- 함수명이 **밑줄(`_`)로 끝나면** GAS 실행 드롭다운에 안 뜬다(private 헬퍼로 간주). 수동 테스트할 함수는 `lt_test`처럼 밑줄 없이.

## CORS 참고
GAS 웹앱은 응답 헤더를 완전히 제어 못 해서 브라우저 콘솔에 CORS 경고가 뜰 수 있다. 하지만 Pixel/Extension이 **응답을 읽지 않는 fire-and-forget**(sendBeacon 또는 text/plain fetch)이라 데이터는 도달한다. 실제 검증은 BQ 조회로.

## 별개 GAS: 손님 마스터 싱크 2종 (System_Automation 프로젝트)
방문 추적 웹앱(LT_, 별도 프로젝트)과 달리, 손님 마스터 싱크는 **System_Automation** 프로젝트에 있다:
- **`ShopifyCustomerSync.gs`** (`SCM_`) — Shopify REST `/customers.json` → `shopify_customer_master`. 주소·tags·is_wholesale·signup_period 파생. 일일 트리거. truncate+insertAll.
- **`CustomerMasterSync.gs`** (`CCM_`) — Cin7 `/customer` → `asung_customer_master`. branch=Location, 주소 default 선택. 일일 트리거. truncate+insertAll.
- 상세: `references/customer-master.md`. 이건 fire-and-forget 웹앱이 아니라 스케줄 배치라 재배포 개념(New Version) 없이 트리거만 관리.
