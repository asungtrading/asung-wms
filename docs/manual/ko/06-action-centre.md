# 6. Action Centre(할 일 모음)

<!-- sections 1-7 written (manual-6 · docs-1106 added Pickups not scheduled) · one section per tab, in the order of the tabs -->
<!-- out of this chapter: the work itself stays in its own chapter — sales orders and customers -> chapter 1 · stock adjustments -> chapter 3 · POS -> chapter 5 -->

<a id="action-start"></a>
## Action Centre 란
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, sales -->

**무엇인가**
**Action Centre** 는 매니저가 볼 것을 모읍니다: 장부에 재고 없이 나간 판매, 덜 받은 즉시 결제 인보이스, 끝내지 않은 POS 판매, counter 오더, 새 고객, 잡히지 않은 Freightcom 픽업. 보여 주기만 하고, 일은 원래 화면에서 합니다.

**누가**
판매 오더를 다루는 사람은 모두 엽니다. 매니저 이상: **Sold without stock** 의 **Mark checked…**

**언제**
매니저는 하루에 한 번 엽니다.

**어떻게**
1. IMS 모드의 메뉴에서 **Action Centre** 를 누릅니다(**Inventory ▾** 와 **Settings ▾** 사이).
2. 탭을 누릅니다. 탭의 빨간 숫자가 기다리는 건수입니다.
   메뉴의 **Action Centre** 에도 빨간 숫자가 붙습니다: 모든 브랜치에서 기다리는 것의 합입니다. 기다리는 것이 없으면 숨고, 2 분마다 새로 셉니다.
3. **All branches** 에서 브랜치 하나를 고릅니다.
4. 오더 · 인보이스 · 고객을 누르면 원래 화면에서 열립니다.

**탭**
- [Sold without stock](#action-sold-short)(재고 없이 나감)
- [Unpaid at hand-over](#action-unpaid)(건넸는데 덜 받음)
- [POS not finished](#action-pos)(끝내지 않은 POS)
- [Counter orders](#action-counter)(counter 오더)
- [New customers to review](#action-new-customers)(확인할 새 고객)
- [Pickups not scheduled](#action-pickups)(잡히지 않은 픽업)

<!-- SCREENSHOT: action-start-1 · 탭 다섯과 배지가 있는 Action Centre -->

<a id="action-sold-short"></a>
## Sold without stock(재고 없이 나감)
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 ; 2026-11-11 · ml v1.6 (Count & check) -->
<!-- who: manager -->

**여기 뜨는 것**
그 브랜치의 장부보다 많이 나간 판매입니다. "These sold more than the book showed in that branch — the goods were there, the count was not."(장부보다 많이 나갔다 — 물건은 있었고 숫자가 틀렸다)

- **Not checked yet**(아직 확인 안 함) — 오래된 것까지 전부. 탭의 빨간 숫자가 이것을 셉니다.
- **Checked**(확인함) — 최근 30일. 누가 · 언제 · 메모가 함께 나옵니다.

줄마다 **Sold on** · **Order** · **Customer** · **SKU** · **Branch** · **Qty short**(모자란 수량) · **Cost** 가 나옵니다(IMS 에 원가가 없으면 **cost unknown**).

확인 안 된 줄마다 단추가 둘 있습니다(매니저 이상):
- **Count & check…**(세고 확인) — "count the shelf, type what you found, and IMS fixes the stock and checks every open line of that SKU in one go"(선반을 세어 적으면 IMS 가 재고를 고치고 그 SKU 의 열린 줄을 한 번에 확인한다). 그 브랜치의 Stock adjustments 권한이 필요합니다.
- **Mark checked…**(확인함) — "the books are already right — it only records that you looked and does not change stock."(장부가 이미 맞다 — 봤다는 기록만 남기고 재고는 안 바꾼다)

**어떻게 — Count & check**
1. 판매를 보려면 오더 번호를 누릅니다. **Sales Orders** 에서 그 오더가 열립니다 — POS 판매도 같습니다.
2. **Count & check…** 를 누릅니다. 창에 그 브랜치의 그 SKU bin 마다 **Book**(장부) · **Picked, not shipped**(픽했지만 안 나감) · **Shelf should be**(선반에 있어야 할 수)가 나옵니다.
3. 선반을 세어 **You counted** 에 적습니다. "must count — below zero"(0 아래 — 꼭 센다) 표시가 있는 bin 은 꼭 적어야 합니다. 다른 선반에서 찾았으면 bin 을 적고 **+ add bin** 을 누릅니다. **Note** 는 적지 않아도 됩니다.
4. **Preview** 를 누르고 바뀔 것을 읽습니다. 센 수를 바꾸면 **Preview** 를 다시 누릅니다.
5. **Count & check** 를 누릅니다. IMS 가 재고 조정 하나를 만들고 확정한 뒤 열린 줄을 확인합니다. "It cannot be undone — a mistake is fixed with a new adjustment."(되돌릴 수 없다 — 실수는 새 조정으로) 센 수가 장부와 같으면 재고는 안 바뀌고 확인만 됩니다.

**어떻게 — Mark checked**
1. 선반을 셉니다. 장부가 맞으면 **Mark checked…** 를 누르고 찾은 것을 적습니다("counted, fixed, reason" — 셌다 · 고쳤다 · 까닭).

**알아 둘 것**
- **Count & check** 로 재고가 바뀌었으면 확인된 줄에 조정 번호(ADJ-…)가 나옵니다.
- 그 브랜치의 Stock adjustments 권한이 없으면 창에 "You can see this but not change stock here — that needs the Stock adjustments key for …"(볼 수는 있지만 재고는 못 바꾼다) 가 나옵니다. 장부가 맞으면 **Mark checked** 를 쓰고, 아니면 권한 있는 사람에게 부탁합니다.
- bin **UNASSIGNED** "(no shelf yet)"(아직 선반 없음)는 그 브랜치에 bin 이 없는 제품을 POS · counter 로 팔 때 빠지는 자리입니다. 여기서 세어 실제 bin 으로 옮깁니다.
- bin 없는 옛 줄은 보이기만 합니다: "is fixed separately — not by this count"(따로 고친다 — 이 셈으로는 아님)
- "Someone else just checked this line."(다른 사람이 방금 확인했다) — 창을 닫고 목록을 다시 엽니다.
- 창고의 **Not enough stock** 과는 다릅니다. 그것은 픽커가 물건을 찾지 못한 것입니다([WMS Admin](04-wms.md#wms-admin)).

<a id="action-unpaid"></a>
## Unpaid at hand-over(건넸는데 덜 받음)
<!-- screen: manager-list.html · BUILD 2026-11-03 · ml v1.4 -->
<!-- who: manager, accounting -->

**여기 뜨는 것**
결제 조건이 「물건을 받기 전이나 받을 때 낸다」인 고객 — 예: C.B.S · C.O.D — 의 인보이스 중 아직 남은 돈이 있는 것입니다. "The customer's term says pay before or on delivery …, but the goods went out with money still owed."(결제 조건은 즉시 결제인데 남은 돈이 있는 채 나갔다)

줄마다 **Invoice** · **Issued**(며칠 전인지도) · **Customer** · **Term** · **Orders** · **Total** · **Paid · credited** · **Still owed** 가 나옵니다. 가장 오래된 것이 위에 옵니다.

**어떻게**
1. 인보이스 번호를 누릅니다. **Sales Invoices** 에서 열립니다.
2. 결제를 받고 적습니다([고객 결제와 선수금](01-sales.md#sales-payments)).

**알아 둘 것**
- "It drops off this list once it is paid."(다 받으면 목록에서 빠진다)
- 목록과 숫자는 **Branch** 고르기를 따릅니다 — 물건을 내준 브랜치입니다. **All branches** 이면 **Branch** 칸이 나옵니다. IMS 에 오더가 없는 인보이스(이월)는 고객의 기본 브랜치이고 **customer's branch** 라고 적힙니다.

<a id="action-pos"></a>
## POS not finished(끝내지 않은 POS)
<!-- screen: manager-list.html · BUILD 2026-11-11 · ml v1.6 -->
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
<!-- screen: manager-list.html · BUILD 2026-11-11 · ml v1.6 -->
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
<!-- screen: manager-list.html · BUILD 2026-11-11 · ml v1.6 -->
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


<a id="action-pickups"></a>
## Pickups not scheduled(잡히지 않은 픽업)
<!-- screen: manager-list.html · BUILD 2026-11-11 · ml v1.6 -->
<!-- who: manager, sales -->

**여기 뜨는 것**
IMS 에서 예약한 Freightcom 발송 가운데 운송사 픽업이 확인되지 않은 것입니다. 픽업은 오더가 출고된 뒤에 거절될 수도 있고, 그때는 오더 화면에 더는 보이지 않습니다 — 그것을 보는 곳이 이 탭입니다.

줄마다 **Pickup**(날짜 · 준비 시각) · **Orders** · **Customer** · **Carrier** · **What Freightcom says**(Freightcom 이 말하는 것) · **Booked** · **Last checked**(마지막 확인) · **Tracking** 이 나옵니다.

**어떻게**
1. **What Freightcom says** 를 읽습니다 — 예: 운송사가 픽업을 거절했다.
2. Freightcom 사이트에서 픽업을 잡습니다.
3. **Check pickup** 을 누릅니다. IMS 가 Freightcom 에서 픽업을 다시 읽어(요금 없음) 결과를 보여 줍니다.

**알아 둘 것**
- "IMS also checks again every few minutes, and a booking drops off this list once the pickup is confirmed (or 2 days after the pickup date)."(IMS 도 몇 분마다 다시 확인하고, 픽업이 확인되면(또는 픽업 날 2 일 뒤) 목록에서 빠진다)
- "Every Freightcom pickup is scheduled." 는 할 일이 없다는 뜻입니다.
- 줄을 「확인함」 으로 표시하는 단추는 없습니다 — 픽업이 확인되면 빠집니다.
- 토 · 일에는 픽업이 없습니다. 금요일 늦게 예약하면 월요일에 가져갑니다.
- 창고에 **Contact** 와 **Phone**(10 자리)이 있어야 예약됩니다(**Settings** › **Warehouse** › **Edit**). 없으면 IMS 가 예약을 막습니다 — 운송사가 연락처 없는 픽업을 거절하기 때문입니다.

<!-- SCREENSHOT: action-pickups-1 · What Freightcom says 와 Check pickup 이 있는 Pickups not scheduled -->

<!-- rulings: 1040, 1041, 1048, 1049, 1050, 1051, 152, 165, 240, 709, 713, 714, 715, 719, 720, 723, 725, 732, 735, 1172, 1173, 1176 -->
