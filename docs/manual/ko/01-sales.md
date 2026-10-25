# 1. 판매

<!-- sections 1-21 written (manual-1a ~ 1d) · sections follow the order of the work, not the order of the screens -->
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
- 수량 아래 **available** 은 이 창고에 지금 남은 수량입니다. 수량보다 적으면 빨갛게 보입니다([재고 찾기](03-inventory.md#stock-availability)).

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
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
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
| Reserved | 라인 전체가 확보됐다 |
| Partly reserved | 라인 일부가 확보됐다 · 나머지는 백오더 오더로 간다 |
| Backordered | 하나도 확보하지 못했다 · 라인이 백오더 오더로 간다 |
| Preorder | 라인이 프리오더 오더로 간다 |
| On hold | 보류로 확정했다 · 아무것도 확보하지 않았다 |

**예**
Customer A 의 SO-99001 이 제품 X 를 30 주문했습니다. 창고에 남은 것은 18 입니다.
- **Reserved** 18 · **Backorder** 12
- 창에 "Split off: SO-99001a backorder (1 line)"(나뉨) 이 나옵니다.
- SO-99001 은 18 을 가지고 창고로 갈 수 있습니다. SO-99001a 는 12 를 가지고 **Backorders** 화면에서 기다립니다.

**알아 둘 것**
- **이어받기.** 새 오더를 확정하면, 같은 고객 · 같은 제품의 예전 열린 백오더를 오래된 것부터 닫습니다. 창의 "Backorders taken over from earlier orders" 아래에 보입니다. 그 수요는 이제 새 오더가 가집니다.
- 가격이 **없는** 라인이 있으면 확정이 막힙니다. 먼저 가격을 넣습니다.
- 매니저가 아닌 직원에게는 **Confirm…** 이 보이지 않습니다. 매니저에게 확정을 부탁합니다.
- **Counter 오더** — 매니저 이상: counter 초안에서 **Confirm** 을 누릅니다. "Every line is reserved as it is — counter orders never split or backorder."(모든 라인을 그대로 확보 · counter 오더는 나뉘지도 백오더가 되지도 않는다)
- **서비스 오더** — 판매 오더를 다루는 사람이면 누구나 서비스 초안에서 **Confirm** 을 누릅니다. 인보이스는 그 뒤 **Invoice…** 로 냅니다([Ship & invoice](#sales-ship-invoice)).

<!-- SCREENSHOT: sales-confirm-1 · Confirm 미리 보기 창: Reserved · Backorder · Preorder 칸과 "Split off" 줄 -->

<a id="sales-release"></a>
## 창고로 보내기
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: sales, office -->

**무엇인가**
**Release to WMS** 는 확정된 오더를 창고로 보냅니다. 창고 매니저의 **Split & Waves** 화면에 나타납니다([오더를 묶음과 웨이브로 나누기](04-wms.md#wms-waves)). 상태가 **Released to WMS** 가 되고, 픽을 시작하면 **Working** 이 됩니다.

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
- 창고가 일을 시작하면(**Working**) 단추가 회색입니다: "The warehouse is working on it — ask the warehouse manager to send it back first"(창고 매니저에게 먼저 돌려 달라고 하라 · [WMS Admin](04-wms.md#wms-admin))

**Delete draft**
1. 초안에서 **Delete draft** 를 누릅니다.
2. "Delete draft SO-99001? It has never been confirmed, so it disappears — the number is not reused." 에 OK 를 누릅니다.

**Unconfirm — supervisor · admin**
1. IMS 안에 있는 확정 오더에서 **Unconfirm** 을 누릅니다.
2. "Unconfirm SO-99001? Reserved stock is released and split-off backorder/preorder orders come back into this one (supervisor)." 에 OK 를 누릅니다.
3. 오더가 다시 초안이 됩니다. 그 확정 때 나뉜 백오더 · 프리오더 오더(예: SO-99001a)가 이 오더 안으로 돌아옵니다. 이 오더가 예전 오더에서 이어받았던 백오더 라인은 다시 열리고, IMS 가 몇 라인인지 알려 줍니다.
- 이 오더가 쓴 쿠폰은 다시 쓸 수 있습니다.
- 확정된 서비스 오더도 같은 방법으로 초안으로 돌아갑니다.

**Unconfirm 이 거절할 때**

| IMS 의 글(줄임) | 할 일 |
|---|---|
| only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) | Recall 하거나, 창고에 먼저 되돌려 달라고 합니다 |
| was itself split off at confirmation — unconfirm the original order … instead | 원래 오더를 Unconfirm 합니다(SO-99001a 가 아니라 SO-99001) |
| has a hand-made split order … (cancel or merge it first) | 손으로 나눈 오더를 먼저 정리합니다 |
| was split again after confirmation | Unconfirm 은 확정 때 나뉜 것만 되돌립니다 |
| Split order … was changed after the split | 더는 할 수 없습니다 — 오더를 취소하거나 고칩니다 |

**Counter 오더 — 매니저 이상**
**Reopen as draft** 를 누릅니다. "Reserved stock is released."(확보한 재고가 풀린다)

**조심할 것**
- 오더를 아주 닫으려면 [오더 취소](#sales-cancel)를 봅니다.

<a id="sales-divide-merge"></a>
## 오더 나누기 · 합치기
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
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
백오더는 고객이 주문했지만 확정 때 확보하지 못한 것입니다. 재고가 들어올 때까지 따로 오더(예: SO-99001a)로 기다립니다. 프리오더도 같은 방식으로 기다립니다.
창고에서 모자란 몫도 백오더가 됩니다 — [물건이 모자랄 때](04-wms.md#wms-pick-short)
**Sales ▾** › **Backorders** 에는 탭이 넷 있습니다: **Arrivals**(처음 열림) · **Insights** · **All backorders** · **Emails**

**Arrivals(입고)**
- 맨 위 **Ready to ship now** 는 지금 재고로 보낼 수 있는 백오더입니다.
- 그 아래는 들어온 재고와 그것을 기다리는 고객입니다. 같은 브랜치 고객이 먼저 나옵니다. **Other branches**(다른 브랜치)는 회색입니다 — 먼저 재고를 옮기거나 오더의 창고를 바꿉니다.

**진행(Proceed) — 매니저 이상**
1. 줄의 **proceed**(**Arrivals** 나 **All backorders**)나, 오더 화면의 **Proceed backorder…** 를 누릅니다.
2. **Proceed SO-99001a — reserve stock that is here now** 창이 **Reserved**(확보) 와 **Still backordered**(아직 백오더)를 보여 줍니다. **Proceed** 를 누릅니다.
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
- 프리오더도 만료되지 않고 이어받히지 않습니다. 진행하거나 취소할 때까지 기다립니다.

<!-- SCREENSHOT: sales-backorders-1 · Arrivals 탭: Ready to ship now 와 한 입고 아래 기다리는 고객들 -->

<a id="sales-charges"></a>
## 운임과 그 밖의 비용
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office -->

**무엇인가**
비용은 오더에 붙는 금액만 있는 라인입니다 — 운임, 포장비 등. 인보이스에서 제품 아래에 나옵니다.

**언제**
운임은 보통 실제 금액을 아는 **Ship & invoice** 때 넣습니다. 고객과 미리 금액을 정했으면 먼저 넣어도 됩니다.

**어떻게**
1. 초안에서 **Add a charge** 를 누릅니다.
2. **Name** 은 "Freight" 로 시작합니다. 다른 비용이면 바꿉니다.
3. **Amount**(금액)를 적습니다(0 이상).
4. **Discount**: **none** · **%** · **$** 와 숫자
5. 원하면 **Description**, 그리고 **Account**(계정)를 고릅니다. 새 비용은 **_99_**(운임 매출)로 시작합니다. 운임이 아닌 비용이면 다른 계정을 고릅니다.
6. **Save** 를 누릅니다. **✎** 는 비용을 고치고, **✕** 는 지웁니다.

**팩이 끝난 뒤 — master 권한도 필요**
**Finalized** 오더에서도, 판매 오더를 다루면서 **master 권한도 있는** 사람은 **Add a charge** 를 누를 수 있습니다(예: 포장비). "The charge goes on the invoice when you Ship & invoice — the Ship & invoice window shows it."(Ship & invoice 때 인보이스에 실린다)

**알아 둘 것**
- **Ship & invoice** 전에는 Warehouse 오더의 운임에 **estimate**(견적) 표시가 붙습니다: "Before Ship & invoice the freight is an estimate — Ship & invoice updates this line with the actual freight"
- "Tax follows the order's tax rule."(세금은 오더의 세금 규칙을 따른다)
- 할인은 인보이스에 따로 한 라인으로 나옵니다 — 운임과 운임 할인을 나눠 둡니다.

**조심할 것**
- "A charge cannot be negative — money back is a credit note."(비용은 음수가 될 수 없다 · 돌려줄 돈은 크레딧 노트)
- 체크아웃에서 운임을 이미 낸 웹 오더가 있습니다. 그런 오더에는 팩이 끝난 뒤 **Add a charge** 가 나오지 않습니다.

<a id="sales-ship-invoice"></a>
## Ship & invoice(출고 + 인보이스)
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office -->

**무엇인가**
창고가 오더를 끝내면 상태가 **Finalized** 가 됩니다. 그러면 오피스가 **Ship & invoice** 를 누릅니다: 물건이 장부에서 빠지고 인보이스가 발행됩니다. 한 번에 일어납니다.

**언제**
**Finalized** 오더를 보낼 준비가 되면 바로 — 운임 견적과 운송사가 정해졌을 때.

**어떻게 — 오더 하나**
1. **Finalized** 오더를 열고 **Ship & invoice…** 를 누릅니다.
2. 맨 위 **What the warehouse packed** 에 팔레트 · 박스마다 크기와 무게가 나옵니다 — 운임 견적에 씁니다([상자 · 팔레트에 담기](04-wms.md#wms-fulfillment)). "⚠ … unit(s) have no dimensions — ask the warehouse before quoting freight."(크기 없는 짐 · 창고에 먼저 묻는다)
3. 운임: 오더에 이미 있는 비용의 금액을 실제 운임으로 바꾸거나, **Freight amount** 에 새 라인 금액을 적습니다. 비우면 운임 라인이 없습니다.
4. **Carrier**(운송사)를 고르고 **Tracking number**(송장 번호)를 적습니다(박스가 여럿이면 쉼표로 나눔). 필요하면 **Shipping notes** 도 적습니다.
5. **Preview** 를 누릅니다. **What will happen** 을 읽습니다: 라인마다 **Ordered** · **Ships** · **Short**, 비용, 인보이스
6. **Ship & invoice** 를 누르고 확인합니다. 여기서는 되돌릴 수 없습니다.
7. 결과에 **Invoice** · **Amount due** · **Still owed** 와 **Print invoice** · **Email invoice…** 단추가 나옵니다.

**여러 오더를 인보이스 한 장으로**
1. 같은 창에서 **Other packed orders for …** 를 엽니다 — 같은 청구처 · 같은 통화의 **Finalized** 오더(30 개까지)
2. 함께 보낼 오더를 체크합니다. 오더마다 운임 · 운송사 · 송장 번호 · 메모를 따로 적습니다.
3. **Preview** 뒤 **Ship & invoice** 를 누릅니다. "Orders invoiced together go on one invoice for this bill-to (or one per store, if the customer is set to split by store)."(함께 낸 오더는 청구처 한 장 · 매장별로 나누는 고객이면 매장마다 한 장)

**운송사 종류**
- 운송 회사: "A tracking number is needed."(송장 번호가 필요하다)
- **Pickup**: "the customer collects it. No tracking number."(고객이 찾아간다 · 송장 없음) [픽업 오더와 추적번호](#sales-pickup)
- **Delivery**(우리 트럭): 송장 번호 없음

**Counter 오더 — 매니저 이상**
1. 확정된 counter 오더에서 **Hand over — ship and invoice…** 를 누릅니다.
2. 창에 라인마다 꺼낼 bin 과 금액이 나옵니다: **Invoice total** · **Paid for this order** · **Credit / balance used** · **Amount due**
3. **Ship and invoice** 를 누릅니다. "Nothing blocks the hand-over — whatever is not paid stays as an unpaid invoice."(막는 것은 없다 · 안 낸 돈은 미수 인보이스로 남는다)

**알아 둘 것**
- 주문보다 덜 팩됐으면: "the rest goes to a backorder order"(나머지는 백오더 오더로 · [물건이 모자랄 때](04-wms.md#wms-pick-short))
- **Put back to the shelf**(선반에 돌려놓기): 콤보는 통째로 나가거나 안 나갑니다. 콤보가 다 갖춰지지 않으면 남는 구성품을 bin 에 돌려놓으라는 목록이 나옵니다.
- 오더에 이미 받은 결제는 그 인보이스에 저절로 붙습니다.
- **Preview** 뒤에 창의 무엇을 바꾸면 **Preview** 를 다시 누릅니다.

**조심할 것 — 팩된 오더에서 고객이 일부를 빼 달라고 할 때**
1. 오더를 평소대로 Ship & invoice 합니다. 인보이스에는 팩된 수량 그대로 실립니다.
2. 매니저 이상: 그 인보이스에서 뺀 수량만큼 크레딧 노트를 만듭니다. 라인마다 **Back to stock** 을 **to bin** 으로 두고, 물건이 있는 bin 을 그대로 둡니다. **Reason** 은 **Other** 를 고르고 **Note** 에 「출고 전에 고객이 뺐다」고 적습니다. [크레딧 노트](#sales-credits)
3. 뺀 물건은 창고를 떠나지 않았습니다 — 선반에 그대로 둡니다.
- 예: 30 팩 · 고객이 5 를 뺌 → 인보이스 30 · 크레딧 노트 5 · 실제 출고 25. 재고는 실제로 나간 수량과 맞고, 고객은 인보이스와 크레딧 노트 두 장을 받습니다.
- 고객의 **Final invoice emails** 가 자동이면 인보이스가 먼저 메일로 나갑니다. 고객에게 미리 알립니다.

<!-- SCREENSHOT: sales-ship-invoice-1 · Ship & invoice 창: 운임 · 운송사 · 송장 · "Other packed orders for …" 펼친 모습 -->

<a id="sales-pickup"></a>
## 픽업 오더와 추적번호
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office, warehouse -->

**무엇인가**
운송사를 **Pickup** 으로 보낸 오더는 고객을 기다립니다. 고객이 가져갈 때까지 **waiting for pickup**(픽업 대기) 표시가 붙습니다.

**어떻게 — 고객이 가져갔을 때**
1. 오더를 찾습니다. 목록 필터 **Waiting for pickup** 이 모두 보여 줍니다.
2. **Picked up** 을 누릅니다.
3. "Mark SO-99001 as picked up by the customer? … This cannot be undone here." 에 OK 를 누릅니다. 표시가 **picked up** 으로 바뀝니다.
- 웹 오더면 Shopify 에도 알립니다 — 고객에게 메일은 가지 않습니다.

**어떻게 — 운송사 · 송장 번호 고치기**
1. 운송 회사로 보낸 출고 오더에서 **Fix tracking…** 을 누릅니다.
2. **Carrier** 나 **Tracking number** 를 고칩니다(박스가 여럿이면 쉼표로 나눔).
3. **Preview** 뒤 **Save** 를 누릅니다.
- 웹 오더면 Shopify 도 고쳐집니다 — 고객에게 메일은 가지 않습니다.

**조심할 것**
- **Pickup** 과 **Delivery** 는 송장 번호가 없습니다. 고르면 송장 칸이 잠깁니다.
- **Fix tracking…** 은 운송사 이름과 송장 번호만 고칩니다. 운송 회사 오더를 픽업으로 바꿀 수는 없습니다.

<a id="sales-print-email"></a>
## 인쇄와 메일
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office -->

**무엇인가**
문서마다 쓰고 있는 양식으로 인쇄하거나, PDF 를 붙여 메일로 보냅니다.

| 문서 | 어디서 | 단추 |
|---|---|---|
| 판매 오더 | 인보이스가 아직 없는 열린 오더 | **Print order** · **Email order…** |
| Ship Ready(PROFORMA) | **Ship & invoice** 창 안 · **Preview** 뒤 | **Ship Ready (proforma)** · **Email Ship Ready…** |
| 인보이스 | **Ship & invoice** 뒤, 그리고 **Sales Invoices** | **Print invoice** · **Email invoice…** / **Email to customer…** |
| 배송 영수증 | **Sales Invoices** | **Print delivery receipt** |

**어떻게 — 인쇄**
1. 인쇄 단추를 누릅니다. 문서가 인쇄하거나 PDF 로 저장할 수 있게 열립니다.

**어떻게 — 메일**
1. 메일 단추를 누릅니다. 창에 보내는 사람(**From**)과 **To** · **Subject** · **Message** 가 채워져 나옵니다.
2. 원하면 고칩니다. "The PDF of this … is attached, made with the layout in use."(쓰고 있는 양식으로 만든 PDF 가 붙는다)
3. **Send** 를 누릅니다. "The email goes out within a minute or two."(1~2 분 안에 나간다)

**Ship Ready**
- 인보이스가 생기기 전에 나갈 것과 금액을 보여 줍니다. **Ship & invoice** 창에서 먼저 **Preview** 를 누릅니다 — 미리 보기에 나온 그대로 찍힙니다.
- 인보이스 묶음마다 한 장입니다. 찍어도 아무것도 저장되지 않습니다.
- **Email Ship Ready…** 는 미리 보기의 인보이스가 하나일 때만 됩니다: "One email carries one PDF — with more than one invoice, print the Ship Ready instead"(메일 한 통에 PDF 하나 · 인보이스가 여럿이면 인쇄)

**인보이스 메모**
**Sales Invoices** 에서 **Note** 옆의 **Edit** 를 누릅니다. "Note on the document (customers see it)"(고객이 보는 문서 메모). 인보이스에 찍힙니다. "Up to 2,000 characters. Leave it empty to remove the note."(2,000 자까지 · 비우면 메모를 지운다)

**자동 인보이스 메일**
고객의 **Final invoice emails** 가 **automatic** 이면([고객 찾기 · 더하기](#sales-customers)), 인보이스가 발행될 때 PDF 가 저절로 메일로 갑니다. 그래도 손으로 한 통 더 보낼 수 있습니다.

**알아 둘 것**
- 인보이스의 **Emails** 칸에 모든 메일이 보입니다: 언제 · 누구에게 · 상태(**waiting to send** · **sent** · **failed** …) · 보낸 사람(또는 "automatic")
- 아직 기다리는 메일은 **Cancel** 로 멈출 수 있습니다. 까닭을 적어야 합니다.
- 배송 영수증은 지역 배송용입니다 — 기사가 서명을 받습니다. 메일로 보내지 않습니다.

<a id="sales-invoices"></a>
## 판매 인보이스
<!-- screen: so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office, accounting -->

**무엇인가**
**Sales ▾** › **Sales Invoices** 에 모든 인보이스가 있습니다. 인보이스 한 장에 같은 청구처의 오더 여럿이 담길 수 있습니다. 인보이스 번호는 `99001` 같은 꼴입니다.

**인보이스 찾는 법**
1. "Invoice · customer · SO number · reference" 로 검색합니다.
2. 상태로 필터합니다: **Open — still owed**(미수) · **Overdue**(연체) · **Open with no due date**(기한 없는 미수) · **Paid in full**(완납) · **Cancelled** · **All** — 그리고 발행일
3. 인보이스를 누릅니다. **Bill to** · **Issued** · **Due** · **Currency** · **Orders**(누르면 그 오더가 열림), 라인, **Payments** · **Credits applied** · **Emails** 가 보입니다.

**Cancel invoice… — 매니저 이상**
문서 전체가 틀렸을 때만 취소합니다. 일부만 틀렸으면 크레딧 노트를 만듭니다.
1. **Cancel invoice…** 를 누릅니다.
2. "Cancel invoice 99001? Its orders go back to shipped and wait for a new invoice." 에 까닭을 적고(필수) OK 를 누릅니다.
3. 오더가 **Invoice cancelled** 로 보입니다. 물건은 나간 그대로입니다.

**취소가 거절될 때**
- "… payment allocation(s) applied by hand — detach them first (or issue a credit note instead)"(손으로 붙인 결제를 먼저 뗀다 · 또는 크레딧 노트)
- "… credit note allocation(s) applied by hand — detach them first"(손으로 붙인 크레딧을 먼저 뗀다)
저절로 붙은 결제와 크레딧은 저절로 풀립니다.

**Reissue… — 매니저 이상**
1. 취소된 인보이스를 열고 **Reissue…** 를 누릅니다.
2. "Issue a new invoice for SO-99001, dated today (Toronto)? Tax rates are taken as of today." 에 OK 를 누릅니다.
3. 새 번호로 새 인보이스가 열립니다. 취소된 번호는 다시 쓰지 않습니다.

**알아 둘 것**
- "⚠ No due date — the order had no payment term. It is not counted as overdue."(결제 조건이 없던 오더 · 연체로 세지 않는다)
- **↓ CSV** 는 필터에 맞는 인보이스를, **↓ Lines CSV** 는 그 라인을 한 라인 한 행으로 내려받습니다.

<!-- SCREENSHOT: sales-invoices-1 · 인보이스 상세: Orders · Payments · Credits applied · Emails -->

<a id="sales-payments"></a>
## 고객 결제와 선수금
<!-- screen: so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: accounting, office -->

**무엇인가**
결제는 고객이 우리에게 준 돈입니다. IMS 는 그 돈이 어디로 갔는지 적어 둡니다: 인보이스로, 오더를 위해 맡아 둔 돈으로, 또는 고객 계정(잔액)으로.

**어떻게 — 인보이스 전 선수금**
1. 초안 오더에서 **Take a deposit…** 을 누릅니다. 인보이스가 아직 없는 확정 · Finalized 오더에서는 **Take a payment…** 를 누릅니다.
2. "No invoice yet — the payment is recorded against this order and attaches itself when the invoice is issued."(인보이스가 생기면 저절로 붙는다)
3. **Method**(방법)를 고르고 **Amount** · **Paid on** · **Reference**(카드 영수증 · 수표 번호 등) · 필요하면 **Note** 를 적습니다.
4. **Account** 는 "Default for this method and branch"(방법과 브랜치의 기본) 그대로 두어도 됩니다.
5. **Record payment** 를 누릅니다. 인보이스가 나올 때까지 돈은 **Held for orders**(오더를 위해 맡아 둠)입니다.

**어떻게 — 인보이스에 결제하기**
1. 오더나 **Sales Invoices** 에서 **Take a payment…** 를 누릅니다. 창에 "Applied to invoice 99001 · still owed …" 가 나오고 금액이 채워집니다.
2. 금액을 확인하고 **Record payment** 를 누릅니다.

**어떻게 — 고객 계정에 넣기**
1. **Sales ▾** › **Customer Payments** 에서 **+ Record a payment** 를 누르고, 고객을 골라 결제를 적습니다.
2. "It attaches itself to the next invoice they get — or open it here and attach it by hand."(다음 인보이스에 저절로 붙거나, 손으로 붙인다)
3. 손으로 붙이려면: 결제를 열고 **Attach to invoices…** → **Suggest (oldest first)**(오래된 것부터 제안) 또는 금액을 적고 → **Attach**

**예**
Customer A 가 계정에 $500.00 을 냅니다. 다음 인보이스 99001 은 $188.77 입니다. 발행될 때 $188.77 이 저절로 붙고 $311.23 은 계정에 남습니다.

**매니저 이상**
- **Refund…**(**Customer Payments** 에서): "A refund first pays off credit notes owed to the customer, then money on account. It cannot be more than both together."(먼저 고객에게 줄 크레딧, 그다음 계정의 돈에서 · 둘을 합친 것보다 많을 수 없다) **Record refund** 를 누릅니다.
- **Void payment…**: 잘못 넣은 결제에 씁니다. "Everything it paid or covered is released — nothing is deleted."(그 결제가 갚은 것은 모두 풀리고, 지워지지는 않는다) 까닭이 필수입니다.
- 인보이스의 결제 라인에 있는 **detach** 는 그 결제를 인보이스에서 뗍니다. 돈은 계정으로 돌아갑니다.

**결제 태그**
**Sales Orders** 목록에서 인보이스가 나온 오더에 **unpaid**(미결제) · **partly paid**(일부 결제) · **paid**(완납) · **overdue Nd**(N 일 연체)가 붙습니다. 필터 **Any payment** · **Unpaid** · **Partly paid** · **Overdue** · **Paid** 로 찾습니다.

**알아 둘 것**
- **Customer Payments** 필터: **Active** · **Not attached — money on account**(안 붙은 계정의 돈) · **Held for orders** · **Refunds** · **Voided** · **All**
- 결제에는 바꿀 상태가 없습니다. 잘못된 결제는 고치지 않고 Void 합니다.

<a id="sales-credits"></a>
## 크레딧 노트
<!-- screen: so-credits.html · BUILD 2026-10-25 · cr v5a -->
<!-- who: accounting, office -->

**무엇인가**
크레딧 노트는 인보이스에 대해 고객에게 돈을 돌려줍니다 — 돌아온 물건, 너무 높았던 가격, 운임, 실수. 물건을 재고로 되돌릴 수도 있습니다. 크레딧 번호는 `CR-99001` 같은 꼴입니다.

**어떻게 — 매니저 이상**
1. **Sales Invoices** 에서 인보이스를 열고 **Raise a credit note…** 를 누릅니다(또는 **Credit Notes** 의 **+ New credit note** 에서 인보이스를 찾습니다).
2. **Credit note**: **Reason** 을 고릅니다 — **Customer return** · **Damaged** · **Billing error** · **Price adjustment** · **Other**(Other 는 **Note** 필수). **Credit date** 와 **Goods come back to**(돌아올 브랜치)를 확인합니다.
3. **Products**: 라인마다 **Return**(돌려받을 수량)을 적습니다. **Can return** 이 아직 크레딧할 수 있는 수량입니다.
4. **Back to stock**: **to bin** 이면 물건이 재고로 돌아갑니다. bin 칸에는 "the bin the product sits in now (usual bin first)"(지금 그 제품의 bin · 평소 bin 먼저)가 미리 채워집니다. 재고에 넣지 않으려면 **not restocked**(**Damaged** · **Not returned** · **Other**)를 고릅니다.
5. **Freight and charges**: 돌려줄 운임이 있으면 적습니다. 그 할인은 저절로 따라옵니다.
6. **Preview** 로 금액과 세금을 읽고 **Issue credit note** 를 누릅니다.

**가격 조정**
고객은 물건을 그대로 가지고 차액만 돌려받습니다. **Price adjustment — past sale price** 에 **Qty to adjust** 와 **New unit price** 를 적습니다. "No stock moves."(재고는 움직이지 않는다) 사유는 **Price adjustment** 를 고릅니다.

**재입고 수수료(Restocking fee)**
판매한 지 60 일이 넘었으면 IMS 가 알림을 보이고 20 % 수수료를 제안합니다. 받으려면 **Charge a fee** 를 체크하고(% 를 바꿀 수 있다) **Fee account** 를 고릅니다. 저절로 붙지는 않습니다.

**출고 전에 뺀 물건**
[팩된 오더에서 고객이 일부를 빼 달라고 할 때](#sales-ship-invoice)의 두 번째 걸음입니다.
1. 그 인보이스에서 뺀 수량만큼 크레딧을 만듭니다 — 30 팩 · 5 뺌 → 크레딧 5
2. **Back to stock**: **to bin** · 물건이 있는 bin 을 그대로 둡니다.
3. **Reason**: **Other** · **Note**: 「출고 전에 고객이 뺐다」

**IMS 인보이스가 없는 판매**
IMS 이전의 인보이스라면 새 크레딧 창에서 **Credit with a reference number…** 를 누릅니다. **Customer** 를 고르고 **Reference number**(종이 인보이스의 번호 · 필수) · **Invoice date**, 제품마다 **Unit price paid**(낸 단가)를 적습니다.

**크레딧 쓰기**
- 크레딧은 고객의 다음 인보이스가 발행될 때 저절로 붙습니다.
- 손으로 붙이려면: 크레딧을 열고 **Attach to invoices…** → **Fill oldest first**(오래된 것부터) 또는 금액을 적고 → **Attach**
- 돈으로 돌려주려면: **Refund on Customer Payments →**(매니저 이상)

**매니저 이상**
- **Cancel credit note…**: "Returned stock goes back out of the bins it came into. It must not be attached to anything first."(돌아온 재고는 들어온 bin 에서 다시 나간다 · 먼저 아무 데도 붙어 있지 않아야 한다) 까닭이 필수입니다.
- **detach** 는 인보이스에서 크레딧을 뗍니다.

**알아 둘 것**
- 단가와 세금은 인보이스에서 옵니다 — 적지 않습니다.
- **Print credit note** · **Email to customer…** 는 인보이스와 같습니다([인쇄와 메일](#sales-print-email)).

<!-- SCREENSHOT: sales-credits-1 · 새 크레딧 노트 창: Products 의 Return · Back to stock · 꺼진 Restocking fee -->

<a id="sales-web-orders"></a>
## 웹 오더
<!-- screen: shopify-orders.html · BUILD 2026-10-14 · wo v4d -->
<!-- who: office -->

**무엇인가**
웹 숍의 오더는 저절로 들어옵니다. IMS 가 1 분 안에 하나하나 판매 오더로 만듭니다. **Sales ▾** › **Web Orders** 에 들어온 것과 사람이 봐야 할 것이 보입니다.

**상태**

| 상태 | 뜻 |
|---|---|
| Waiting | "Ready — the system makes the sales order within a minute"(1 분 안에 판매 오더를 만든다) |
| Needs review | "The system stopped — pick what it could not decide"(시스템이 멈췄다 · 정하지 못한 것을 골라라) |
| Done | "Sales order made"(판매 오더를 만들었다) |
| Error | "The system could not make the sales order"(만들지 못했다) |
| Cancelled | "Cancelled in Shopify"(Shopify 에서 취소) |

**어떻게 — Needs review**
1. **Needs review** 로 필터하고 오더를 엽니다.
2. 고객: 맞는 고객을 누르거나, **Pick the customer…** / **Another customer…** 로 찾습니다. "The next orders from this Shopify customer will go to this customer by themselves."(이 Shopify 고객의 다음 오더는 저절로 이 고객으로 간다)
3. 라인: "Type the right SKU, or tick leave out. The order is made without left-out lines."(맞는 SKU 를 적거나 leave out 을 체크 · 뺀 라인 없이 만든다) **Save line choices** 를 누릅니다.
4. 오더가 **Waiting** 으로 돌아가고, 1 분 안에 판매 오더가 만들어집니다.
- 매니저 이상: **Process waiting now** 를 누르면 기다리지 않고 바로 합니다.

**경고**
웹 오더나 그 판매 오더에 경고가 붙을 수 있습니다. 경고 글이 할 일을 말합니다. 끝나면 **Mark checked** 를 누릅니다. **Reopen** 은 다시 엽니다. 자주 보는 것:
- "Discount differs from IMS rules" · "List price differs from IMS" — Shopify 가격을 지킵니다.
- "Freight not added (decided at shipping)" — **Ship & invoice** 때 넣습니다.
- "Not confirmed — needs a fix on the sales order"(확정 안 됨 · 판매 오더를 고쳐야 함)
- "Cancelled in Shopify — check the sales order"(Shopify 에서 취소 · 판매 오더 확인)
- "Refunded in Shopify — make a credit note in IMS if needed"(Shopify 에서 환불 · 필요하면 IMS 크레딧 노트)
- "Paid in Shopify, but IMS will not ship part of it — refund that part in Shopify"(그 몫을 Shopify 에서 환불) — 확인 표시에 메모가 필요합니다.
- "Pickup order — no province for tax; pick a tax rule on the sales order"(판매 오더에서 세금 규칙을 고른다)
- "Changed in Shopify after the sales order was made"(판매 오더를 만든 뒤 Shopify 에서 바뀜)

**판매 오더에서**
웹 오더의 판매 오더에는 **Shopify** 꼬리표와 Shopify 내용 카드가 있습니다. **Paid in Shopify** 도 거기 있습니다.

**조심할 것**
- 웹 오더 자체는 여기서 고치지 않습니다. 판매 오더에서 고칩니다.
- 라인에는 Shopify 할인이 그대로 남습니다.

<a id="sales-cancel"></a>
## 오더 취소
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: sales, manager -->

**무엇인가**
취소는 확정 오더를 아주 닫습니다. 초안은 취소하지 않고 **Delete draft** 를 씁니다([오더 되돌리기](#sales-undo)).

**어떻게 — 매니저 이상**
1. IMS 안에 있는 확정 오더에서 **Cancel order…** 를 누릅니다.
2. **Reason**(까닭 · 필수)을 적고 **Check** 를 누릅니다.
3. 결과를 읽습니다: "Orders that will be cancelled (split-off orders go with it)"(나뉜 오더도 함께 취소) — 예: SO-99001 과 SO-99001a 가 함께
4. 이 오더가 예전 오더의 백오더를 이어받았다면 **Reopen** 이나 **Keep closed** 를 고릅니다. 꼭 하나를 골라야 합니다.
5. **Cancel the order** 를 누릅니다.

**무엇이 일어나나**
- 확보한 재고가 다른 오더를 위해 풀립니다.
- 이 오더가 쓴 쿠폰은 다시 쓸 수 있습니다.
- 오더가 **Cancelled** 로 보입니다. 되돌리기는 없습니다.

**조심할 것**
- 창고에 간 오더는 취소할 수 없습니다. 먼저 Recall 하거나 창고에 돌려 달라고 합니다([오더 되돌리기](#sales-undo)).
- 매니저가 아닌 직원에게는 **Cancel order…** 가 보이지 않습니다. 매니저에게 부탁합니다.

<a id="sales-statuses"></a>
## 상태의 뜻
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->

**상태 — 배지와 필터**
배지는 오더에 붙는 색 이름표입니다. 필터는 **Sales Orders** 의 **Status** 목록입니다. 창고 화면은 [창고 쪽 상태](04-wms.md#wms-statuses)를 봅니다.

| 배지(색) | 필터 | 뜻 |
|---|---|---|
| Draft(회색) | Draft | 오피스가 쓰고 있다 |
| Confirmed(파랑) | Confirmed | 확정됨 — 다음: 창고로 보내기 |
| Released to WMS(보라) | With warehouse | 창고 매니저를 기다린다 |
| Working(보라) | With warehouse | 창고가 픽 · 팩 중이다 |
| Finalized(주황) | Finalized — waiting for the office | 준비됨 — 오피스가 **Ship & invoice** 할 차례 |
| Invoice cancelled(진한 주황) | — | 나갔지만 인보이스가 취소됐다 — 인보이스를 다시 낸다 |
| Fulfilled(초록) | Fulfilled | 끝 |
| Cancelled(빨강) | Cancelled | 나가지 않고 닫혔다 · 합쳐진 오더는 "merged" |

다른 필터: **Open**(끝나지 않은 것 전부) · **Draft — reprice suggested** · **Waiting for pickup** · **All**

**배지 옆 꼬리표**
- **unpaid** · **partly paid** · **paid** · **overdue Nd** — [고객 결제와 선수금](#sales-payments)
- **waiting for pickup** · **picked up** — [픽업 오더와 추적번호](#sales-pickup)
- **reprice** — 가격이 낡았을 수 있다 · 오더를 열고 **Reprice**
- **split** — 다른 오더에서 나뉜 오더
- **Shopify** — 웹 오더 · **Counter** · **Service** · **POS** — 채널

**끝나기까지 걸린 날**
Fulfilled 오더에는 만든 날부터 Fulfilled 된 날까지 걸린 날이 보입니다: **same day**(초록) · 1~3 일(호박색) · 3 일 넘음(빨강)

<a id="sales-csv"></a>
## CSV 내려받기
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 ; so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so-credits.html · BUILD 2026-10-25 · cr v5a ; so-backorders.html · BUILD 2026-10-25 · bo cf words v1 -->
<!-- who: office, accounting -->

**무엇인가**
대부분의 판매 화면에서 스프레드시트(CSV)를 내려받을 수 있습니다.

| 화면 | 넓은 목록 | 문서 하나 |
|---|---|---|
| Sales Orders | **↓ CSV** | **↓ Lines CSV** |
| Sales Invoices | **↓ CSV** · **↓ Lines CSV** | **↓ Invoice CSV** |
| Customer Payments | **↓ CSV** | **↓ Payment CSV** |
| Credit Notes | **↓ CSV** | **↓ Credit CSV** |
| Backorders | **↓ CSV** | — |

**어떻게**
1. 넓은 목록에서 필터와 검색을 맞춥니다.
2. **↓ CSV** 를 누릅니다. 필터에 맞는 행이 모두 내려받아집니다 — 화면의 한 페이지만이 아닙니다.
3. 문서 하나의 CSV 단추는 그 문서만 내려받습니다.

**알아 둘 것**
- 바코드와 SKU 는 엑셀에서 글자 그대로 열립니다 — 긴 숫자가 1.23E+12 로 바뀌지 않고 앞의 0 도 남습니다.
- GP(매출 이익) 칸은 `cost` 권한이 있는 사람의 **↓ Lines CSV** 에만 나옵니다.
- 이 파일은 내부용입니다. 고객에게는 인쇄 문서를 보냅니다([인쇄와 메일](#sales-print-email)).

<!-- rulings: 245, 246, 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 349, 357, 433, 436, 437, 438, 443, 449, 452, 455, 467, 469, 473, 484, 488, 489, 490, 507, 514, 516, 517, 526, 529, 532, 540, 541, 545, 546, 549, 590, 602, 609, 610, 612, 628, 709, 713, 714, 715, 719, 720, 723, 724, 725, 726, 727, 729 -->
