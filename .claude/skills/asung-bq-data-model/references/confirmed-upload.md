# asung_sales_confirmed 적재 파이프라인 (confirmed-upload) — v5

`asung_sales_confirmed`(확정 매출 + FIFO COGS/GP)를 만드는 `SalesConfirmedUpload.gs`의
설계 규칙과 **리포트 선택·grain·적재 방식의 함정**. 이 테이블은 `asung_sales_unified` VIEW의
① 파티션이라, 여기가 틀어지면 analytics·portal 매출이 통째로 틀어진다.

이 문서는 **2026-07 v4→v5 재구축**의 결론이다. v4(Product grain)를 절대 되살리지 말 것.

---

## 0. 한 줄 요약 (v5)

confirmed는 **Sale Invoices & Credit Notes 리포트를 grain(행 단위)으로** 만든다:

- **grain·매출·날짜·Location·크레딧구분 = Sale Invoices & Credit Notes**
  - `sale = Amount`(세전). `total = sale`. (Invoice의 `Total`은 세후라 안 씀)
  - `invoice_date = Date`(텍스트 `19-May-2026`, 안전). 인보이스/크레딧이 **각자 실제 날짜**로 별도 행.
- **COGS/Profit = Sales by Product Details 룩업 전용**, 키 = **(Order#, SKU)**
  - `profit = sale − cogs`로 재계산 (Invoice Amount 기준으로 내부 일관)
- **report_month = 각 행 invoice_date 의 월(YYYY-MM)** — 파일 단위가 아니라 **행 단위**
- **status = 'COMPLETED'** 로 적재 (인보이스 발행됨 = 확정)
- **적재 = load job → staging → CREATE OR REPLACE** (streaming insertAll 금지)

**❌ v4의 것들을 되살리지 말 것:** Product를 grain으로 쓰기 / Document# 첫 인보이스번호로 JOIN /
파일 단위 report_month 감지 / status='' 적재 / streaming insertAll + DELETE.

---

## R-CU1. Cin7 리포트마다 날짜 컬럼 타입이 다르다 — datetime 리포트는 뒤집힌다

xlsx→Google Sheets 변환 시 **날짜 셀이 datetime 객체면 DD/MM ↔ MM/DD로 뒤집힐 수 있다**
(일·월 둘 다 ≤12인 날짜만, 1~2%). 텍스트 날짜 리포트는 안전.

| 리포트 | 날짜 컬럼 | 원본 타입 | 안전? |
|---|---|---|---|
| **Sale Invoices & Credit Notes** | `Date` | 텍스트 `19-May-2026` | ✅ 안전 (v5 grain) |
| **Sales by Product Details** | `Invoice date` | 텍스트 `05-Jul-2026` | ✅ 안전 (COGS 룩업) |
| Sale Order Details | `Invoice date` | datetime | ❌ 폐기 |
| Sale Credit Notes by Product | `Credit note date` | datetime | ❌ 폐기 |

`sc_formatDate`가 Date객체/`DD-Mon-YYYY`/`YYYY-MM-DD`/`MM/DD/YYYY`를 모두 방어 처리.

---

## R-CU2. COGS 룩업 키는 (Order#, SKU) — Document# 파싱 폐기 (v5 변경)

- **v4 방식(폐기):** Product의 Document# 첫 인보이스번호 + SKU 로 JOIN. 문제: Product의 크레딧
  Document#는 복합값(`CR-00370, 37045` / `41066, CR-00362`)이라 첫 숫자 위치가 제각각이고,
  Invoice의 크레딧 Document#(`CR-00370` 순수)와 **매칭 실패** → 크레딧 COGS 깨짐.
- **v5 방식:** COGS/Profit을 Product에서 **`(Order#, SKU)`** 로 룩업.
  - Product `(Order#, SKU)`는 유니크(중복 0), 같은 키에 양수/음수 라인 공존 0 (검증됨).
  - Invoice grain 행 100% 매칭 (2026-05: 25,828행 unmatched 0).
- **완전 반품 쌍 주의:** 같은 (Order#,SKU)가 Invoice에 인보이스+크레딧 두 줄로 있으면(예: +89.9/−89.9,
  2026-05 44건) 두 줄이 Product의 같은 COGS를 참조 → **라인별 GP는 근사**. 매출(Amount)·총 COGS는 정확.

---

## R-CU3. total 컬럼은 sale(세전)을 쓴다

`sale = Invoice Amount`(세전), `total = sale`. Invoice의 `Total`은 세후라 안 쓴다.
(v3의 freight 전파 손상 이슈 이후 계속 유지.)

---

## R-CU4. 세전/세후 — confirmed는 세전(Amount)이다

- **Sale Invoices & Credit Notes:** `Amount` = 세전, `Total` = 세후. → confirmed sale = **Amount**.
- Product Details: `Sale` = 세전, `Invoice` = 세후.
- ⚠️ historical(Cin7Core, SalesOrderData.gs)은 API `Order.Lines[].Total`(세전) + `Tax`(별도)를
  담는다 — **현재 코드는 세전으로 정상**. (테이블에 세후 잔재가 보이면 과거 버전 legacy — data-contract §5)

---

## R-CU5. status = 'COMPLETED' — Status가 권위, Order_Progress는 참고용 (v5 변경)

- **v4는 status=''로 적재**했다(Invoice 리포트에 Status 컬럼 없음). 이 `''`가 소비 앱의
  `UPPER(Status) IN ('CLOSED','COMPLETED')` 필터에서 탈락해 **confirmed 전 월이 화면에서 사라졌다**
  (2026-07 포털/analytics 사고).
- **v5는 status = 'COMPLETED'로 적재.** 근거(사용자 회계 모델):
  - **"인보이스가 발행됨(=confirmed에 있음) = 확정 = CLOSED/COMPLETED."** Status가 권위 신호.
  - **`Order_Progress`는 사람이 수동 표기하는 참고용.** 대개 `4.Invoiced`/`5.Fulfilled`지만
    `3.Finalized`·`Credit Issued`일 수도 있다. **매출 판별을 Order_Progress로 하지 말 것.**
- 그 결과 앱들의 기존 `Status IN ('CLOSED','COMPLETED')` 필터가 그대로 통과 → 수정 불필요.
- VIEW의 confirmed 파티션도 `'COMPLETED' AS Status`로 투영 중(이중 안전). v5 적재가 이미 'COMPLETED'라
  VIEW 투영은 belt-and-suspenders — 나중에 `CAST(status AS STRING)`로 단순화 가능.

> 과거 서술 "상태 판별은 Order_Progress(`5.Fulfilled`,`4.Invoiced`)로"는 **틀림**. 그건 수동표기라
> 확정 오더를 누락시킨다(3.Finalized 등). 확정 판별의 권위는 **Status(=인보이스 발행 여부)**다.

---

## R-CU6. 크레딧(반품)은 발생주의로 이미 정확 — 발생월 자연 귀속

- Invoice grain에서 **크레딧노트는 발행일(Date)을 가진 별도 행**으로 들어온다 → 발생월에 자연 귀속.
- 크레딧 판별은 `Invoice/ credit note = 'Credit note'` 컬럼(명시) 또는 `sale < 0`. **절대
  `document_number LIKE '%CR-%'`로 하지 말 것** — 복합 Document의 양수 판매 라인까지 크레딧으로
  오분류된다(2026-07: 1월에 2월 판매 63,439이 report_month로 끌려간 원인).
- 크레딧 행은 sale·cogs·profit이 음수 → 발생월 순매출에서 정확히 차감. 별도 부호 처리 불필요.
- 검증: 2026-05 = 25,828행, sale 1,205,615.35, 크레딧 80행 −4,233.21 (전부 5월 발생).

---

## R-CU7. grain = Invoice → 매출 0(무료증정/샘플) 라인 제외 (v5)

- Product에만 있고 Invoice에 없는 라인(2026-05: 564행)은 전부 **Amount 0**(무료증정/샘플/미인보이스).
  Invoice grain이라 자동 제외 — **매출 영향 0**.
- 부작용: 그 라인들의 COGS(~$12k/월)도 제외됨 = "매출 없는 증정품 원가"는 confirmed에 안 담김.
  "sales confirmed"엔 판매만 담는 게 맞으므로 정상. (전사 원가 분석이 필요하면 별도 소스로.)

---

## R-CU8. report_month = 행별 invoice_date 월 (파일 단위 감지 폐기, v5)

- **v4는 report_month를 "파일 단위 최다월"로 감지** → 한 파일에 다른 달이 섞이면 통째로 오적재.
  실제 사고: 1월 파일에 2월 invoice 18,854행/+776,038이 섞여 **report_month=2026-01에 흡수**
  (1월 매출 947k → 1,721k 부풀고, 2월은 아예 없어짐). 3월도 4월을 삼킴.
- **v5는 각 행의 invoice_date 월을 report_month로** 부여 → 파일에 섞여도 각 행이 제 달로 감. 오적재 원천 차단.
- 그래도 **단일 월 파일로 pull하는 규칙은 유지** (Invoice date 범위를 딱 그 달로). 이중 안전.

---

## R-CU9. 적재 = load job → staging → CREATE OR REPLACE (streaming 금지, v5)

- **v4의 streaming insertAll은 적재 직후 DELETE가 buffer에 막혀** 재적재가 조용히 실패
  (`would affect rows in the streaming buffer`). status/grain 바꿔 올려도 옛 행이 안 지워짐.
- **v5 절차:**
  1. `sc_stageAllMonthsV5()` — 전 월을 **load job**으로 `asung_sales_confirmed_staging`에 적재 (buffer 없음)
  2. `sc_verifyStagingV5()` — 월별 sale/cogs/크레딧/min~max 확인
  3. `sc_commitRebuildV5()` — `CREATE OR REPLACE TABLE ... PARTITION BY DATE_TRUNC(invoice_date,MONTH)
     CLUSTER BY customer,brand,sku AS SELECT * FROM staging` (DELETE 없이 통째 교체 = buffer 무관)
- 단일 월 검증: `sc_testMonthV5()` (TARGET 월만 `_staging_test`에 올려 숫자 확인, main 무건드림).
- 파일 감지: `sc_dryRunCheckV5()`.

---

## 매달 운영 (v5)

월마다 **단일월 2파일**:
1. **Sale Invoices & Credit Notes** — 그 달 Date 범위만. (grain·매출·날짜·Location·Order Progress·크레딧)
2. **Sales by Product Details** — 같은 달. (COGS/Profit 룩업용)

파일명 규칙: 월 태그 필수(`NOV25`…`JUN26`), 리포트 식별어(`saleinvoices`/`creditnotes`, `salesbyproduct`).
`sc_extractMonthFromFilename`은 월 태그 뒤 `.`/`_`/공백/`V`/끝을 인식(`..._MAY26_V2.xlsx` OK).

절차: `sc_dryRunCheckV5()` → `sc_testMonthV5()`(한 달) → `sc_stageAllMonthsV5()` →
`sc_verifyStagingV5()` → `sc_commitRebuildV5()` → `checkSalesConfirmedStatus()`.

---

## VIEW(asung_sales_unified) 연동 메모

- confirmed 파티션은 `WHERE sale IS NOT NULL`만(status 조건 금지 — R-CU5 이력).
- confirmed↔historical 중복 제거는 **order_number 기준**(`Order_Number NOT IN confirmed_orders`).
- **크레딧 발생월 CASE 단순화 가능(v5):** v4 VIEW는 `CASE WHEN sale<0 THEN PARSE_DATE(report_month)
  ELSE invoice_date END AS sale_date`로 크레딧을 report_month로 옮겼다. v5는 크레딧이 이미
  발생일(invoice_date)을 가지므로 이 CASE가 불필요 → `sale_date = invoice_date`로 단순화하면
  sale_date축 = invoice_date축이 되어 축 혼란이 사라진다.

---

## 검증 쿼리

```sql
-- 월별 정합 (min~max가 그 달 범위여야, non_completed=0 이어야)
SELECT report_month, COUNT(*) rows_cnt, ROUND(SUM(sale),2) sale, ROUND(SUM(cogs),2) cogs,
  ROUND(SUM(profit)/NULLIF(SUM(sale),0)*100,1) gm_pct,
  COUNTIF(sale<0) credit_lines, COUNTIF(status!='COMPLETED') non_completed,
  MIN(invoice_date) min_d, MAX(invoice_date) max_d
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_confirmed`
GROUP BY report_month ORDER BY report_month;

-- VIEW 통과 매출 (앱이 보는 값)
SELECT FORMAT_DATE('%Y-%m', invoice_date) m, ROUND(SUM(sale),2) revenue,
  COUNT(DISTINCT order_number) orders
FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_unified`
WHERE invoice_date >= '2025-11-01' AND UPPER(Status) IN ('CLOSED','COMPLETED')
GROUP BY m ORDER BY m;
```

## 검증된 기준선 (2026-07 v5 재구축)

| 월 | sale | 비고 |
|---|---|---|
| 2025-11 | 763,897.56 | grain 바뀌어도 동일(크레딧 전부 11월) |
| 2026-01 | 947,331.13 | v4 오적재 1,721,477 → 정상화(2월 흡수분 제거) |
| 2026-02 | 774,146.38 | v4엔 없던 독립 월로 복구 |
| 2026-03 | 958,595.19 | v4 오적재 1,877,122 → 정상화 |
| 2026-04 | 908,754.10 | v4엔 없던 독립 월로 복구 |
| 2026-05 | 1,205,615.35 | Invoice grain(발생주의). v4 Product netted는 1,207,518 |
