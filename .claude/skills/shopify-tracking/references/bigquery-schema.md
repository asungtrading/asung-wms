# BigQuery: shopify_customer_login_event

## 위치
- Project: `geometric-rock-487814-k4`
- Dataset: `Cin7_Customer_Data` (Shopify 행동 데이터 전용 — Cin7 매출/재고와 분리)
- Table: `shopify_customer_login_event`

## 테이블 생성 DDL

데이터셋(최초 1회):
```sql
CREATE SCHEMA IF NOT EXISTS `geometric-rock-487814-k4.Cin7_Customer_Data`
OPTIONS (
  location = 'US',   -- ⚠️ 기존 Cin7_Sales_Data와 동일 리전이어야 조인 가능
  description = 'Shopify 등 고객 행동/계정 데이터 (Cin7 매출·재고와 분리)'
);
```

테이블:
```sql
CREATE TABLE IF NOT EXISTS `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_login_event` (
  customer_id  STRING    OPTIONS(description="Shopify customer GID, e.g. gid://shopify/Customer/12345"),
  email        STRING    OPTIONS(description="로그인 시점 손님 이메일 (비로그인이면 null)"),
  event_time   TIMESTAMP OPTIONS(description="이벤트 발생 시각 (ISO)"),
  page         STRING    OPTIONS(description="pathname, 예: /products/..."),
  received_at  TIMESTAMP OPTIONS(description="GAS 웹앱 수신 서버 시각"),
  event_type   STRING    OPTIONS(description="account_view | page_view | product_view | test"),
  page_url     STRING    OPTIONS(description="방문 페이지 전체 URL"),
  page_type    STRING    OPTIONS(description="page_viewed엔 없어서 보통 null; pathname으로 판별"),
  page_title   STRING    OPTIONS(description="페이지 제목"),
  client_id    STRING    OPTIONS(description="익명 방문자 식별자 (비로그인 반복방문 추적)"),
  referrer     STRING    OPTIONS(description="유입 경로"),
  -- product_view 이벤트 전용 (2026-07 추가)
  product_sku   STRING   OPTIONS(description="상품 SKU (Cin7 포맷, 예: AS00964BRO)"),
  product_title STRING   OPTIONS(description="상품명"),
  product_brand STRING   OPTIONS(description="브랜드 (mixed-case로 옴, UPPER(TRIM()) 정규화 필요)"),
  product_price STRING   OPTIONS(description="가격 문자열"),
  product_id    STRING   OPTIONS(description="Shopify product id")
)
PARTITION BY DATE(event_time)
CLUSTER BY email, client_id;
```

> ⚠️ **초기 잔재**: event_type이 빈값(null)인 행이 소수 존재 — event_type 필드 추가 전 초기 픽셀 버전. 2026-07 이후 안 쌓이니 무해. 집계 시 `event_type IN (...)`로 자연 배제됨.

## 연관 테이블 (같은 데이터셋)
방문 이벤트만으론 "누가·어디·승인고객인지" 모름 → 두 손님 마스터로 조인. **상세는 `references/customer-master.md` 필독.**
- `shopify_customer_master` — Shopify 전체 손님 + 주소 + `is_wholesale`(승인 여부) + `signup_period` + `tags`(staff 제외용)
- `asung_customer_master` — Cin7 전체 고객 + `branch`(Cin7 Location = 지점 정답) + 주소 + `price_tier`

## 컬럼 추가 (스키마 확장 시)
기존 행을 안 깨고 컬럼 추가:
```sql
ALTER TABLE `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_login_event`
  ADD COLUMN IF NOT EXISTS <name> <TYPE> OPTIONS(description="...");
```
추가 후 GAS `doPost`의 row 매핑에도 필드를 넣고 **New Version 재배포**해야 실제로 채워진다.

## event_type 구분
- `page_view` — Custom Pixel(page-view-custom)이 보낸 전체 사이트 페이지뷰 (주력)
- `product_view` — Custom Pixel의 product_viewed 구독. SKU/브랜드/가격 포함 (2026-07 추가)
- `account_view` — Customer Account UI Extension이 보낸 계정 페이지 조회 (보조)
- `test` — 수동 테스트 행
- (빈값) — 초기 버전 잔재, 무해

## ⚠️ 시간대 + 파티션 프루닝 (필수)
분석은 **`America/Toronto`** 기준으로 집계한다(UTC면 토론토 저녁이 다음날로 밀림). 그런데 시간대 변환 `DATE(event_time,'America/Toronto')`는 파티션(UTC DATE 기준)을 **프루닝 못 해 풀스캔**한다. 반드시 프루닝용 TIMESTAMP 조건을 **병행**:
```sql
WHERE DATE(event_time, 'America/Toronto') >= DATE_SUB(CURRENT_DATE('America/Toronto'), INTERVAL 30 DAY)  -- 정확성
  AND event_time >= TIMESTAMP(DATE_SUB(CURRENT_DATE('America/Toronto'), INTERVAL 32 DAY))                 -- 프루닝(2일 여유)
```

## 쿼리 레시피 (⚠️ 날짜 필터 필수 — 파티션 프루닝)

### 방문 빈도 (손님별)
```sql
SELECT
  COALESCE(email, client_id) AS visitor,
  email,
  MIN(event_time) AS first_seen,
  MAX(event_time) AS last_seen,
  COUNT(*) AS page_views,
  COUNT(DISTINCT DATE(event_time)) AS active_days
FROM `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_login_event`
WHERE event_type = 'page_view'
  AND DATE(event_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY visitor, email
ORDER BY page_views DESC;
```

### 정탐/미거래 후보: ⭐ wholesale 승인받아 가격 보는데 구매 없음
```sql
-- 핵심 인사이트: "구매 없음"만으론 부정확(미승인자=가격 못봄까지 섞임).
-- 진짜 후보 = is_wholesale(가격 열람 가능) + 구매 0 + 방문 잦음.
WITH visits AS (
  SELECT LOWER(email) AS email, COUNT(*) AS views, MAX(event_time) AS last_visit
  FROM `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_login_event`
  WHERE event_type IN ('page_view','product_view','account_view')
    AND email IS NOT NULL
    AND DATE(event_time,'America/Toronto') >= DATE_SUB(CURRENT_DATE('America/Toronto'), INTERVAL 30 DAY)
    AND event_time >= TIMESTAMP(DATE_SUB(CURRENT_DATE('America/Toronto'), INTERVAL 32 DAY))
  GROUP BY LOWER(email)
),
shop AS (SELECT LOWER(email) AS email, orders_count, is_wholesale, company
         FROM `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_master` WHERE email IS NOT NULL),
whole AS (SELECT DISTINCT LOWER(email) AS email
          FROM `geometric-rock-487814-k4.Cin7_Customer_Data.asung_customer_master`
          WHERE email IS NOT NULL AND price_tier IN ('Wholesale','USWholesale USD'))
SELECT v.email, v.views, v.last_visit, s.is_wholesale, s.company
FROM visits v
LEFT JOIN shop s ON s.email = v.email
LEFT JOIN whole w ON w.email = v.email
WHERE w.email IS NULL AND COALESCE(s.orders_count,0) = 0   -- 구매기록 전무
  AND s.is_wholesale = TRUE                                 -- ⭐ 가격 볼 수 있는 승인자만
ORDER BY v.views DESC;
```

### staff(직원) 제외 — 모든 방문 집계 공통
```sql
-- WHERE에 추가. 직원 계정에 staff 태그 → 테스트 노이즈 제거
AND (email IS NULL OR LOWER(email) NOT IN (
  SELECT LOWER(email) FROM `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_master`
  WHERE email IS NOT NULL
    AND CONCAT(',', REPLACE(LOWER(IFNULL(tags,'')), ' ', ''), ',') LIKE '%,staff,%'))
```

### 가격/상품 페이지만 골라보기
```sql
SELECT email, client_id, page_url, event_time
FROM `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_login_event`
WHERE event_type = 'page_view'
  AND (page LIKE '/products/%' OR page LIKE '/collections/%')
  AND DATE(event_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY event_time DESC;
```

## 비용
로그인/페이지뷰 이벤트는 행당 수백 바이트. 수십만 건 모여도 스토리지·streaming insert 비용은 센트 단위. 쿼리는 날짜 필터만 지키면 무료 한도 내. `asung_sales_unified` 등 큰 테이블과 조인 시에만 날짜 필터 누락 주의.
