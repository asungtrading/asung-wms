# 1. 판매

<!-- skeleton: manual-1a · sections 1-5 manual-1b · 6-10 manual-1b2 · 11-21 manual-1c · sections follow the order of the work, not the order of the screens -->
<!-- out of this chapter: Discount Rules and Issue coupons -> chapter 7 Settings · Finish on POS -> chapter 5 POS · Action Centre -> chapter 6 · counter orders (Hand over — ship and invoice…) stay in this chapter -->

<a id="sales-customers"></a>
## 손님 찾기 · 더하기
<!-- screen: customers.html · BUILD 2026-10-23 · cs v6 -->
<!-- who: sales, office -->

**무엇인가**
**Customers** 화면(**Sales ▾** › **Customers**)에 모든 손님이 있습니다: 이름, 가격 조건, 주소, 연락처, 매장, 주문 이력.

**언제**
새 오더 전에, 손님이 바뀐 것을 알려 올 때, 새 손님이 처음 살 때.

**손님 찾는 법**
1. **Customers** 를 엽니다. **Search name** 에 이름 일부를 적습니다.
2. **Active only**(활성만)는 처음에 체크돼 있습니다. 꺼진 손님도 보려면 체크를 풉니다.
3. **New — not reviewed** 를 체크하면 매니저가 아직 확인하지 않은 새 손님만 보입니다.
4. 손님을 누릅니다. **Price tier**(가격 등급) · **Discount %**(할인) · **Payment term**(결제 조건) · **Currency**(통화) · **Bill to**(청구처) · **Default warehouse**(기본 창고) · **Tax rule**(세금 규칙), **Stores** 카드, **Order history**(주문 이력), **Addresses**(주소), **Contacts**(연락처)가 보입니다.

**손님 더하는 법**
1. **+ New customer** 를 누릅니다.
2. **Name \*** 을 적습니다(꼭 적어야 하는 칸은 이것 하나). 알면 **Default warehouse** · **Tax number** · **Tags** · **Note** 도 적습니다.
3. 청구 주소를 적습니다. **Shipping address is the same**(배송 주소가 같다)을 체크한 채 두거나, 풀고 배송 주소를 적습니다.
4. 연락처를 적습니다: **Name** · **Phone** · **Email** 등. **Marketing email** 은 **Unknown** · **Opt in** · **Opt out** 중 손님이 말한 대로 고릅니다.
5. **Create** 를 누릅니다.
6. ⚠ 줄이 나오면 읽습니다. 예: "1 active customer(s) already have the name …" 은 같은 이름의 손님을 보여 줍니다. 정말 다른 손님이면 **Confirm and save** 를 누릅니다. 같은 손님이면 **Cancel** 을 누르고 있는 손님을 씁니다.
7. ✕ 줄은 아무것도 저장되지 않았다는 뜻입니다. 적힌 대로 고친 뒤 **Save** 를 다시 누릅니다.

**손님 고치는 법**
1. 손님을 열고 **Edit** 를 누르면 이름 · 메모 · 세금 번호 · 기본 창고를 바꿀 수 있습니다.
2. **Addresses** · **Contacts** 에서 **+ Add** 를 누르거나, 줄의 **Edit** · **Make default**(기본으로) · **Remove** 를 누릅니다.

**master 권한이 있는 사람**
- 새 손님은 기본 조건으로 시작합니다: Wholesale · 0% · C.B.S · CAD. master 권한이 있는 사람이 **Edit** 에서 바꿉니다(가격 등급 · 할인 · 결제 조건 · 통화 · 계정).
- **Reviewed** › **Mark reviewed** 를 누르면 "new — not reviewed by a manager" 표시가 사라집니다.
- **Bill to** › **Change** 는 이 손님의 인보이스를 다른 손님에게 보내게 합니다.
- **Set parent** 는 이 손님을 본사의 매장으로 만듭니다. 본사에서 **+ Add store** 를 누르면 **Add a store to …** 창이 열립니다: 매장을 고르고, 본사에 청구하려면 **Send its invoices to …** 를 체크한 채 두고, **Add store** 를 누릅니다. **Detach** 는 매장을 떼어 냅니다.
- **Deactivate** 는 손님을 끕니다. **Activate** 는 다시 켭니다.

**매니저 이상**
- **Backorder emails**: **Turn on** / **Turn off** — 백오더 물건을 보낼 수 있게 되면 손님에게 메일이 가는지
- **Final invoice emails**: **Make automatic** / **Make manual** — 인보이스가 발행될 때 PDF 가 저절로 메일로 가는지

**알아 둘 것**
- 본사의 **Split invoice by store** 가 켜져 있으면, 여러 매장이 함께 나갈 때 매장마다 인보이스가 따로 나옵니다. 누구에게 청구하는지는 바뀌지 않습니다.
- **Order history** 에는 IMS 오더와 IMS 이전 오더가 함께 보입니다.

**조심할 것**
- **Bill to** 를 바꾸면 새 오더만 따라갑니다. "Orders already created keep the bill-to they were made with."(이미 만든 오더는 그대로)
- 꺼진 손님에게는 새 오더를 만들 수 없습니다.

<a id="sales-new-order"></a>
## 새 판매 오더
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
판매 오더는 **Draft**(초안)로 시작합니다. 초안에서는 무엇이든 바꿀 수 있습니다. 창고에 재고가 아직 잡히지 않습니다.

**언제**
손님이 전화 · 이메일 · 직접 와서 주문할 때.

**어떻게**
1. **Sales ▾** › **Sales Orders** 를 열고 **+ New sales order**(또는 좁은 목록 위의 **+ New**)를 누릅니다.
2. **Search customer by name** 에 손님 이름을 적고 손님을 누릅니다. 활성 손님만 나옵니다.
3. **Channel**(아래 참고)과 **Warehouse** 를 고릅니다. 창고는 손님의 기본 창고로 시작합니다.
4. **Create** 를 누릅니다. 초안이 번호와 함께 열립니다. 예: `SO-99001`
5. **Create** 뒤에 ⚠ 글이 나오면 읽습니다 — 예: 손님에게 배송 주소가 없다.

**Channel 세 가지**
- **Warehouse** — 창고에서 픽 · 팩합니다. 대부분의 오더
- **Counter** — 매장 카운터에서 건넵니다. 매니저 이상: 여기서 **Counter** 를 고르고, 초안을 **Confirm** 한 뒤, 손님이 물건을 가져갈 때 **Hand over — ship and invoice…** 를 누릅니다.
- **Service** — 물건 없이 서비스만 청구합니다(예: 준비 작업). 줄은 **Add a service** 로 넣습니다 — [줄 넣기](#sales-add-lines)

**초안 윗부분**
"Tax, price tier, discount and addresses are copied from the customer. You can change them on the draft."(세금 · 가격 등급 · 할인 · 주소는 손님에게서 복사되고, 초안에서 바꿀 수 있다)
- **Warehouse** · **Order date** · **Required by** · **Reference**(손님의 PO 번호) · **Payment term** · **Price tier** · **Customer discount %** · **Order discount %** · **Coupon** · **Carrier** · **Tax rule** · **Comments** · **Shipping notes** — 값을 누르면 바꿀 수 있습니다.
- **Ship to…** 는 이 오더의 배송 주소만 바꿉니다.
- **Tax rule** 은 **Auto — from ship-to province**(배송지 주에서 자동)로 시작합니다.

**조심할 것**
- **Ship to…** 에서 주나 나라를 바꾸면 새 주소로 세금 규칙을 다시 고릅니다. 손으로 정한 세금 규칙은 풀립니다.
- **Order date** 가 어느 딜과 쿠폰이 맞는지를 정합니다. 손님이 정말 다른 날 주문했을 때만 바꿉니다.

<a id="sales-add-lines"></a>
## 줄 넣기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
줄은 오더에 담긴 제품입니다. 하나씩 고르거나, 스프레드시트에서 여러 줄을 한 번에 붙여 넣을 수 있습니다.

**어떻게 — 목록에서 고르기**
1. 초안에서 **Add lines** 를 누릅니다.
2. SKU · 제품 이름 · 바코드를 적습니다. 원하는 제품을 누르면 아래 목록으로 옮겨집니다.
3. 제품마다 **Qty**(수량)를 적습니다.
4. 무상 줄은 **Free?** 에서 까닭을 고릅니다(**sample** · **promotion** · **replacement** · **other**). **other** 는 **Note** 가 필요합니다.
5. **Check** 로 결과를 미리 보고 **Add lines** 를 누릅니다.
- 매니저 이상: **Include sets (cases · packs)** 를 체크하면 케이스 · 팩 SKU 가 보입니다. 없으면 케이스는 낱개 SKU × 케이스 안 개수로 팝니다.

**어떻게 — 스프레드시트에서 붙여 넣기**
1. **Paste lines** 를 누릅니다.
2. 한 줄에 제품 하나씩 붙여 넣습니다: SKU, 수량, 원하면 가격. 스프레드시트에서 복사한 칸은 그대로 됩니다. 칸 사이를 쉼표로 적으면 가격에 천 단위 쉼표를 쓰지 않습니다(1250.00 · 1,250.00 아님).
3. **Check** 를 누릅니다. 줄마다 **Verdict**(판정)가 나옵니다: **ok** · **merged into the existing line**(있는 줄에 합침) · **not found** · **inactive product** · **no price — confirming is blocked until it gets one**(가격이 없어 확정이 막힘) 등
4. ok 가 아닌 줄을 고치고 **Check** 를 다시 누른 뒤 **Add lines** 를 누릅니다.

**가격**
- 가격을 안 적은 줄은 평소 가격을 받습니다: 가격 등급, 그리고 가장 큰 할인([할인 · 딜 · 추가 요금](#sales-discounts-deals))
- 직접 적은 가격은 그대로 굳습니다. 오더 할인이 그 줄에는 걸리지 않습니다.
- **Lines** 표에서 **Qty** · **Disc %** · **Unit** 을 칸에서 바꿉니다. **↺** 는 시스템 가격으로 되돌립니다. **✕** 는 줄을 지웁니다.
- **Price from** 은 가격이 어디서 왔는지 알려 줍니다: **customer** · **deal · …** · **set discount** · **discount by hand** · **price set by hand** · **free · …**. 손으로 정한 가격 옆에는 누가 언제 정했는지 보입니다. 예: "by Staff C"
- 수량 아래 **available** 은 이 창고에 지금 남은 수량입니다. 수량보다 적으면 빨갛게 보입니다.

**Clear lines…**
**Clear lines…** 는 초안의 모든 줄을 한 번에 지웁니다. 창이 몇 줄이 지워지는지 알려 줍니다. 비용 줄은 남고, 쿠폰도 남아서 줄이 다시 들어오면 다시 걸립니다. **Remove … lines** 를 누르면 지웁니다.

**서비스 오더**
**Service** 초안에서 **Add a service** 를 누릅니다. **Service** 를 고르고 **Quantity** · **Unit price** 를 적고, 원하면 **Description** 을 적은 뒤 **Save** 를 누릅니다. **Amount** 는 수량 × 단가입니다.

**조심할 것**
- "same SKU at another price — change that line instead": 이미 있는 줄을 고칩니다.
- 콤보는 콤보 줄에서 바꾸거나 지웁니다. 그 아래 구성품 줄이 따라갑니다.
- 웹 오더에는 **Clear lines…** 가 없습니다.

<a id="sales-discounts-deals"></a>
## 할인 · 딜 · 추가 요금
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
IMS 가 할인을 스스로 셉니다. 두 층입니다.
1. **줄 층.** 줄마다 할인이 **하나**만 걸립니다: 손님 할인 · 그 제품의 딜 · 세트 할인 중 가장 큰 것. **더하지 않습니다.**
2. **오더 층.** 오더 전체에 오더 할인이 **하나** 걸립니다: 오더 할인 규칙과 쿠폰 중 큰 것. 줄 층 **위에 한 번 더** 걸립니다.

**예**
Customer A 의 손님 할인은 10% 입니다. 딜이 제품 X 에 15% 를 줍니다. X 의 정가는 $20.00 입니다.
- 줄은 15% 를 받습니다 — 25% 가 아니라 큰 쪽입니다. **Unit** = $17.00 · **Price from** 은 **deal · …**
- 쿠폰이 오더에 5% 를 줍니다. 5% 는 줄 할인 뒤에 빠집니다: **Net unit** = $16.15

**손으로 정한 할인**
- 줄의 **Disc %** 에 % 를 적으면 손으로 정한 할인이 됩니다. 칸을 비우면 시스템 할인으로 돌아갑니다.
- 가격이나 할인을 손으로 정한 줄에는 오더 할인이 걸리지 않습니다. **Net unit** 이 그렇게 알려 줍니다.
- **Order discount %** 에 % 를 적으면 손으로 정한 오더 할인이 됩니다. 규칙과 쿠폰보다 앞섭니다. 나중에 규칙이 더 많이 주게 되면 "A discount rule now gives more than the order discount % set by hand — clear Order discount % to go back to the rules." 가 나옵니다.

**Reprice**
1. **Reprice** 를 누르면 시스템 줄을 오늘 규칙으로 다시 매깁니다 — 오더 날짜 · 등급 · 손님 할인 · 딜
2. 손으로 정한 가격이나 할인 줄은 그대로 둡니다.
3. 오더를 만든 뒤 딜이 바뀌면 단추가 **Reprice ●** 로 보입니다. 목록 필터 **Draft — reprice suggested** 로 그런 오더를 찾습니다.

**추가 요금(Surcharge)**
추가 요금(예: 미국 관세)은 가격 위에 개당 붙고, 인보이스에 따로 한 줄로 나옵니다.
1. 줄의 **Surcharge** 칸에서 **+** 를 누르거나, 여러 줄을 체크하고 **Set surcharge…** 를 누릅니다.
2. **Name** 을 적고 **Charge as** 에서 **% of the unit price**(단가의 %) 또는 **$ per unit**(개당 $)을 고르고 금액을 적습니다.
3. **Save on picked lines** 를 누릅니다. **Clear on picked lines** 는 떼어 냅니다.

**조심할 것**
- 추가 요금은 오더 할인에 들어가지 않습니다. 무상 줄에는 붙일 수 없습니다.
- 오더를 나누면 오더 할인이 손님이 처음 주문한 금액 기준으로 **locked**(잠김) 됩니다. 줄을 바꾸거나 **Reprice** 를 해도 바뀌지 않습니다.
- 딜과 오더 할인 규칙은 **Discount Rules** 화면에서 만듭니다 — 설정 장을 보세요.

<a id="sales-coupons"></a>
## 쿠폰 쓰기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
쿠폰은 오더 할인을 주는 코드입니다. 쿠폰 하나는 손님 한 명의 것입니다.

**어떻게**
1. 초안의 **Coupon** 칸에 코드를 적고 **Apply** 를 누릅니다.
2. IMS 가 코드와 함께 **applied · …%**(적용됨) 또는 **not used**(안 쓰임)와 까닭을 보여 줍니다.
3. 다른 코드를 쓰려면 적고 **Replace** 를 누릅니다.
4. 쿠폰을 떼려면 옆의 **✕** 를 누릅니다. 손님은 그 쿠폰을 다른 오더에 쓸 수 있습니다.

**쿠폰이 안 쓰이는 까닭**

| IMS 의 글 | 할 일 |
|---|---|
| the order already gets a bigger discount | 할 것 없음 — 큰 할인이 이깁니다 |
| the order is below the minimum amount of the coupon's deal | 줄을 더하거나 그대로 둡니다 |
| the order discount % was set by hand | 쿠폰을 쓰려면 **Order discount %** 를 비웁니다 |
| it belongs to another customer | 손님을 확인합니다 |
| it was already used on another order | 두 번 쓸 수 없습니다 |
| it expired before the order date | 오더 날짜가 쿠폰 마지막 날보다 뒤입니다 |
| it was voided · its deal is switched off · its deal no longer takes coupons | 매니저에게 묻습니다 |

**알아 둘 것**
- **Order date** 가 쿠폰 마지막 날 이전이면 쿠폰이 맞습니다 — 확정이 늦어져도 됩니다.
- 쿠폰은 오더를 확정할 때 쓴 것이 됩니다. 그 오더가 취소되거나 초안으로 돌아가면 다시 쓸 수 있습니다.
- 확정할 때 쿠폰이 안 쓰이고 있으면 IMS 가 오더에서 떼고, 손님은 쿠폰을 그대로 가집니다.

**조심할 것**
- 쿠폰은 **Discount Rules** 화면에서 만듭니다 — 설정 장을 보세요.
<a id="sales-confirm"></a>
## 오더 확정
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, manager -->
<!-- TODO manual-1b2 -->

<a id="sales-release"></a>
## 창고로 보내기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

<a id="sales-undo"></a>
## 오더 되돌리기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office, manager -->
<!-- TODO manual-1b2 -->

<a id="sales-divide-merge"></a>
## 오더 나누기 · 합치기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

<a id="sales-backorders"></a>
## 백오더
<!-- screen: so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

<a id="sales-charges"></a>
## 운임과 그 밖의 비용
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-ship-invoice"></a>
## Ship & invoice(출고 + 인보이스)
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-pickup"></a>
## 픽업 오더와 추적번호
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office, warehouse -->
<!-- TODO manual-1c -->

<a id="sales-print-email"></a>
## 인쇄와 메일
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-invoices"></a>
## 판매 인보이스
<!-- screen: so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office, accounting -->
<!-- TODO manual-1c -->

<a id="sales-payments"></a>
## 손님 결제와 선수금
<!-- screen: so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: accounting, office -->
<!-- TODO manual-1c -->

<a id="sales-credits"></a>
## 크레딧 노트
<!-- screen: so-credits.html · BUILD 2026-10-23 · cr v5 -->
<!-- who: accounting, office -->
<!-- TODO manual-1c -->

<a id="sales-web-orders"></a>
## 웹 오더
<!-- screen: shopify-orders.html · BUILD 2026-10-14 · wo v4d -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-cancel"></a>
## 오더 취소
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, manager -->
<!-- TODO manual-1c -->

<a id="sales-statuses"></a>
## 상태의 뜻
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: all -->
<!-- note for 1b: two columns — badge (Released to WMS, Working, Finalized, Invoice cancelled …) and filter (With warehouse, Finalized — waiting for the office, Waiting for pickup …) -->
<!-- TODO manual-1c -->

<a id="sales-csv"></a>
## CSV 내려받기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 ; so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so-credits.html · BUILD 2026-10-23 · cr v5 ; so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: office, accounting -->
<!-- TODO manual-1c -->

<!-- rulings: 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 507, 517, 529, 532, 541, 545, 546, 590, 709, 713, 714, 715, 719 -->
