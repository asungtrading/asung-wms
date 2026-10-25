# 2. 구매

<!-- sections 1-13 · manual-2a writes purch-suppliers, purch-reorder, purch-new-po, purch-confirm · the rest manual-2b · sections follow the order of the work, not the order of the screens -->

<a id="purch-suppliers"></a>
## 공급처 찾기 · 더하기
<!-- screen: suppliers.html · BUILD 2026-10-25 · sup v3c -->
<!-- who: office -->

**무엇인가**
**Suppliers**(**Purchasing ▾** › **Suppliers**)에 모든 공급처가 있습니다: 조건 · 주소 · 연락처 · 할인 · 구매 이력

**공급처 찾는 법**
1. **Suppliers** 를 열고 이름 일부를 적습니다.
2. **Purchasable** 필터는 **Yes**(지금 사는 공급처)로 시작합니다. 다른 공급처도 보려면 **All** 을 고릅니다.
3. 공급처를 누릅니다. 조건, **Purchase history**(구매 이력), **Addresses**, **Contacts**, **Discounts** 가 보입니다.

**공급처 더하는 법**
1. **+ New supplier** 를 누릅니다.
2. **Name \*** 과 아는 조건을 적습니다: **Currency** · **Payment term** · **Tax rule** · **Account payable** · **Type**
3. 주소와 연락처를 넣습니다.
4. **Create** 를 누릅니다.

**공급처 고치는 법**
1. **Edit** 로 이름 · 조건 · 메모를 바꿉니다.
2. **Addresses** · **Contacts** 에서 **+ Add** 를 누르거나 줄의 **Edit** · **Make default** · **Remove** 를 누릅니다.
3. **Purchasable**(**Yes** · **No** · **Not set**)은 지금도 이 공급처에서 사는지를 나타냅니다. 바꾸면 바로 저장됩니다.

**master 권한이 있는 사람**
- **Deactivate** / **Activate** 는 공급처를 끄거나 켭니다.
- **Discounts** — 공급처의 상시 할인(**Seq** · **Name** · **Percent**). 이 공급처의 새 PO 에 걸립니다.

**알아 둘 것**
- **Purchase history** 는 이 공급처의 오더를 최신순으로 보여 줍니다. **Show … more** 로 더 봅니다.
- purchasing · master 권한이 없는 사람에게는 지금 사는 활성 공급처만 보입니다.

<a id="purch-reorder"></a>
## 무엇을 주문할지 정하기(Reorder Planner)
<!-- screen: purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office -->

**무엇인가**
**Reorder Planner**(**Purchasing ▾** › **Reorder Planner**)는 판매 · 재고 · 주문 중인 재고 · 백오더를 보고 공급처에서 제품마다 얼마나 주문할지 계산합니다. 그리고 PO 초안을 만들어 줍니다.
화면 글자는 대부분 한국어입니다. 이 매뉴얼은 화면 글자와 영어 뜻을 함께 적습니다. 예: **발주 추천**(Order suggestions)

**시작 전에 — Google 연결**
2026-11-01 이전 판매는 회사 판매 기록에서 읽습니다. "🔑 지난 판매 이력 … 연결해야 추천 발주가 계산됩니다" 가 보이면 **Google 연결 →**(Connect Google)을 누르고 회사 구글 계정으로 로그인합니다. 연결하지 않으면 추천이 계산되지 않습니다.

**어떻게**
1. 위에서 브랜치를 고릅니다: **TOR** · **EDM** · **합산**(둘 합침)
2. 왼쪽 **Supplier 검색...**(Search supplier)에서 공급처를 찾아 고릅니다.
3. 왼쪽에서 공급처 설정을 확인합니다: **Lead Time** · **발주주기**(order cycle) · **목표 재고**(target stock · 일 수). IMS 가 다음 번을 위해 기억합니다.
4. **발주 추천**(Order suggestions) 탭에 제품마다 **일판매량**(daily sales) · **재고일수**(days of stock) · **Available** · **추천발주**(suggested quantity)가 보입니다.
5. 추천 수량을 누르면 **실발주량**(order quantity)에 들어갑니다. 직접 적어도 됩니다. **전체 추천 적용**(Apply all suggestions)은 모든 추천을 한 번에 넣습니다.
6. **→ IMS 발주 초안**(Create IMS draft PO)을 누릅니다. "…개 SKU를 IMS 발주 초안(draft PO)으로 만들까요?" 에 OK 를 누릅니다.
7. PO 초안이 만들어집니다. 예: PO-99001. 열어서 확인합니다([PO 시작하기](#purch-new-po)).

**초안에 들어가는 것**
- 주문 수량이 0 보다 큰 제품만. 수량을 0 으로 지우면 빠집니다.
- 지금 필터와 검색에 보이는 것만
- 가격: 이 공급처의 고정 단가, 없으면 최근 단가, 없으면 0(경고 표시)
- 창고: **TOR** → Toronto · **EDM** → Edmonton · **합산** → Toronto

**다른 탭**
- **데드 스톡**(Dead stock) — 오래 안 팔린 제품
- **Forecast** — 앞으로 30 · 60 · 90 일 예상 판매
- **📦 입고 검증**(Receiving check) · **📊 Supplier 분석**(Supplier analysis) — 지난 입고와 공급처 성과

**알아 둘 것**
- 초안은 "재고 · 회계에 영향 없음" 입니다. 확정은 **Purchase Orders** 에서 합니다.
- **↓ CSV** 는 주문 목록이나 전체 제품을 공급처 하나 또는 전체로 내려받습니다.
- master 권한이 필요한 것: 제품의 공급처 고정 단가(💲) 바꾸기

<!-- SCREENSHOT: purch-reorder-1 · 발주 추천 탭: 공급처 고름 · 추천발주와 실발주량 칸 · → IMS 발주 초안 단추 -->

<a id="purch-new-po"></a>
## PO 시작하기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->

**무엇인가**
PO(구매 오더)는 공급처 하나에 주문하는 것입니다. **Draft**(초안)로 시작합니다.

**어떻게**
1. **Purchasing ▾** › **Purchase Orders** 를 열고 **+ New purchase order** 를 누릅니다. (Reorder Planner 에서 만든 초안은 이미 여기 있습니다.)
2. "New purchase order — pick a supplier": 공급처를 찾아 누릅니다. 다른 공급처도 보려면 **Show all (including not-purchasable)** 을 체크합니다.
3. 초안이 번호와 함께 열립니다. 예: PO-99001. "no ship-to warehouse — pick one"(받을 창고를 고르라) 경고가 나오면 **Ship to** 를 정합니다.
4. 라인을 넣습니다:
  - **Add a line** — "SKU · supplier SKU · product name" 으로 찾고(이 공급처의 제품만), 수량을 적고 **Check** 뒤 **Add lines**
  - **Paste lines** — 한 줄에 하나씩: SKU, 수량, 가격(선택). "Tab, comma or two spaces — any of them works." "A price you give is the unit price before the PO discount."(적은 가격은 PO 할인 전 단가) **Check** 뒤 **Add lines**
5. 윗부분을 확인합니다: **Order date** · **Required by** · **Payment term** · **Ship to** · **Currency** · **Tax rule** · **Note**(내부 메모)
6. **Add a discount** 는 PO 전체에 할인을 더합니다(**Name** · **Percent**).

**알아 둘 것**
- 라인마다 **Supplier SKU** · **Qty** · **Unit price** · **Amount** · **Received** · **Remaining** 이 보입니다. **✕** 는 라인을 지웁니다.
- 할인이 여럿이면 더하지 않고 차례로 걸립니다.
- purchasing 이 **read** 인 사람은 PO 를 볼 수만 있고 저장은 되지 않습니다.

**조심할 것**
- 초안은 지울 수 있습니다(**Delete**). "The number … is not given to another order — it stays empty."(그 번호는 다른 오더에 주지 않고 빈 채로 둔다)

<a id="purch-confirm"></a>
## PO 확정하고 보내기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->

**무엇인가**
**Confirm** 은 주문할 라인과 수량이 정해졌다는 뜻입니다. PO 를 잠그지도 않고 아무것도 보내지 않습니다. 확정 뒤에도 라인을 고칠 수 있습니다 — 예: 공급처와 통화한 뒤

**어떻게**
1. 초안에서 **Confirm** 을 누르고 OK 를 누릅니다. 상태가 **Ordered** 가 됩니다 — "Confirmed — waiting for the supplier to send"(공급처가 보내기를 기다림)
2. **↓ PO CSV** 를 누릅니다. 스프레드시트가 내려받아집니다: PO · 공급처 · 주문일 · 필요일 · 통화 · 결제 조건, 그리고 라인마다 **Line** · **SKU** · **Supplier SKU** · **Barcode** · **Product** · **Qty** · **Unit price** · **Amount**, 할인과 합계
3. 그 파일을 메일에 붙여 공급처에 보냅니다. IMS 가 메일을 보내지는 않습니다.

**알아 둘 것**
- **↓ PO CSV** 는 확정된 뒤에 나옵니다(초안 · 취소된 PO 에는 없음).
- 내부 **Note** 는 파일에 들어가지 않습니다.
- 엑셀에서 SKU 와 바코드는 글자 그대로 열립니다.

**조심할 것**
- 보낸 뒤 라인을 바꾸면 **↓ PO CSV** 를 다시 내려받아 새 파일을 보냅니다.

<!-- SCREENSHOT: purch-confirm-1 · Ordered 상태의 확정 PO 와 ↓ PO CSV 단추 -->

<a id="purch-invoice"></a>
## 공급처 인보이스 넣기
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 ; po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-documents"></a>
## 공급처 서류 올리기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: office, accounting -->
<!-- TODO manual-2b -->

<a id="purch-charges"></a>
## 운임 · 관세 · 그 밖의 비용
<!-- screen: charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-receipts"></a>
## 오피스 입고
<!-- screen: receiving.html · BUILD 2026-10-22 · rcv latest v1 -->
<!-- who: office -->
<!-- TODO manual-2b -->

<a id="purch-credits"></a>
## 공급처 크레딧
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-payments"></a>
## 공급처 결제
<!-- screen: payments.html · BUILD 2026-10-22 · pay gone v1 -->
<!-- who: accounting -->
<!-- TODO manual-2b -->

<a id="purch-undo"></a>
## 취소 · 되살리기 · 지우기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->
<!-- TODO manual-2b -->

<a id="purch-statuses"></a>
## 상태의 뜻
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: all -->
<!-- TODO manual-2b -->

<a id="purch-csv"></a>
## CSV 내려받기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office, accounting -->
<!-- TODO manual-2b -->

<!-- rulings: 88, 606, 607, 616, 709, 711, 713, 714, 715, 719, 720, 723, 725, 732, 733 -->
