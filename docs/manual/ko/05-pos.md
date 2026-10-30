# 5. POS (계산대)

<!-- sections 1-8 written (manual-5) · sections follow the order of the work at the counter -->
<!-- out of this chapter: counter orders (Hand over — ship and invoice…) -> chapter 1 · returns -> chapter 1 credit notes · B-grade bins and prices -> chapter 3 -->

<a id="pos-start"></a>
## POS 시작하기
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 ; ims-auth.js · BUILD nav v10 -->
<!-- who: sales -->

**무엇인가**
**POS** 는 계산대 화면입니다. 계산대 앞에 선 고객에게 팔고, 결제를 받고, 물건을 건넵니다. POS 판매는 모두 고객 계정에 달린 판매 오더입니다.

**누가**
판매 오더를 다루는 사람 모두. POS 만의 권한은 따로 없고, 매니저만 하는 걸음도 없습니다.

**어떻게**
1. Asung 로고 옆의 **POS** 를 누릅니다([모드: IMS · WMS · POS](00-getting-started.md#start-modes)).
2. 왼쪽 위에서 이 계산대의 매장을 고릅니다. "This counter's store — remembered on this device"(이 계산대의 매장 — 이 기기에 기억된다)
3. **+ New sale** 을 누릅니다.

**알아 둘 것**
- POS 에는 ☰ Menu 가 없습니다. 다른 화면으로 가려면 **IMS** 를 누릅니다.
- 매장은 이 태블릿에만 기억됩니다. 다른 태블릿에서는 매장을 다시 고릅니다. 잃는 것은 없습니다 — 판매마다 자기 매장을 가집니다.
- 재고는 그 매장의 창고에서 나갑니다.

**조심할 것**
- 매장을 고르지 않으면 시작할 수 없습니다: "Pick this counter's store first (top left)."(먼저 왼쪽 위에서 매장을 고른다)

<!-- SCREENSHOT: pos-start-1 · 매장을 고른 POS 화면과 + New sale -->

<a id="pos-sale"></a>
## 판매 찍기
<!-- screen: pos.html · BUILD 2026-10-26 · pos v1.14 ; combo hint BUILD 2026-10-30 · pos v1.17 ; ims-overdue.js · BUILD 2026-10-26 · overdue v1 -->
<!-- who: sales -->

**무엇인가**
판매는 고객을 고르는 데서 시작하고, 그다음 물건을 스캔합니다. "Pick the customer first — every POS sale is on a customer account."(먼저 고객을 고른다 — POS 판매는 모두 고객 계정에 달린다)

**어떻게**
1. **+ New sale**(또는 **Customer…**)을 누릅니다. **Customer for this sale** 에서 이름 일부를 적고 고객을 누릅니다.
  그 고객에게 기한이 지난 인보이스가 있으면 **Overdue invoices**(연체 인보이스) 창이 열립니다. 읽고 결제를 물어본 뒤 **OK** 를 누릅니다 — 판매를 막지 않습니다([새 판매 오더 시작](01-sales.md#sales-new-order)).
2. 바코드를 스캔하거나 SKU 를 적고 Enter 를 누릅니다. 가장 나중 물건이 맨 위에 오고, 그 사진이 오른쪽 위에 크게 나옵니다.
3. 코드가 맞지 않으면 **Find…** 를 눌러 SKU 나 이름으로 찾습니다. "Nothing matched that code exactly — pick from the list."(정확히 맞는 코드가 없다 — 목록에서 고른다)
4. 수량은 **−** · **+** 로 바꾸거나 숫자를 적습니다. **✕** 는 그 물건을 뺍니다.
5. 다 스캔했으면 **Confirm — show the amount** 를 누릅니다([결제 받기](#pos-pay)).

**처음 사는 고객**
IMS 는 고객 계정 없이 팔지 않습니다. 계정을 먼저 만듭니다: **IMS** 를 누르고 **Sales ▾** › **Customers**([고객 찾기 · 더하기](01-sales.md#sales-customers)). 그다음 돌아와 **Customer…** 를 누릅니다.

**알아 둘 것**
- 위 막대에 고객 · 가격 등급 · 결제 조건이 나옵니다. **Credit**(쓸 수 있는 크레딧) · **Open invoices**(덜 받은 인보이스) · **Overdue**(연체) 칩은 보기만 합니다 — 판매를 막지 않습니다.
- 세트로 팔지 않는 세트는 낱개로 들어갑니다: 예를 들어 "DEMO-001-6 is not sold as a set — added DEMO-001 × 6 instead"(세트로 팔지 않는다 — DEMO-001 × 6 을 대신 넣었다)
- 콤보는 그 아래 작은 줄로 구성품을 보입니다.
- 찍은 물건이 콤보의 구성품으로도 팔리면 "Also sold as combo …"(콤보로도 판다) 칩과 **Use combo** 가 나옵니다. **Use combo** 는 콤보 하나를 넣고, 같은 물건을 콤보 하나에 드는 수만큼 판매에서 뺍니다(나중에 담은 라인부터). 무상 라인 · B급 라인은 건드리지 않습니다. 제안일 뿐이라 누르기 전에는 아무것도 바뀌지 않습니다.
- 창고에 있는 것보다 많으면 먼저 묻습니다: "Only … available in this store's warehouse (on hand minus what other orders hold). Sell … anyway?"(이 매장 창고에 …개뿐 — 그래도 팔까)

**조심할 것**
- "No tax rule — pick one before Confirm."(세금 규칙이 없다 — Confirm 전에 고른다) 경고 아래의 **Tax rule** 을 고릅니다.
- "A line has no price — Confirm is blocked until it gets one."(가격이 없는 라인이 있으면 Confirm 이 막힌다) 가격을 넣습니다([가격 · 할인 · 쿠폰](#pos-prices)).
- "This SKU is already on the sale at another price — change that line's quantity instead."(이 SKU 가 다른 가격으로 이미 있다 — 그 라인의 수량을 바꾼다)

<!-- SCREENSHOT: pos-sale-1 · 고객 막대 · 물건 셋 · 큰 사진이 있는 초안 판매 -->

<a id="pos-prices"></a>
## 가격 · 할인 · 쿠폰
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**무엇인가**
가격은 고객의 가격 등급 · 고객 할인 · 딜에서 옵니다 — 판매 오더와 같습니다. POS 는 할인이 어디서 왔는지 큰 글씨로 보입니다.

**라인에 나오는 것**
- **Sale** — 딜. 원래 가격에 줄이 그어집니다.
- **Customer discount** — 그 고객의 할인
- **Set discount** — 세트의 할인
- **Discount by hand** · **price set by hand** — 계산대에서 누가 바꾼 것. 누가 · 언제가 라인에 남습니다.

**어떻게 — 물건 하나의 가격 바꾸기**
1. 초안 판매에서 가격 옆의 **✎** 를 누릅니다.
2. **Price each**(낱개 가격) 또는 **or Discount %**(할인 %) — 둘 중 하나만 적습니다. "A price or discount set here is final for this item — the order discount does not apply to it. Your name is kept on the line."(여기서 정한 가격 · 할인이 이 물건의 마지막 값 — 오더 할인은 붙지 않는다. 내 이름이 라인에 남는다)
3. **Save** 를 누릅니다. **Back to the usual price** 는 가격 등급 · 고객 할인 · 딜로 되돌립니다.

**예**
DEMO-001 의 정가가 10.00 입니다. **Price each** 에 8.50 을 적으면 8.50 에 팝니다. **or Discount %** 에 20 을 적으면 8.00 에 팝니다.

**쿠폰**
**COUPON** 칸은 고객에게 쓸 수 있는 쿠폰이 있거나, 이미 판매에 쿠폰이 붙어 있을 때만 나옵니다.
1. 쿠폰 옆의 **Use** 를 누릅니다(또는 코드를 적고 **Apply**).
2. 판매 하나에 쿠폰 하나. **Use instead** · **Replace** 는 바꿔 붙입니다. **✕** 는 뗍니다 — "The customer can still use it later."(고객은 나중에 다시 쓸 수 있다)
- 쿠폰이 이기지 못하면 **not used** 와 까닭이 나옵니다. **Confirm** 때 쓰이지 않은 쿠폰은 떨어집니다: "The coupon was not used, so it was taken off — the customer can still use it."

**조심할 것**
- "The price must be above 0 — a free item needs a reason (Sales Orders screen)."(가격은 0 보다 커야 한다 — 무상은 사유가 필요하다 · Sales Orders 화면)

<a id="pos-bgrade"></a>
## B급 팔기
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**무엇인가**
B급은 포장이 상한 같은 제품입니다. B급 bin 에 자기 가격을 달고 있습니다([B급 재고](03-inventory.md#stock-bgrade)). POS 에서만 팔고, 최종 판매(final sale)입니다.

**어떻게**
1. 평소처럼 스캔합니다.
2. 그 물건의 **B** 를 누릅니다 — "Sell as B-grade — damaged package, from a B-grade bin, final sale"(B급으로 판다 — 포장 손상 · B급 bin 에서 · 최종 판매)
3. B급 bin 이 여럿이면: "Pick the one it came from — each bin has its own price."(어디서 왔는지 고른다 — bin 마다 가격이 다르다) 가격이 없는 bin 은 고를 수 없습니다.
4. 수량이 2 이상이면 몇 개가 B급인지 적습니다. 나머지는 보통 물건으로 남습니다.

그 라인에 "B-grade · bin … · Final sale — no return, no refund"(B급 · 최종 판매 — 반품 · 환불 없음)가 나옵니다.

**알아 둘 것**
- B급 가격이 마지막 값입니다. 고객 할인 · 딜 · 쿠폰 · **✎** 가 붙지 않고, surcharge(관세 부가 요금)도 붙지 않습니다. 세금은 붙습니다.
- **✕B** 는 보통 가격의 보통 물건으로 되돌립니다.
- 같은 bin 의 B급을 또 넣으면 먼저 있던 B급 라인에 합쳐집니다: "It was added to the B-grade line already on this sale."

**조심할 것**
- 장부보다 많으면 먼저 묻습니다: "The books have only … B-grade in bin …. Sell … anyway?"(장부에는 B급이 …개뿐 — 그래도 팔까) 팔면 그 bin 이 0 아래로 내려갑니다 — 세는 사람에게 알립니다.

<a id="pos-pay"></a>
## 결제 받기
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**무엇인가**
**Confirm — show the amount** 가 판매를 확정하고 낼 금액을 보입니다. 그다음 결제를 하나씩 적습니다.

**어떻게**
1. **Confirm — show the amount** 를 누릅니다. 모든 물건이 그대로 이 판매에 확보됩니다 — 여기서 선반을 확인하지 않습니다. 오른쪽에 **Items** · **Tax** · **Total** · **To pay**(낼 금액)가 나옵니다.
2. 고객이 단말기로 냅니다. 단말기가 승인한 뒤에 적습니다.
3. 결제 방법을 누릅니다: **Cash** · **Debit** · **Credit** · **e-Transfer**
4. **Amount** 에는 남은 금액이 채워져 있습니다. 일부만 내면 고칩니다. **Reference**(전표 · 승인 번호)를 적습니다.
5. **Record** 를 누릅니다.

**나눠 내기**
"A split payment is just two payments — record each one."(나눠 내기는 결제 둘 — 하나씩 적는다) 예를 들어 **Debit** 30.00, 나머지는 **Cash**.

**현금**
**Cash given**(받은 현금)을 적으면 거스름돈이 보입니다. "Record the amount kept, not the cash handed over (change is not recorded)."(받은 돈이 아니라 남긴 금액을 적는다 — 거스름돈은 적지 않는다)

**알아 둘 것**
- 받아 둔 돈(money on account)과 열린 크레딧 노트는 저절로 이 판매를 냅니다. 오른쪽에 **Credit / on account** 로 나옵니다.
- **Confirm** 뒤에는 스캔 칸이 "Confirmed — Reopen to add or change items"(확정됨 — 물건을 바꾸려면 Reopen)라고 합니다. 바꾸려면 **Reopen to change items** 를 누릅니다 — "Payments already taken stay on it."(이미 받은 결제는 그대로 남는다)

<!-- SCREENSHOT: pos-pay-1 · 결제 단추 넷과 To pay 가 있는 확정된 판매 -->

<a id="pos-finish"></a>
## 끝내고 인보이스 인쇄하기
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 ; ims-doc.js -->
<!-- who: sales -->

**무엇인가**
**Finish** 는 물건을 건네고 인보이스를 한 번에 발행합니다.

**어떻게**
1. **Finish — hand over and invoice** 를 누릅니다.
2. **Finish SO-99001** 창에 **Total** · **Paid for this sale**(이 판매에 받은 돈) · **Credit / money on account used**(쓴 크레딧 · 받아 둔 돈) · **Nothing left to pay**(낼 것 없음) — 또는 **Still owed — goes on the invoice**(남은 돈 — 인보이스에 남는다)가 나옵니다.
3. **Finish** 를 누릅니다.
4. 화면에 인보이스 번호(예: 99001)와 **Paid in full**(다 냄) 또는 **Still owed**(남음)가 나옵니다.
5. **Print invoice** 를 눌러 고객에게 인쇄해 줍니다. 또는 **Sales Invoices** 에서 엽니다.
6. 다음 고객은 **+ New sale** 을 누릅니다.

**알아 둘 것**
- "Finish hands the goods over and issues the invoice now. It does not stop you if something is still owed — that stays on the invoice."(남은 돈이 있어도 막지 않는다 — 인보이스에 남는다) 남은 돈은 고객의 결제 조건대로 받습니다.
- 고객에게 주는 종이는 인보이스입니다. 따로 계산대 영수증은 없습니다.
- 장부보다 많이 나가도 Finish 는 됩니다. [Action Centre](06-action-centre.md#action-sold-short) 에 나옵니다.

**조심할 것**
- Finish 뒤에는 POS 에서 판매를 바꿀 수 없습니다. 반품은 크레딧 노트로 합니다([크레딧 노트](01-sales.md#sales-credits)). B급은 최종 판매입니다.

<a id="pos-park"></a>
## 판매를 잠시 두고 다시 잡기
<!-- screen: pos.html · BUILD 2026-10-26 · pos v1.14 -->
<!-- who: sales -->

**무엇인가**
**Park** 는 확정된 판매를 옆으로 두고 다음 고객을 받게 합니다 — "it stays open at this store"(이 매장에 열린 채 남는다). 물건은 그 판매에 확보된 채입니다.

**어떻게**
1. 확정된 판매에서 **Park** 를 누릅니다. 화면이 비워집니다.
2. 그 판매가 **Parked and open at this store**(이 매장에 잠시 둔 · 열린 판매)에 **Customer** · **State** · **Amount** · **Paid** 와 함께 나옵니다.
3. 이어서 하려면 그 판매를 누릅니다. "Click to pick it up at this counter."(눌러서 이 계산대에서 잡는다) 이 매장의 어느 계산대에서든 잡을 수 있습니다.

**초안 지우기**
확정한 적이 없는 초안은 지울 수 있습니다 — 예: 잘못 시작한 판매
1. 열린 초안의 위쪽 **Delete draft** 를 누르거나, **Parked and open at this store** 의 그 줄 **✕** 를 누릅니다(판매를 열지 않습니다).
2. "Delete draft …? It has never been confirmed, so it disappears — the number is not reused."(확정한 적이 없어 사라진다 — 번호는 다시 쓰지 않는다)를 묻습니다. **OK** 를 누릅니다.
- 확정된 판매에는 **Delete draft** 도 **✕** 도 없습니다. IMS 가 거절하면 까닭을 알려 줍니다.
- **Sales Orders** 의 **Delete draft** 와 같은 일입니다.

**알아 둘 것**
- 시작한 초안도 여기에 "draft — scanning"(초안 — 스캔 중)으로 나옵니다.
- Park 는 상태가 아닙니다. 판매는 confirmed 그대로입니다.

**조심할 것**
- "A confirmed sale not finished by the end of the day shows on the manager list."(그날 끝내지 못한 확정 판매는 매니저 목록에 나온다) 여기서는 "confirmed from … — not finished" 로 나옵니다. 끝내거나, 다시 열어 물건을 뺍니다. 매니저 목록은 [Action Centre](06-action-centre.md#action-pos) 입니다.

<a id="pos-statuses"></a>
## 상태의 뜻
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: all -->

위의 판매 번호 옆에 상태가 나옵니다. 예: "SO-99001 · draft"

| 상태 | 뜻 |
|---|---|
| draft | 스캔하는 중. 물건 · 가격 · 쿠폰을 바꿀 수 있습니다. |
| confirmed | 금액이 정해지고 물건이 확보됨. 결제를 받고 **Finish**. **Reopen to change items** 는 draft 로 되돌립니다. |
| fulfilled | 끝남 — 물건을 건넸고 인보이스가 발행됨 |

**Sales Orders** 에서 POS 판매에는 **POS** 꼬리표가 붙습니다. 배지는 다른 오더와 같습니다 — [상태의 뜻](01-sales.md#sales-statuses)

**하루 마감**
현금 세기와 카드 단말기 마감은 IMS 밖에서 합니다. 그날 받은 결제를 맞춰 보려면: **Sales ▾** › **Customer Payments** 에서 결제 방법을 고르고(**All methods** 에 목록이 있다), 두 날짜를 그날로 맞춘 뒤 **↓ CSV** 를 누릅니다([고객 결제와 선수금](01-sales.md#sales-payments)).

<!-- rulings: 159, 225, 283, 546, 547, 629, 886, 633, 634, 635, 640, 644, 647, 648, 709, 713, 714, 715, 719, 720, 723, 725, 732, 735, 736, 737, 769, 773 -->
