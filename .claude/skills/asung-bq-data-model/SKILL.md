---
name: asung-bq-data-model
description: >
  Asung Trading의 BigQuery 데이터 모델을 다룰 때 반드시 이 스킬을 먼저 읽으세요.
  매출/판매/COGS/GP 분석, 재고 현황 조회, 발주 이력 분석, 고객·브랜드·SKU 집계 등
  BQ 데이터를 쿼리하거나 새 테이블/뷰를 만들 때, 그리고 SalesOrderData.gs 등
  적재 스크립트나 purchasing/analytics/customer-portal 앱이 공유하는 테이블을
  수정할 때 트리거됩니다.
  "매출 뽑아줘", "판매 데이터", "BQ 쿼리", "asung_sales", "asung_stock", "COGS", "GP",
  "재고 조회", "발주 이력", "데이터셋", "테이블 만들어", "뷰 수정", "백오더",
  "SalesOrderData", "앱이 안 돼", "데이터 계약" 등의 키워드가 나오면
  추측으로 테이블을 고르지 말고 이 스킬에서 올바른 테이블·grain·필터를 확인하세요.
  잘못된 테이블이나 필터를 쓰면 매출 숫자가 틀어지고(Credit Issued 중복, 멀티월 netting 버그 등),
  공유 테이블·적재 로직을 하류 확인 없이 고치면 다른 앱이 조용히 깨집니다
  (references/data-contract.md의 의존 지도와 불변 규칙 R1~R5를 반드시 따를 것).
---

# Asung Trading BigQuery 데이터 모델 스킬

Asung은 Cin7 Core 데이터를 BigQuery에 적재하고, 그 위에서 분석 앱(analytics.html, purchasing.html, Customer Portal)을 돌립니다. **어떤 테이블을 골라 어떤 필터를 거느냐가 숫자의 정확성을 좌우합니다.** 이 문서는 "어느 테이블이 무슨 grain인지"와 "절대 틀리면 안 되는 필터 규칙"을 정리합니다.

## 프로젝트 / 데이터셋

| 항목 | 값 |
|------|-----|
| GCP Project | `geometric-rock-487814-k4` |
| 판매·재고 데이터셋 | `Cin7_Sales_Data` |
| 발주 데이터셋 | `Cin7_Purchase_Data` |

전체 경로는 항상 `geometric-rock-487814-k4.Cin7_Sales_Data.<table>` 형태로 씁니다.

---

## 핵심 원칙 (먼저 외울 것)

1. **매출 분석은 `asung_sales_unified` VIEW를 단일 진입점으로 쓴다.** 개별 테이블을 직접 쿼리하면 월 경계·COGS 처리·historical 합산을 직접 신경 써야 해서 실수가 난다. VIEW가 그걸 이미 해결해 둔다.
2. **`grain`(행 1개가 무엇을 뜻하는지)을 항상 먼저 확인한다.** 주문 단위 테이블과 라인아이템 단위 테이블을 섞으면 합계가 부풀거나 줄어든다.
3. **streaming buffer 때문에 `DELETE`가 막힐 수 있다.** 적재 직후 데이터를 지우거나 갈아끼울 때는 `DELETE` 대신 **CTAS(`CREATE OR REPLACE TABLE … AS SELECT`)** 패턴을 쓴다. (자세한 내용은 `references/data-hygiene.md`)
4. **`asung_order_details_historical`은 append-only다 — "현재 상태"를 읽을 땐 latest-state dedup 필수.** 같은 (Order_Number, SKU)에 상태별 행이 누적되므로(Backordered 행 + Invoiced 행 공존), `ROW_NUMBER() OVER (PARTITION BY Order_Number, SKU ORDER BY COALESCE(cin7_updated, loaded_at) DESC) = 1` 없이 상태 필터만 걸면 유령 행을 센다. (`references/data-contract.md` R1)
5. **Apps Script에서 BQ TIMESTAMP를 읽을 땐 `UNIX_MILLIS()` 캐스팅 필수.** REST 응답이 지수표기 문자열(`"1.783E9"`)이라 `new Date()` 직파싱은 Invalid Date가 되어 비교 로직이 조용히 죽는다 — 2026-07 백오더 회귀의 원인. (`references/data-contract.md` R2)
6. **raw 테이블(`asung_order_details_historical`)의 상태 컬럼은 대소문자·접두어가 혼재 — 항상 `UPPER(TRIM())`로 비교.** `Status`에 `'ORDERED'`와 `'Ordered'`가, `Order_Progress`에 `'5.Fulfilled'`/`'Fulfilled'` 등이 섞여 있어, `Status='Ordered'`처럼 등호 직접 비교하면 대문자 행이 통째로 누락된다 (백오더 사고의 직접 원인). 새 상태 필터를 짜기 전엔 `GROUP BY`로 실제 값 분포를 먼저 확인할 것. (`references/data-contract.md` R6)
7. **Cin7 리포트를 xlsx→Sheets로 파싱할 때, 날짜 컬럼이 datetime 객체면 DD/MM↔MM/DD로 뒤집힌다.** `asung_sales_confirmed` 적재에는 **텍스트 날짜 리포트만** 쓴다 (Sales by Product Details, Sale Invoices & Credit Notes). Sale Order Details·Sale Credit Notes by Product는 datetime이라 뒤집혀서 **폐기**. 새 리포트를 파이프라인에 넣기 전 날짜 컬럼 원본 타입을 반드시 확인. (`references/confirmed-upload.md` R-CU1)

**⚠️ 공유 테이블·적재 스크립트(SalesOrderData.gs 등)를 수정하기 전에는 반드시 `references/data-contract.md`의 의존 관계 지도에서 하류 소비자(purchasing/analytics/portal)를 먼저 확인할 것.**

---

## 테이블 카탈로그

### 매출 (Cin7_Sales_Data)

| 테이블 / 뷰 | grain | 용도 | 주의 |
|------------|-------|------|------|
| **`asung_sales_unified`** (VIEW) | 라인아이템 | **매출 분석의 기본 진입점.** 확정월 + 당월 + Omni historical을 UNION ALL로 합침 | 아래 "VIEW 구성" 참고 |
| `asung_sales_confirmed` | 라인아이템 (Invoice grain, v5) | FIFO COGS/GP가 확정된 과거 월. `PARTITION BY invoice_date MONTH`, `CLUSTER BY customer/brand/sku` | grain=Sale Invoices & Credit Notes, 매출=`Amount`(세전), COGS=Product Details (Order#,SKU) 룩업, report_month=행별 invoice_date, status='COMPLETED'. 단일 월 파일로 업로드 |
| `asung_order_details_historical` | 라인아이템 | 당월(아직 확정 안 된) 주문 상세 + 백오더 판별 소스. COGS=null | GP 계산 불가(원가 미확정). **append-only — 현재 상태 조회 시 latest-state dedup 필수** (`references/data-contract.md` R1) |
| `asung_sales_historical_data` | 라인아이템 | Cin7 Omni 시절 데이터 (고정 범위 2022-02-01 ~ 2025-10-31) | COGS/GP null |

### 재고 / 발주

| 테이블 | grain | 용도 |
|--------|-------|------|
| `asung_stock_daily` (Cin7_Sales_Data) | SKU × 일자 × location | 일별 재고 스냅샷. backorder 가용성 판단, purchasing 재고 체크에 사용 |
| `asung_purchase_history` (Cin7_Purchase_Data) | 발주 라인 | 공급업체별 발주 이력, 시즌성·리드타임 분석 |
| `asung_product_master` (Cin7_Sales_Data) | SKU | SKU → name/brand/supplier 마스터. `AdditionalAttribute3` = Discontinued 플래그 |

### 보조 데이터

- `asung_unfulfilled_demand` — 취소/void된 backorder의 수요를 보존한 테이블(2,297건). lost demand 분석용.

---

## `asung_sales_unified` VIEW 구성

VIEW가 3개 소스를 합칩니다:

```
asung_sales_unified =
    확정된 과거 월   → asung_sales_confirmed          (FIFO COGS/GP 있음)
  + 당월(미확정)     → asung_order_details_historical  (COGS = null)
  + Omni historical → asung_sales_historical_data     (2022-02-01 ~ 2025-10-31, COGS/GP null)
```

**왜 이렇게 나뉘나:** COGS는 월 마감 후 Cin7에서 FIFO로 확정되어 내려옵니다. 그래서 당월은 매출(`sale`/`total`)만 정확하고 GP는 못 냅니다. GP가 필요한 분석이면 **당월을 제외**하거나, COGS가 null인 행을 따로 처리하세요.

---

## 표준 컬럼 이름 (analytics 정합성)

2026년 6월 정합화 작업으로 컬럼명이 통일되었습니다. **옛 이름을 쓰지 마세요.**

| 의미 | 올바른 컬럼명 | (구) 쓰지 말 것 |
|------|--------------|----------------|
| 단가 | `sale` | ~~Unit_Price~~ |
| 수량 | `quantity` | ~~Quantity~~ |
| 라인 합계 | `total` | ~~Total~~ |
| 매출 집계 | `SUM(sale)` | — |
| 날짜 기준 | `invoice_date` | (order_date 아님) |

---

## 매출 쿼리의 정답 필터 (가장 중요)

매출/판매 집계 시 **반드시** 아래 규칙을 지키세요. 안 지키면 숫자가 부풀어요.

```sql
-- ✅ 올바른 매출 집계
SELECT
  invoice_date,
  customer,
  brand,
  SUM(sale) AS revenue
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE UPPER(Status) IN ('CLOSED', 'COMPLETED')   -- 확정 판별의 권위 = Status
  AND invoice_date BETWEEN @start AND @end
GROUP BY 1, 2, 3
```

- **상태 필터는 `UPPER(Status) IN ('CLOSED','COMPLETED')` 를 쓴다.** 사용자 회계 모델상 **"인보이스 발행됨(=확정) = CLOSED/COMPLETED"** 이고, Status가 권위 신호다. confirmed는 v5에서 status='COMPLETED'로 적재되고, historical/omni는 실제 Status를 담는다. analytics.html·CustomerPortal.gs 전부 이 필터를 쓴다.
- **⚠️ `Order_Progress`로 매출을 판별하지 말 것.** `Order_Progress`(`4.Invoiced`/`5.Fulfilled`/`3.Finalized`/`Credit Issued` 등)는 **사람이 수동 표기하는 참고용**이라, `IN ('5.Fulfilled','4.Invoiced')`로 필터하면 `3.Finalized` 같은 확정 오더를 누락시킨다. (과거 이 문서가 Order_Progress 기준을 권했으나 **틀림** — 2026-07 정정.)
- **`Credit Issued`를 "전액 반품"으로 오해하지 말 것.** 이건 주문 단위 참고 표기("이 주문에 크레딧이 하나라도 있음")일 뿐, 그 주문 순매출은 양수가 정상이다. 반품 여부는 `sale < 0`으로 판별한다. confirmed는 판매(+)/반품(−)을 각각 발생월에 담아 이미 발생주의로 정확하다. (`references/confirmed-upload.md` R-CU6)
- **confirmed의 `status`는 `'COMPLETED'`** (v5). v4의 `''`가 앱의 `Status IN ('CLOSED','COMPLETED')` 필터에서 탈락해 confirmed 8개월이 통째로 사라진 사고(2026-07) 이후 'COMPLETED'로 적재. confirmed 파티션은 여전히 `WHERE sale IS NOT NULL`만(status 조건 금지). (`references/confirmed-upload.md` R-CU5)
- 날짜 기준은 항상 `invoice_date`.

데이터 정합성 관련 알려진 이슈(현재 수정 진행 중)와 그 회피법은 `references/data-hygiene.md`에 정리되어 있습니다. 이상한 숫자가 나오면 **반드시** 그 파일을 먼저 확인하세요.

---

## 자주 쓰는 쿼리 레시피

구체적인 쿼리 예시(브랜드별 매출, 고객 구매 빈도, 재고 커버리지, GP 마진 등)는 `references/query-recipes.md`를 참고하세요.

---

## 새 테이블/뷰를 만들거나 적재할 때

- **파티션·클러스터**: 큰 테이블은 `asung_sales_confirmed`처럼 `PARTITION BY <date> MONTH`, `CLUSTER BY` 자주 거는 컬럼으로 만든다.
- **재적재(갈아끼우기)**: `DELETE` 후 `INSERT`는 streaming buffer에 막힌다. confirmed(v5)는 **load job → staging → `CREATE OR REPLACE TABLE ... AS SELECT * FROM staging`** 로 통째 교체(buffer 무관). streaming insertAll 금지.
- **단일 월 업로드 규칙**: `asung_sales_confirmed`는 Cin7 리포트를 **월별 개별 파일**로 올린다. v5는 report_month를 행별 invoice_date로 부여해 파일에 다른 달이 섞여도 각 행이 제 달로 가지만(오적재 차단), 단일 월 pull 규칙은 이중 안전으로 유지.
  - **grain = Sale Invoices & Credit Notes** (2026-07 v5 재구축): 이 리포트가 grain·매출(`Amount` 세전)·날짜·Location·크레딧구분. **Sales by Product Details**는 **COGS/Profit 룩업 전용**, 키 = **(Order#, SKU)**. (v4의 Product grain + Document# JOIN은 폐기)
  - **❌ Sale Order Details는 폐기** — 날짜 컬럼이 datetime이라 xlsx→Sheets 변환 시 DD/MM↔MM/DD로 뒤집힌다.
  - 상세 설계·리포트별 날짜 함정·COGS 룩업 키·status='COMPLETED'·재적재 절차는 **`references/confirmed-upload.md` 필독**.

---

## 데이터 흐름의 윗단/아랫단

- **앱 생태계 의존 지도 + 불변 규칙(R1~R6)**: `references/data-contract.md` — 공유 테이블·적재 스크립트 수정 전 필독. 백오더 판별 표준, TIMESTAMP 읽기 규칙, 배포 규칙, 헬스체크 포함.
- **confirmed 적재 파이프라인(SalesConfirmedUpload.gs v5)**: `references/confirmed-upload.md` — grain=Sale Invoices & Credit Notes(매출 `Amount` 세전·날짜·크레딧), COGS 룩업=Product Details (Order#,SKU), 행별 report_month, status='COMPLETED', load job/staging/CTAS 재적재, 크레딧 발생주의, VIEW 중복 제거, 매달 운영 절차. **confirmed나 VIEW를 손대기 전 필독.**
- **윗단(적재 자동화)**: Apps Script가 Cin7 → BQ 적재를 담당. 적재 로직을 건드리려면 `asung-apps-script` 스킬을 참고.
- **아랫단(앱)**: 이 데이터를 화면에 쓰는 도구는 `asung-bq-apps` 스킬을 참고.
- **Cin7 API 원본**: 필드 의미가 헷갈리면 `cin7-api` 스킬의 references를 참고.
