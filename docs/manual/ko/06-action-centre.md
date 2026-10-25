# 6. Action Centre(할 일 모음)

<!-- sections 1-6 written (manual-6) · one section per tab, in the order of the tabs -->
<!-- out of this chapter: the work itself stays in its own chapter — sales orders and customers -> chapter 1 · stock adjustments -> chapter 3 · POS -> chapter 5 -->

<a id="action-start"></a>
## Action Centre 란
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, sales -->

**무엇인가**
**Action Centre** 는 매니저가 볼 것을 모읍니다: 장부에 재고 없이 나간 판매, 덜 받은 즉시 결제 인보이스, 끝내지 않은 POS 판매, counter 오더, 새 고객. 보여 주기만 하고, 일은 원래 화면에서 합니다.

**누가**
판매 오더를 다루는 사람은 모두 엽니다. 매니저 이상: **Sold without stock** 의 **Mark checked…**

**언제**
매니저는 하루에 한 번 엽니다.

**어떻게**
1. IMS 모드의 메뉴에서 **Action Centre** 를 누릅니다(**Inventory ▾** 와 **Settings ▾** 사이).
2. 탭을 누릅니다. 탭의 빨간 숫자가 기다리는 건수입니다.
3. **All branches** 에서 브랜치 하나를 고릅니다.
4. 오더 · 인보이스 · 고객을 누르면 원래 화면에서 열립니다.

**탭**
- [Sold without stock](#action-sold-short)(재고 없이 나감)
- [Unpaid at hand-over](#action-unpaid)(건넸는데 덜 받음)
- [POS not finished](#action-pos)(끝내지 않은 POS)
- [Counter orders](#action-counter)(counter 오더)
- [New customers to review](#action-new-customers)(확인할 새 고객)

<!-- SCREENSHOT: action-start-1 · 탭 다섯과 배지가 있는 Action Centre -->

<a id="action-sold-short"></a>
## Sold without stock(재고 없이 나감)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**여기 뜨는 것**
그 브랜치의 장부보다 많이 나간 판매입니다. "These sold more than the book showed in that branch — the goods were there, the count was not."(장부보다 많이 나갔다 — 물건은 있었고 숫자가 틀렸다)

- **Not checked yet**(아직 확인 안 함) — 오래된 것까지 전부. 탭의 빨간 숫자가 이것을 셉니다.
- **Checked**(확인함) — 최근 30일. 누가 · 언제 · 메모가 함께 나옵니다.

줄마다 **Sold on** · **Order** · **Customer** · **SKU** · **Branch** · **Qty short**(모자란 수량) · **Cost** 가 나옵니다(IMS 에 원가가 없으면 **cost unknown**).

**어떻게**
1. 오더 번호를 누릅니다. **Sales Orders** 에서 그 오더가 열립니다 — POS 판매도 같습니다.
2. 선반을 셉니다. 재고는 평소대로 재고 조정으로 고칩니다([재고 조정](03-inventory.md#stock-adjustments)).
3. 매니저 이상: **Mark checked…** 를 누르고 찾은 것을 적습니다("counted, fixed, reason" — 셌다 · 고쳤다 · 까닭).

**알아 둘 것**
- "Checking does not change stock."(확인은 재고를 바꾸지 않는다) 재고를 먼저 고치고 확인합니다.
- 재고 조정에는 Stock adjustments 권한이 필요합니다. 없으면 가진 사람에게 부탁합니다.
- 창고의 **Not enough stock** 과는 다릅니다. 그것은 픽커가 물건을 찾지 못한 것입니다([WMS Admin](04-wms.md#wms-admin)).

<a id="action-unpaid"></a>
## Unpaid at hand-over(건넸는데 덜 받음)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, accounting -->

**여기 뜨는 것**
결제 조건이 「물건을 받기 전이나 받을 때 낸다」인 고객 — 예: C.B.S · C.O.D — 의 인보이스 중 아직 남은 돈이 있는 것입니다. "The customer's term says pay before or on delivery …, but the goods went out with money still owed."(결제 조건은 즉시 결제인데 남은 돈이 있는 채 나갔다)

줄마다 **Invoice** · **Issued**(며칠 전인지도) · **Customer** · **Term** · **Orders** · **Total** · **Paid · credited** · **Still owed** 가 나옵니다. 가장 오래된 것이 위에 옵니다.

**어떻게**
1. 인보이스 번호를 누릅니다. **Sales Invoices** 에서 열립니다.
2. 결제를 받고 적습니다([고객 결제와 선수금](01-sales.md#sales-payments)).

**알아 둘 것**
- "It drops off this list once it is paid."(다 받으면 목록에서 빠진다)
- 이 탭은 늘 모든 브랜치를 보입니다.

<a id="action-pos"></a>
## POS not finished(끝내지 않은 POS)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, sales -->

**여기 뜨는 것**
확정했지만 끝내지 않은 POS 판매입니다. "A confirmed POS sale holds its stock until it is finished."(확정된 POS 판매는 끝날 때까지 재고를 잡고 있다)

- "not finished — from an earlier day"(전날부터 안 끝남) — 위에 옵니다. 탭의 빨간 숫자가 이것을 셉니다.
- "today · parked or at the counter"(오늘 · 잠시 두었거나 계산대에 있음) — 아직 받는 중이거나 잠시 둔 것([판매를 잠시 두고 다시 잡기](05-pos.md#pos-park))

줄마다 **Sale** · **Customer** · **Branch** · **Confirmed**(언제 · 누가) · **Amount** · **Paid** 가 나옵니다.

**어떻게**
"Open it on POS to finish it, reopen it, or cancel it on Sales Orders."(POS 에서 열어 끝내거나 다시 열고, 취소는 Sales Orders 에서)
1. 판매 번호를 누릅니다. **POS** 에서 열립니다.
2. 끝내거나([끝내고 인보이스 인쇄하기](05-pos.md#pos-finish)), 다시 열어 바꿉니다.
3. 고객이 돌아오지 않으면 **Sales Orders** 에서 취소합니다([오더 취소](01-sales.md#sales-cancel)).

<a id="action-counter"></a>
## Counter orders(counter 오더)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**여기 뜨는 것**
최근 30일의 counter 오더입니다. "Counter orders take stock out without going through the warehouse screens — this list is how a manager sees them."(counter 오더는 창고 화면을 거치지 않고 재고를 내보낸다 — 매니저는 이 목록으로 본다)

줄마다 **Order** · **Status** · **Ordered** · **Customer** · **Branch** · **Handed over**(언제 · 누가) 가 나옵니다.

**어떻게**
- 오더 번호를 누르면 **Sales Orders** 에서 열립니다. 건네는 걸음은 [Ship & invoice](01-sales.md#sales-ship-invoice) 에 있습니다.

**알아 둘 것**
- 이 탭에는 빨간 숫자가 없습니다. 고칠 것의 목록이 아니라 훑어보는 목록입니다.
- 30일보다 오래된 오더는 **Sales Orders** 에서 찾습니다.

<a id="action-new-customers"></a>
## New customers to review(확인할 새 고객)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**여기 뜨는 것**
IMS 에서 만들었고 매니저가 아직 확인하지 않은 고객입니다. "Customers made by sales start on the default terms (Wholesale · 0% · C.B.S · CAD)."(sales 가 만든 고객은 기본 조건으로 시작한다)

줄마다 **Customer** · **City** · **Created**(언제 · 누가) · **Terms now**(지금 조건) · **Orders** · **First order** 가 나옵니다. 가장 오래된 것이 위에 옵니다.

**어떻게**
1. **Open** 을 누릅니다. **Customers** 에서 그 고객이 열립니다.
2. master 권한 필요: 필요하면 조건을 바꾸고 **Reviewed** › **Mark reviewed** 를 누릅니다([고객 찾기 · 더하기](01-sales.md#sales-customers)).

**알아 둘 것**
- "Changing a money term counts as reviewed too."(돈 조건을 바꾸면 그것도 확인으로 친다)
- 확인하면 목록에서 빠집니다.
- **Branch** 는 고객의 기본 창고를 따릅니다.

<!-- SCREENSHOT: action-new-customers-1 · Terms now 와 Open 이 있는 New customers to review -->

<!-- rulings: 152, 165, 240, 709, 713, 714, 715, 719, 720, 723, 725, 732, 735 -->
