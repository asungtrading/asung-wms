# 자주 쓰는 쿼리 레시피 (query-recipes)

모든 예시는 `geometric-rock-487814-k4` 프로젝트 기준. 매출 집계는 항상 `Order_Progress IN ('5.Fulfilled','4.Invoiced')` 필터와 `invoice_date` 기준을 지킬 것.

## 1. 월별 매출 추이

```sql
SELECT
  DATE_TRUNC(invoice_date, MONTH) AS month,
  SUM(sale) AS revenue
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE Order_Progress IN ('5.Fulfilled', '4.Invoiced')
GROUP BY 1
ORDER BY 1;
```

## 2. 브랜드별 매출 Top N

```sql
SELECT
  brand,
  SUM(sale) AS revenue,
  COUNT(DISTINCT customer) AS customers
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE Order_Progress IN ('5.Fulfilled', '4.Invoiced')
  AND invoice_date BETWEEN @start AND @end
GROUP BY brand
ORDER BY revenue DESC
LIMIT 20;
```

## 3. 고객별 SKU 구매 빈도 (재구매 추천 기반)

```sql
SELECT
  customer,
  sku,
  COUNT(DISTINCT invoice_date) AS purchase_days,
  SUM(quantity) AS total_qty,
  MAX(invoice_date) AS last_purchase
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE Order_Progress IN ('5.Fulfilled', '4.Invoiced')
  AND customer = @customer
GROUP BY customer, sku
ORDER BY last_purchase DESC;
```

## 4. GP 마진 (확정월만 — COGS null 제외)

```sql
SELECT
  brand,
  SUM(sale) AS revenue,
  SUM(COGS) AS cogs,
  SAFE_DIVIDE(SUM(sale) - SUM(COGS), SUM(sale)) AS gp_margin
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE Order_Progress IN ('5.Fulfilled', '4.Invoiced')
  AND COGS IS NOT NULL          -- 당월/historical(원가 미확정) 제외
GROUP BY brand
ORDER BY revenue DESC;
```

## 5. SKU 재고 커버리지 (며칠치 남았나)

```sql
WITH adu AS (              -- 최근 90일 평균 일판매
  SELECT sku, SAFE_DIVIDE(SUM(quantity), 90) AS avg_daily_units
  FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
  WHERE Order_Progress IN ('5.Fulfilled', '4.Invoiced')
    AND invoice_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY sku
),
stock AS (                -- 가장 최근 재고 스냅샷
  SELECT sku, stock_location, on_hand
  FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_stock_daily`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_stock_daily`)
)
SELECT
  s.sku, s.stock_location, s.on_hand, a.avg_daily_units,
  SAFE_DIVIDE(s.on_hand, a.avg_daily_units) AS days_of_cover
FROM stock s
LEFT JOIN adu a USING (sku)
ORDER BY days_of_cover ASC;
```

> 컬럼명(`on_hand`, `stock_location`, `snapshot_date` 등)은 실제 스키마와 다를 수 있으니, 모르면 `bq show --schema` 또는 `INFORMATION_SCHEMA.COLUMNS`로 먼저 확인하세요.

## 6. 스키마 빠르게 확인

```sql
SELECT column_name, data_type
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'asung_sales_unified'
ORDER BY ordinal_position;
```

## 작은 팁

- `SAFE_DIVIDE`를 써서 0 나눗셈 에러를 피한다.
- 큰 스캔을 줄이려면 `invoice_date` 범위를 항상 건다 (파티션 프루닝).
- 문자열에 작은따옴표가 들어가면(예: 고객명 `O'Brien`) 이스케이프 필요 — analytics.html에서는 `\u0027` 패턴을 씀.
