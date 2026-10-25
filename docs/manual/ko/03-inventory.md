# 3. 재고

<!-- sections 1-12 written (manual-3a · 3b) · sections follow the order of the work, not the order of the screens -->

<a id="stock-availability"></a>
## 재고 찾기(Stock Availability)
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: all -->

**무엇인가**
**Stock Availability**(**Inventory ▾** › **Stock Availability**)는 제품마다 브랜치별로 얼마나 있는지, 어디에 있는지, 무엇이 잡고 있는지 보여 줍니다. 로그인한 사람은 누구나 엽니다.

**어떻게**
1. "SKU, name, brand or barcode" 로 찾습니다. 예: `DEMO-001`
2. 브랜치나 **Both branches**(두 브랜치)를 고릅니다. **All brands** · **All categories** · **All suppliers** 로 좁힙니다.
3. 제품마다 **On hand** · **Allocated** · **Transfer res.** · **Available** · **On order** · **In transit** · **Last movement** · **On sale %** 가 보입니다.
4. 줄의 **▸** 를 누르면 그 제품의 세트 · bin · 최근 움직임이 펼쳐집니다. 제품을 누르면 오른쪽에 열립니다.
5. 상세에서 **Allocated** · **Transfer res.** 를 누르면 "Show the sales orders holding this stock"(이 재고를 잡은 판매 오더) 또는 트랜스퍼가 나옵니다.

**숫자의 뜻**
- **On hand** — 이 브랜치 선반에 있는 것
- **Allocated** — 확정된 판매 오더에 확보된 것
- **Transfer res.** — 다른 브랜치로 갈 트랜스퍼에 묶인 것
- **Available** — 지금 팔 수 있는 것
- **On order** — 확정된 PO 에 있고 아직 안 온 것
- **In transit** — 다른 브랜치에서 오는 중
- 예: On hand 50 · Allocated 18 · Transfer res. 5 → Available 27

**알아 둘 것**
- **Zero stock** 은 재고 · 확보 · 주문이 모두 없는 제품도 보여 줍니다. **On sale** 은 지금 딜이 걸린 제품을 보여 줍니다.
- B급 bin 의 재고는 **On hand** · **Available** 에 들어가지 않습니다 — "sold at the POS only"(POS 에서만 판다). 줄에 작은 표시로 나옵니다.
- 움직임은 "Balance is shown at the end of each day."(잔고는 하루 끝 기준) **Full history ›** 로 전부 봅니다. "Loaded history — not an IMS document" 는 IMS 이전 움직임 표시입니다.
- **↓ CSV** 는 필터에 맞는 제품을 모두 내려받습니다.
- `cost` 권한이 있으면 **Value** · **Layer qty (EA)** 도 보이고, **Stock value total** 이 맞는 것 전체의 금액을 더합니다.
- 창고에서는 같은 숫자를 [재고 찾아보기](04-wms.md#wms-stock-lookup)에서 봅니다.

<!-- SCREENSHOT: stock-availability-1 · Stock Availability: 제품 하나의 ▸ 펼침(세트 · bin · 움직임) -->

<a id="stock-products"></a>
## 제품 찾기 · 고치기
<!-- screen: products.html · BUILD pr v5f -->
<!-- who: office, manager -->

**무엇인가**
**Products**(**Inventory ▾** › **Products**)에 모든 제품이 있습니다: 이름 · 브랜드 · 분류 · 단위 · 가격 · 공급처 · 바코드 · 세트 · 패밀리 · 사진 · 태그

**제품 찾는 법**
1. **Products** 를 열고 **Search SKU or name** 에 적습니다.
2. **Singles** 는 낱개 제품, **Sets only** 는 케이스 · 팩만 보여 줍니다. **Active only** 는 체크된 채 시작합니다.
3. 제품을 누릅니다. 오른쪽에 카드가 열립니다: 판매 등급별 가격 · **Suppliers** · **Barcodes** · **Sets of this product** · **Family** · **Photos** · **Tags**

**제품 고치는 법 — master 권한 필요**
1. **Edit** 를 누릅니다. "Change several fields, then save once."(여러 칸을 고치고 한 번에 저장)
2. 필요한 것을 바꿉니다 — 이름 · 브랜드 · 분류 · 단위 · 가격 · 공급처 · 바코드
3. **Check & save** 를 누릅니다. IMS 가 먼저 검사합니다:
   - "Not saved — fix these first" 에 고쳐야 할 것이 나옵니다.
   - 경고는 읽고 **Save anyway** 로 넘길 수 있습니다.

**알아 둘 것**
- 자기 가격이 없는 세트는 **calculated** 로 보입니다 — 낱개 가격을 따릅니다.
- **Last change before IMS** 는 IMS 이전에 마지막으로 바뀐 날입니다.
- 제품의 surcharge 그룹은 **Edit** 에서 제품 카드의 **Surcharge group** 으로 고릅니다([Surcharge 그룹](07-settings.md#set-surcharge)).
- 제품은 감추지 않습니다 — 꺼진 제품도 찾을 수 있습니다.
- 여러 제품을 한꺼번에 고치려면 [Product Sheet](#stock-sheet)를 씁니다.

<a id="stock-new-product"></a>
## 새 제품 · 세트 · 콤보 만들기
<!-- screen: products.html · BUILD pr v5f -->
<!-- who: office, manager -->

**무엇인가**
**세트**는 같은 제품의 케이스 · 팩입니다. 예: 6 개 케이스. 재고는 낱개로 셉니다. **콤보**는 서로 다른 제품 여럿으로 이루어진 SKU 하나이고, 재고는 구성품이 가집니다.

**어떻게 — 새 제품(master 권한 필요)**
1. **+ New product** 를 누릅니다.
2. **Barcode(s)**("one or more — the first is primary" · 여럿이면 처음 것이 대표) · **Brand** · **SKU** · **Name** · **Category** · **Unit** · **Weight** 를 적습니다. **Suggest** 는 "Brand prefix + barcode digits"(브랜드 앞글자 + 바코드 숫자)로 SKU 를 만들어 줍니다.
3. 등급마다 **Sale prices**(판매가)를 적습니다.
4. **Supplier** · **Supplier SKU** · **Cost**, 있으면 **Fixed cost**(고정 단가)를 넣습니다.
5. 세트도 함께 만들려면 **+ ×6** · **+ ×12** · **+ other** 를 누릅니다. "Leave the name of a set blank to get the usual name."(세트 이름을 비우면 보통 이름이 붙는다) 예: DEMO-001 의 6 개 세트 → DEMO-001-6
6. **Check & create** 를 누릅니다. "Not saved — fix these first" 를 고치거나, 경고는 **Save anyway** 로 넘깁니다.

**어떻게 — 있는 제품에 세트 더하기**
1. 낱개 제품을 열고 **Add set** 을 누릅니다. **Sets now** 에 이미 있는 세트가 보입니다(✓).
2. 새 세트로 **+ ×6** · **+ ×12** · **+ other** 를 누르고, 있으면 케이스 바코드를 적습니다(예: `0000000000017`).
3. **Check & add** 를 누릅니다.

**어떻게 — 콤보 만들기**
1. 콤보 SKU 가 될 제품을 열고 **Make combo** 를 누릅니다.
2. 구성품 SKU 와 콤보 하나에 들어가는 수량을 넣고, 그 창에서 저장합니다.
3. 나중에 **Edit components** 로 구성품을 바꾸고, **Release combo** 로 보통 제품으로 돌립니다.

**조심할 것**
- 세트는 콤보가 될 수 없고, 콤보는 세트를 가질 수 없습니다.
- 구성품은 **Edit** 와 따로, 자기 창에서 저장합니다.

<!-- SCREENSHOT: stock-new-product-1 · New product 창: 판매가 · 공급처 · + ×6 세트 -->

<a id="stock-families"></a>
## 패밀리
<!-- screen: families.html · BUILD fam v5c -->
<!-- who: office, manager -->

**무엇인가**
패밀리는 한 물건의 변형인 제품들을 묶습니다 — 색이나 크기만 다른 같은 물건. 웹 숍에서 옵션이 있는 한 제품으로 보일지를 정합니다. 재고나 주문에는 영향이 없습니다. 패밀리가 없는 제품이 많은 것이 정상입니다.

**패밀리 찾는 법**
1. **Inventory ▾** › **Families** 를 열고 패밀리 SKU 나 이름으로 찾습니다.
2. 패밀리를 누르면 **Options**(예: Color · Size)와 **Products** 가 보입니다.

**어떻게 — master 권한 필요**
- **New family from existing SKUs**(있는 SKU 로 새 패밀리): **Family SKU**(비우면 "first variant SKU + FAM") · **Family name** · **Options** 를 셋까지("Option 1 — e.g. Color") 적습니다. 넣을 SKU 를 찾고 **Check and create** 를 누릅니다.
- **New family (new SKUs)**(새 SKU 로 새 패밀리): Products 화면의 New family 창을 엽니다 — 아직 없는 SKU 를 패밀리와 함께 만듭니다.
- **Add member…** 는 패밀리에 제품을 더합니다. 옵션 값(예: Color = Red)을 정하고 **Check and add** 를 누릅니다.
- **Remove** 는 제품을 패밀리에서 뺍니다.

**조심할 것**
- "A SKU already in another family moves out of it into this one — you will be asked to confirm. If that old family is on Shopify, the SKU drops from that Shopify product until this new family is listed."(다른 패밀리에 있던 SKU 는 이 패밀리로 옮겨진다 · 그 패밀리가 Shopify 에 있으면 새 패밀리가 올라갈 때까지 그 제품에서 빠진다)
- "Two members of one family cannot have the same option values."(한 패밀리의 두 제품은 옵션 값이 같을 수 없다)

<a id="stock-sheet"></a>
## 여러 제품을 한꺼번에 고치기(Product Sheet)
<!-- screen: product-sheet.html · BUILD sheet v2b -->
<!-- who: office, manager -->

**무엇인가**
**Product Sheet**(**Inventory ▾** › **Product Sheet**)는 여러 제품을 표로 보여 줍니다. 한 행이 제품 하나입니다. 스프레드시트처럼 고치고 한 번에 저장합니다. 저장에는 master 권한이 필요합니다.

**어떻게 — 제품 고치기**
1. **Edit products** 를 고릅니다. 필터(검색 · **Brand** · **Category** · **Supplier** · **Singles** / **Sets only**)를 정하고 **Load** 를 누릅니다. 300 행까지 불러오고, **Next 300** 은 더 불러옵니다.
2. 칸을 눌러 고칩니다. Enter 는 아래로 갑니다. 이름 · 브랜드 · 분류 · 단위 · 등급별 판매가 · 기본 공급처의 공급처 SKU 와 단가 · 활성 · 단종 · 세트 할인 % 를 고칠 수 있습니다.
3. 엑셀에서 붙여 넣으려면 덩어리를 복사해 첫 칸에 붙여 넣습니다. "Paste follows the visible columns from left to right — line up your Excel columns with what you see. SKU always stays."(보이는 칸 순서대로 붙는다 · 엑셀 칸을 화면에 맞춘다 · SKU 는 그대로) **Columns** 로 보일 칸을 고릅니다.
4. **Save** 를 누릅니다. "Not saved — fix these first (rows in red)"(빨간 행을 먼저 고쳐라)에 고칠 것이 나오고, 경고는 **Save anyway** 로 넘깁니다.

**어떻게 — 새 제품**
1. **New products** 를 고릅니다. **+ 20 rows** 는 빈 행을 더합니다.
2. 새 제품을 적거나 붙여 넣고 **Save** 를 누릅니다.

**가격 공식**
"Filter by a supplier and press Load to use a price formula."(공급처로 필터하고 Load 해야 가격 공식을 쓴다)
1. 공급처 하나로 필터하고(예: Supplier B) **Load** 를 누릅니다.
2. 공식을 고르거나 **— new formula —** 를 고릅니다. 칸은 **Cur** · **Duty %** · **Freight · other ×** · **Margin ÷** 입니다. ★ 은 그 공급처의 기본 공식입니다.
3. 끝자리를 고릅니다: **.49 · .99** 또는 **.x9 all**
4. **Preview** 뒤 **Apply** 로 가격을 채웁니다. **Save as new** · **Update this formula** 는 공식을 다음을 위해 남깁니다.
- "Sets are not priced by a formula."(세트는 공식으로 매기지 않는다)
- "Costs are in the supplier's currency (Cur) — not converted."(단가는 공급처 통화 그대로)

**알아 둘 것**
- 공급처 하나가 파는 것을 보려면 그 **Supplier** 로 필터하고 **Load** 합니다.
- **Open these in Edit** 는 불러온 제품을 고치기 방식으로 엽니다.
- **Discard** 는 저장하지 않은 변경을 버립니다.

<!-- SCREENSHOT: stock-sheet-1 · 공급처 하나로 필터한 Product Sheet 와 가격 공식 칸 -->

<a id="stock-descriptions"></a>
## 설명 · 사진 · 태그 · 웹 숍
<!-- screen: products.html · BUILD pr v5f ; ims-desc.js ; ims-shop.js ; families.html · BUILD fam v5c -->
<!-- who: office, manager -->

**설명**
설명은 웹 숍이 제품에 보여 주는 글입니다. IMS 에서 쓰고 IMS 에 둡니다.
1. 제품에서 **Edit description** 을 누릅니다.
2. **Text** · **H2** · **H3** · **• List** · **1. List** · **Link** · **Clear format** 으로 씁니다 — 또는 **HTML** 로 코드를 고칩니다.
3. **Save** 를 누릅니다.
- "Pasted text is cleaned the same way. YouTube and Facebook videos are kept; other embedded boxes are dropped."(붙여 넣은 글도 같게 정리 · 유튜브 · 페이스북 영상은 남고 다른 끼워 넣은 상자는 빠진다)
- 빈 설명은 먼저 묻습니다: "Save an empty description? The site will show none."
- 카드에 "Last edited … by …"(마지막으로 고친 때 · 사람)가 보입니다.

**사진 · 태그 · 바코드** — master 권한 필요
1. 제품에서 **Edit** 를 누릅니다.
2. **Upload photos** 로 사진을 더합니다. **Make primary** 로 대표 사진을 정합니다. "This set has no photo of its own — the single's primary photo is shown."(세트에 자기 사진이 없으면 낱개 대표 사진이 보인다)
3. 태그: "Tags are case-sensitive — pick from the list to keep one spelling. ✕ takes a tag off when you save."(대소문자를 가린다 · 목록에서 골라 철자를 하나로 · ✕ 는 저장할 때 뗀다)
4. 바코드: **Add a barcode** 에 더합니다. "A new barcode can be made primary after saving."(새 바코드는 저장 뒤 대표로 정할 수 있다)
5. **Check & save** 를 누릅니다. "Save checks every change on this page — prices, suppliers, barcodes and tags included."

**웹 숍(Shopify 카드)** — 매니저 이상(Shopify 권한)
제품의 Shopify 카드에 스토어마다 한 줄이 있습니다.
1. **Turn on** — "Send this to the Shopify store"(이 스토어로 보낸다)
2. **Send now** 는 바로 보내고 결과를 보여 줍니다. **Send stock now** 는 재고 숫자를 보냅니다.
3. **Turn off** — "Stop sending — the Shopify product becomes Archived (not deleted)"(보내기를 멈추고 Shopify 제품은 보관됨 · 지우지 않음)
4. **Choose photo** 는 Shopify 의 첫 사진을 고릅니다.
- 패밀리에 묶인 제품에는 "Sent to Shopify as a variant of its family"(패밀리의 변형으로 보낸다)가 보입니다. 그 패밀리의 Shopify 카드에서 켭니다(**Inventory ▾** › **Families** — [패밀리](#stock-families)).
- "Sets are not sent to Shopify. Only a set marked sellable can be switched on."(세트는 보내지 않는다 · 팔 수 있다고 표시한 세트만 켤 수 있다)
- 권한이 없으면: "You can see this, but turning it on or off needs the Shopify permission."

<a id="stock-adjustments"></a>
## 재고 조정
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: manager -->

**무엇인가**
재고 조정은 재고 장부를 선반에 실제로 있는 대로 고칩니다 — 실사 · 분실 · 파손 뒤

**누가**
admin, 그리고 Stock adjustments 권한이 켜진 manager · supervisor. 화면만 열 수 있는 사람은 볼 수만 있습니다: "Read-only — adjusting stock needs the Stock adjustments key."

**어떻게**
1. **New adjustment** 를 누릅니다. **Warehouse** 를 고르고 **Note** 를 적습니다. "One adjustment is one warehouse. The note cannot be changed later."(조정 하나는 창고 하나 · 메모는 나중에 못 바꾼다)
2. **Add line** 을 누릅니다. **Product** 와 **Bin** 을 고릅니다.
3. **What to do**(할 일):
   - **Shelf holds** — 선반에 있는 수를 적습니다. IMS 가 바뀔 양을 셉니다.
   - **Add (+) or take (−)** — 바뀔 양 자체를 적습니다.
4. **Reason**(까닭)을 고릅니다: **Found — more than the books** · **Lost / missing** · **Damaged / thrown out** · **Count difference** · **Other (note needed)**. 재고를 늘리는데 원가를 알면 **Unit cost** 를 적습니다.
5. 라인을 더 넣고 **Confirm** 을 누릅니다.

**예**
장부에는 bin 에 DEMO-001 이 43 입니다. 선반에는 40 이 있습니다. **Shelf holds** 를 고르고 40 을 적으면 바뀜은 −3 입니다. **Add (+) or take (−)** 를 고르고 −3 을 적어도 결과는 같습니다.

**알아 둘 것**
- "Not enough stock" 보고에서 시작하면, WMS Admin 의 **Adjust stock** 이 픽한 자리로 채운 조정을 엽니다([WMS Admin](04-wms.md#wms-admin)).
- 원가를 모르는 채 재고를 늘리면 "These go into the books at cost 0"(원가 0 으로 장부에 들어간다) 경고가 나옵니다.
- **Delete draft** 는 확정하지 않은 조정을 지웁니다.

**조심할 것**
- 확정한 조정은 되돌리거나 지울 수 없습니다. 실수는 새 조정으로 바로잡습니다.

<!-- SCREENSHOT: stock-adjustments-1 · Add a line: What to do = Shelf holds 와 장부 바뀜 -->

<a id="stock-bgrade"></a>
## B급 재고
<!-- screen: stock-bgrade.html · BUILD 2026-10-23 · bgr v1 -->
<!-- who: manager -->

**무엇인가**
B급 재고는 포장이 상한 물건을 같은 SKU 로 B급 bin 에 둔 것입니다. **On hand** · **Available** 에서 빠지고, 보통 오더에는 픽되지 않으며, POS 에서만 B급 가격으로 팝니다. bin 을 B급으로 정하는 것은 **Settings** 에서 합니다([목록](07-settings.md#set-master)).

**누가**
재고 조정과 같은 사람 — admin, 그리고 Stock adjustments 권한이 켜진 manager · supervisor

**어떻게 — B급으로 옮기기**
1. **Inventory ▾** › **B-grade Stock** 에서 **Move to B-grade** 를 누릅니다.
2. **Product** · **From bin** · **To B-grade bin** · **Quantity** 를 고르고 저장합니다.
3. **Set price** 를 누릅니다. 가격이나 **% off Wholesale**(도매가에서 몇 % 할인)를 적습니다. "Every unit of this SKU in this bin takes the new price."(이 bin 의 이 SKU 는 모두 새 가격)

**알아 둘 것**
- **Reprice** 는 가격을 바꿉니다. **Move back** 은 보통 bin 으로 돌려놓습니다.
- 가격이 없는 B급 재고는 POS 에서 팔 수 없습니다([B급 팔기](05-pos.md#pos-bgrade)).
- 옮겨도 원가는 바뀌지 않습니다.

<a id="stock-transfers"></a>
## 창고 간 트랜스퍼
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: office, warehouse -->

**무엇인가**
트랜스퍼는 한 창고의 재고를 다른 창고로 옮깁니다. 판매 오더처럼 창고를 거칩니다. transfer 권한이 필요합니다.

**어떻게**
1. **Inventory ▾** › **Transfers** 에서 **New transfer** 를 누릅니다. 출발 · 도착을 고르고 **Add line** 이나 **Paste lines** 로 넣습니다.
2. **Confirm** 을 누릅니다. 출발 창고의 재고가 이 트랜스퍼에 묶입니다(**Transfer res.**).
3. **Release to WMS** 를 누릅니다. 창고가 픽 · 검수 · 포장합니다([오더 픽하기](04-wms.md#wms-picking) · [상자 · 팔레트에 담기](04-wms.md#wms-fulfillment)).
4. 창고가 Finalize 하면 떠납니다 — **in transit**
5. 도착 창고가 **Receiving** 에서 세고 끝내면 — **received**([PO · 트랜스퍼 받기](04-wms.md#wms-receiving)). 오피스 확정은 없습니다.

**맞지 않을 때 — Stock adjustments 권한 필요**
- **덜 왔다**: **Settle in transit** 을 누릅니다. 라인마다 **Lost**(잃음) 또는 **Returned to sender**(출발 창고 bin 으로 돌아감)를 고르고 **Save settlement** 를 누릅니다.
- **보낸 것보다 많이 왔다**: 도착 창고는 보낸 만큼만 받았습니다. **Decide** 를 누르고 **… sent more**(출발 창고가 더 보냄) 또는 **Found at …**(도착 창고에서 찾음)을 고른 뒤 **Save decision** 을 누릅니다. "These may go into the books at cost 0."

**알아 둘 것**
- 픽커가 다 찾지 못했으면 픽한 만큼만 떠납니다. 나머지는 이 트랜스퍼에서 닫힙니다 — 새 트랜스퍼를 만듭니다.
- **Add freight charge** 는 운임을 도착한 물건의 원가에 얹습니다.
- 보내기 전: **Back to draft** · **Delete draft** · **Cancel transfer** · 보낸 뒤: **Recall from warehouse**

<!-- SCREENSHOT: stock-transfers-1 · in transit 트랜스퍼와 Settle in transit -->

<a id="stock-bin-moves"></a>
## 오피스의 bin 이동
<!-- screen: stock-moves.html · BUILD 2026-09-28 · sm v1 -->
<!-- who: office, warehouse -->

**무엇인가**
**Bin Moves (office)** 는 한 창고 안에서 bin 사이 재고를 문서로 옮깁니다: 적고, 확정합니다. 창고는 같은 일을 [bin 사이 재고 옮기기](04-wms.md#wms-bin-moves)에서 스캔으로 합니다.

**어떻게**
1. **New move** 를 누릅니다. **Warehouse** 를 고르고 **Note** 를 적습니다("One move is one warehouse. The note cannot be changed later.").
2. **Add line**: **Product** · **From bin** · **To bin** · **Quantity**
3. **Confirm** 을 누릅니다.

**알아 둘 것**
- "Picked, not shipped" · "Waiting for pickers" 인 재고는 옮길 수 없습니다.
- 재고가 옮겨지면 그 재고를 가리키던 픽 계획도 따라갑니다("Pick plans moved with this stock").
- Bin moves 권한이 필요합니다: "Read-only — moving stock needs the Bin moves key."

<a id="stock-statuses"></a>
## 상태의 뜻
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 ; stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: all -->

**트랜스퍼**(오피스 화면)

| 상태 | 뜻 |
|---|---|
| draft | 쓰는 중 |
| confirmed | 출발 창고 재고가 묶였다 |
| at warehouse | 창고로 보냄 — Split & Waves 에서 기다림 |
| picking | 창고가 작업 중 |
| in transit | 출발 창고를 떠났다 |
| receiving | 도착 창고가 세는 중 |
| received | 도착했다 |
| cancelled | 취소 |

창고 화면은 같은 단계를 자기 글자로 보여 줍니다 — [상태의 뜻(창고)](04-wms.md#wms-statuses)

**조정 · bin 이동**
**Draft** · **Confirmed**

<a id="stock-csv"></a>
## CSV 내려받기
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: office, accounting -->

- [재고 찾기](#stock-availability)의 **↓ CSV** 는 필터에 맞는 제품을 모두 내려받습니다.
- **Product Sheet** 는 반대 방향입니다: 엑셀에서 표로 붙여 넣습니다([Product Sheet](#stock-sheet)).

<!-- rulings: 49, 50, 53, 83, 145, 176, 194, 200, 202, 204, 205, 206, 209, 210, 247, 257, 258, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 567, 578, 629, 631, 632, 637, 638, 642, 644, 645, 646, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732, 735 -->
