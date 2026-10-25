# 4. WMS (창고)

<!-- sections 1-12 written (manual-4a · 4b) · sections follow the order of the work, not the order of the screens -->

<a id="wms-start"></a>
## WMS 에 들어가기
<!-- screen: ims-auth.js · BUILD nav v12 -->
<!-- who: warehouse, manager -->

**무엇인가**
WMS 는 IMS 의 창고 모드입니다. 화면이 태블릿과 바코드 스캐너에 맞춰져 있습니다: 픽 · 검수 · 포장 · 리시빙 · 재고 옮기기

**어떻게**
1. 평소대로 로그인합니다([로그인](00-getting-started.md#start-sign-in)).
2. IMS 나 POS 도 쓰는 사람이면 Asung 로고 옆의 **WMS** 를 누릅니다.
3. 화면은 탭 한 줄로 있습니다: **Split & Waves** · **Picking** · **Packing** · **Fulfillment** · **Receiving** · **Bin Moves** · **Stock Lookup** · **WMS Admin**. 권한이 있는 것만 보입니다.
4. 첫 화면은 매니저면 **Split & Waves**, 아니면 **Picking** 입니다.
5. **☰ Menu** 에도 같은 화면이 있습니다. 맨 끝의 **Manual** 은 이 매뉴얼을 새 탭에 엽니다.

**스캔하기와 누르기**
- 「스캔한다」는 스캐너를 바코드에 대는 것입니다. 화면이 스캔 칸을 늘 준비해 두므로 먼저 누를 필요가 없습니다.
- 「누른다」는 화면의 단추를 손가락으로 누르는 것입니다.
- 종이 픽리스트에도 바코드가 있습니다. 스캔하면 그 묶음이 화면에 열립니다.

**알아 둘 것**
- **🗺 Map** 은 창고 지도를 새 탭에 엽니다. 지도의 재고는 하루에 한 번 바뀝니다.
- WMS 화면에는 **Change Password** 단추가 없습니다. 비밀번호는 IMS 모드 화면에서 바꿉니다.
- **Sign Out** 은 오른쪽 위에 있습니다. 여럿이 쓰는 태블릿에서는 일이 끝나면 로그아웃합니다.

<a id="wms-waves"></a>
## 오더를 묶음과 웨이브로 나누기
<!-- screen: wms-manager.html · BUILD 2026-09-29 · wm v1.2 ; wms-picklist.js -->
<!-- who: manager -->

**무엇인가**
오피스가 **Release to WMS** 를 누르면 오더가 **Split & Waves** 의 **Released to WMS** 아래에 나타납니다. 매니저가 그것을 픽 일로 바꿉니다: 큰 오더는 묶음으로 나누고, 작은 오더는 웨이브로 모읍니다.

**어떻게 — 매니저 이상: 큰 오더 나누기**
1. **Split & Waves** 를 열고 **Split** 을 그대로 둡니다.
2. 왼쪽에서 오더를 고릅니다.
3. **max lines per batch**(묶음당 최대 라인)와 **max units**(최대 수량)를 정합니다. "Both values are ceilings applied together — a batch is cut when adding the next line would exceed either limit."(둘 다 상한 · 다음 라인을 더하면 하나라도 넘을 때 묶음을 자른다) max units 보다 큰 라인 하나는 그 자체로 묶음이 됩니다.
4. **Preview** 로 묶음을 보고, **Create batches** 를 누르고 확인합니다.
5. 묶음마다 픽리스트가 인쇄됩니다 — 예: `SO-99001-1` · `SO-99001-2`. 보드에 붙입니다.

**어떻게 — 매니저 이상: 작은 오더를 웨이브로 모으기**
1. **Group** 을 누릅니다.
2. "Tap orders to add them to the wave — up to 10 totes, one warehouse."(오더를 눌러 웨이브에 넣는다 · 토트 10 개까지 · 창고 하나) 오더를 둘 이상 고릅니다.
3. "Selection order = tote number" — 처음 누른 오더가 토트 1 에 들어갑니다.
4. **Create wave** 를 누르고 확인합니다. 웨이브 전체에 픽리스트 한 장이 인쇄됩니다. 예: `W-1025-1`

**알아 둘 것**
- 창고(**All** · TOR · EDM)나 가격 등급(**All tiers**)으로 필터합니다.
- 창고 간 트랜스퍼는 **Transfer** 꼬리표로 나오고 같은 방법으로 나눕니다.
- 검수와 포장은 웨이브의 토트 하나하나를 각각의 오더로 확인합니다.

<!-- SCREENSHOT: wms-waves-1 · Split: max lines · max units 를 적고 묶음 미리 보기 -->

<a id="wms-picking"></a>
## 오더 픽하기
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b -->
<!-- who: warehouse -->

**무엇인가**
픽은 묶음 하나(오더의 한 부분)나 웨이브 하나(한 동선에 담은 작은 오더 여럿)의 물건을 선반에서 꺼내는 일입니다. 묶음마다 바코드가 찍힌 종이 픽리스트가 있습니다. 예: `SO-99001-1`. 웨이브의 바코드는 `W-1025-1` 같은 꼴입니다.

**언제**
매니저가 **Split & Waves** 에서 묶음을 만들고 픽리스트가 보드에 붙었을 때.

**어떻게**
1. **Picking** 을 엽니다. **My In Progress**(내가 하는 중) · **Waiting Batches**(기다리는 묶음) · **Waiting Waves — one route, sort into totes**(기다리는 웨이브)가 보입니다.
2. 보드에서 픽리스트를 떼어 바코드를 스캔합니다(또는 기다리는 묶음의 **Start** 를 누릅니다). 이제 그 묶음은 내 것입니다.
3. 화면은 라인을 하나씩(**Single**) 또는 전부(**List**) 보여 줍니다. 라인마다 bin · 제품 · 사진이 나옵니다.
4. bin 으로 가서 물건을 하나씩 스캔합니다. "single scan = barcode-unit quantity" — 케이스 바코드를 스캔하면 케이스 하나가 통째로 셉니다.
5. 스캔이 안 되는 물건은 **Enter quantity** 를 누르고 수량을 적습니다.
6. **Next →** 로 다음 라인에 갑니다. **← List** 는 묶음 목록으로 돌아갑니다.
7. 모든 라인이 차면 **Pick complete** 를 누릅니다.

**보류와 이어받기**
- **Hold (later)**: "Your progress is saved and the batch returns to the waiting list. You or another worker can resume it later."(한 것은 저장되고 묶음은 기다리는 목록으로 돌아간다 · 나나 다른 사람이 이어서 한다)
- **Resume** 은 내가 보류한 묶음을 다시 엽니다.
- 자리를 비운 사람의 묶음에는 **Take over**(이어받기)가 보입니다. 그 픽리스트를 스캔해도 이어받습니다. 그 사람이 픽한 것은 남습니다.
- 다른 사람이 내 묶음을 가져가면 화면에 "⚠ Ownership changed" 가 나옵니다. **Reload** 를 누릅니다. 그 뒤에 적은 수량은 저장되지 않았습니다.

**물건에 문제가 있을 때**
- **⚑ Wrong location** — 목록에 적힌 자리에 없다. IMS 가 어디서 찾았는지 묻습니다.
- **⚑ Barcode changed** — 물건의 바코드가 다르다.
- **⚑ Image differs** — 사진이 제품과 다르다.
모두 [WMS Admin](#wms-admin) 으로 갑니다. 픽은 계속합니다.

**알아 둘 것**
- **🖨 Print** 는 픽리스트를 다시 찍습니다.
- 창고 간 트랜스퍼도 같은 방법으로 픽합니다([창고 간 트랜스퍼](03-inventory.md#stock-transfers)). 오더 번호 자리에 트랜스퍼 번호가, 고객 이름 자리에 도착 창고가 나옵니다.
- "Part of a combo" 표시가 있는 라인도 다른 물건처럼 픽합니다. 콤보는 나중에 맞춥니다.

**조심할 것**
- 픽리스트를 보드에 다시 붙이면 화면의 묶음도 닫습니다(**Hold (later)**). 안 그러면 두 사람이 같은 오더를 픽하게 됩니다.

<!-- SCREENSHOT: wms-picking-1 · Picking Single 화면: bin · 제품 사진 · 스캔 칸 · Hold (later) · Pick complete -->

<a id="wms-pick-short"></a>
## 물건이 모자랄 때
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; wms-confirm-modal.js -->
<!-- who: warehouse -->

**무엇인가**
선반에 모자랄 때가 있습니다. 까닭에 따라 할 일이 다릅니다.

| 찾은 것 | 할 일 | 뜻 |
|---|---|---|
| 정해진 bin 은 비었지만 다른 데 있다 | **⇄ Different bin** 을 누르고 **This bin was empty (tell the manager)** 를 체크한 뒤 다른 bin 에서 픽 | 매니저에게 알려진다 · 수량은 다 픽한다 |
| 정말 없다 | **⚠ Not enough stock** 을 누른다 | 재고 문제 — 내 실수가 아니다 · 매니저가 선반을 확인한다 |
| 그래도 모자란 채 끝내야 한다 | **Complete as incomplete** 를 누른다 | 오더는 모자란 채 진행된다 · 오피스가 픽한 만큼 보내고 나머지는 백오더가 된다 |

**어떻게 — 재고가 정말 없을 때**
1. 찾을 수 있는 만큼 픽합니다.
2. 그 라인에서 **⚠ Not enough stock** 을 누릅니다.
3. "Declare NOT ENOUGH STOCK on the shelf? Needed 30, you could only find 18. This is NOT counted as a picker mistake …"(선반 재고 부족을 선언할까? · 픽커 실수로 세지 않는다)에 OK 를 누릅니다.
4. 단추가 **✓ Not enough stock** 으로 바뀝니다. 다시 누르면 선언을 취소합니다.

**어떻게 — 다른 bin 에서 픽하기**
1. 그 라인에서 **⇄ Different bin** 을 누릅니다. **Pick from a different bin** 창에 **Planned**(정해진) bin 과 재고가 있는 다른 bin 이 나옵니다.
2. 정해진 bin 이 비었으면 **This bin was empty (tell the manager)** 를 체크합니다.
3. bin 을 고르거나, "Other bin — type its name" 에 이름을 적고 **Select** 를 누릅니다.
4. **Pick from …** 을 누르고 평소처럼 스캔합니다.

**어떻게 — 모자란 채 끝내기**
1. **Complete as incomplete** 를 누릅니다.
2. 선언하지 않은 부족 라인이 있으면 창이 모자란 수량을 직접 적게 합니다: "Type the short quantity to enable End". 그 뒤 **End** 단추를 누릅니다.

**예**
SO-99001-1 에 제품 X 가 30 필요합니다. 선반에는 18 이 있습니다. 18 을 픽하고 **⚠ Not enough stock** 을 누른 뒤 **Complete as incomplete** 를 누릅니다. **Ship & invoice** 때 12 는 백오더 오더가 되고, 고객은 받았던 가격을 그대로 유지합니다.

**조심할 것**
- 선언하지 않은 부족은 내 실수로 셉니다. 선반에 정말 모자라면 꼭 **⚠ Not enough stock** 을 누릅니다.
- 라인이 모자라면 **Pick complete** 는 되지 않습니다 — "There are short lines. Press 'Complete as incomplete'."

<a id="wms-packing"></a>
## 뽑은 오더 검수(Packing)
<!-- screen: wms-packer.html · BUILD 2026-10-20 · pa v1.6b ; wms-confirm-modal.js -->
<!-- who: warehouse -->

**무엇인가**
**Packing** 은 픽한 묶음의 물건을 처음부터 다시 스캔해 확인합니다. 기준은 고객이 주문한 수량입니다. 상자 · 팔레트에 담는 것은 그다음 **Fulfillment** 에서 합니다.

**어떻게**
1. **Packing** 을 엽니다. **My In Progress** 와 **Pack Queue**(픽이 끝난 묶음)가 보입니다.
2. 픽리스트를 스캔합니다(또는 묶음을 고릅니다). 이제 그 묶음은 내 것입니다.
3. **Verify: scan a barcode…** 에 물건을 하나씩 스캔합니다. 라인마다 주문 수량을 향해 찹니다. 스캔이 안 되는 물건은 **Enter quantity** 를 누르고 적습니다.
4. 픽이 모자랐으면 화면에 "⚠ Pick incomplete — Find and fill the quantities below from other locations"(다른 자리에서 찾아 채워라)가 나옵니다. 다른 bin 에서 모자란 물건을 가져와 스캔합니다.
5. **Complete pack** 을 누릅니다.
6. 오더의 묶음이 모두 검수되면 IMS 가 그 오더가 "is ready to be finalized" 라고 알립니다 — **Fulfillment** 로 넘어갑니다.

**너무 많이 스캔됐을 때**
라인이 넘치면 "⚠ Over-scan — count the items"(물건을 세어라)가 나옵니다. 실제로 있는 것을 세고 그 라인에서 고릅니다:
- **Picker brought extra — N items are here** — 정말 많다. 남는 것을 돌려놓습니다. 픽커 실수로 기록됩니다.
- **I scanned twice — only N are here** — 수량은 맞고 한 번 더 스캔했다. 누구의 실수로도 세지 않습니다.
- 확실하지 않으면 **← Go back and recount**

**알아 둘 것**
- **Search SKU / product…** 로 라인을 빨리 찾습니다. **Clear** 는 검색을 비웁니다.
- **Hold (later)** · **Resume** · 이어받기는 [오더 픽하기](#wms-picking)와 같습니다.
- 선반을 확인한 뒤라면 여기서도 **⚠ Not enough stock** 을 쓸 수 있습니다.

**조심할 것**
- **I scanned twice** 는 정직하게 고릅니다. 픽커가 하지 않은 실수를 덮어쓰지 않게 해 주고, 나에게도 불리하지 않습니다.
- **Complete pack** 을 누를 때 아무도 선언하지 않은 부족 라인이 있으면, 모자란 수량을 직접 적어야 끝낼 수 있습니다.

<!-- SCREENSHOT: wms-packing-1 · Packing 의 "Over-scan — count the items" 고르기 창 -->

<a id="wms-fulfillment"></a>
## 상자 · 팔레트에 담기(Fulfillment)
<!-- screen: wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 ; wms-packing.js -->
<!-- who: warehouse -->

**무엇인가**
**Fulfillment** 는 검수된 오더를 팔레트와 상자에 담고, 패킹리스트를 찍고, **✓ Finalize order(s)** 로 창고 일을 끝냅니다.

**언제**
오더의 모든 묶음이 **Packing** 에서 검수되어야 여기 나타납니다 — "it appears here when ALL are packed"

**어떻게**
1. **Select orders ▾** 를 누르고 "Orders to ship together"(함께 보낼 오더)를 체크한 뒤 **Start working selected orders** 를 누릅니다. 픽리스트를 스캔해도 됩니다.
2. **+ Pallet** 이나 **+ Box** 를 누릅니다. 짐마다 **L** · **W** · **H** · **Weight** 를 적습니다. **+ Nest box** 는 상자를 팔레트 위에 얹습니다.
3. 제품을 짐에 넣습니다: "Drag, tap, or scan products into a pallet or box."(끌거나 누르거나 스캔한다) 먼저 팔레트나 상자를 눌러 넣을 곳으로 정합니다.
4. 스캔은 두 가지입니다: **Scan qty**(한 번에 하나) 또는 **Move all**(한 번 스캔으로 아직 안 담은 그 제품을 전부). **↩ Undo last scan** 은 마지막 스캔을 되돌립니다.
5. **Unassigned products**(안 담은 제품)가 다 비면 인쇄합니다: **🖨 Box list** · **🖨 Pallet list** · 매장별 **🖨 List** · **🖨 All stores (at once)**
6. **✓ Finalize order(s)** 를 누르고 확인합니다. "Finalized orders leave the fulfillment board." 이제 오피스가 **Ship & invoice** 를 합니다([Ship & invoice](01-sales.md#sales-ship-invoice)).

**트랜스퍼**([창고 간 트랜스퍼](03-inventory.md#stock-transfers))
- 판매 오더와 트랜스퍼는 함께 작업할 수 없습니다: "A sale and a transfer cannot be on the same workbench — finish or clear one first"
- Finalize 한 트랜스퍼는 바로 떠납니다: "… left for … — in transit"
- 모자란 트랜스퍼는 보낸 만큼으로 닫힙니다 — 백오더를 만들지 않습니다.

**알아 둘 것**
- 짐의 **Delete** 는 그 제품을 안 담은 쪽으로 돌려놓습니다.
- "A box can only go on a pallet."(상자는 팔레트 위에만)

<!-- SCREENSHOT: wms-fulfillment-1 · Fulfillment 보드: 팔레트 · 얹은 상자 · Unassigned products -->

<a id="wms-receiving"></a>
## PO · 트랜스퍼 받기
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse, manager -->

**무엇인가**
리시빙은 들어온 물건을 PO 나 트랜스퍼와 맞춰 셉니다. 그다음 제자리에 넣습니다([풋어웨이](#wms-putaway)).

**언제**
오피스가 공급처 인보이스를 확정한 PO 만 받을 수 있습니다([공급처 인보이스 넣기](02-purchasing.md#purch-invoice)): "No POs with a confirmed invoice to receive — the office confirms the supplier invoice first."

**어떻게**
1. **Receiving** 을 엽니다. PO 바코드를 스캔하거나, **↻ POs** 를 눌러 고릅니다(예: Supplier B 의 PO-99001). **Start**(또는 **Resume**)를 누릅니다.
2. 물건을 하나씩 스캔합니다. "box scan = ×factor units" — 상자 바코드는 상자 하나를 통째로 셉니다.
3. 스캔이 안 되면 **Enter quantity** 를 누르고 적습니다.
4. 걷는 순서에 맞게 **PO order** · **SKU** · **Product** · **Zone / Last bin** 으로 정렬합니다.
5. 다 세면 **Putaway →** 를 누릅니다.

**일어날 수 있는 일**

| 경우 | IMS 의 글 | 결과 |
|---|---|---|
| 인보이스보다 많다 | "exceeds expected quantity … More than the invoice — the extra is put away and the office decides it (off-invoice)" | 넣어 둔다 · 오피스가 정한다 |
| PO 에 없는 물건 | "not on this PO. Add as OFF-INVOICE …? Put it away as usual — the office accepts or rejects it later." | 같다 |
| 인보이스보다 적다 | "Anything not counted is kept as short — the order stays open so the rest can be received on it later" | 나머지를 받도록 PO 가 열린 채 남는다 |
| 두 사람이 같은 라인에 적었다 | **Quantity conflict** — **Keep theirs** · **Use mine** · **Recount** | 하나를 고른다 |
| 트랜스퍼 | "Complete = arrival … anything not received stays in transit for the office to settle." | 나머지는 오피스가 **Transfers** 에서 정리한다([창고 간 트랜스퍼](03-inventory.md#stock-transfers)) |

**알아 둘 것**
- **Hold (later)** 와 **Resume** 은 [오더 픽하기](#wms-picking)와 같습니다.
- **⚑** 신고(바코드 · 사진)도 픽과 같습니다.
- 오피스가 물건을 거절하면 라인에 "Rejected — take it off the shelf"(선반에서 빼라)가 나옵니다. 빼고 **Removed** 를 누릅니다.
- 오피스는 같은 입고를 **Purchase Receipts** 에서 봅니다([오피스 입고](02-purchasing.md#purch-receipts)).

**조심할 것**
- 끝내기 전에 들어온 것을 다 셉니다. "Unknown barcode — ask the office to register the product" 는 제품이 아직 등록되지 않았다는 뜻입니다.

<!-- SCREENSHOT: wms-receiving-1 · 리시빙 라인과 "exceeds expected quantity" 확인 창 -->

<a id="wms-putaway"></a>
## 풋어웨이(제자리에 넣기)
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 ; wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: warehouse, manager -->

**무엇인가**
풋어웨이는 받은 물건을 bin 에 넣는 일입니다. "The suggested bin is where this product was last kept."(제안 bin 은 그 제품을 마지막에 둔 곳)

**어떻게**
1. **Putaway →** 뒤에 "Walk the route below and place items at each bin."(아래 경로를 따라 bin 마다 넣는다)
2. 제품마다 **Last bin** 이나 **No last bin** 이 보입니다. 다른 곳에 두려면 **Assign bin**(또는 **Change**)을 누릅니다: "Scan the bin barcode — or pick from the list below"
3. 물건을 bin 에 넣고 **Placed** 를 누릅니다.
4. 다 넣으면 **Complete** 를 누르고 확인합니다. 창고 쪽 입고가 끝납니다.

**Confirm receipt — 입고 확정 권한이 필요**
입고가 확정되어야 재고로 셉니다. "This writes the stock ledger and cannot be undone here."(재고 장부에 쓰고 여기서는 되돌릴 수 없다) 세 곳에서 할 수 있습니다:
- 이 화면의 **Confirm receipt** — `wms_receiving_confirm` 권한이 켜진 매니저
- **WMS Admin** › **Receiving** 의 **Confirm into stock** — 같은 권한
- 오피스의 **Purchase Receipts**([오피스 입고](02-purchasing.md#purch-receipts))
창이 PO 가 "stays open"(더 받을 것이 남음)인지 "closes on confirm"(확정하면 닫힘)인지 알려 줍니다.

**조심할 것**
- IMS 가 모르는 bin 이름: "… is not a bin at … — ask the office to add it"(오피스에 bin 을 더해 달라고 한다)
- **← Receiving** 은 세기로 돌아갑니다. **Complete** 뒤에는 매니저만 다시 열 수 있습니다("ask a manager to reopen it").

<!-- SCREENSHOT: wms-putaway-1 · 풋어웨이 경로: Last bin 과 Placed -->

<a id="wms-bin-moves"></a>
## bin 사이 재고 옮기기
<!-- screen: wms-mover.html · BUILD 2026-10-05 · mv v2.3 -->
<!-- who: warehouse -->

**무엇인가**
**Bin Moves** 는 같은 창고 안에서 재고를 bin 에서 bin 으로 옮깁니다.

**어떻게**
1. "Scan the FROM bin"(꺼낼 bin 스캔 · 또는 **List**). **Show what is here** 가 그 bin 의 물건을 보여 줍니다.
2. "Scan the product" 하고 수량을 적은 뒤(**All** 은 전부) **Add to list** — 또는 **Add all in this bin**
3. "Scan the bin you put it in"(넣을 bin 스캔)
4. **Move** 를 누릅니다. IMS 가 이동 번호와 「어디서 → 어디로」를 보여 줍니다. **Start over** 는 목록을 비웁니다.

**알아 둘 것**
- **Recent moves in this warehouse** 에 최근 이동이 보입니다.
- "Picked, not shipped"(픽했지만 안 나감) · "Waiting for pickers"(픽커 대기) 몫은 옮길 수 없습니다.

**조심할 것**
- 옮기려면 사람마다 켜는 Bin moves 권한이 필요합니다: "You can look at bin moves but not make them — moving stock needs the Bin moves key. Ask a manager to switch it on for you."(볼 수는 있지만 옮길 수는 없다 · 매니저에게 켜 달라고 한다)

<a id="wms-stock-lookup"></a>
## 재고 찾아보기
<!-- screen: wms-stock.html · BUILD 2026-10-20 · ws v1a -->
<!-- who: warehouse -->

**무엇인가**
**Stock Lookup** 은 제품이 어디에 얼마나 있는지 보여 줍니다. "Scan or type — both branches are shown."(스캔하거나 적는다 · 두 브랜치가 다 보인다) WMS 에 들어올 수 있는 사람은 누구나 씁니다.

**어떻게**
1. 바코드를 스캔하거나 SKU · 이름을 적습니다.
2. 브랜치마다 bin, **Available**(가용) · **Allocated to sales orders**(판매 오더에 확보) · **Held for transfers out**(나갈 트랜스퍼에 묶임)이 보입니다. 누르면 어느 오더 · 트랜스퍼가 잡고 있는지 나옵니다.
3. **Recent movements** 를 누르면 들어오고 나간 것이 보입니다.

**알아 둘 것**
- **Value**(금액) 줄은 `cost` 권한이 있는 사람에게만 보입니다.
- "Opening stock from the starting count is not listed as a movement here."(처음 센 기초 재고는 움직임으로 나오지 않는다)
- 오피스는 같은 숫자를 [재고 찾기](03-inventory.md#stock-availability)에서 봅니다.

<a id="wms-admin"></a>
## WMS Admin
<!-- screen: wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: manager -->

**무엇인가**
**WMS Admin** 은 창고 매니저 화면입니다. 탭이 아홉입니다: **Status** · **Health** · **Discrepancy** · **Receiving** · **Reports** · **Rollback** · **Finalized** · **Stats** · **Trace**. 매니저 이상이 엽니다.

**Rollback — 오더를 한 단계 되돌리기**
"There is no one-click void — undo one stage at a time and check the goods on the shelf at each step."(한 번에 지우는 길은 없다 · 한 단계씩 되돌리며 단계마다 선반의 물건을 확인한다)
1. **Rollback** 을 열고 오더를 찾습니다. **Current stage** 가 지금 단계입니다.
2. 그 단계의 단추를 누릅니다: **↩ Undo Finalize** · **↩ Undo Fulfillment** · **↩ Undo Pack** · **↩ Reset Pick** · **↩ Undo Split**. 웨이브는 **Undo Wave**
3. 창마다 무엇이 지워지는지 적혀 있습니다 — 예: "Undo split for … Deletes ALL batches for this order … The order returns to Released to WMS — the office can recall it from there" OK 를 누릅니다.
4. 오더가 **Released to WMS** 가 될 때까지 되풀이합니다. 그다음 오피스가 **Recall from WMS** 를 누릅니다([오더 되돌리기](01-sales.md#sales-undo)).
- "On a pallet — Undo Fulfillment first."(팔레트에 있다 · 먼저 Undo Fulfillment) · "Finalized — undo finalize first."
- 일부 창고만 맡은 사람은 그 창고의 오더만 보고 되돌립니다.

**Reports — 작업자가 알린 문제**
"wrong location · barcode changed · image differs · not enough stock (from picking/packing)"
1. **Reports** 를 열고 하나하나 선반에서 확인합니다.
2. 재고 부족이면 **Adjust stock** 이 그 제품의 재고 조정을 엽니다(재고 조정 권한이 있는 사람 · [재고 조정](03-inventory.md#stock-adjustments)).
3. 처리했으면 **Mark resolved** 를 누릅니다.

**Receiving — 오피스 확정을 기다리는 입고**
- **Completed — awaiting office confirmation**: **Review** · **Reopen**("Complete is undone and the receipt can be changed again in the receiving screen") · **Confirm into stock**([풋어웨이](#wms-putaway))
- **Off-PO / off-invoice items waiting for a decision**(정할 것을 기다리는 PO 밖 · 인보이스 밖 물건) · **Awaiting putaway**("stock the pickers cannot find" · 픽커가 찾을 수 없는 재고)

**다른 탭**
- **Status** — 진행 중인 오더와 **Live now**: 누가 어떤 묶음을 쥐고 있나. **Release** 는 자리를 비운 사람의 묶음을 한 것은 남긴 채 기다리는 목록으로 돌려놓습니다.
- **Discrepancy** — 작업자별 실수(short pick · over-pick …). **✓ Resolved** 로 닫습니다.
- **Finalized** — Finalize 된 오더의 패킹리스트를 다시 냅니다: **🖨 Print** · **⬇ PDF** · **⬇ CSV**
- **Health** — 늘 맞아야 하는 검사. "a red card means the rule broke and needs review" — IMS 관리자에게 알립니다.
- **Stats** — **Today** · **This week** · **This month** · **All** 의 묶음 · 시간 · 실수
- **Trace** — 누가 언제 어디서 그 오더를 다뤘나

<!-- SCREENSHOT: wms-admin-1 · Rollback: Current stage 와 Undo 단추 -->

<a id="wms-statuses"></a>
## 상태의 뜻(창고)
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->

**판매 오더**

| 창고 화면 | 판매 화면 | 뜻 |
|---|---|---|
| Released to WMS | Released to WMS | **Split & Waves** 에서 기다린다 |
| Working | Working | 픽 · 검수 · 포장 중 |
| Finalized | Finalized | 창고 일 끝 — 오피스가 **Ship & invoice** 할 차례 |
| Shipped | Invoice cancelled | 같은 상태다. 물건은 나갔고, 인보이스가 취소되어 다시 내야 한다 |
| Fulfilled | Fulfilled | 끝 |
| Cancelled | Cancelled | 닫혔다 |

[상태의 뜻](01-sales.md#sales-statuses)도 봅니다.

**트랜스퍼**
Confirmed · Released to WMS · Working · **In transit** · **Receiving** · **Received** · Cancelled
트랜스퍼에는 **Finalized** 가 없습니다. 창고가 Finalize 하면 곧장 **In transit** 이 됩니다.
오피스 화면의 말은 [상태의 뜻](03-inventory.md#stock-statuses)을 봅니다.

<!-- rulings: 17, 20, 21, 25, 72, 74, 83, 84, 88, 224, 567, 578, 600, 709, 713, 714, 715, 719, 720, 723, 725, 728, 731 -->
