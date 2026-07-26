---
name: shopify-tracking
description: >
  Asung Trading의 Shopify(asung.ca) 손님 행동 추적·방문 분석 시스템을 다룰 때 반드시 먼저 읽으세요.
  손님 로그인/방문/페이지뷰/상품조회 추적, Shopify Pixel(Custom Pixel / Customer Account UI extension),
  GAS 웹앱, BigQuery `Cin7_Customer_Data`(방문 이벤트 + 손님 마스터 2종), 그리고 visitor-analytics 대시보드를
  만들거나 수정할 때 트리거됩니다. 키워드: "방문 추적", "페이지뷰", "정탐꾼", "미거래 방문 고객", "구매 고객 방문",
  "경쟁사 가격 체크", "Custom Pixel", "page-view-custom", "webPixelCreate", "shopify app deploy",
  "shopify_customer_login_event", "shopify_customer_master", "asung_customer_master", "손님 마스터",
  "ShopifyCustomerSync", "CustomerMasterSync", "is_wholesale", "wholesale 태그", "승인 고객", "signup_period",
  "staff 태그", "직원 제외", "visitor-analytics", "방문 분석", "지역 분포", "브랜치", "product_view", "조회자",
  "Cin7_Customer_Data" 등이 나오면 추측하지 말고 이 스킬의 검증된 아키텍처·함정·해결책을 먼저 확인하세요.
  특히 Web Pixel 활성화는 extension-only 앱에서 구조적으로 막히니(App pixel Disconnected) 반드시 Custom Pixel을 쓸 것.
---

# Asung Trading Shopify 손님 행동 추적 스킬

Asung은 asung.ca(Shopify) 손님의 **로그인·방문·페이지뷰**를 추적해 BigQuery에 쌓고, 그 위에서 분석합니다. 목적은 두 가지: **(1) 경쟁사/정탐꾼 솎아내기** — 등록·로그인은 자주 하지만 주문은 안 하는 손님, **(2) 실제 구매 손님의 사이트 이용 빈도 파악**.

이 문서는 "왜 이 아키텍처인가"와 "절대 다시 밟으면 안 되는 함정"을 인코딩합니다. 2026-07 구축 당시 시행착오로 알아낸 것들이라 문서에도 잘 안 나옵니다.

---

## 핵심 아키텍처 (한눈에)

```
[asung.ca 손님 행동]
   │
   ├─ 계정 페이지 조회 → Customer Account UI Extension (App pixel) → GAS → BQ
   │     (login tracker 앱의 login-tracker extension)
   │
   └─ 전체 페이지뷰 + 상품조회 → Custom Pixel (page-view-custom) → GAS → BQ
         (⭐ page_viewed + product_viewed 둘 다 구독. 정탐 추적의 핵심)
   │
   ▼
[GAS 웹앱: Shopify Customer Login Tracker]  doPost() → BigQuery streaming insert
   │
   ▼
[BigQuery: Cin7_Customer_Data]
   ├─ shopify_customer_login_event   (방문/페이지뷰/상품조회 — 익명 client_id + 로그인 email)
   ├─ shopify_customer_master        (Shopify 전체 손님 + 주소 + is_wholesale + signup_period)  ← 일일 싱크
   └─ asung_customer_master          (Cin7 전체 고객 + branch + 주소 + price_tier)              ← 일일 싱크
   │   (조인: asung_sales_unified 매출까지 3-way)
   ▼
[분석] visitor-analytics.html (tools.asung.ca, @asung.ca OAuth) — 9개 탭
        ※ 매출 전용 analytics.html과는 별개 앱
```

**세 갈래 데이터:**
- **방문 이벤트** — 누가(email/client_id) 뭘(page/product) 봤나.
- **손님 마스터 2종** — 방문자가 실제 누구인지·어디 지역인지·승인(가격 열람) 고객인지 채움. `references/customer-master.md`.
- **분석 앱** — `references/visitor-analytics-app.md`.

**두 개의 추적 지점이 공존:**
- **Custom Pixel `page-view-custom`** = 스토어 전체(page_viewed) + 상품(product_viewed). ⭐ 주력.
- **Customer Account UI Extension** = 로그인 후 계정 페이지만. App pixel 자동 작동. 보조.

---

## ⚠️ 절대 규칙 (다시 헤매지 않으려면)

### R1 — Web Pixel은 Custom Pixel로 만든다. App pixel 활성화 시도 금지.
우리 login tracker 앱은 **extension-only**(백엔드 없음)라, App pixel(`page-view-tracker` extension) 활성화가 **구조적으로 불가능**하다. `webPixelCreate` mutation이 필요한데:
- BCI Connector 토큰 → "No extension found" (그 앱 소유 extension이 아님)
- automation token(`atkn_`) → 401 (CI/CD 전용, Admin API 인증 안 됨)
- `shopify app dev` GraphiQL → 실제 스토어는 dev store가 아니라 거부됨
- 정공법(앱 백엔드 or dev store)은 우리 구조상 불가

**결론: Custom Pixel을 쓴다.** Admin → Settings → Customer events → "Add custom pixel" → 코드 붙여넣기 → Save → Connect. 앱·토큰·mutation 전부 불필요하고 Connect 버튼으로 100% 켜진다. 현재 운영 중인 것은 **`page-view-custom`** (초록불 = 작동). App pixel(`login tracker`, 회색/Disconnected)은 무해하니 방치.

### R2 — 정탐 판별의 진짜 기준: wholesale 승인 + 구매 0 (단순 "매출 없음" 아님).
asung.ca는 **등록 후 승인**받아야 가격이 보인다. 승인 시 `wholesale` 태그가 붙고(자동), 이게 있어야 가격 열람·주문 가능. **`wholesale` 태그 없으면 로그인돼도 가격 안 보여 무해**(정탐해도 볼 게 없음).
- 따라서 정탐 후보 = **`shopify_customer_master.is_wholesale=TRUE` + 구매 0 + 방문 잦음**. (단순 "매출 없음"은 미승인자까지 섞여 부정확.)
- 회사·역할 이메일(sales@, info@)이거나 방문 빈도 높을수록 의심 가중.
- 상세 로직·쿼리: `references/customer-master.md`, `references/bigquery-schema.md`.
- (Shopify 이메일 ↔ Cin7 고객명은 여전히 직접 조인 불가 — 마스터 테이블의 email로 브릿지.)

### R3 — 세션 유지 문제: "로그인 이벤트"가 아니라 "페이지뷰"를 본다.
asung.ca는 한 번 로그인하면 로그아웃 전까지 세션 유지 → 로그인 이벤트는 재방문을 못 잡는다. 대신 **페이지뷰(`page_view`)가 방문할 때마다 찍히므로** 이걸로 방문 빈도를 측정한다. 비로그인 손님도 `client_id`(익명 브라우저 식별자)로 반복 방문 추적 가능.

### R4 — GAS 웹앱은 절대 URL 바뀌지 않게: New Version 재배포만.
GAS 코드 수정 후 "새 배포"를 또 만들면 `/exec` URL이 바뀌어 모든 Pixel의 ENDPOINT가 깨진다. 반드시 **배포 관리 → 편집 → 새 버전 → 배포** (URL 유지). (asung-apps-script 스킬 규칙 4와 동일.)

### R5 — 노출된 토큰은 즉시 Revoke.
작업 중 automation token 등이 화면/명령어에 노출되면 작업 후 반드시 Dev Dashboard에서 Revoke.

### R6 — 시간대는 America/Toronto, 파티션 프루닝 병행 필수.
모든 날짜 집계·필터는 **`America/Toronto`** 기준(UTC면 토론토 저녁 방문이 다음날로 밀림). 그런데 `DATE(event_time,'America/Toronto')`는 파티션(UTC DATE)을 **프루닝 못 해 풀스캔**한다 → 반드시 프루닝용 `event_time >= TIMESTAMP(...)` 조건을 **병행**(2일 여유). 안 하면 데이터 쌓일수록 "최근 7일" 조회가 전체를 훑음. `references/bigquery-schema.md` 참조.

### R7 — 직원 테스트는 staff 태그로 제외.
직원 Shopify 계정에 `staff` 태그 → 방문 통계 전 탭에서 제외(NOT_STAFF 조건). 감지는 공백 제거 후 `,staff,` 포함. ⚠️ 단 **로그인 안 하고 테스트하면 익명(client_id)으로 잡혀 못 거름** → 직원은 로그인 후 테스트하는 운영 규칙 필요.

### R8 — 분석 대시보드는 탭 전환 시 항상 재조회.
`visitor-analytics.html`은 탭 열 때마다 재조회(1회 캐싱 X) — 안 그러면 오래 켜둔 화면이 stale. 파티션 프루닝(R6) 덕에 재조회해도 가벼움. 헤더에 "조회: HH:mm"(토론토) 표시.

---

## 구성요소 상세

### 1) BigQuery — 데이터셋 `Cin7_Customer_Data` (2026-07 신설, Cin7 매출/재고와 분리)
- **`shopify_customer_login_event`** — 방문 이벤트. `event_type`: `page_view`|`product_view`|`account_view`|`test`|(빈값=초기잔재). product_view는 SKU/브랜드/가격 포함. 파티션 `DATE(event_time)`, 클러스터 `email, client_id`.
- **`shopify_customer_master`** — Shopify 전체 손님(주소·`is_wholesale`·`signup_period`·`tags`). 일일 싱크(`ShopifyCustomerSync.gs`, `SCM_`).
- **`asung_customer_master`** — Cin7 전체 고객(`branch`=Cin7 Location, 주소, `price_tier`). 일일 싱크(`CustomerMasterSync.gs`, `CCM_`).
- 스키마·조인·마스터 상세: `references/bigquery-schema.md`, `references/customer-master.md`
- 쿼리 시 **토론토 날짜 필터 + 파티션 프루닝 병행**(R6)

### 2) GAS 웹앱 — Shopify Customer Login Tracker
- 별도 GAS 프로젝트(System_Automation과 분리). prefix `LT_`.
- `doPost()`가 JSON body 받아 BQ streaming insert. `doGet()`은 헬스체크.
- BigQuery Advanced Service 활성화 필수(`BigQuery.Tabledata.insertAll`).
- 웹앱 배포: 실행=본인, 액세스=**모든 사용자(Anyone)** (외부 Pixel이 호출).
- 전체 코드: `references/gas-webapp.md`

### 3) Custom Pixel (주력 추적)
- Admin → Settings → Customer events → `page-view-custom`
- `page_viewed` + `product_viewed` 구독 → GAS로 `navigator.sendBeacon` 전송
- CORS 우회: `Content-Type: text/plain` (preflight 없음)
- ⚠️ 샌드박스라 IP/위치 못 얻음 (익명 지역은 외부 IP API 필요)
- 전체 코드: `references/custom-pixel.md`

### 4) Customer Account UI Extension (보조)
- login tracker 앱(Dev Dashboard, extension-only). handle `login-tracker`.
- target: `customer-account.order-index.block.render` (로그인 후 첫 화면)
- Customer Account API로 손님 식별 → GAS 전송. 화면엔 아무것도 안 그리는 조용한 블록.
- 배포: `shopify app deploy` → New version release. Customer accounts 편집기에서 블록 배치 필요.
- 코드·toml: `references/account-extension.md`

---

## 새 추적 지점을 추가하거나 수정할 때

1. **Shopify 쪽 함정** → `references/shopify-extension-gotchas.md` 필독 (toml 구조, 배포 에러, App vs Custom pixel 판단)
2. **GAS/BQ 스키마 변경** → `ADD COLUMN IF NOT EXISTS` 먼저, **그 다음** GAS row 매핑 추가 + New Version 재배포 (마스터 싱크는 컬럼 추가 후 재실행). 순서 어기면 insertAll 에러.
3. **분석 앱 수정** → `references/visitor-analytics-app.md` + `asung-bq-apps` 스킬. ⚠️ R6(토론토+프루닝)·R7(staff)·R8(재조회) 항상 적용.
4. **손님 마스터/조인** → `references/customer-master.md`

## reference 파일 지도
- `bigquery-schema.md` — 이벤트 테이블 DDL, event_type, 쿼리 레시피(정탐/staff/프루닝)
- `customer-master.md` — Shopify/Cin7 손님 마스터 2종, is_wholesale/signup/branch, 3-way 조인 (핵심)
- `visitor-analytics-app.md` — visitor-analytics.html 9개 탭·엔진·함정 (핵심)
- `custom-pixel.md` — page_viewed + product_viewed 픽셀 코드
- `gas-webapp.md` — LT_ 웹앱 doPost/재배포
- `account-extension.md` — Customer Account UI Extension
- `shopify-extension-gotchas.md` — Shopify 배포 함정

---

## 연계 스킬
- **BQ 테이블·필터 규칙(매출 조인 등)** → `asung-bq-data-model`
- **GAS 컨벤션(getProp, prefix, 재배포)** → `asung-apps-script`
- **분석 프론트엔드(OAuth, bqQuery, 배포)** → `asung-bq-apps`
- **Cin7 API(고객·주소·Location 필드)** → `cin7-api`
