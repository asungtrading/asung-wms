# Customer Portal 상세 (customer-portal)

`customer-portal.html` + `CustomerPortal.gs` ("Customer Purchase Data" Apps Script 프로젝트). tools.asung.ca에 GoDaddy CNAME으로 배포.

> ⚠️ **비밀값은 여기 적지 않습니다.** 포털 비밀번호·로그인 자격증명·토큰은 Script Properties / 설정 시트에만 두세요. 아래는 운영 식별자와 구조만 다룹니다.

## 작업 전 체크리스트

1. GitHub에서 **최신 `customer-portal.html`을 먼저 fetch** → 그걸 베이스로 수정. (stale 베이스가 Edmonton 재고 분리를 덮어쓴 사고 있었음)
2. `.gs` 수정 시 **New Version 재배포** 필수.
3. 배포 후 캐시 갱신이 필요하면 `clearPriceListCache()` / `clearConfigCache()` 실행.

## 설정 (Config Spreadsheet)

- 탭: `Groups`, `Stores`, `Sessions`.
- `Stores` 시트 컬럼:
  - col C `store_name` = 화면 표시용 이름 (display only)
  - col D `bq_names` = 파이프(`|`)로 구분된 이름 별칭 (BQ 매칭용)
- 가격 그룹(Groups): 고객을 할인율 그룹에 매핑. 각 그룹은 price list 스프레드시트에 연결.

## 가격 그룹 / Price List

- 가격 그룹별로 별도의 price list 스프레드시트가 있음. 그룹→스프레드시트 ID 매핑은 설정에 보관.
- 알려진 price list 스프레드시트 ID (운영 식별자):
  - 7% 그룹: `1xXUO7hYOLqjxLvrfQ_s4CZ72Tn7_tIptQI4b5_53MZU`
  - 10% 그룹: `18bch3F2mM2eOM3_mAnJhha7X3H4rxqN-sKJsBXxOorA`
- Price List 탭 UI: 썸네일 hover 확대, list price 취소선, Your Price 초록, 볼륨 배지, 필터, 100건 페이지네이션.
- 숨김 컬럼: Tags / Best Discount / Image URL.
- Service 카테고리는 추천 쿼리에서 제외.

## 탭 4개

1. **Overview** — 요약.
2. **Buy More / Reorder** — 재구매 추천 (고객 구매 이력 기반, `asung-bq-data-model`의 고객별 SKU 빈도 쿼리 참고).
3. **Price List** — 그룹별 가격표.
4. **Order History** — By Order ↔ All Line Items 토글(아코디언), 페이지네이션.

## 재고 표시 (Edmonton 분리 — 영구)

- `Stock_Toronto` / `Stock_Edmonton` **별도 컬럼**. `_plStockLoc` / `stock_location`이 구동.
- **단일 Stock 컬럼으로 합치지 말 것.**

## 성능 패턴 (HTML 측)

- 공유 SKU 상세 캐시: `getSkuDetail` / `_skuDetailCache` / `_skuCacheKey`.
- 백그라운드 탭 프리페치: `prefetchOtherTabs()`.
- promise 중복 제거.

## 이미지 연동 (진행 중 / pending)

- Cin7 이미지 연동을 `PriceCalculator.gs` 경유로 계획:
  - imageFolderId: `1A0r8zRz2wTfQJVGvsXVeTXlXPPMe2mpG`
  - `ImagesAndAttachments_YYYYMMDD.csv` (Default=Yes, 8,291 SKUs)
  - `asung_product_images` BQ 테이블을 만들어 `_queryPriceList`에서 JOIN하는 방안 검토.

## 데이터 흐름 요약

```
고객 브라우저 (customer-portal.html)
   │  비밀번호 인증 → 세션
   │  JSONP 호출
   ▼
CustomerPortal.gs (Apps Script 웹앱)  ← 서버사이드에서만 BQ 접근
   │  설정 시트로 그룹/스토어/세션 해석
   │  BQ 쿼리 (asung_sales_unified 등)
   ▼
JSONP 응답 → 화면 렌더
```

고객은 BQ·자격증명에 직접 닿지 않습니다. 모든 쿼리는 `CustomerPortal.gs`가 대신 수행.
