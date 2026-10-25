# 3. 재고

<!-- sections 1-12 · manual-3a writes stock-availability, stock-products, stock-new-product, stock-families · the rest manual-3b · sections follow the order of the work, not the order of the screens -->

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
<!-- TODO manual-3b -->

<a id="stock-descriptions"></a>
## 설명 · 사진 · 태그 · 웹 숍
<!-- screen: products.html · BUILD pr v5f ; ims-desc.js ; ims-shop.js -->
<!-- who: office, manager -->
<!-- TODO manual-3b -->

<a id="stock-adjustments"></a>
## 재고 조정
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: manager -->
<!-- TODO manual-3b -->

<a id="stock-bgrade"></a>
## B급 재고
<!-- screen: stock-bgrade.html · BUILD 2026-10-23 · bgr v1 -->
<!-- who: manager -->
<!-- TODO manual-3b -->

<a id="stock-transfers"></a>
## 창고 간 트랜스퍼
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: office, warehouse -->
<!-- TODO manual-3b -->

<a id="stock-bin-moves"></a>
## 오피스의 bin 이동
<!-- screen: stock-moves.html · BUILD 2026-09-28 · sm v1 -->
<!-- who: office, warehouse -->
<!-- TODO manual-3b -->

<a id="stock-statuses"></a>
## 상태의 뜻
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 ; transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: all -->
<!-- TODO manual-3b -->

<a id="stock-csv"></a>
## CSV 내려받기
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: office, accounting -->
<!-- TODO manual-3b -->

<!-- rulings: 145, 176, 194, 200, 202, 209, 210, 247, 257, 258, 567, 578, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732 -->
