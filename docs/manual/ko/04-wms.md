# 4. WMS (창고)

<!-- sections 1-12 · manual-4a writes wms-start, wms-picking, wms-pick-short, wms-packing · the rest manual-4b · sections follow the order of the work, not the order of the screens -->

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
<!-- screen: wms-manager.html · BUILD 2026-09-29 · wm v1.2 -->
<!-- who: manager -->
<!-- TODO manual-4b -->

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
모두 매니저 목록으로 갑니다. 픽은 계속합니다.

**알아 둘 것**
- **🖨 Print** 는 픽리스트를 다시 찍습니다.
- 창고 간 트랜스퍼도 같은 방법으로 픽합니다. 오더 번호 자리에 트랜스퍼 번호가, 고객 이름 자리에 도착 창고가 나옵니다.
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
<!-- screen: wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-receiving"></a>
## PO · 트랜스퍼 받기
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse, manager -->
<!-- TODO manual-4b -->

<a id="wms-putaway"></a>
## 풋어웨이(제자리에 넣기)
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-bin-moves"></a>
## bin 사이 재고 옮기기
<!-- screen: wms-mover.html · BUILD 2026-10-05 · mv v2.3 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-stock-lookup"></a>
## 재고 찾아보기
<!-- screen: wms-stock.html · BUILD 2026-10-20 · ws v1a -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-admin"></a>
## WMS Admin
<!-- screen: wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: manager -->
<!-- TODO manual-4b -->

<a id="wms-statuses"></a>
## 창고 쪽 상태
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->
<!-- note for 4b: pair table with the sales chapter — same status: warehouse screens Shipped · sales screens Invoice cancelled (manual-4a review reply) -->
<!-- TODO manual-4b -->

<!-- rulings: 17, 20, 21, 25, 83, 224, 709, 713, 714, 715, 719, 720, 723, 725, 728, 731 -->
