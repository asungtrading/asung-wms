# Customer Account UI Extension: login-tracker (보조 추적)

## 개요
- 앱: **login tracker** (Dev Dashboard 생성, extension-only, asung-trading에 설치)
- Extension handle: `login-tracker`, target `customer-account.order-index.block.render`
- 로그인 후 계정 Orders 페이지 조회 시 Customer Account API로 손님 식별 → GAS 전송. 화면엔 아무것도 안 그리는 조용한 블록.
- 로컬 프로젝트: `C:\Users\chang\asung-customer-login-tracker\login-tracker`

## 이 Extension의 위치와 한계
- **잡는 것**: 로그인 손님이 계정 페이지(Orders)를 볼 때만. 정탐꾼은 계정 페이지 안 보므로 커버리지 좁음 → 주력은 Custom Pixel(page-view-custom).
- 계정 페이지 조회는 이걸로, 전체 사이트 페이지뷰는 Custom Pixel로 이원화.

## shopify.extension.toml
```toml
api_version = "2026-04"

[[extensions]]
name = "login-tracker"
handle = "login-tracker"
type = "ui_extension"
uid = "d3208f7c-18e0-1cec-476b-37d07b412f04a56109c0"   # CLI 자동생성, 변경 금지

[[extensions.targeting]]
module = "./src/OrderStatusBlock.jsx"
target = "customer-account.order-index.block.render"

[extensions.capabilities]
api_access = true
network_access = true   # GAS(외부) fetch 위해 필수. Dev Dashboard에선 toml만으로 처리됨(별도 승인 버튼 없음)
```

## src/OrderStatusBlock.jsx
```javascriptreact
import '@shopify/ui-extensions/preact';
import {render} from 'preact';
import {useEffect} from 'preact/hooks';

const LOGIN_EVENT_ENDPOINT = 'https://script.google.com/macros/s/AKfycbyy7ri1Q2sCOfF9vbDNfn1p_kLvjxCSHSc_Io8eisaFCUPXwqpDghfDyb0eQXNdbq_J/exec';

export default async () => {
  render(<Extension />, document.body);
};

function Extension() {
  useEffect(() => {
    let cancelled = false;
    async function logLogin() {
      try {
        const res = await fetch('shopify://customer-account/api/2026-04/graphql.json', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query: `{ customer { id emailAddress { emailAddress } } }` }),
        });
        const { data } = await res.json();
        const customer = data && data.customer;
        if (!customer || cancelled) return;
        await fetch(LOGIN_EVENT_ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify({
            customerId: customer.id,
            email: (customer.emailAddress && customer.emailAddress.emailAddress) || '',
            eventTime: new Date().toISOString(),
            page: 'order-index',
            eventType: 'account_view',   // 통합 테이블 구분용
          }),
        });
      } catch (err) { console.error('login-tracker error', err); }
    }
    logLogin();
    return () => { cancelled = true; };
  }, []);
  return null;   // 조용한 트래커
}
```
> 참고: 현재 배포본은 eventType 미포함일 수 있음. 다음 배포 때 `eventType: 'account_view'` 추가 권장.

## 배포 절차
1. 코드 수정 후 저장
2. 프로젝트 폴더에서 `shopify app deploy` → `y` (New version release)
3. Admin → Settings → **Customer accounts** → 편집기 → **Orders** 페이지 → Add block → `login-tracker` 배치 → **Save**
   - 배포만으론 화면에 안 붙음. 편집기에서 블록 배치 필수.

## shopify.app.toml 주의 (배포 에러 방지)
- CLI 템플릿이 심는 `[metaobjects...]`, `[product.metafields...]`, `[sidekick]` 블록은 **삭제**할 것. 남기면 `write_products` scope를 요구해 배포가 막힘(우리 앱엔 불필요).
- extension-only로 갈 거면 `shopify app init` 시 "Build an extension-only app" 선택.
- 안 쓰는 템플릿 extension(app-home, app-tools)은 `extensions/` 에서 삭제. 남기면 그들의 scope 요구로 전체 릴리즈가 막힘.
