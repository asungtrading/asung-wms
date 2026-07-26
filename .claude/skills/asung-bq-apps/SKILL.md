---
name: asung-bq-apps
description: >
  Asung Trading의 BigQuery 데이터를 쓰는 프론트엔드 앱·포털을 만들거나 수정할 때 반드시 이 스킬을 먼저 읽으세요.
  GitHub Pages 내부 도구(analytics.html, purchasing.html, OpenOrders.html), 고객용 Customer Portal,
  Shopify 연동 페이지 등의 작업에서 트리거됩니다.
  "analytics.html", "purchasing.html", "Customer Portal", "포털", "대시보드", "도구 추가",
  "OAuth 로그인", "JSONP", "GitHub Pages 배포", "tools.asung.ca", "고객 화면", "재고 표시" 등의
  키워드가 나오면 이 스킬의 패턴(내부=@asung.ca OAuth, 고객용=JSONP+서버사이드 BQ, GitHub Actions 배포,
  Edmonton 재고 분리 규칙, 캐시 패턴)을 반드시 따르세요. 특히 customer-portal.html은 작업 전
  최신 GitHub 버전을 먼저 가져오지 않으면 다른 사람의 변경을 덮어쓸 수 있습니다.
---

# Asung Trading BQ 활용 앱/포털 스킬

Asung의 화면 도구는 두 부류입니다: **직원용 내부 도구**(GitHub Pages, `@asung.ca` 계정 제한)와 **고객용 포털**(비밀번호 인증, 서버사이드 BQ). 데이터 접근 방식과 인증이 서로 달라서, 어느 부류인지 먼저 구분하고 그에 맞는 패턴을 쓰세요.

## 두 부류 비교

| | 내부 도구 | 고객용 포털 |
|---|----------|------------|
| 호스팅 | GitHub Pages (`asungtrading/tools`) | tools.asung.ca (GoDaddy CNAME) |
| 인증 | Google OAuth, `@asung.ca` 도메인 제한 | 비밀번호 + 세션 |
| BQ 접근 | 클라이언트가 OAuth 토큰으로 직접 / 또는 사전 push된 JSON | **서버사이드(Apps Script)만**, JSONP로 전달 |
| 예시 | analytics.html, purchasing.html, OpenOrders.html | customer-portal.html |

**원칙: 고객은 BQ에 직접 닿지 않는다.** 고객용은 Apps Script 웹앱이 BQ를 대신 쿼리하고 JSONP로 결과만 내려줍니다. 자격증명·내부 식별자가 고객 브라우저에 노출되면 안 됩니다.

---

## 내부 도구 패턴 (GitHub Pages)

### 배포
- 레포 `asungtrading/tools`, GitHub Actions(`deploy.yml`), `cancel-in-progress: true`.
- 파일: `OpenOrders.html`, `SalesOverview.html`, `analytics.html`, `purchasing.html` 등 단일 HTML.

### OAuth 도메인 제한
- OAuth Client ID(공개값, 프론트에 노출되어도 무방)로 Google 로그인.
- `@asung.ca` 도메인만 허용. analytics.html은 Google Identity Services 폴링 패턴으로 도메인 체크.

### 데이터 공급
- 자주 쓰는 마스터/재고는 Apps Script가 GitHub API로 **사전 push**: `master.json`(SKU→name/brand/supplier, 8,800+), `stock.json`.
- 무거운 분석 쿼리는 클라이언트에서 OAuth 토큰으로 BQ 직접 호출.

---

## 고객용 포털 패턴 (Customer Portal)

가장 활발히 작업하는 영역입니다. **작업 전 반드시 아래 두 가지를 지키세요.**

### ⚠️ 작업 전 필수
1. **최신 GitHub 버전의 `customer-portal.html`을 먼저 가져온 뒤** 수정하세요. 오래된 로컬본을 베이스로 작업하면 다른 변경(예: Edmonton 재고 분리)을 덮어씁니다 — 실제로 그렇게 날아간 적 있습니다.
2. 백엔드(`CustomerPortal.gs`)를 고쳤으면 **New Version 재배포** (안 하면 반영 안 됨 — `asung-apps-script` 스킬 규칙 4).

### 아키텍처
- 프론트: `customer-portal.html` (GitHub Pages → tools.asung.ca)
- 백엔드: `CustomerPortal.gs` ("Customer Purchase Data" Apps Script 프로젝트), 비밀번호 인증 + JSONP + 서버사이드 BQ.
- 설정 시트(Config Spreadsheet): 탭 `Groups`, `Stores`, `Sessions`.
- 탭 4개: Overview / Buy More-Reorder / Price List / Order History.

### Edmonton 재고 분리 (영구 규칙 — 되돌리지 말 것)
- 재고는 `Stock_Toronto` / `Stock_Edmonton` **별도 컬럼**으로 표시. `_plStockLoc` / `stock_location`이 구동.
- **절대 단일 `Stock` 컬럼으로 합치지 말 것.**

### 캐시 / 성능 (HTML 측)
- 공유 SKU 상세 캐시: `getSkuDetail` / `_skuDetailCache` / `_skuCacheKey`.
- 백그라운드 탭 프리페치: `prefetchOtherTabs()`.
- promise 중복 제거(deduplication).
- 백엔드 캐시 즉시 갱신: `clearPriceListCache()` / `clearConfigCache()`.

### Price List 탭
- 썸네일 hover 확대, list price 취소선, Your Price 초록, 볼륨 배지, 필터, 100건 페이지네이션.
- 숨김 컬럼: Tags / Best Discount / Image URL.
- Service 카테고리는 추천 쿼리에서 제외.

상세(설정 시트 구조, price list 그룹, 이미지 연동 등)는 `references/customer-portal.md` 참고.

---

## 새 도구를 만들 때 결정 트리

1. **누가 보는가?** 직원만 → 내부 도구(GitHub Pages + @asung.ca OAuth). 고객 → 포털(서버사이드 BQ + JSONP).
2. **데이터가 얼마나 무거운가?** 가벼운 마스터/재고 → 사전 push된 JSON. 무거운 집계 → BQ 쿼리(내부는 직접, 고객용은 Apps Script 경유).
3. **쿼리는 어떻게 짜는가?** → `asung-bq-data-model` 스킬의 올바른 테이블·필터 규칙을 따른다. (매출은 `Order_Progress IN ('5.Fulfilled','4.Invoiced')`, Credit Issued 제외 등)
4. **인증·비밀값?** OAuth Client ID는 공개값이라 프론트에 둬도 되지만, 포털 비밀번호·토큰·API 키는 절대 HTML/JS에 박지 않는다.

---

## 프론트엔드 작성 시

- HTML 도구를 새로 만들거나 UI를 다듬을 때는 `frontend-design` 스킬의 디자인 토큰·스타일 가이드를 함께 참고.
- 단일 HTML 파일 패턴(CSS·JS 인라인)을 유지 — 기존 도구들과 일관성.

---

## 연계 스킬

- **쿼리할 테이블·필터** → `asung-bq-data-model` (반드시 이걸로 매출 필터 확인)
- **백엔드 .gs·배포·트리거** → `asung-apps-script`
- **Cin7 API 원본 필드** → `cin7-api`
- **UI 디자인** → `frontend-design`
