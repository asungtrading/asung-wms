# visitor-analytics.html (방문 분석 대시보드)

방문 데이터 분석은 **`analytics.html`(매출 전용)과 분리된 별도 앱** `visitor-analytics.html`로 구축됨. GitHub Pages `asungtrading/tools` → `tools.asung.ca/visitor-analytics.html`. analytics.html의 검증된 뼈대(OAuth implicit flow, bqQuery, 다크 테마 CSS, 탭 구조)를 재활용.

- 인증: analytics.html과 **같은 CLIENT_ID** (`105948904172-...`), @asung.ca 도메인 제한, implicit flow. localStorage 키: `asung_va_token` / `asung_va_token_exp`.
- ⚠️ 배포 시 Google Cloud Console OAuth 클라이언트의 redirect URI에 `https://tools.asung.ca/visitor-analytics.html` **정확한 전체 경로** 추가 필요 (origin만으론 부족).
- 상세 프론트엔드 패턴은 `asung-bq-apps` 스킬.

## 9개 탭
1. **개요** — KPI + 일별 추이 (데이터 1~2일이면 bar, 그 이상 line 자동 전환). 추적 시작일 고정 상수 `TRACKING_START='2026-07-16'`.
2. **👁 미거래 방문 고객** — 구매 0 방문자. `승인 상태` 필터(승인만/전체/미승인만) 기본 "승인만". 컬럼: 이름·이메일·회사명·승인·지점·가입시기(JUL26+정규화)·유형·PV·방문일수. 이름 클릭 → 인라인 확장.
3. **🛒 구매 고객 방문** — 온라인 주문 有 방문자 (미거래의 대칭). 온라인 주문수·구매액 컬럼. 이름 클릭 → 인라인 확장.
4. **인기 페이지** — URL 정규화(쿼리스트링/앵커 제거, 검색은 q= 보존) + **메뉴/위치별 아코디언 그룹**(홈/컬렉션/상품/검색/계정/장바구니/안내/기타).
5. **많이 찾는 SKU·브랜드** — 총/로그인/익명/익명% 구분. **브랜드 클릭 → SKU 필터링**. 각 행 👥 버튼 → 조회자 모달.
6. **카테고리 관심도** — collection별 로그인/익명.
7. **🗺 지역 분포** — 방문 고객/전체 등록 토글. 캐나다 주별 타일 지도(SVG, geocoding 없음) + 도시 TOP 막대 + 지점 KPI.
8. **이탈 고객** — 구매O 최근 방문X.
9. **미방문 고객** — 구매O 방문 전무.

## 재사용 엔진 (공용 함수)
- **정렬 테이블**: `registerTable/renderTable/sortTable`, `_tables`/`_sortState`. cellRender[i]=커스텀 렌더, numCols=숫자 정렬. ⚠️ `renderTable`은 `r.slice(0, headers.length)`로 **헤더 개수만 렌더** — 초과 컬럼은 정렬/렌더용 숨김 데이터(플래그, 원본 URL 등).
- **CSV**: `_csvCache[key]`, `csvBtn(key)`, `downloadCsv(key)`. BOM 포함(한글). 표·방문상세·조회자 목록 전부 지원.
- **인라인 확장(드릴다운)**: `toggleVisitorRow(el, email, name)` — customer-portal 스타일로 행 아래 펼침, 한 번에 하나. 공용 `fetchVisitorEvents(email)` + `renderVisitorEvents(rows, csvKey)`.
- **모달**: `showVisitorDetail`(조회자 팝업 내 체이닝용), `showProductViewers(type, value)`(SKU/브랜드 조회자 — 로그인 조회자 목록 + 익명 요약, 각자 구매고객/미거래 태그).

## ⚠️ 시간대 + 파티션 프루닝 (중요)
- 모든 날짜 집계·필터는 **`America/Toronto`** 기준. UTC로 하면 토론토 저녁 방문이 다음날로 밀림. `DATE(event_time, 'America/Toronto')`, `CURRENT_DATE('America/Toronto')`.
- ⚠️ **함정**: 시간대 변환된 `DATE(event_time, 'America/Toronto')`는 파티션(`PARTITION BY DATE(event_time)`, UTC 기준)을 **프루닝 못 함** → 매번 풀스캔. 반드시 프루닝용 조건을 **병행**: `AND event_time >= TIMESTAMP(DATE_SUB(CURRENT_DATE('America/Toronto'), INTERVAL ${days+2} DAY))` (경계 오차 2일 여유). 손님 방문 상세는 최근 180일 상한.

## staff 제외 (전 탭 공통)
```sql
-- NOT_STAFF 상수를 모든 EVT 쿼리 WHERE에 추가
(email IS NULL OR LOWER(email) NOT IN (
  SELECT LOWER(email) FROM `...shopify_customer_master`
  WHERE email IS NOT NULL
    AND CONCAT(',', REPLACE(LOWER(IFNULL(tags,'')), ' ', ''), ',') LIKE '%,staff,%'
))
```

## 탭 재조회 (stale 방지)
탭 전환 시 **항상 재조회**(처음 1회만 X). 헤더에 "조회: HH:mm"(토론토) 표시 — bqQuery 성공 시마다 갱신. 파티션 프루닝 덕에 재조회해도 가벼움.

## 익명 방문자 지역 (미구현, 옵션 2)
익명(비로그인) 방문자의 지역은 현재 **불가**. Custom Pixel은 샌드박스라 IP/위치 접근 차단, GAS 웹앱도 원본 IP 못 받음. 유일한 길: **Custom Pixel 안에서 외부 IP geolocation API**(ipapi.co 등) fetch → 지역만 payload에 실어 전송. 무료 한도(월 3~5만) 때문에 **세션당 1회 캐싱** 필요. 로그인 손님은 등록 주소로 이미 커버되므로 익명만 대상. 개인정보상 IP 원본은 저장 안 하고 지역 결과만.
