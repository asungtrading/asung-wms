# 앱 생태계 데이터 계약 (data-contract)

세 앱(purchasing.html / analytics.html / customer-portal)과 적재 스크립트가 서로 충돌하지 않게 하는 공유 규칙.
**어느 한 곳(특히 적재 스크립트나 테이블 스키마)을 수정하기 전에, 여기서 그 대상의 하류 소비자를 먼저 확인할 것.**

## 1. 의존 관계 지도 — "이걸 고치면 어디가 깨지나"

```
Cin7 Core API
   │
   ├─ SalesOrderData.gs ──→ asung_order_details_historical ──┬─→ purchasing.html (직접 쿼리: ADU·백오더·판매)
   │      (일별/주간 트리거)         (append-only!)            └─→ asung_sales_unified VIEW ─┬─→ analytics.html
   │                                                                                        └─→ CustomerPortal.gs → customer-portal.html
   ├─ (스냅샷 적재) ──→ asung_stock_daily ──→ purchasing.html, analytics.html, BackorderedItemEmail.gs
   └─ PurchaseHistory.gs ──→ asung_purchase_history ──→ purchasing.html (Supplier 분석)
```

| 수정 대상 | 반드시 함께 점검할 곳 |
|---|---|
| **SalesOrderData.gs** | purchasing.html 발주추천·백오더, unified VIEW 경유 analytics·portal 당월 매출 |
| **asung_order_details_historical 스키마/의미** | 위 전부 + `asung_sales_unified` VIEW 정의 |
| **asung_sales_unified VIEW** | analytics.html 전체, CustomerPortal.gs |
| **asung_stock_daily** | purchasing.html 재고/Ordered, analytics 재고 커버리지, BackorderedItemEmail.gs |
| **customer-portal.html / CustomerPortal.gs** | (독립적 — 위 테이블 소비만. 단 CP_PRICE_LIST 시트, Config 시트는 포털 전용) |

## 2. 불변 규칙

### R1. `asung_order_details_historical`은 append-only다
- streaming insert만 하고 DELETE하지 않는다. insertId가 `Order_Number_SKU_Order_Progress`라서
  **같은 (Order_Number, SKU)에 상태별 행이 누적된다** (예: Backordered 행 + Invoiced 행 공존).
- 따라서 이 테이블에서 "현재 상태"를 읽는 모든 쿼리는 반드시 latest-state dedup을 거친다:
  ```sql
  ROW_NUMBER() OVER (
    PARTITION BY Order_Number, SKU
    ORDER BY COALESCE(cin7_updated, loaded_at) DESC, loaded_at DESC
  ) = 1
  ```
- 이 패턴 없이 `WHERE Order_Progress='Backordered'`만 쓰면 **해소된 백오더의 유령 행**을 세게 된다.
- 적용 위치: purchasing.html `boSQL`, Supplier 분석 `backorders` CTE (2026-07-05 개편).

### R2. Apps Script에서 BQ TIMESTAMP를 읽을 때는 UNIX_MILLIS() 필수
- `BigQuery.Jobs.query`(REST)는 TIMESTAMP를 지수표기 epoch초 문자열(`"1.783E9"`)로 반환한다.
- `new Date(그 값)` = **Invalid Date** → 모든 비교가 false → diff 로직이 조용히 죽는다.
- 항상: `SELECT UNIX_MILLIS(ts_col)` → `new Date(parseInt(ms, 10))`.
- 공용 헬퍼: `sd_getOrderUpdateMap_()` (SalesOrderData.gs v7).

### R3. 상태 필터 표준 (반드시 R6의 UPPER(TRIM())과 함께 쓸 것)
| 테이블/뷰 | 백오더 판별 | 매출/판매 판별 |
|---|---|---|
| `asung_order_details_historical` (raw) | `UPPER(TRIM(Order_Progress))='BACKORDERED' AND UPPER(TRIM(Status))='ORDERED'` + **R1 dedup** | `UPPER(TRIM(Order_Progress))='INVOICED'` (또는 판매 상태값 분포 확인 후 목록 확장) |
| `asung_sales_unified` (VIEW) | (백오더 용도 아님) | `UPPER(Status) IN ('CLOSED','COMPLETED')` — 확정 판별의 권위 = Status(=인보이스 발행). Credit Issued는 "전액 반품" 아님(주문 단위 참고 표기), 반품은 sale<0로 판별 |

**⚠️ 매출은 Status로 판별하고 Order_Progress로 판별하지 않는다 (2026-07 정정).**
사용자 회계 모델: **"인보이스 발행됨 = 확정 = CLOSED/COMPLETED"** 이고 Status가 권위 신호다.
`Order_Progress`(`4.Invoiced`/`5.Fulfilled`/`3.Finalized`/`Credit Issued`)는 **사람이 수동 표기하는 참고용**이라,
`Order_Progress IN ('5.Fulfilled','4.Invoiced')`로 필터하면 `3.Finalized` 등 확정 오더를 누락시킨다.
(과거 이 문서가 Order_Progress 기준을 "표준"이라 했으나 **틀림**.) analytics.html·CustomerPortal.gs 전부 Status 필터를 쓴다.

**confirmed 파티션 주의:** `asung_sales_confirmed`의 `status`는 v5에서 **`'COMPLETED'`** 로 적재된다
(v4는 `''`였고, 그 `''`가 앱의 `Status IN ('CLOSED','COMPLETED')` 필터에서 탈락해 confirmed 8개월이
통째 사라진 2026-07 사고). VIEW의 confirmed 파티션은 여전히 `WHERE sale IS NOT NULL`만 건다
(status 조건 금지). (`references/confirmed-upload.md` R-CU5)

**VIEW의 confirmed↔historical 중복 제거는 order_number 기준으로 한다.**
월 기준(`FORMAT_DATE NOT IN confirmed_months`)은 historical 날짜가 뒤집히면 제외를 빠져나가 중복이 남는다.
→ `confirmed_orders` CTE로 `Order_Number NOT IN (...)`. confirmed가 권위 소스(세전·발생주의·COGS 보유).

✅ **불일치 해소됨 (2026-07):** analytics.html·CustomerPortal.gs가 쓰던 `UPPER(Status) IN ('CLOSED','COMPLETED')`가
**올바른 표준**임이 확정됐다(Status 권위 모델). confirmed가 status='COMPLETED'로 적재되므로 이 필터로
confirmed·historical·omni 전부 일관되게 잡힌다. 앱 필터를 바꿀 필요 없음.

⚠️ **미해결 (후속 과제):** purchasing.html의 ADU 판매 필터가 `Order_Progress='Invoiced'` 하나만 쓴다.
raw 테이블엔 `5.Fulfilled` / `Fulfilled` 등 완료 상태가 여러 표기로 존재하므로, 이대로면 판매의 상당수가
빠져 ADU가 과소 계산되고 추천발주가 축소된다. **고치기 전에 반드시 R6의 상태값 분포 쿼리로 실제 값을 확인**하고,
판매로 쳐야 할 상태 목록을 정한 뒤 `UPPER(TRIM())` + `IN (...)`으로 확장할 것.

### R6. raw 테이블 상태 컬럼은 대소문자·접두어가 혼재 — 반드시 UPPER(TRIM()) 비교
`asung_order_details_historical`의 상태 컬럼(`Status`, `Order_Progress`)은 Cin7 적재 과정에서
**같은 의미의 값이 여러 표기로 섞여 저장**된다:
- `Status`: `'ORDERED'`(대문자)와 `'Ordered'`가 공존
- `Order_Progress`: `'5.Fulfilled'` / `'Fulfilled'`, `'Closed'` / `'CLOSED'` 등 접두어·대소문자 혼재

BigQuery의 `=`는 대소문자를 구분하므로 `Status = 'Ordered'`는 `'ORDERED'` 행을 **통째로 누락**시킨다.
이게 2026-07 백오더 사고에서 ADA83705가 목록에서 사라졌던 핵심 원인이다.

**규칙:**
- 이 raw 테이블의 상태 컬럼을 비교할 땐 **항상 `UPPER(TRIM(컬럼)) = '대문자값'`** 형태를 쓴다. 등호 직접 비교(`Status='Ordered'`) 금지.
- 여러 값을 허용할 땐 `UPPER(TRIM(컬럼)) IN ('A','B')`.
- 새 상태 필터를 짜기 전엔 아래로 **실제 저장된 값의 분포를 먼저 확인**한다 (추측 금지):
  ```sql
  SELECT Order_Progress, Status, COUNT(*) AS rows, SUM(Quantity) AS qty
  FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_order_details_historical`
  WHERE Invoice_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND Quantity > 0
  GROUP BY Order_Progress, Status ORDER BY qty DESC;
  ```
- 근본 해결은 적재(SalesOrderData.gs) 측에서 상태값을 정규화(대문자 통일 등)하는 것이나, 그 전까지는 읽는 쪽에서 R6로 방어한다.

### R7. Cin7 리포트의 날짜 컬럼 타입에 따라 xlsx→Sheets 변환이 날짜를 뒤집는다
- xlsx를 Google Sheets로 변환해 파싱할 때, **날짜 셀이 datetime 객체면 DD/MM↔MM/DD로 뒤집힐 수 있다**
  (`07/05`=7월5일 → 5월7일). 로케일(en_US) 무관, **일·월 둘 다 ≤12인 날짜만** 뒤집혀 1~2%만 틀린다.
- 텍스트 날짜(`05-Jul-2026`, `02-Jan-2026`) 리포트는 안전. datetime 리포트는 위험.
  - 안전: **Sales by Product Details**, **Sale Invoices & Credit Notes**
  - 위험(폐기): **Sale Order Details**, **Sale Credit Notes by Product**
- `asung_sales_confirmed` 적재는 텍스트 날짜 리포트만 쓴다. 새 리포트 도입 전 날짜 컬럼 원본 타입 확인 필수.
- 상세: `references/confirmed-upload.md` R-CU1.

### R4. 컬럼 의미를 바꾸지 않는다
- `Order_Progress` = Cin7 Sale 상세의 `AdditionalAttributes.AdditionalAttribute1` (raw 테이블 기준).
- `cin7_updated` = Cin7 `sale.Updated` 원본. diff 판별의 유일한 기준.
- `stock_toronto`/`stock_edmonton` 분리는 영구 규칙 (단일 Stock 복귀 금지).

### R5. 배포 규칙
- **HTML 3종**: GitHub `asungtrading/tools` push → Pages 자동 배포. customer-portal.html은 **수정 전 반드시 최신본 pull**.
- **트리거 스크립트**(SalesOrderData 등): 저장만으로 반영. 단, 큰 수정 후에는 **"버전 기록 → 새 버전 저장"으로 스냅샷** 남기기 (회귀 추적 가능하게).
- **웹앱**(CustomerPortal.gs 등): 수정 후 New Version 재배포 필수.

## 3. 조용한 사망 방지 — 상류 헬스체크

SystemMonitor에 주 1회 체크 (미등록 상태면 등록 권장):

```javascript
// SystemMonitor.gs — 백오더 파이프라인 생존 신호
// 최근 7일 내 Order_Progress='Backordered' 신규 적재가 0건이면 로더 diff 사망 의심
function mon_checkBackorderPipeline() {
  const q = `
    SELECT COUNT(*) AS recent_bo_rows
    FROM \`geometric-rock-487814-k4.Cin7_Sales_Data.asung_order_details_historical\`
    WHERE Order_Progress = 'Backordered'
      AND loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  `;
  const res = BigQuery.Jobs.query({query:q, useLegacySql:false, timeoutMs:30000},
    'geometric-rock-487814-k4');
  const cnt = parseInt(res.rows[0].f[0].v, 10);
  if (cnt === 0) {
    Logger.log('🚨 7일간 백오더 신규 적재 0건 — SalesOrderData diff 로직 점검 필요');
    // Google Space 알림은 SystemMonitor 기존 알림 함수 사용
  } else {
    Logger.log('✅ 백오더 파이프라인 정상 (' + cnt + '건/7일)');
  }
}
```

## 4b. 사고 기록 (2026-07 confirmed 날짜 뒤집힘 + VIEW 누락)

- **증상**: SO-09032 등 일부 주문이 매출에 이중 계상. analytics/portal 매출이 이상.
- **원인 (여러 겹):**
  1. **리포트 날짜 datetime 뒤집힘 (R7/R-CU1)** — confirmed 적재에 쓰던 **Sale Order Details**의
     Invoice date가 datetime → xlsx→Sheets 변환이 `07/05`(7월5일)를 5월7일로 뒤집음. 1,164개 주문 오염.
  2. **VIEW 월 기준 제외 실패** — historical의 일부 **legacy 행**(과거 로더 버전이 남긴 날짜 뒤집힘 잔재)로
     월이 달라지자 `FORMAT_DATE NOT IN confirmed_months` 제외를 빠져나가 confirmed(5월)+historical(7월) 중복.
     (현재 SalesOrderData.gs 코드는 ISO 날짜를 정상 처리 — §5 #7 참고. 제외는 order_number 기준으로 전환해 해결.)
  3. **confirmed status='' 탈락 (R-CU5)** — v4가 status를 `''`로 적재했는데 VIEW가 `status IS NULL`만
     허용 → confirmed 8개월이 VIEW에서 통째 누락(2개월만 표시됨).
- **해결 (2026-07, 2단계):**
  - **1차 (v3→v4):** Sale Order Details 폐기 → **Sale Invoices & Credit Notes**(텍스트 날짜)로 교체.
    VIEW: confirmed 파티션 `WHERE sale IS NOT NULL`(status 조건 제거) + historical 제외를 order_number 기준으로.
    화면 즉시 복구를 위해 VIEW에서 confirmed status를 `'COMPLETED'`로 투영.
  - **2차 (v4→v5, 근본 재구축):** v4가 Product를 grain으로 써서 크레딧을 네팅(발생주의 어긋남)하고,
    report_month를 파일 단위로 감지해 **1월이 2월을, 3월이 4월을 통째 흡수**하는 오적재가 드러남.
    → grain을 **Sale Invoices & Credit Notes**로 전환(매출=`Amount` 세전), COGS=Product Details **(Order#,SKU)** 룩업,
    **report_month=행별 invoice_date**(오적재 차단), **status='COMPLETED' 적재**, **load job/staging/CTAS** 재적재.
  - 검증: 8개월 전부 단일 월로 분리(1월 947k·3월 958k 정상화, 2·4월 독립 복구), 5월 1,205,615.35(발생주의),
    non_completed=0, GM% 30~36%. VIEW 통과 매출 = confirmed 일치.
- **가짜 경보였던 것 (기록):** 중간에 "Credit Issued 양수 $73만 부풀림"으로 의심했으나,
  원본 인보이스/크레딧 문서 대조 결과 **매출·부호·귀속월 모두 정확**이었다. `Credit Issued`는 주문 단위
  참고 표기일 뿐 전액 반품이 아니며(R-CU6), Invoice grain이 판매/반품을 각 발생월에 이미 정확히 담는다.
- **교훈**: ①리포트마다 날짜 타입이 다르다(도입 전 확인) ②숫자가 걸린 문제는 원본 문서까지 대조하고
  섣불리 "부풀림" 단정 말 것 ③적재 스키마 변경(status='')이 하류 VIEW 필터를 조용히 깬다
  ④grain·report_month 결정이 크레딧 발생주의와 월 귀속을 좌우한다(Product netting vs Invoice 라인별).
- 상세: `references/confirmed-upload.md`.

## 4. 사고 기록 (2026-07 백오더 회귀) — 이 계약이 생긴 이유

- **증상**: purchasing.html에서 재발 백오더가 발주추천에 반영 안 됨. 나오더라도 숫자가 이상함 (7/3~7/5).
- **원인은 무려 다섯 겹이었다:**
  1. **로더 diff 사망 (R2)** — v6이 BQ TIMESTAMP를 `new Date("1.783E9")`로 파싱 → Invalid Date → 비교 항상 false → 기존 오더 상태 변경이 영구 스킵.
  2. **append-only 유령 행 (R1)** — 해소된 백오더의 옛 Backordered 행이 남아 계속 집계됨.
  3. **물리적 완전중복 행** — force reload 반복 실행이 같은 행을 여러 벌 적재 (13,927행). CTAS로 청소.
  4. **null행 정렬 역전 (R1)** — `COALESCE(cin7_updated, loaded_at)`가 cin7_updated=null 행을 loaded_at으로 최신처럼 뽑아 옛 상태가 대표가 됨. `CASE WHEN cin7_updated IS NULL THEN 1 ELSE 0 END ASC`로 해결.
  5. **대소문자 필터 (R6)** — `Status='Ordered'`가 `'ORDERED'`(대문자) 행을 통째 누락. ADA83705가 목록에서 사라진 직접 원인. → `UPPER(TRIM())`로 해결.
  6. **고객명 갈림** — 고객이 Cin7에서 이름 변경(`BMG Industries`→`BMG Industries Inc.`) 시 과거 주문의 `Customer` 문자열이 소급 갱신 안 됨 → 같은 회사가 둘로 갈려 백오더 과다집계(517→681). 수동 UPDATE로 통일. **근본 해결은 CustomerID(GUID) 적재** (아래 후속 과제).
- **교훈**: 세 앱이 직접 충돌한 게 아니라 공유 상류(SalesOrderData.gs)가 조용히 죽었는데 하류에 경보가 없어 3일간 미발견 → §3 헬스체크.

## 5. 후속 과제 (미해결, 다음 세션에서 이어감)

1. **ADU 판매 필터 대소문자** — purchasing.html이 `Order_Progress='Invoiced'`만 씀 → `5.Fulfilled` 등 누락으로 ADU 과소 → 추천발주 축소. R6의 분포 쿼리 확인 후 `UPPER(TRIM())` + 상태목록 확장.
2. **완전중복 행 재청소** — CTAS 청소 후에도 남은 잔재(예: SO-12309 동일행 3개). null행/동일-timestamp 중복 포함해 재청소.
3. **null행 생성 근본 원인** — SalesOrderData가 `sale.Updated` 없을 때 cin7_updated=null로 적재. v7 보강 필요.
4. **고객명 갈림 근본 해결** — SalesOrderData가 `CustomerID`(GUID)도 적재하도록 스키마 추가 → 집계를 이름 대신 ID 기반으로. 이름 변경에 강건. (portal의 bq_names 파이프 나열도 이 문제의 우회책이었음.)
5. **weekly catchup 시간 가드** — `runWeeklySalesOrderCatchup`은 시간 가드 없이 전량 forEach → 대량(예: 1,819건)이면 30분 초과로 사망하며 그날 작업 통째 유실. daily/force-reload처럼 25분 가드 + 체크포인트 추가.
6. **상태값 정규화 (근본, R6 관련)** — 읽는 쪽에서 매번 UPPER(TRIM) 방어하는 대신, 적재 측에서 Status/Order_Progress를 정규화(대문자 통일 등)하면 R6 자체가 불필요해짐. 단 하류 전체 영향 확인 필요.
7. **historical legacy 잔재 정리 (SalesOrderData.gs 코드는 정상 확인됨, 2026-07)** — 당월(confirmed 없는 최신 달)은
   VIEW가 historical을 쓴다. 오늘 `debugInspectSO09032` 등으로 검증한 결과 **현재 SalesOrderData.gs 코드는 정상**이다:
   Cin7 API가 날짜를 ISO(`2026-05-07T00:00:00`)로 주고 `sd_formatDate`가 그대로 보존하며(MM/DD 파싱은 fallback일 뿐),
   금액은 API `Order.Lines[].Total`(세전)을 담는다. 다만 테이블엔 **과거 로더 버전이 남긴 legacy 행**이 있다:
   날짜 뒤집힘 ~11,572행(~7%), 세후 금액 ~47,222행(~29%, HST13/GST5). 확정월은 order_number 제외로 배제되어
   매출엔 무영향이고, ADU도 수량 기반이라 세후 잔재는 무관하나, **날짜 뒤집힘 legacy는 purchasing ADU의 기간 귀속을
   흔든다.** → runForceReloadSafe 재적재 + CTAS로 legacy 청소 필요(급하지 않음). (`references/confirmed-upload.md` R-CU1/R-CU4)
