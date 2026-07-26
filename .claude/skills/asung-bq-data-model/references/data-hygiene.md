# 데이터 정합성 이슈 & 회피법 (data-hygiene)

`asung_sales_unified` VIEW와 관련해 **현재 인지·수정 진행 중인** 데이터 품질 이슈들입니다. 이상한 숫자가 나오면 여기부터 확인하세요. 이 이슈들은 "영구적 사양"이 아니라 고쳐 나가는 중인 항목이므로, 작업 시점에 이미 해결됐을 수 있습니다 — 의심되면 실제 데이터로 검증하세요.

## 알려진 이슈

### 1. Credit Issued가 매출을 부풀림
- **증상**: 특정 월 매출이 비정상적으로 큼 (과거 5월에 ~$600K 과대).
- **원인**: 상태 필터에 Credit Issued류가 섞여 들어감.
- **회피**: 매출 집계 필터를 `Order_Progress IN ('5.Fulfilled','4.Invoiced')` **만**으로 제한. Credit Issued를 매출 라인으로 세지 말 것.

### 2. Closed / CLOSED 중복 행
- **증상**: 동일 거래가 두 번 집계됨.
- **원인**: 적재 시 `insertId`에 Status 문자열이 포함되어, 대소문자만 다른 'Closed' vs 'CLOSED'가 서로 다른 행으로 들어감.
- **회피**: 집계 시 중복 제거(거래 식별자 기준 dedupe), 근본 수정은 적재 측 `insertId`에서 Status를 빼는 것.

### 3. Historical 테이블의 COGS/GP null
- **증상**: GP/마진이 비거나 0으로 나옴.
- **원인**: `asung_sales_historical_data`(Omni)와 당월 `asung_order_details_historical`은 원가가 확정 전이라 COGS=null.
- **회피**: GP 분석에서는 COGS가 null인 행을 제외하거나, 매출-only 분석으로 한정. 당월을 빼면 대부분 해결.

## 근본 수정 순서 (적재 측에서)

이슈를 코드로 고칠 때의 권장 순서:

1. 필터에서 Credit Issued 제거
2. `insertId`에서 Status 제거 (Closed/CLOSED 중복 해소)
3. `SalesOrderData.gs`에 AverageCost 컬럼 추가 (COGS/GP 보강)

## streaming buffer 함정

- BQ에 막 적재(streaming insert)된 데이터는 일정 시간 buffer에 머물며 이 동안 `DELETE`/`UPDATE`가 거부됩니다.
- 같은 기간을 재적재하려면:
  - **CTAS 통째 교체**: `CREATE OR REPLACE TABLE … AS SELECT …` — 가장 안전.
  - 또는 적재 직전에 해당 `report_month` 파티션만 비우고 새로 넣기.
- 절대 "적재 직후 곧바로 DELETE" 패턴에 의존하지 말 것.

## 멀티월 netting 버그 (asung_sales_confirmed)

- Cin7의 Sales by Product Details 리포트를 여러 달 합쳐서 추출하면, 환불(credit note)이 원래 invoice가 발생한 월로 netting되어 흡수됩니다 → 월별 매출이 왜곡.
- **규칙**: 항상 월별 개별 파일로 추출·업로드.
  - Sales by Product Details: Invoice date 범위 = 단일 월
  - Sale Order Details: Order date 범위 = 직전월 + 당월
