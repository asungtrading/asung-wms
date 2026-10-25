# 2. 구매

<!-- sections 1-13 written (manual-2a · 2b) · sections follow the order of the work, not the order of the screens -->

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
- 왼쪽 **보정 Override**(adjustments) — 공급처의 **계절보정**(season) · **트렌드**(trend)를 직접 적습니다. 비우면 자동값을 씁니다. **Override 초기화**(Reset overrides)는 지웁니다.

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

**무엇인가**
공급처 인보이스가 오면 PO 에 대해 넣습니다. 확정하면 줄 돈이 장부에 오르고 — **창고가 그 물건을 받을 수 있게 됩니다.**

**어떻게**
1. PO 를 열고 **Create an invoice** 를 누릅니다.
2. **Number**("as printed on the document" — 문서에 찍힌 번호 · 예: 99001) · **Document date** · **Due date** · **Printed total**(인쇄된 합계 · 모르면 비움)을 적습니다.
3. 라인마다 **On this invoice** 가 **Left to bill**(남은 청구 수량)로 시작합니다. 인보이스가 청구한 수량으로 바꿉니다. **Check** 뒤 **Create** 를 누릅니다.
4. 인보이스가 **Purchase Invoices & Credits** 에 초안으로 열립니다. **Add a line** · **Add a discount** · **Add lines from a PO** 를 쓸 수 있습니다.
5. **Confirm** 을 누르고 OK 를 누릅니다.

**Confirm 이 하는 일**
"It is then taken into the books: the amount owed appears and the discount reaches cost. Lines can no longer be edited."(장부에 오른다 · 줄 돈이 생기고 할인이 원가에 닿는다 · 라인은 더 고칠 수 없다)
그리고 창고에 오더를 풀어 줍니다. 청구되지 않은 몫은 다음 글자가 붙은 새 오더로 옮겨져 자기 인보이스를 기다립니다.
- 예: PO-99001 이 100 을 주문했습니다. 인보이스가 60 을 청구합니다. PO-99001 은 60 을 갖고 창고가 받을 수 있습니다. PO-99001a 가 40 을 갖고 다음 인보이스를 기다립니다.
- 모두 청구되면: "The whole order is billed — nothing was split off. The warehouse can receive it now."

**Printed total(인쇄 합계)**
**Printed total** 이 비었거나 우리 계산과 다르면 IMS 가 먼저 알립니다("⚠ No printed total" · "⚠ The printed total does not match … difference …"). 라인을 확인하거나, OK 로 그대로 확정합니다.

**알아 둘 것**
- **Reopen** 은 확정된 인보이스를 초안으로 돌립니다. "Quantities that confirming split off go back onto their original order."(확정 때 나뉜 수량은 원래 오더로 돌아간다)
- 창고가 그 인보이스로 받기 시작하면 **Reopen** · **Cancel** 이 회색입니다: "The warehouse has received against this invoice — correct it with a credit note"([공급처 크레딧](#purch-credits))
- 라인을 **billed here but settled elsewhere**(여기 청구됐지만 다른 데서 정산)로 표시할 수 있습니다 — 예: 인보이스에 실렸지만 따로 내는 운임
- 창고 쪽: [PO · 트랜스퍼 받기](04-wms.md#wms-receiving)

<!-- SCREENSHOT: purch-invoice-1 · Confirm 뒤 글: PO-99001 은 청구분을 갖고 나머지는 PO-99001a 로 -->

<a id="purch-documents"></a>
## 공급처 서류 올리기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; charges.html · BUILD 2026-10-24 · chg docs v1 ; ims-podocs.js · BUILD 2026-10-24 · podocs v1 -->
<!-- who: office, accounting -->

**무엇인가**
PO 와 비용 빌 맨 아래에 **Documents** 구역이 있습니다. 공급처 서류를 여기 둡니다: 인보이스 · BOL · 원산지 증명 · 패킹 리스트 · B3 / CAD

**어떻게**
1. **Upload a document** 를 누릅니다.
2. 종류를 고릅니다: **Supplier invoice** · **BOL** · **Certificate of Origin** · **Packing list** · **B3 / CAD** · **Other**("Other needs a short description" — Other 는 짧은 설명이 필요)
3. 있으면 **Document date** 와 **Document number** 를 적습니다. "The date and number go into the file name in Drive."(날짜와 번호가 드라이브 파일 이름에 들어간다)
4. 파일을 고르고 — "PDF, JPEG or PNG · up to 10 MB" — **Upload** 를 누릅니다.

**알아 둘 것**
- 서류마다 **Waiting to go to Drive**(드라이브로 갈 차례) · **In Drive**(드라이브에 있음) · **Drive failed**(실패)가 보입니다.
- **Remove** 는 서류를 감춥니다: "It is hidden here and renamed REMOVED_ in Drive. Nothing is deleted."(여기서 감추고 드라이브에서는 REMOVED_ 로 이름을 바꾼다 · 지워지는 것은 없다)
- 서류는 관리자가 **Settings** 에서 켠 뒤, 거기 정한 시작 날짜부터 회사 구글 드라이브로 갑니다.

<!-- SCREENSHOT: purch-documents-1 · PO 의 Documents 구역 · In Drive 서류 하나 -->

<a id="purch-charges"></a>
## 운임 · 관세 · 그 밖의 비용
<!-- screen: charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: accounting, office -->

**무엇인가**
비용(Charge)은 공급처가 아닌 곳의 빌입니다 — 운임 · 관세 · 통관 수수료. 컨테이너 하나에 여러 PO 의 물건이 들어 있으니 비용 하나를 여러 PO 에 나눕니다. 비용의 세금 전 금액이 그 물건의 원가에 얹힙니다.

**어떻게**
1. PO 에서 **Add a charge** 를 누르거나, **Purchasing ▾** › **Charges** 에서 **New charge** 를 누릅니다.
2. **Kind**(**Freight** · **Duty** · **Brokerage** · **Other**) · **Billed by** · **Number** · **Charge date** · **Due date** · **Currency** · **Before tax** · **Tax** · **Tax rule** 을 적습니다.
3. 비용이 걸치는 PO 마다 **Add a purchase order** 를 누릅니다. PO 마다 몫을 적거나, **Spread by amount** 로 오더 금액 비율대로 전체를 나눕니다.
4. 다른 통화의 비용이면 환율(CAD per …)을 적습니다.
5. **Confirm** 을 누르고 OK 를 누릅니다. "The split is then settled and will be laid down on cost. Amounts and allocations can no longer be edited."(나눔이 정해져 원가에 얹힌다 · 금액과 나눔은 더 고칠 수 없다)

**알아 둘 것**
- "Allocated and Not allocated are before tax — only the amount before tax goes onto the cost of the goods; the tax is owed to the biller but comes back as a tax credit."(나눈 몫 · 안 나눈 몫은 세금 전 · 원가에는 세금 전 금액만 · 세금은 세금 공제로 돌아온다)
- 필터 **Not fully allocated** 로 아직 다 나누지 않은 비용을 찾습니다.
- 몫은 적은 순간 고정됩니다. PO 가 나중에 바뀌어도 몫은 저절로 움직이지 않습니다.

**조심할 것**
- 몫의 합이 비용과 맞을 때까지 Confirm 이 거절됩니다.
- **Spread by amount** 는 모든 몫을 덮어씁니다 — "including ones you typed"(직접 적은 것까지)

<!-- SCREENSHOT: purch-charges-1 · PO 둘에 나눈 비용 · Not allocated 0 -->

<a id="purch-receipts"></a>
## 오피스 입고
<!-- screen: receiving.html · BUILD 2026-10-22 · rcv latest v1 -->
<!-- who: office -->

**무엇인가**
**Purchase Receipts** 는 들어온 것을 오피스가 보는 화면입니다. 세기와 넣기는 창고가 합니다([PO · 트랜스퍼 받기](04-wms.md#wms-receiving) · [풋어웨이](04-wms.md#wms-putaway)). 오피스는 재고에 넣고 차이를 정리합니다. receiving 권한이 필요합니다.

**Post now — 기다릴 수 없는 재고**
1. 초안 입고에서 **Post now…** 를 누릅니다. "Put what is already counted and in a bin into stock now — the rest is counted later."(이미 세서 bin 에 넣은 것을 지금 재고로 · 나머지는 나중에)
2. bin 이 있는 행만 넣을 수 있습니다. **Check** 뒤 **Post to stock** 을 누릅니다.
- 넣은 행은 "can no longer be moved or changed here; fix a mistake with a stock adjustment"(여기서 더 옮기거나 고칠 수 없다 · 실수는 재고 조정으로)

**입고 확정**
1. 창고가 끝내면 **Confirm** 을 누릅니다.
2. 창이 받을 수량 · 이미 재고에 든 몫 · 모자라거나 넘친 라인 · PO 가 열린 채 남는지를 알려 줍니다. "This cannot be undone." OK 를 누릅니다.

**차이 정리**
- **모자람** — **Settle** 을 누르고 까닭을 고릅니다:
  - **Split shipment** — 나머지가 이 PO 로 아직 온다(열린 채)
  - **Supplier was out of stock** — 나머지는 오지 않는다
  - **Lost or damaged in transit** — 오지 않는다 · 크레딧을 청구한다
  - **We counted it wrong** — 더 받을 것이 없다
- **인보이스보다 많거나 PO 에 없는 물건** — 물건은 이미 선반에 있습니다. **Decide** 를 누릅니다: **Accepted — free, into stock at no cost**(무상 · 원가 0) 또는 **Accepted — billed, into stock at the invoice price**(청구 · 인보이스 가격). 공급처 반품은 따로 하는 일입니다.

**알아 둘 것**
- **Split** 은 행의 일부를 두 번째 bin 으로 옮깁니다. 합계는 그대로입니다.
- **Reopen** 은 정리한 차이를 다시 엽니다.
- **Delete** 는 초안 입고와 거기서 센 것을 지웁니다. "The purchase order is untouched."(PO 는 그대로)

<!-- SCREENSHOT: purch-receipts-1 · 모자란 라인이 있는 입고와 Settle 고르기 -->

<a id="purch-credits"></a>
## 공급처 크레딧
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 -->
<!-- who: accounting, office -->

**무엇인가**
공급처 크레딧 노트는 우리가 줄 돈을 줄입니다 — 오지 않은 물건이나 틀린 가격

**어떻게**
1. 공급처 인보이스를 열고 **Create a credit note** 를 누릅니다. "The draft arrives already filled with the gap between what was billed and what actually arrived."(초안에 청구된 것과 실제 온 것의 차이가 채워져 온다)
2. 라인을 확인하고 까닭을 고릅니다: **Not received** · **Price difference**
3. 공급처의 크레딧 번호와 **Credit date** 를 적고 **Confirm** 을 누릅니다.

**알아 둘 것**
- 확정한 크레딧은 재고 원가를 바꿀 수 있습니다. IMS 가 얼마인지("Stock cost changed on … lines"), 무엇이 물건 도착을 기다리는지 알려 줍니다.
- 크레딧 노트는 지울 수 없습니다. 취소합니다([취소 · 되살리기 · 지우기](#purch-undo)).
- 필터 **Credit due only** 는 아직 다 쓰지 않은 크레딧을 보여 줍니다.

<a id="purch-payments"></a>
## 공급처 결제
<!-- screen: payments.html · BUILD 2026-10-22 · pay gone v1 -->
<!-- who: accounting -->

**무엇인가**
**Supplier Payments** 는 공급처 인보이스와 비용에 대해 은행에서 나간 돈을 적습니다. 결제 하나가 한 통화의 여러 문서를 정산할 수 있습니다. purchasing 권한(write)이 필요합니다.

**어떻게**
1. **To pay** 를 누릅니다(또는 PO · 인보이스 · 비용의 **Pay**).
2. **Paying on**(내는 날)을 정합니다. "Click the invoices and charges this payment settles. A green discount is earned when paid on the date above."(이 결제가 정산할 인보이스 · 비용을 누른다 · 초록 할인은 위 날짜에 내면 받는다)
3. 문서를 하나씩 누릅니다. 처음 고른 문서가 통화를 정하고, 다른 통화 문서는 회색이 됩니다.
4. 라인마다 금액과 할인을 확인합니다. **Paid** 는 직접 적지 않으면 라인 합에서 할인을 뺀 값입니다.
5. **Pay selected** 를 누릅니다. "Which account did the money leave from?"(어느 계좌에서 나갔나) — **From account** 를 고르고 **Reference**(송금 번호 · 수표 번호 · 카드)를 적습니다.
6. IMS 가 내기 전에 알리면 — 예: "an early-pay discount was available but not taken"(조기 결제 할인을 받을 수 있었는데 안 받았다) — 읽고 OK 로 그대로 냅니다.

**할인**
- **Adjust discount** 는 결제 안 문서 하나의 할인을 바꿉니다.
- **Settle with discount** 는 "takes what is still owed as discount, when the supplier let it go"(공급처가 봐줬을 때 남은 금액을 할인으로 처리)

**조심할 것**
- 결제에는 취소 상태가 없습니다. **Delete** 가 "the only way to undo one"(되돌리는 유일한 길)이고 — "everything it settled goes back to being owed"(정산한 것은 다시 줄 돈이 된다)
- 라인의 **✕** 는 그 문서를 결제에서 뗍니다: "What it was owed goes back to being owed."

<!-- SCREENSHOT: purch-payments-1 · To pay: 인보이스 둘을 고르고 초록 할인 -->

<a id="purch-undo"></a>
## 취소 · 되살리기 · 지우기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: office -->

**PO**
- **Cancel PO**: "It stays on the list with a cancelled tag and its lines are kept. You can restore it later."(취소 표시로 목록에 남고 라인도 남는다 · 나중에 되살릴 수 있다)
- **Restore**: "It goes back to the state it was in before it was cancelled."
- **Delete** — 한 번도 확정하지 않은 PO 만: "The order and its lines disappear for good."(아주 사라진다)

**IMS 가 거절할 때**

| IMS 의 글(줄임) | 할 일 |
|---|---|
| is closed (receiving finished) — a closed order cannot be cancelled | 크레딧이나 재고 조정으로 바로잡는다 |
| has … receipt line(s) — a received order cannot be cancelled | 같다 · 입고는 일어난 그대로 남는다 |
| was confirmed on … — cancel it instead | **Cancel PO** 를 쓴다 |
| is referenced by … invoice/credit document(s) | 그 라인을 빼거나 그 문서를 먼저 지운다 |
| has … charge allocation(s) | 먼저 비용에서 PO 를 뺀다 |
| has … split document(s) pointing at it | 나뉜 오더를 먼저 정리한다 |

**인보이스 · 크레딧 · 비용**
- **Cancel**: "It stays on the list with a cancelled tag and drops out of the money."(취소 표시로 남고 돈에서 빠진다) **Restore** 로 되살립니다.
- **Delete** — 한 번도 확정하지 않은 인보이스: "The number becomes free for this supplier again."(그 번호를 이 공급처에 다시 쓸 수 있다) 크레딧 노트는 지울 수 없습니다.
- 창고가 그 인보이스로 받기 시작한 뒤에는 다시 열거나 취소할 수 없습니다 — 크레딧 노트를 씁니다.

**결제**
- **Delete** 만 — [공급처 결제](#purch-payments)

<a id="purch-statuses"></a>
## 상태의 뜻
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: all -->

**PO**

| 상태 | 뜻 |
|---|---|
| Draft | 오피스가 쓰고 있다 |
| Ordered | 확정됨 — 공급처가 보내기를 기다림 |
| Receiving | 일부가 왔다 — 나머지가 오는 중 |
| Received | 다 왔다 — 오피스가 마무리(인보이스 · 비용 · 결제 · 완료) |
| Completed | 끝 |
| Cancelled | 취소 |

- 다른 PO 에서 나뉜 PO 에는 "split from PO-…" 가 보입니다.
- 결제 필터: **Unpaid** · **Partly paid** · **Paid**

**인보이스 · 크레딧 · 비용 · 입고**
**Draft** · **Confirmed** · **Cancelled**
필터: 인보이스 — **Invoices** · **Credits** · **Unpaid only** · **Credit due only** · 비용 — **All kinds** · **Not fully allocated**

<a id="purch-csv"></a>
## CSV 내려받기
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office, accounting -->

- 확정한 PO 의 **↓ PO CSV** — 공급처에 보내는 파일([PO 확정하고 보내기](#purch-confirm))
- **Reorder Planner** 의 **↓ CSV**(주문 목록 · 전체 제품 — 공급처 하나 또는 전체) · **↓ Dead Stock CSV** · **↓ Forecast CSV**
- 엑셀에서 SKU 와 바코드는 글자 그대로 열립니다.

<!-- rulings: 88, 92, 99, 389, 391, 396, 400, 550, 606, 607, 616, 621, 691, 692, 697, 704, 707, 709, 711, 713, 714, 715, 719, 720, 723, 725, 732, 733, 734, 735 -->
