# 스크립트 인벤토리 (script-inventory)

현재 운영 중인 주요 Apps Script 자동화. 기존 스크립트를 수정하기 전에 해당 항목의 핵심 규칙을 확인하세요.

## 적재 (Cin7 → BQ)

### SalesOrderData.gs
- 판매 주문 상세를 `asung_order_details_historical` 등으로 적재.
- **BQ diff-check 증분 적재** (실행시간 1800s → ~1min).
- v4/v5에서 `Avg_Cost`/`COGS`/`GP` 컬럼 추가.
- `sd_formatDate()`가 Cin7 API의 ISO 날짜(`2026-05-07T00:00:00`)를 그대로 보존(정상). `MM/DD/YYYY`는 fallback 경로일 뿐 — API는 ISO를 준다.
- ⚠️ 테이블에 과거 로더 버전이 남긴 **legacy 행**(날짜 뒤집힘·세후 금액) 잔재 있음. 현재 코드는 정상, 청소는 별도 재적재 필요 (`asung-bq-data-model` data-contract §5 #7).
- `runFullAudit()` / `startAutoFullAudit()` 로 적재 완전성 점검.

### SalesConfirmedUpload.gs (v5 — Invoice grain)
- 월 마감된 FIFO 확정 데이터를 `asung_sales_confirmed`에 적재.
- **grain = Sale Invoices & Credit Notes** (매출 `Amount` 세전 / 날짜 `Date` 텍스트 / Location / 크레딧구분).
- **COGS/Profit = Sales by Product Details 룩업**, 키 = **(Order#, SKU)**. `profit = sale − cogs`. (v4의 Document#+SKU JOIN 폐기)
- **report_month = 행별 invoice_date 월** (파일 단위 감지 폐기 — 1월이 2월 삼키는 오적재 차단).
- **status = 'COMPLETED'** 로 적재 (v4의 `''`가 앱 필터에서 탈락한 사고 이후).
- **적재 = load job → staging → `CREATE OR REPLACE`** (streaming insertAll의 DELETE buffer 트랩 회피).
- 함수: `sc_dryRunCheckV5()` → `sc_testMonthV5()`(한 달 검증) → `sc_stageAllMonthsV5()` → `sc_verifyStagingV5()` → `sc_commitRebuildV5()` → `checkSalesConfirmedStatus()`.
- **단일 월 파일 규칙 유지** (Invoice+Product 쌍, 파일명 월 태그). 상세: `asung-bq-data-model` `references/confirmed-upload.md` 필독.
- ⚠️ Config.gs `ALLOWED_FUNCTIONS`에 v5 함수명 등록 필요(옛 `runSalesConfirmedUpload` 참조는 프로젝트 로드 에러 유발).

### PurchaseHistory.gs
- `asung_purchase_history` (`Cin7_Purchase_Data` 데이터셋)에 발주 이력 적재.
- Advanced Purchase(`v2/advanced-purchase`) 자동 감지, 없으면 Simple Purchase fallback.
- `setupDailyPurchaseTrigger()`로 일 1회 실행.

## 알림 / 워크플로우

### BackorderedItemEmail.gs
- backorder된 품목에 대해 고객에게 자동 이메일.
- **핵심 규칙: Cin7 `Status=ORDERED` + `AdditionalAttribute1='Backordered'`로 판별. 절대 `Status=BACKORDERED`를 쓰지 말 것** (그런 상태값은 split order에서 신뢰 불가).
- 재고는 Cin7 API per-line이 아니라 `asung_stock_daily` BQ 테이블로 확인.
- `bo_getDefaultEmailMap_()`가 Cin7 Customer API에서 Default:true 연락처를 가져옴.
- 상수: `BO_` prefix, `LOG_FOLDER_ID`로 실행 로그 저장.

### InvoiceDateErrorNotification.gs (v3.1)
- invoice date 오류를 감지해 알림.
- CheckLedger 시트 + SaleList 레벨 예비 필터 사용 (InvoiceNumber/OrderDate/InvoiceDate/CustomerReference 필드 기반, 상태 추측 안 함).

### DailyPurchasingReport.gs
- Google Space webhook로 일일 발주 리포트 전송.
- ABC A/B 등급 필터링, urgency 스코어(urgent×3 + A-grade×1).
- 5일치 재고 커버리지 필터, 3일 이상 미발주 시 🔥 N일째미발주 표시.
- Supplier당 20 SKU 캡.

## 모니터링

### SystemMonitor.gs (System_Automation 프로젝트)
- 주요 스크립트 실행 결과를 `Asung_System_Monitor` 시트에 로깅.
- 실패 시 Google Space 알림.
- prefix `MON_`. 새 스크립트 추가 시 모니터링 대상에 등록.

## 웹앱 (/exec URL — 수정 후 New Version 재배포 필수)

### CustomerPortal.gs ("Customer Purchase Data" 프로젝트)
- Customer Portal 백엔드. 비밀번호 인증 + JSONP + 서버사이드 BQ.
- 자세한 구조는 `asung-bq-apps` 스킬 참고.

### BarcodeLogger.gs (standalone 프로젝트)
- 액션: `search`, `getDuplicateCheckData`, `saveRows`.
- GS1 prefix `829534`, GTIN-12 + GTIN-14 (pack type용).
- pack qty 변경 시 GTIN-14 유지.

### reorder-proxy.gs
- Shopify 재주문 페이지(`asung.ca/pages/my-reorder-list`)용 프록시.
- CORS/CSP 이슈 주의 (Shopify theme.liquid CSP에 script.google.com 허용 필요).

## 공통 주의

- 모든 프로젝트의 비밀값은 Script Properties + `getProp()`.
- 전역 상수는 prefix 규약 (BO_/FO_/EI_/MON_/RO_/BC_).
- 웹앱은 수정 후 반드시 New Version 재배포.
- 적재 재실행은 streaming buffer 때문에 DELETE 대신 CTAS 우선.
