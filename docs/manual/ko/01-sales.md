# 1. 판매

<!-- skeleton: manual-1a · sections 1-5 manual-1b · 6-10 manual-1b2 · 11-21 manual-1c · sections follow the order of the work, not the order of the screens -->
<!-- out of this chapter: Discount Rules and Issue coupons -> chapter 7 Settings · Finish on POS -> chapter 5 POS · Action Centre -> chapter 6 · counter orders (Hand over — ship and invoice…) stay in this chapter -->

<a id="sales-customers"></a>
## 고객 찾기 · 더하기
<!-- screen: customers.html · BUILD 2026-10-23 · cs v6 -->
<!-- who: sales, office -->

**무엇인가**
**Customers** 화면(**Sales ▾** › **Customers**)에 모든 고객이 있습니다: 이름, 가격 조건, 주소, 연락처, 매장, 주문 이력.

**언제**
새 오더 전에, 고객이 바뀐 것을 알려 올 때, 새 고객이 처음 살 때.

**고객 찾는 법**
1. **Customers** 를 엽니다. **Search name** 에 이름 일부를 적습니다.
2. **Active only**(활성만)는 처음에 체크돼 있습니다. 꺼진 고객도 보려면 체크를 풉니다.
3. **New — not reviewed** 를 체크하면 매니저가 아직 확인하지 않은 새 고객만 보입니다.
4. 고객을 누릅니다. **Price tier**(가격 등급) · **Discount %**(할인) · **Payment term**(결제 조건) · **Currency**(통화) · **Bill to**(청구처) · **Default warehouse**(기본 창고) · **Tax rule**(세금 규칙), **Stores** 카드, **Order history**(주문 이력), **Addresses**(주소), **Contacts**(연락처)가 보입니다.

**고객 더하는 법**
1. **+ New customer** 를 누릅니다.
2. **Name \*** 을 적습니다(꼭 적어야 하는 칸은 이것 하나). 알면 **Default warehouse** · **Tax number** · **Tags** · **Note** 도 적습니다.
3. 청구 주소를 적습니다. **Shipping address is the same**(배송 주소가 같다)을 체크한 채 두거나, 풀고 배송 주소를 적습니다.
4. 연락처를 적습니다: **Name** · **Phone** · **Email** 등. **Marketing email** 은 **Unknown** · **Opt in** · **Opt out** 중 고객이 말한 대로 고릅니다.
5. **Create** 를 누릅니다.
6. ⚠ 줄이 나오면 읽습니다. 예: "1 active customer(s) already have the name …" 은 같은 이름의 고객을 보여 줍니다. 정말 다른 고객이면 **Confirm and save** 를 누릅니다. 같은 고객이면 **Cancel** 을 누르고 있는 고객을 씁니다.
7. ✕ 줄은 아무것도 저장되지 않았다는 뜻입니다. 적힌 대로 고친 뒤 **Save** 를 다시 누릅니다.

**고객 고치는 법**
1. 고객을 열고 **Edit** 를 누르면 이름 · 메모 · 세금 번호 · 기본 창고를 바꿀 수 있습니다.
2. **Addresses** · **Contacts** 에서 **+ Add** 를 누르거나, 줄의 **Edit** · **Make default**(기본으로) · **Remove** 를 누릅니다.

**master 권한이 있는 사람**
- 새 고객은 기본 조건으로 시작합니다: Wholesale · 0% · C.B.S · CAD. master 권한이 있는 사람이 **Edit** 에서 바꿉니다(가격 등급 · 할인 · 결제 조건 · 통화 · 계정).
- **Reviewed** › **Mark reviewed** 를 누르면 "new — not reviewed by a manager" 표시가 사라집니다.
- **Bill to** › **Change** 는 이 고객의 인보이스를 다른 고객에게 보내게 합니다.
- **Set parent** 는 이 고객을 본사의 매장으로 만듭니다. 본사에서 **+ Add store** 를 누르면 **Add a store to …** 창이 열립니다: 매장을 고르고, 본사에 청구하려면 **Send its invoices to …** 를 체크한 채 두고, **Add store** 를 누릅니다. **Detach** 는 매장을 떼어 냅니다.
- **Deactivate** 는 고객을 끕니다. **Activate** 는 다시 켭니다.

**매니저 이상**
- **Backorder emails**: **Turn on** / **Turn off** — 백오더 물건을 보낼 수 있게 되면 고객에게 메일이 가는지
- **Final invoice emails**: **Make automatic** / **Make manual** — 인보이스가 발행될 때 PDF 가 저절로 메일로 가는지

**알아 둘 것**
- 본사의 **Split invoice by store** 가 켜져 있으면, 여러 매장이 함께 나갈 때 매장마다 인보이스가 따로 나옵니다. 누구에게 청구하는지는 바뀌지 않습니다.
- **Order history** 에는 IMS 오더와 IMS 이전 오더가 함께 보입니다.

**조심할 것**
- **Bill to** 를 바꾸면 새 오더만 따라갑니다. "Orders already created keep the bill-to they were made with."(이미 만든 오더는 그대로)
- 꺼진 고객에게는 새 오더를 만들 수 없습니다.

<a id="sales-new-order"></a>
## 새 판매 오더
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
판매 오더는 **Draft**(초안)로 시작합니다. 초안에서는 무엇이든 바꿀 수 있습니다. 창고에 재고가 아직 확보되지 않습니다.

**언제**
고객이 전화 · 이메일 · 직접 와서 주문할 때.

**어떻게**
1. **Sales ▾** › **Sales Orders** 를 열고 **+ New sales order**(또는 좁은 목록 위의 **+ New**)를 누릅니다.
2. **Search customer by name** 에 고객 이름을 적고 고객을 누릅니다. 활성 고객만 나옵니다.
3. **Channel**(아래 참고)과 **Warehouse** 를 고릅니다. 창고는 고객의 기본 창고로 시작합니다.
4. **Create** 를 누릅니다. 초안이 번호와 함께 열립니다. 예: `SO-99001`
5. **Create** 뒤에 ⚠ 글이 나오면 읽습니다 — 예: 고객에게 배송 주소가 없다.

**Channel 세 가지**
- **Warehouse** — 창고에서 픽 · 팩합니다. 대부분의 오더
- **Counter** — 매장 카운터에서 건넵니다. 매니저 이상: 여기서 **Counter** 를 고르고, 초안을 **Confirm** 한 뒤, 고객이 물건을 가져갈 때 **Hand over — ship and invoice…** 를 누릅니다.
- **Service** — 물건 없이 서비스만 청구합니다(예: 준비 작업). 라인은 **Add a service** 로 넣습니다 — [라인 넣기](#sales-add-lines)

**초안 윗부분**
"Tax, price tier, discount and addresses are copied from the customer. You can change them on the draft."(세금 · 가격 등급 · 할인 · 주소는 고객에게서 복사되고, 초안에서 바꿀 수 있다)
- **Warehouse** · **Order date** · **Required by** · **Reference**(고객의 PO 번호) · **Payment term** · **Price tier** · **Customer discount %** · **Order discount %** · **Coupon** · **Carrier** · **Tax rule** · **Comments** · **Shipping notes** — 값을 누르면 바꿀 수 있습니다.
- **Ship to…** 는 이 오더의 배송 주소만 바꿉니다.
- **Tax rule** 은 **Auto — from ship-to province**(배송지 주에서 자동)로 시작합니다.

**조심할 것**
- **Ship to…** 에서 주나 나라를 바꾸면 새 주소로 세금 규칙을 다시 고릅니다. 손으로 정한 세금 규칙은 풀립니다.
- **Order date** 가 어느 딜과 쿠폰이 맞는지를 정합니다. 고객이 정말 다른 날 주문했을 때만 바꿉니다.

<a id="sales-add-lines"></a>
## 라인 넣기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
라인은 오더에 담긴 제품입니다. 하나씩 고르거나, 스프레드시트에서 여러 라인을 한 번에 붙여 넣을 수 있습니다.

**어떻게 — 목록에서 고르기**
1. 초안에서 **Add lines** 를 누릅니다.
2. SKU · 제품 이름 · 바코드를 적습니다. 원하는 제품을 누르면 아래 목록으로 옮겨집니다.
3. 제품마다 **Qty**(수량)를 적습니다.
4. 무상 라인은 **Free?** 에서 까닭을 고릅니다(**sample** · **promotion** · **replacement** · **other**). **other** 는 **Note** 가 필요합니다.
5. **Check** 로 결과를 미리 보고 **Add lines** 를 누릅니다.
- 매니저 이상: **Include sets (cases · packs)** 를 체크하면 케이스 · 팩 SKU 가 보입니다. 없으면 케이스는 낱개 SKU × 케이스 안 개수로 팝니다.

**어떻게 — 스프레드시트에서 붙여 넣기**
1. **Paste lines** 를 누릅니다.
2. 한 줄에 제품 하나씩 붙여 넣습니다: SKU, 수량, 원하면 가격. 스프레드시트에서 복사한 칸은 그대로 됩니다. 칸 사이를 쉼표로 적으면 가격에 천 단위 쉼표를 쓰지 않습니다(1250.00 · 1,250.00 아님).
3. **Check** 를 누릅니다. 줄마다 **Verdict**(판정)가 나옵니다: **ok** · **merged into the existing line**(있는 라인에 합침) · **not found** · **inactive product** · **no price — confirming is blocked until it gets one**(가격이 없어 확정이 막힘) 등
4. ok 가 아닌 줄을 고치고 **Check** 를 다시 누른 뒤 **Add lines** 를 누릅니다.

**가격**
- 가격을 안 적은 라인은 평소 가격을 받습니다: 가격 등급, 그리고 가장 큰 할인([할인 · 딜 · 추가 요금](#sales-discounts-deals))
- 직접 적은 가격은 고정됩니다. 오더 할인이 그 라인에는 걸리지 않습니다.
- **Lines** 표에서 **Qty** · **Disc %** · **Unit** 을 칸에서 바꿉니다. **↺** 는 시스템 가격으로 되돌립니다. **✕** 는 라인을 지웁니다.
- **Price from** 은 가격이 어디서 왔는지 알려 줍니다: **customer** · **deal · …** · **set discount** · **discount by hand** · **price set by hand** · **free · …**. 손으로 정한 가격 옆에는 누가 언제 정했는지 보입니다. 예: "by Staff C"
- 수량 아래 **available** 은 이 창고에 지금 남은 수량입니다. 수량보다 적으면 빨갛게 보입니다.

**Clear lines…**
**Clear lines…** 는 초안의 모든 라인을 한 번에 지웁니다. 창이 몇 라인이 지워지는지 알려 줍니다. 비용 라인은 남고, 쿠폰도 남아서 라인이 다시 들어오면 다시 걸립니다. **Remove … lines** 를 누르면 지웁니다.

**서비스 오더**
**Service** 초안에서 **Add a service** 를 누릅니다. **Service** 를 고르고 **Quantity** · **Unit price** 를 적고, 원하면 **Description** 을 적은 뒤 **Save** 를 누릅니다. **Amount** 는 수량 × 단가입니다.

**조심할 것**
- "same SKU at another price — change that line instead": 이미 있는 라인을 고칩니다.
- 콤보는 콤보 라인에서 바꾸거나 지웁니다. 그 아래 구성품 라인이 따라갑니다.
- 웹 오더에는 **Clear lines…** 가 없습니다.

<a id="sales-discounts-deals"></a>
## 할인 · 딜 · 추가 요금
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
IMS 가 할인을 스스로 셉니다. 두 층입니다.
1. **라인 층.** 라인마다 할인이 **하나**만 걸립니다: 고객 할인 · 그 제품의 딜 · 세트 할인 중 가장 큰 것. **더하지 않습니다.**
2. **오더 층.** 오더 전체에 오더 할인이 **하나** 걸립니다: 오더 할인 규칙과 쿠폰 중 큰 것. 라인 층 **위에 한 번 더** 걸립니다.

**예**
Customer A 의 고객 할인은 10% 입니다. 딜이 제품 X 에 15% 를 줍니다. X 의 정가는 $20.00 입니다.
- 라인은 15% 를 받습니다 — 25% 가 아니라 큰 쪽입니다. **Unit** = $17.00 · **Price from** 은 **deal · …**
- 쿠폰이 오더에 5% 를 줍니다. 5% 는 라인 할인 뒤에 빠집니다: **Net unit** = $16.15

**손으로 정한 할인**
- 라인의 **Disc %** 에 % 를 적으면 손으로 정한 할인이 됩니다. 칸을 비우면 시스템 할인으로 돌아갑니다.
- 가격이나 할인을 손으로 정한 라인에는 오더 할인이 걸리지 않습니다. **Net unit** 이 그렇게 알려 줍니다.
- **Order discount %** 에 % 를 적으면 손으로 정한 오더 할인이 됩니다. 규칙과 쿠폰보다 앞섭니다. 나중에 규칙이 더 많이 주게 되면 "A discount rule now gives more than the order discount % set by hand — clear Order discount % to go back to the rules." 가 나옵니다.

**Reprice**
1. **Reprice** 를 누르면 시스템 라인을 오늘 규칙으로 다시 계산합니다 — 오더 날짜 · 등급 · 고객 할인 · 딜
2. 손으로 정한 가격이나 할인 라인은 그대로 둡니다.
3. 오더를 만든 뒤 딜이 바뀌면 단추가 **Reprice ●** 로 보입니다. 목록 필터 **Draft — reprice suggested** 로 그런 오더를 찾습니다.

**추가 요금(Surcharge)**
추가 요금(예: 미국 관세)은 가격 위에 개당 붙고, 인보이스에 따로 한 라인으로 나옵니다.
1. 라인의 **Surcharge** 칸에서 **+** 를 누르거나, 여러 라인을 체크하고 **Set surcharge…** 를 누릅니다.
2. **Name** 을 적고 **Charge as** 에서 **% of the unit price**(단가의 %) 또는 **$ per unit**(개당 $)을 고르고 금액을 적습니다.
3. **Save on picked lines** 를 누릅니다. **Clear on picked lines** 는 떼어 냅니다.

**조심할 것**
- 추가 요금은 오더 할인에 들어가지 않습니다. 무상 라인에는 붙일 수 없습니다.
- 오더를 나누면 오더 할인이 고객이 처음 주문한 금액 기준으로 **locked**(잠김) 됩니다. 라인을 바꾸거나 **Reprice** 를 해도 바뀌지 않습니다.
- 딜과 오더 할인 규칙은 **Discount Rules** 화면에서 만듭니다 — 설정 장을 보세요.

<a id="sales-coupons"></a>
## 쿠폰 쓰기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**무엇인가**
쿠폰은 오더 할인을 주는 코드입니다. 쿠폰 하나는 고객 한 명의 것입니다.

**어떻게**
1. 초안의 **Coupon** 칸에 코드를 적고 **Apply** 를 누릅니다.
2. IMS 가 코드와 함께 **applied · …%**(적용됨) 또는 **not used**(안 쓰임)와 까닭을 보여 줍니다.
3. 다른 코드를 쓰려면 적고 **Replace** 를 누릅니다.
4. 쿠폰을 떼려면 옆의 **✕** 를 누릅니다. 고객은 그 쿠폰을 다른 오더에 쓸 수 있습니다.

**쿠폰이 안 쓰이는 까닭**

| IMS 의 글 | 할 일 |
|---|---|
| the order already gets a bigger discount | 할 것 없음 — 큰 할인이 이깁니다 |
| the order is below the minimum amount of the coupon's deal | 라인을 더하거나 그대로 둡니다 |
| the order discount % was set by hand | 쿠폰을 쓰려면 **Order discount %** 를 비웁니다 |
| it belongs to another customer | 고객을 확인합니다 |
| it was already used on another order | 두 번 쓸 수 없습니다 |
| it expired before the order date | 오더 날짜가 쿠폰 마지막 날보다 뒤입니다 |
| it was voided · its deal is switched off · its deal no longer takes coupons | 매니저에게 묻습니다 |

**알아 둘 것**
- **Order date** 가 쿠폰 마지막 날 이전이면 쿠폰이 맞습니다 — 확정이 늦어져도 됩니다.
- 쿠폰은 오더를 확정할 때 쓴 것이 됩니다. 그 오더가 취소되거나 초안으로 돌아가면 다시 쓸 수 있습니다.
- 확정할 때 쿠폰이 안 쓰이고 있으면 IMS 가 오더에서 떼고, 고객은 쿠폰을 그대로 가집니다.

**조심할 것**
- 쿠폰은 **Discount Rules** 화면에서 만듭니다 — 설정 장을 보세요.
<a id="sales-confirm"></a>
## 오더 확정
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, manager -->

**무엇인가**
확정하면 초안이 진짜 오더가 됩니다. 그 순간 IMS 는:
- 오더 창고에서 재고를 확보하고,
- 가격과 할인을 고정하고,
- 쿠폰을 쓴 것으로 하고,
- 확보하지 못한 것을 따로 새 오더로 옮깁니다 — **백오더** 오더나 **프리오더** 오더

**언제**
고객의 주문이 확정됐을 때.

**어떻게 — 매니저 이상**
1. 초안에서 **Confirm…** 을 누릅니다. **Confirm SO-99001 — preview**(미리 보기) 창이 열립니다. 아직 아무것도 저장되지 않습니다.
2. 라인마다 **Ordered**(주문) · **Result**(결과) · **Reserved**(확보) · **Backorder** · **Preorder** 를 읽습니다.
3. 프리오더로 기다려야 할 라인은 **Preorder?** 를 체크합니다 — 재고가 오면 보내겠다는 약속입니다.
4. 오더가 기다려야 하면 **Confirm on hold — do not reserve stock for the whole order**(보류로 확정 — 오더 전체 재고를 확보하지 않음)를 체크합니다([보류](#sales-release)).
5. **Confirm** 을 누릅니다. 알릴 것이 없으면 창이 저절로 닫힙니다. 있으면 "Confirmed — check the result above, then Close." 가 나옵니다.

**Result 의 단어**

| Result | 뜻 |
|---|---|
| allocated | 라인 전체가 확보됐다 |
| partial | 라인 일부가 확보됐다 · 나머지는 백오더 오더로 간다 |
| backorder | 하나도 확보하지 못했다 · 라인이 백오더 오더로 간다 |
| preorder | 라인이 프리오더 오더로 간다 |
| hold | 보류로 확정했다 · 아무것도 확보하지 않았다 |

**예**
Customer A 의 SO-99001 이 제품 X 를 30 주문했습니다. 창고에 남은 것은 18 입니다.
- **Reserved** 18 · **Backorder** 12
- 창에 "Split off: SO-99001b backorder (1 line)"(나뉨) 이 나옵니다.
- SO-99001 은 18 을 가지고 창고로 갈 수 있습니다. SO-99001b 는 12 를 가지고 **Backorders** 화면에서 기다립니다.

**알아 둘 것**
- **이어받기.** 새 오더를 확정하면, 같은 고객 · 같은 제품의 예전 열린 백오더를 오래된 것부터 닫습니다. 창의 "Backorders taken over from earlier orders" 아래에 보입니다. 그 수요는 이제 새 오더가 가집니다.
- 가격이 **없는** 라인이 있으면 확정이 막힙니다. 먼저 가격을 넣습니다.
- 매니저가 아닌 직원에게는 **Confirm…** 이 보이지 않습니다. 매니저에게 확정을 부탁합니다.
- **Counter 오더** — 매니저 이상: counter 초안에서 **Confirm** 을 누릅니다. "Every line is reserved as it is — counter orders never split or backorder."(모든 라인을 그대로 확보 · counter 오더는 나뉘지도 백오더가 되지도 않는다)
- **서비스 오더** — 판매 오더를 다루는 사람이면 누구나 서비스 초안에서 **Confirm** 을 누릅니다. 인보이스는 그 뒤 **Invoice…** 로 냅니다([Ship & invoice](#sales-ship-invoice)).

<!-- SCREENSHOT: sales-confirm-1 · Confirm 미리 보기 창: Reserved · Backorder · Preorder 칸과 "Split off" 줄 -->

<a id="sales-release"></a>
## 창고로 보내기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->

**무엇인가**
**Release to WMS** 는 확정된 오더를 창고로 보냅니다. 창고 매니저의 **Split & Waves** 화면에 나타납니다. 상태가 **Released to WMS** 가 되고, 픽을 시작하면 **Working** 이 됩니다.

**어떻게**
1. 확정된 Warehouse 오더를 엽니다.
2. **Release to WMS** 를 누릅니다. 묻는 창이 없습니다 — **Recall from WMS** 로 되돌릴 수 있습니다([오더 되돌리기](#sales-undo)).

**단추가 회색일 때**
단추에 마우스를 대면 까닭이 나옵니다.
- "Release the hold first — an order on hold cannot go to the warehouse"(보류를 먼저 풀어라)
- "Proceed or clear the backorder / preorder lines first"(백오더 · 프리오더 라인을 먼저 진행하거나 정리하라) — 백오더 · 프리오더 오더는 재고가 확보된 뒤에만 창고로 갑니다([백오더](#sales-backorders)).

**보류(Hold) — 매니저 이상**
보류는 오더가 확보한 재고를 다른 오더에 풀어 주고, 오더는 기다리게 합니다.
1. 재고가 확보된 확정 오더에서 **Hold** 를 누릅니다.
2. "Put SO-99001 on hold? Reserved stock is released for other orders; the lines stay on the order. Release the hold later to reserve again." 에 OK 를 누릅니다.
3. 보류를 끝내려면 **Release hold** 를 누릅니다. 재고가 되는 만큼 다시 확보합니다. **Hold released — SO-99001** 창이 결과를 보여 줍니다. 모자란 것은 백오더 오더가 됩니다.

**조심할 것**
- 보류는 늘 오더 전체입니다. 라인 하나만 보류할 수 없습니다.
- **Release hold** 뒤에는 전보다 덜 확보될 수 있습니다 — 그사이 다른 오더가 재고를 가져갔을 수 있습니다.

<!-- SCREENSHOT: sales-release-1 · 확정 오더 · 회색 Release to WMS 와 까닭 글 -->

<a id="sales-undo"></a>
## 오더 되돌리기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office, manager -->

**무엇인가**
한 번에 한 단계씩 되돌립니다: 창고에서 **Confirmed** 로, **Confirmed** 에서 **Draft** 로.

**Recall from WMS**
1. **Released to WMS** 인 오더에서 **Recall from WMS** 를 누릅니다.
2. "Recall SO-99001 from the warehouse? It goes back to Confirmed and leaves the WMS Split screen." 에 OK 를 누릅니다.
- 창고가 일을 시작하면(**Working**) 단추가 회색입니다: "The warehouse is working on it — ask the warehouse manager to send it back first"(창고 매니저에게 먼저 돌려 달라고 하라)

**Delete draft**
1. 초안에서 **Delete draft** 를 누릅니다.
2. "Delete draft SO-99001? It has never been confirmed, so it disappears — the number is not reused." 에 OK 를 누릅니다.

**Unconfirm — supervisor · admin**
1. IMS 안에 있는 확정 오더에서 **Unconfirm** 을 누릅니다.
2. "Unconfirm SO-99001? Reserved stock is released and split-off backorder/preorder orders come back into this one (supervisor)." 에 OK 를 누릅니다.
3. 오더가 다시 초안이 됩니다. 그 확정 때 나뉜 백오더 · 프리오더 오더(예: SO-99001b)가 이 오더 안으로 돌아옵니다. 이 오더가 예전 오더에서 이어받았던 백오더 라인은 다시 열리고, IMS 가 몇 라인인지 알려 줍니다.
- 이 오더가 쓴 쿠폰은 다시 쓸 수 있습니다.
- 확정된 서비스 오더도 같은 방법으로 초안으로 돌아갑니다.

**Unconfirm 이 거절할 때**

| IMS 의 글(줄임) | 할 일 |
|---|---|
| only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) | Recall 하거나, 창고에 먼저 되돌려 달라고 합니다 |
| was itself split off at confirmation — unconfirm the original order … instead | 원래 오더를 Unconfirm 합니다(SO-99001b 가 아니라 SO-99001) |
| has a hand-made split order … (cancel or merge it first) | 손으로 나눈 오더를 먼저 정리합니다 |
| was split again after confirmation | Unconfirm 은 확정 때 나뉜 것만 되돌립니다 |
| Split order … was changed after the split | 더는 할 수 없습니다 — 오더를 취소하거나 고칩니다 |

**Counter 오더 — 매니저 이상**
**Reopen as draft** 를 누릅니다. "Reserved stock is released."(확보한 재고가 풀린다)

**조심할 것**
- 오더를 아주 닫으려면 [오더 취소](#sales-cancel)를 봅니다.

<a id="sales-divide-merge"></a>
## 오더 나누기 · 합치기
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->

**나누기(Divide) — 매니저 이상**
오더 일부를 따로 보내야 할 때 씁니다 — 예: Customer A 가 30 박스 중 10 박스는 지금, 나머지는 다음 주에 받고 싶어 할 때
1. 확정 오더에서 **Divide…** 를 누릅니다.
2. **Move** 에 라인마다 새 오더로 옮길 수량을 적습니다 — 라인 전체도, 일부도 됩니다.
3. **Check** 로 결과를 읽고 **Divide** 를 누릅니다. "New order: …"(새 오더)가 나옵니다.
- 확보한 재고는 라인을 따라갑니다. 새 오더는 같은 머리(고객 · 조건 · 주소)를 가집니다.
- 콤보는 콤보 단위로 옮겨집니다.

**합치기(Merge)**
고객이 여러 번 보낸 오더를 한 번에 보내야 할 때 씁니다.
1. 초안에서 **Merge…** 를 누릅니다. 같은 고객 · 같은 창고 · 같은 통화의 Warehouse 오더 중 초안이나 확정 상태인 것이 나옵니다.
2. 둘 이상 체크하고 **Preview** 를 누릅니다.
3. **Orders** · **Header from** · **Order date** 와 라인을 읽고 **Merge** 를 누릅니다. **새 초안**이 열립니다.

합치기가 하는 일:
- 머리는 가장 오래된 오더에서 옵니다. 머리가 서로 달랐던 곳은 창에 보입니다 — 새 초안에서 고칩니다.
- **Order date** 는 합친 날입니다.
- 라인 가격은 그대로 두고 손으로 정한 가격으로 표시합니다. 오늘 가격이 더 낫다면 창이 알려 줍니다 — 원하면 라인을 고칩니다.
- 운임은 옮겨지지 않습니다 — 다시 넣습니다. 선수금은 새 오더로 옮겨집니다.
- 옛 오더들은 merged(합쳐짐)로 닫힙니다. 되돌리기는 없습니다.
- 새 오더는 초안이라 아무것도 확보돼 있지 않습니다. 다시 **Confirm** 해야 재고가 확보됩니다.

**합치기 — 매니저 이상**
- 이미 확정된 오더는 매니저만 합칠 수 있습니다("A confirmed order is included — a manager has to do this merge.").
- 확정 오더의 **Merge…** 단추는 매니저에게만 보입니다.

**창고 바꾸기(Change warehouse) — 매니저 이상**
1. 아직 창고로 가지 않은 확정 오더에서 **Change warehouse…** 를 누릅니다.
2. **Move to** 를 고르고 **Preview** 를 누른 뒤 **Change warehouse** 를 누릅니다.
- "Reservations here are released and taken again in the new warehouse. Whatever it does not have becomes a backorder order."(여기 확보한 것은 풀고 새 창고에서 다시 확보 · 없는 것은 백오더 오더)

**조심할 것**
- 열린 백오더가 있는 오더는 합칠 수 없습니다. 먼저 백오더를 진행(Proceed)한 뒤 합칩니다([백오더](#sales-backorders)).

<!-- SCREENSHOT: sales-divide-merge-1 · Merge 미리 보기: Orders · Header from · Order date 와 라인 목록 -->

<a id="sales-backorders"></a>
## 백오더
<!-- screen: so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: sales, office -->

**무엇인가**
백오더는 고객이 주문했지만 확정 때 확보하지 못한 것입니다. 재고가 들어올 때까지 따로 오더(예: SO-99001b)로 기다립니다. 프리오더도 같은 방식으로 기다립니다.
**Sales ▾** › **Backorders** 에는 탭이 넷 있습니다: **Arrivals**(처음 열림) · **Insights** · **All backorders** · **Emails**

**Arrivals(입고)**
- 맨 위 **Ready to ship now** 는 지금 재고로 보낼 수 있는 백오더입니다.
- 그 아래는 들어온 재고와 그것을 기다리는 고객입니다. 같은 브랜치 고객이 먼저 나옵니다. **Other branches**(다른 브랜치)는 회색입니다 — 먼저 재고를 옮기거나 오더의 창고를 바꿉니다.

**진행(Proceed) — 매니저 이상**
1. 줄의 **proceed**(**Arrivals** 나 **All backorders**)나, 오더 화면의 **Proceed backorder…** 를 누릅니다.
2. **Proceed SO-99001b — reserve stock that is here now** 창이 **Reserved**(확보) 와 **Still backordered**(아직 백오더)를 보여 줍니다. **Proceed** 를 누릅니다.
- 진행은 오더 전체에 걸립니다 — 그 오더의 다른 백오더 라인도 재고가 되는 만큼 함께 확보됩니다.
- 그 뒤 오더를 **Release to WMS** 로 보낼 수 있습니다.

**All backorders(모든 백오더)**
모든 백오더 · 프리오더 라인입니다. **Open** · **Ended (backorders)** · **All**, 고객 · 공급처 · 브랜드 · SKU · **Arrived since** · 날짜로 필터합니다. **↓ CSV** 는 필터에 맞는 것을 내려받습니다.

**Insights(분석)**
백오더로 잃는 금액(**Lost sales**)과 자꾸 모자라는 SKU 를 보여 줍니다. SKU 를 누르면 그 오더들이 보입니다.
- 매니저 이상: **mark…** 는 진짜 수요가 아니었던 잃은 판매를 셈에서 뺍니다(**Staff error** · **Duplicate entry** · **Test** · **Other**). **unmark** 는 다시 넣습니다.

**Emails(메일)**
고객에게 가는 입고 알림 메일입니다. 정해진 아침마다 브랜치별로 한 번씩 돕니다. **Only runs with a problem** 은 확인이 필요한 것만 보여 줍니다.
- 매니저 이상: 확인이 필요한 메일에서 **Close as sent** · **Send again** · **Cancel**
- 고객이 이 메일을 받는지는 고객 화면에서 정합니다 — [고객 찾기 · 더하기](#sales-customers)

**백오더가 끝나는 길**

| 끝남 | 뜻 |
|---|---|
| Taken over by a new order | 고객이 같은 제품을 다시 주문했고 그 오더가 확정됐다 |
| Proceeded (stock reserved) | 재고가 와서 매니저가 진행했다 |
| Expired | 원래 주문일에서 90 일이 지나도록 아무도 진행하지 않았다 |
| Cancelled | 누군가 취소했다 |
| Merged | 다른 오더에 합쳐졌다 |

**조심할 것**
- 만료는 나뉜 날이 아니라 **원래** 주문일부터 셉니다.
- 무상 라인(예: replacement)의 백오더는 만료되지도, 이어받히지도 않습니다. 진행하거나 취소해야만 끝납니다.

<!-- SCREENSHOT: sales-backorders-1 · Arrivals 탭: Ready to ship now 와 한 입고 아래 기다리는 고객들 -->

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
## 고객 결제와 선수금
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

<!-- rulings: 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 484, 488, 489, 490, 507, 514, 516, 517, 529, 532, 541, 545, 546, 590, 709, 713, 714, 715, 719, 720, 723 -->
