# Shopify Extension 함정 모음 (2026-07 구축 시 실제로 밟은 것들)

문서에 잘 안 나오거나 시행착오로만 알 수 있던 것들. 다시 Shopify extension을 만질 때 여기부터 확인.

## 1. App pixel vs Custom pixel — 가장 큰 함정
- **App pixel**(앱에 포함된 web_pixel_extension)은 `webPixelCreate` mutation으로만 활성화됨. 이 mutation은 **그 extension을 소유한 앱 자신의 인증 컨텍스트**에서만 실행 가능.
- extension-only 앱(백엔드 없음)은 그 컨텍스트를 못 만든다:
  - 다른 앱 토큰(BCI Connector 등) → "No extension found"
  - automation token(`atkn_`) → 401 (CI/CD 전용)
  - `shopify app dev` GraphiQL → 실제 스토어는 dev store 아니라 거부
- **해결: Custom pixel 사용.** Admin UI에서 코드 붙여넣고 Connect. 앱/토큰/mutation 불필요.
- 증상: Customer events에서 앱 pixel이 **회색/"Disconnected"** 로 남음. Custom pixel은 Connect 후 **초록불**.

## 2. Dev Dashboard로 전환됨 (Partner Dashboard 대체)
- 2026-01부로 Admin의 "Legacy custom app" 신규 생성 불가. Extension 필요한 앱은 **Dev Dashboard**(dev.shopify.com/dashboard)에서 생성.
- Admin에서 만든 커스텀 앱(예: BCI Connector)은 Admin API 토큰 발급용이지 Extension 개발엔 못 씀.
- capability(network_access 등)는 이제 **toml이 유일한 소스** — Dev Dashboard에 별도 승인 토글 없음. `network_access = true`만 넣고 deploy하면 됨.

## 3. shopify.app.toml 템플릿 잔재가 배포를 막음
- `shopify app init` 템플릿이 `[metaobjects.app.faq]`, `[product.metafields.app.faq]`, `[sidekick]` 등을 심음.
- `[product.metafields...]`는 `write_products` scope를 요구 → 배포 시 `[product]: Requires ... write_products` 에러.
- **해결**: `[access_scopes]`, `[auth]` 블록까지만 남기고 그 아래 metaobjects/product/sidekick 전부 삭제.

## 4. 안 쓰는 템플릿 extension이 전체 릴리즈를 막음
- `shopify app init`이 app-home, app-tools 같은 extension을 자동 생성. 이들이 요구하는 scope 때문에 우리 extension까지 릴리즈 실패.
- **해결**: `rmdir /s /q extensions\app-home` 등으로 안 쓰는 extension 폴더 삭제 후 재배포.

## 5. Web Pixel toml 구조 (web_pixel_extension)
- `[settings] type = "object"` 만 있으면 `Missing key 'fields'` 에러.
- `[settings]` 자체를 없애면 `base: Missing expected key(s)` 에러.
- `[customer_privacy]` 블록 누락도 `base: Missing expected key(s)` 유발.
- **올바른 최소 구조**:
  ```toml
  [customer_privacy]
  analytics = true
  marketing = false
  preferences = false
  sale_of_data = "enabled"

  [settings]
  type = "object"

  [settings.fields.accountID]
  name = "Account ID"
  description = "Account ID (unused)"
  type = "single_line_text_field"
  ```
  (validations의 min 강제는 빼야 활성화 시 값 입력 강요 안 함.)
- 단, 위 모든 게 결국 App pixel용 — 우리는 R1대로 Custom pixel을 쓰므로 이 함정 자체를 회피.

## 6. 환경 셋업
- Windows: Node.js(nodejs.org LTS) → `npm install -g @shopify/cli@latest`.
- Shopify CLI가 pnpm 요구 → `npm install -g pnpm`.
- 터미널: cmd 또는 PowerShell(둘 다 Windows 내장). GraphQL/curl은 PowerShell이 따옴표 처리 깔끔.
- `shopify app init` → extension-only 선택 → 기존 앱(login tracker) 연결.
- `shopify app generate extension` → 검색창에 타이핑해서 타입 필터(예: "customer", "web").

## 7. GAS 웹앱 배포 (SKILL.md R4 재강조)
- 코드 수정 후 "새 배포" 만들면 exec URL 바뀜 → Pixel ENDPOINT 깨짐.
- 반드시 "배포 관리 → 편집 → 새 버전 → 배포"로 URL 유지.
- BigQuery Advanced Service 활성화 필수. 액세스 권한 "모든 사용자(Anyone)".

## 8. 보안
- 작업 중 노출된 토큰(automation token 등)은 작업 후 Dev Dashboard에서 즉시 Revoke.
- OAuth Client ID는 공개값이라 무방하나, Secret/Access Token/automation token은 절대 코드·채팅·커밋에 남기지 않음.
