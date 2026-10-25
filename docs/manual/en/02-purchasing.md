# 2. Purchasing

<!-- sections 1-13 · manual-2a writes purch-suppliers, purch-reorder, purch-new-po, purch-confirm · the rest manual-2b · sections follow the order of the work, not the order of the screens -->

<a id="purch-suppliers"></a>
## Find or add a supplier
<!-- screen: suppliers.html · BUILD 2026-10-25 · sup v3c -->
<!-- who: office -->

**What it is**
**Suppliers** (**Purchasing ▾** › **Suppliers**) holds every supplier: terms, addresses, contacts, discounts and purchase history.

**How to find a supplier**
1. Open **Suppliers** and type part of the name.
2. The filter **Purchasable** starts on **Yes** — the suppliers we buy from. Choose **All** to see the others.
3. Click a supplier. You see its terms, **Purchase history**, **Addresses**, **Contacts** and **Discounts**.

**How to add a supplier**
1. Press **+ New supplier**.
2. Fill in **Name \*** and the terms you know: **Currency**, **Payment term**, **Tax rule**, **Account payable**, **Type**.
3. Add the address and a contact.
4. Press **Create**.

**How to change a supplier**
1. Press **Edit** to change the name, terms or notes.
2. In **Addresses** or **Contacts**, press **+ Add**, **Edit**, **Make default** or **Remove** on a row.
3. **Purchasable** (**Yes**, **No** or **Not set**) says whether we still buy from this supplier. It saves as soon as you change it.

**Needs the master key**
- **Deactivate** / **Activate** turns a supplier off or on.
- **Discounts** — the supplier's standing discounts (**Seq**, **Name**, **Percent**). They apply to new purchase orders from this supplier.

**Good to know**
- **Purchase history** lists this supplier's orders, newest first. Press **Show … more** for older ones.
- People without the purchasing or master key see only active suppliers we buy from.

<a id="purch-reorder"></a>
## Decide what to order (Reorder Planner)
<!-- screen: purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office -->

**What it is**
**Reorder Planner** (**Purchasing ▾** › **Reorder Planner**) works out how much of each product to order from a supplier, from sales, stock, stock on order and backorders. It then makes a draft PO for you.
Most of its words are in Korean. This manual gives the screen word and its meaning, for example **발주 추천** (Order suggestions).

**Before you start — connect Google**
Sales before 2026-11-01 are read from the company's sales history. If you see "🔑 지난 판매 이력 … 연결해야 추천 발주가 계산됩니다" (connect your company Google account to calculate suggestions), press **Google 연결 →** (Connect Google) and sign in with your company Google account. Without it, no suggestion is calculated.

**How**
1. Choose the branch at the top: **TOR**, **EDM** or **합산** (both together).
2. On the left, search the supplier in **Supplier 검색...** (Search supplier) and pick it.
3. Check the supplier's settings on the left: **Lead Time**, **발주주기** (order cycle) and **목표 재고** (target stock, in days). IMS keeps them for the next time.
4. On the **발주 추천** (Order suggestions) tab, each product shows **일판매량** (daily sales), **재고일수** (days of stock), **Available** and **추천발주** (suggested quantity).
5. Tap a suggested quantity to copy it into **실발주량** (order quantity), or type your own. Press **전체 추천 적용** (Apply all suggestions) to copy every suggestion at once.
6. Press **→ IMS 발주 초안** (Create IMS draft PO). It asks "…개 SKU를 IMS 발주 초안(draft PO)으로 만들까요?" (make a draft PO with these SKUs?). Press OK.
7. The draft PO is made, for example PO-99001. Open it to check it (see [Start a PO](#purch-new-po)).

**What goes into the draft**
- Only products with an order quantity above 0. Clear a quantity to 0 to leave a product out.
- Only what the current filter and search show.
- Price: the fixed price for this supplier, otherwise the latest price, otherwise 0 (with a warning).
- Warehouse: **TOR** → Toronto · **EDM** → Edmonton · **합산** → Toronto.

**The other tabs**
- **데드 스톡** (Dead stock) — products that have not sold for a long time.
- **Forecast** — expected sales for the next 30, 60 or 90 days.
- **📦 입고 검증** (Receiving check) and **📊 Supplier 분석** (Supplier analysis) — past receiving and supplier performance.

**Good to know**
- A draft "has no effect on stock or accounts". You confirm it on **Purchase Orders**.
- **↓ CSV** downloads the order list or all products, for one supplier or all.
- Needs the master key: changing a product's fixed supplier price (💲).

<!-- SCREENSHOT: purch-reorder-1 · Order suggestions tab with a supplier picked, 추천발주 and 실발주량 columns, and the → IMS 발주 초안 button -->

<a id="purch-new-po"></a>
## Start a PO
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->

**What it is**
A purchase order (PO) is what we order from one supplier. It starts as a **Draft**.

**How**
1. Open **Purchasing ▾** › **Purchase Orders** and press **+ New purchase order**. (A draft from the Reorder Planner is already here.)
2. "New purchase order — pick a supplier": search and click the supplier. Tick **Show all (including not-purchasable)** to see the others.
3. The draft opens with its number, for example PO-99001. If IMS warns "no ship-to warehouse — pick one", set **Ship to**.
4. Add lines:
   - **Add a line** — search by "SKU · supplier SKU · product name" (only this supplier's products), type the quantity, press **Check**, then **Add lines**.
   - **Paste lines** — one per row: SKU, quantity, price (optional). "Tab, comma or two spaces — any of them works." "A price you give is the unit price before the PO discount." Press **Check**, then **Add lines**.
5. Check the top: **Order date**, **Required by**, **Payment term**, **Ship to**, **Currency**, **Tax rule** and **Note** (internal).
6. **Add a discount** adds a discount for the whole PO (**Name**, **Percent**).

**Good to know**
- Each line shows **Supplier SKU**, **Qty**, **Unit price**, **Amount**, **Received** and **Remaining**. **✕** removes a line.
- Several discounts are not added together — they apply one after the other.
- A person with purchasing at **read** can look at POs but cannot save anything.

**Watch out**
- A draft can be deleted (**Delete**). "The number … is not given to another order — it stays empty."

<a id="purch-confirm"></a>
## Confirm a PO and send it
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->

**What it is**
**Confirm** means the lines and quantities to order are settled. It does not lock the PO and it does not send anything. You can still change lines after confirming — for example after a call with the supplier.

**How**
1. On a draft, press **Confirm** and OK. The status becomes **Ordered** — "Confirmed — waiting for the supplier to send".
2. Press **↓ PO CSV**. A spreadsheet downloads with the PO, supplier, order date, required date, currency and payment term, then each line: **Line**, **SKU**, **Supplier SKU**, **Barcode**, **Product**, **Qty**, **Unit price**, **Amount**, and the discounts and totals.
3. Attach the file to an email to the supplier and send it. IMS does not send the email.

**Good to know**
- **↓ PO CSV** appears once the PO is confirmed (not on a draft or a cancelled PO).
- The internal **Note** is not in the file.
- In Excel, SKUs and barcodes open as text, exactly as they are.

**Watch out**
- If you change lines after sending, download **↓ PO CSV** again and send the new file.

<!-- SCREENSHOT: purch-confirm-1 · a confirmed PO with the Ordered status and the ↓ PO CSV button -->

<a id="purch-invoice"></a>
## Record the supplier's invoice
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 ; po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-documents"></a>
## Upload the supplier's documents
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: office, accounting -->
<!-- TODO manual-2b -->

<a id="purch-charges"></a>
## Freight, duty and other charges
<!-- screen: charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-receipts"></a>
## Receipts in the office
<!-- screen: receiving.html · BUILD 2026-10-22 · rcv latest v1 -->
<!-- who: office -->
<!-- TODO manual-2b -->

<a id="purch-credits"></a>
## Supplier credits
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 -->
<!-- who: accounting, office -->
<!-- TODO manual-2b -->

<a id="purch-payments"></a>
## Pay suppliers
<!-- screen: payments.html · BUILD 2026-10-22 · pay gone v1 -->
<!-- who: accounting -->
<!-- TODO manual-2b -->

<a id="purch-undo"></a>
## Cancel, restore or delete
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: office -->
<!-- TODO manual-2b -->

<a id="purch-statuses"></a>
## What each status means
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 -->
<!-- who: all -->
<!-- TODO manual-2b -->

<a id="purch-csv"></a>
## CSV downloads
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office, accounting -->
<!-- TODO manual-2b -->

<!-- rulings: 88, 606, 607, 616, 709, 711, 713, 714, 715, 719, 720, 723, 725, 732, 733 -->
