# Customer Master 싱크 (Shopify + Cin7 → BQ)

방문 이벤트(`shopify_customer_login_event`)는 이메일/client_id만 있어서 "이 방문자가 누구인지·어디 지역인지·승인 고객인지"를 모른다. 그걸 채우는 게 **두 개의 손님 마스터 테이블**이다. 둘 다 System_Automation GAS 프로젝트에서 매일 싱크한다.

---

## 테이블 1: shopify_customer_master (Shopify 전체 손님)

- 위치: `geometric-rock-487814-k4.Cin7_Customer_Data.shopify_customer_master`
- 소스: Shopify Admin REST `/admin/api/2025-10/customers.json` (cursor 페이지네이션)
- 적재: `ShopifyCustomerSync.gs` (prefix `SCM_`), truncate + insertAll, 일일 트리거
- 규모: ~2,784명 (2026-07)

### 컬럼
`customer_id, email, first_name, last_name, phone, orders_count, total_spent, company, city, province, province_code, country, zip, branch_label, tags, is_wholesale, signup_period, created_at, updated_at, synced_at`

### 핵심 파생 필드 (⭐ 정탐 분석의 근거)
- **`is_wholesale`** (BOOL) — `tags`에 `wholesale`가 있으면 true. **가격 열람·주문 가능 여부 = 승인 여부.**
  - asung.ca는 등록 후 **승인**받아야 가격이 보인다. 승인 시 자동으로 `wholesale`, `Asung-Shopify` 태그가 붙는다.
  - **`wholesale` 태그 없으면**: 이메일 인증 로그인은 되지만 **가격 안 보이고 주문 불가** → 사실상 무해 (정탐해도 볼 게 없음).
  - 따라서 정탐 후보 = `is_wholesale=true` + 구매 0 + 방문 잦음. (단순 "구매 없음"은 미승인자까지 섞여 부정확.)
- **`signup_period`** (STRING) — 가입 시기 태그(`JUL26` 형식: 월3자+연2자)를 `YYYY-MM`으로 정규화 (JUL26 → 2026-07). 수동으로 붙이는 태그라 형식은 매우 일정. 정규식: `((?:JAN|FEB|...|DEC)[0-9]{2})`.
- **`branch_label`** — province_code로 추정 (BC/AB/SK → Edmonton, 그 외 → Toronto). Shopify 손님은 Cin7 Location이 없으므로 주소 기반 추정.
- **주소** — 등록 시 주소 필수라 거의 100% 채워짐. `default_address`의 `company`(⚠️ company는 **주소 안**에 있음), city, province_code 등.

### staff 태그 (테스트 노이즈 제거)
직원 계정에 `staff` 태그를 붙이면 방문 통계에서 제외한다. 감지: 공백 제거 후 `,staff,` 포함 검사 (regex 이스케이프 회피). 단 **로그인 안 하고 테스트하면 익명으로 잡혀 못 거름** → 직원은 로그인 후 테스트하는 운영 규칙 필요.

---

## 테이블 2: asung_customer_master (Cin7 전체 고객)

- 위치: `geometric-rock-487814-k4.Cin7_Customer_Data.asung_customer_master`
- 소스: Cin7 Core `GET /customer` (Limit=100 페이지네이션)
- 적재: `CustomerMasterSync.gs` (prefix `CCM_`), truncate + insertAll, 일일 트리거
- 규모: ~8,902명 (Toronto 8,779 / Edmonton 118 / 미설정 5)

### 컬럼
`cin7_customer_id, customer_name, email, all_emails, phone, status, price_tier, branch, branch_label, city, state, country, synced_at`

### 핵심 필드
- **`branch`** = Cin7 `Location` 필드 원본. **이게 브랜치 판별의 정답** (주소 추측 불필요).
  - `"Asung Trading Inc."` → Toronto / `"Asung - Edmonton"` → Edmonton
  - 매출 데이터(`asung_sales_unified`)의 location 표기와 동일.
- **`branch_label`** — 위를 Toronto/Edmonton로 정규화 (`ccm_branchLabel_()`).
- **주소(city/state/country)** — `Addresses[]` 중 default 우선 선택: Shipping default → Billing default → default → 첫 주소. state는 2글자 코드(ON/AB/NU 등).
  - ⚠️ 한 고객이 Shipping/Billing 주소가 서로 다른 주일 수 있음(예: Shipping=Iqaluit/NU, Billing=Edmonton/AB). 그래도 **브랜치는 Location에서** 정하므로 주소 혼동과 무관.
- **`price_tier`** — Wholesale(B2B, 7,331) / AONE(B2C, 별도 사이트, **분석 제외**) / 기타. WHOLESALE_TIERS = `('Wholesale','USWholesale USD')`.

### Cin7 API 주의
- 키: `getProp('CIN7_ACCOUNT_ID')`, `getProp('CIN7_APPLICATION_KEY')` (⚠️ `CIN7_API_KEY` 아님).
- 주소 구조: `Addresses[].{Line1,City,State,Postcode,Country,Type,DefaultForType}`. Type = "Shipping"|"Billing".
- 상세는 `cin7-api` 스킬 참조.

---

## 3-way 조인 로직 (검증됨)

```
방문(email/client_id)
  ↔ shopify_customer_master(email) → orders_count, is_wholesale, signup_period, branch_label, 주소
  ↔ asung_customer_master(email) → customer_name, price_tier, branch(정확)
  ↔ asung_sales_unified(customer=이름) → 매출
```

- **지역 우선순위**: Cin7 branch/주소(정확) → 없으면 Shopify 주소(추정).
- **이름 우선순위**: Cin7 customer_name → Shopify first+last → company.
- **미거래 판별**: Cin7 wholesale tier 없음 AND Shopify orders=0. (여기에 is_wholesale로 "가격 볼 수 있는 승인자"만 필터.)

---

## 컬럼 추가 시 (스키마 확장)
`ADD COLUMN IF NOT EXISTS` 먼저 → **그 다음** 싱크 재실행 (컬럼 없이 insertAll하면 에러). 두 싱크 모두 truncate+insert라 재실행이 곧 전체 갱신.
