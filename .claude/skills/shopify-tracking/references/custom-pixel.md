# Custom Pixel: page-view-custom (주력 추적)

## 왜 Custom Pixel인가
extension-only 앱의 App pixel은 활성화(`webPixelCreate`)가 사실상 불가능하다(SKILL.md R1 참조). Custom Pixel은 앱·토큰·mutation 없이 **Admin UI에서 코드 붙여넣고 Connect만 누르면 100% 작동**한다. 데이터는 여전히 우리 GAS → BQ로만 흐르므로 제3자 노출 없음.

## 생성 절차
1. Shopify Admin → Settings → **Customer events**
2. 우측 상단 **"Add custom pixel"** → 이름 `page-view-custom`
3. Code 영역에 아래 코드 붙여넣기
4. **Save** → **Connect** (초록불 "Web" = 작동)
5. Customer privacy 설정 물으면 내부 분석용으로 적당히 저장

## 검증
초록불 확인 후, 시크릿창으로 asung.ca 방문 → 상품 클릭 → 1~2분 후 BQ에서 `event_type='page_view'` 조회. 실데이터 확인됨 (2026-07: 로그인 손님 email + 익명 client_id 둘 다 정상 수집).

## 코드

```javascript
// Asung Page-View Tracker (Custom Pixel)
const ENDPOINT = 'https://script.google.com/macros/s/AKfycbyy7ri1Q2sCOfF9vbDNfn1p_kLvjxCSHSc_Io8eisaFCUPXwqpDghfDyb0eQXNdbq_J/exec';

analytics.subscribe('page_viewed', (event) => {
  try {
    const ctx = (event && event.context) || {};
    const win = ctx.window || {};
    const doc = ctx.document || {};

    let customer = null;
    try { customer = (init && init.data && init.data.customer) || null; } catch (e) {}

    const payload = {
      eventType:  'page_view',
      customerId: customer && customer.id ? String(customer.id) : null,
      email:      customer && customer.email ? String(customer.email) : null,
      clientId:   event.clientId || null,
      eventTime:  event.timestamp || new Date().toISOString(),
      pageUrl:    (win.location && win.location.href) || null,
      pageTitle:  (doc && doc.title) || null,
      referrer:   (doc && doc.referrer) || null,
      page:       (win.location && win.location.pathname) || null,
      pageType:   null,
    };

    const bodyStr = JSON.stringify(payload);
    if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
      navigator.sendBeacon(ENDPOINT, bodyStr);
    } else {
      fetch(ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: bodyStr, keepalive: true }).catch(() => {});
    }
  } catch (err) {
    console.error('page-view-custom error', err);
  }
});
```

## 확장 (구현됨: product_viewed, 2026-07)
Custom Pixel `page-view-custom`은 **두 이벤트를 구독**한다:
- `page_viewed` → eventType `page_view` (전체 페이지뷰)
- `product_viewed` → eventType `product_view`. `event.data.productVariant`에서 SKU/제목/브랜드/가격 추출:
  - `pv.sku` → product_sku (Cin7 포맷 그대로, 예: AS00964BRO — Cin7 조인 가능)
  - `pv.product.title` → product_title
  - `pv.product.vendor` → product_brand (⚠️ mixed-case로 옴: "Kim & C", "cantu" — 집계 시 `UPPER(TRIM())`)
  - `pv.price.amount` → product_price
- GAS `doPost`가 product_* 필드를 BQ row에 매핑 (gas-webapp.md).
- 다른 표준 이벤트(`collection_viewed`, `search_submitted`)도 같은 방식으로 추가 가능하나 현재는 collection/검색을 **page_url 파싱**으로 처리(카테고리 탭, 인기 페이지 검색어).

## ⚠️ 익명 방문자 위치는 못 얻음
Custom Pixel은 **샌드박스 iframe**이라 IP·위치 정보 접근 불가. `event.context`엔 URL/제목/referrer만. 익명 지역이 필요하면 픽셀 안에서 외부 IP API(ipapi.co 등)를 fetch하는 수밖에 없음(세션당 1회 캐싱). → `visitor-analytics-app.md`의 "옵션 2".

## 데이터 해석 팁
- 같은 `client_id`가 여러 페이지를 연속 조회 = 한 사람의 방문 세션.
- 로그인 손님이면 `email` 채워짐. 비로그인이면 `email`=null, `client_id`로만 반복방문 추적.
- 정탐 후보: **is_wholesale=true(승인) + 구매 0 + 방문 잦음** (bigquery-schema.md 쿼리, customer-master.md 참조). 단순 "매출 없음"은 미승인자까지 섞여 부정확.
