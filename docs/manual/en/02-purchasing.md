# 2. Purchasing

<!-- sections 1-13 written (manual-2a · 2b) · sections follow the order of the work, not the order of the screens -->

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
- **보정 Override** (adjustments) on the left — type your own **계절보정** (season) or **트렌드** (trend) for the supplier. Empty uses the automatic value. **Override 초기화** (Reset overrides) clears them.

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

**What it is**
When the supplier's invoice arrives, you enter it against the PO. Confirming it puts the amount owed in the books — and **lets the warehouse receive the goods**.

**How**
1. Open the PO and press **Create an invoice**.
2. Type the **Number** "as printed on the document" (for example 99001), the **Document date**, the **Due date** and the **Printed total** (leave it blank if not known yet).
3. For each line, **On this invoice** starts with what is **Left to bill**. Change it to what the invoice bills. Press **Check**, then **Create**.
4. The invoice opens on **Purchase Invoices & Credits** as a draft. You can **Add a line**, **Add a discount** or **Add lines from a PO**.
5. Press **Confirm** and OK.

**What Confirm does**
"It is then taken into the books: the amount owed appears and the discount reaches cost. Lines can no longer be edited."
It also releases the order to the warehouse. Anything not billed moves to a new order with the next letter, which waits for its own invoice.
- Example: PO-99001 ordered 100. The invoice bills 60. PO-99001 keeps the 60 and the warehouse can receive them. PO-99001a takes the 40 and waits for the next invoice.
- When everything is billed: "The whole order is billed — nothing was split off. The warehouse can receive it now."

**Printed total**
If the **Printed total** is empty, or does not match our calculation, IMS says so first ("⚠ No printed total" or "⚠ The printed total does not match … difference …"). Check the lines, or press OK to confirm anyway.

**Good to know**
- **Reopen** takes a confirmed invoice back to draft. "Quantities that confirming split off go back onto their original order."
- Once the warehouse has received against the invoice, **Reopen** and **Cancel** are grey: "The warehouse has received against this invoice — correct it with a credit note" (see [Supplier credits](#purch-credits)).
- A line can be marked **billed here but settled elsewhere** — for example freight on the invoice that is paid separately.
- The warehouse side: [Receive a PO or a transfer](04-wms.md#wms-receiving).

<!-- SCREENSHOT: purch-invoice-1 · the message after Confirm: PO-99001 keeps what is billed, the rest moved to PO-99001a -->

<a id="purch-documents"></a>
## Upload the supplier's documents
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; charges.html · BUILD 2026-10-24 · chg docs v1 ; ims-podocs.js · BUILD 2026-10-24 · podocs v1 -->
<!-- who: office, accounting -->

**What it is**
At the bottom of a PO and of a charge there is a **Documents** section. Keep the supplier's papers there: invoice, BOL, certificate of origin, packing list, B3 / CAD.

**How**
1. Press **Upload a document**.
2. Choose the kind: **Supplier invoice**, **BOL**, **Certificate of Origin**, **Packing list**, **B3 / CAD** or **Other** ("Other needs a short description").
3. Type the **Document date** and **Document number** if there is one. "The date and number go into the file name in Drive."
4. Choose the file — "PDF, JPEG or PNG · up to 10 MB" — and press **Upload**.

**Good to know**
- Each document shows **Waiting to go to Drive**, **In Drive** or **Drive failed**.
- **Remove** hides a document: "It is hidden here and renamed REMOVED_ in Drive. Nothing is deleted."
- Documents go to the company Google Drive only after an admin switches it on in **Settings**, and only from the start date set there.

<!-- SCREENSHOT: purch-documents-1 · the Documents section on a PO with one document In Drive -->

<a id="purch-charges"></a>
## Freight, duty and other charges
<!-- screen: charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: accounting, office -->

**What it is**
A charge is a bill from someone other than the supplier — freight, duty, brokerage. One container can hold goods for several POs, so one charge is shared across several POs. The charge's amount before tax goes onto the cost of those goods.

**How**
1. On a PO press **Add a charge**, or on **Purchasing ▾** › **Charges** press **New charge**.
2. Fill in **Kind** (**Freight**, **Duty**, **Brokerage**, **Other**), **Billed by**, **Number**, **Charge date**, **Due date**, **Currency**, **Before tax**, **Tax** and **Tax rule**.
3. **Add a purchase order** for every PO the charge covers. Type each PO's share, or press **Spread by amount** to divide the whole total in proportion to the orders.
4. For a charge in another currency, type the exchange rate (CAD per …).
5. Press **Confirm** and OK. "The split is then settled and will be laid down on cost. Amounts and allocations can no longer be edited."

**Good to know**
- "Allocated and Not allocated are before tax — only the amount before tax goes onto the cost of the goods; the tax is owed to the biller but comes back as a tax credit."
- The filter **Not fully allocated** finds charges still to split.
- A share is fixed when you write it. If a PO changes later, its share does not move by itself.

**Watch out**
- Confirm is refused until the shares add up to the charge.
- **Spread by amount** overwrites every share, "including ones you typed".

<!-- SCREENSHOT: purch-charges-1 · a charge spread over two POs with the Not allocated amount at 0 -->

<a id="purch-receipts"></a>
## Receipts in the office
<!-- screen: receiving.html · BUILD 2026-10-22 · rcv latest v1 -->
<!-- who: office -->

**What it is**
**Purchase Receipts** is the office's view of what arrived. The warehouse counts and puts away (see [Receive a PO or a transfer](04-wms.md#wms-receiving) and [Put away](04-wms.md#wms-putaway)). The office posts the stock and settles the differences. It needs the receiving key.

**Post now — stock that cannot wait**
1. On a draft receipt press **Post now…**. "Put what is already counted and in a bin into stock now — the rest is counted later."
2. Only rows with a bin can be posted. Press **Check**, then **Post to stock**.
- A posted row "can no longer be moved or changed here; fix a mistake with a stock adjustment".

**Confirm the receipt**
1. When the warehouse has finished, press **Confirm**.
2. The window says how much is received, how much is already in stock, which lines are short or over, and whether the PO stays open. "This cannot be undone." Press OK.

**Settle the differences**
- **Short** — press **Settle** and choose why:
  - **Split shipment** — the rest is still coming on this PO (it stays open)
  - **Supplier was out of stock** — the rest is not coming
  - **Lost or damaged in transit** — not coming, claim a credit
  - **We counted it wrong** — nothing more to receive
- **More than the invoice, or not on the PO** — the goods are already on a shelf. Press **Decide**: **Accepted — free, into stock at no cost** or **Accepted — billed, into stock at the invoice price**. A return to the supplier is separate work.

**Good to know**
- **Split** moves part of a row to a second bin. The total does not change.
- **Reopen** opens a settled difference again.
- **Delete** removes a draft receipt and what was counted on it. "The purchase order is untouched."

<!-- SCREENSHOT: purch-receipts-1 · a receipt with a short line and the Settle choices -->

<a id="purch-credits"></a>
## Supplier credits
<!-- screen: invoices.html · BUILD 2026-10-22 · inv printed v2 -->
<!-- who: accounting, office -->

**What it is**
A supplier credit note lowers what we owe — for goods that did not come or a price that was wrong.

**How**
1. Open the supplier's invoice and press **Create a credit note**. "The draft arrives already filled with the gap between what was billed and what actually arrived."
2. Check each line and choose the reason: **Not received** or **Price difference**.
3. Type the supplier's credit number and **Credit date**, then press **Confirm**.

**Good to know**
- A confirmed credit can change the cost of the stock. IMS says how much ("Stock cost changed on … lines"), and what waits for the goods to arrive.
- A credit note cannot be deleted. Cancel it instead (see [Cancel, restore or delete](#purch-undo)).
- The filter **Credit due only** shows credits not used up yet.

<a id="purch-payments"></a>
## Pay suppliers
<!-- screen: payments.html · BUILD 2026-10-22 · pay gone v1 -->
<!-- who: accounting -->

**What it is**
**Supplier Payments** records money that left the bank for supplier invoices and charges. One payment can settle several documents in one currency. It needs the purchasing key (write).

**How**
1. Press **To pay** (or **Pay** on a PO, invoice or charge).
2. Set **Paying on**. "Click the invoices and charges this payment settles. A green discount is earned when paid on the date above."
3. Click each document. The first one sets the currency — documents in other currencies turn grey.
4. Check each line's amount and discount. **Paid** is the lines minus the discounts unless you type it.
5. Press **Pay selected**. "Which account did the money leave from?" — choose the **From account** and type the **Reference** (wire ref, cheque number, card).
6. If IMS warns before paying — for example "an early-pay discount was available but not taken" — read it and press OK to pay anyway.

**Discounts**
- **Adjust discount** changes the discount on one document of a payment.
- **Settle with discount** "takes what is still owed as discount, when the supplier let it go".

**Watch out**
- A payment has no cancelled state. **Delete** is "the only way to undo one" — "everything it settled goes back to being owed".
- **✕** on a line takes that document off the payment: "What it was owed goes back to being owed."

<!-- SCREENSHOT: purch-payments-1 · To pay with two invoices picked and a green discount -->

<a id="purch-undo"></a>
## Cancel, restore or delete
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: office -->

**Purchase orders**
- **Cancel PO**: "It stays on the list with a cancelled tag and its lines are kept. You can restore it later."
- **Restore**: "It goes back to the state it was in before it was cancelled."
- **Delete** — only a PO that was never confirmed: "The order and its lines disappear for good."

**When IMS says no**

| IMS says (shortened) | What to do |
|---|---|
| is closed (receiving finished) — a closed order cannot be cancelled | Correct it with a credit or a stock adjustment. |
| has … receipt line(s) — a received order cannot be cancelled | Same. Receipts stay as they happened. |
| was confirmed on … — cancel it instead | Use **Cancel PO**. |
| is referenced by … invoice/credit document(s) | Remove those lines or delete those documents first. |
| has … charge allocation(s) | Remove the PO from the charge first. |
| has … split document(s) pointing at it | Deal with the split order first. |

**Invoices, credits and charges**
- **Cancel**: "It stays on the list with a cancelled tag and drops out of the money." **Restore** brings it back.
- **Delete** — an invoice never confirmed: "The number becomes free for this supplier again." A credit note cannot be deleted.
- After the warehouse has received against an invoice, it cannot be reopened or cancelled — use a credit note.

**Payments**
- **Delete** only — see [Pay suppliers](#purch-payments).

<a id="purch-statuses"></a>
## What each status means
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; invoices.html · BUILD 2026-10-22 · inv printed v2 ; charges.html · BUILD 2026-10-24 · chg docs v1 -->
<!-- who: all -->

**Purchase orders**

| Status | Meaning |
|---|---|
| Draft | The office is writing it. |
| Ordered | Confirmed — waiting for the supplier to send. |
| Receiving | Part has arrived — the rest is still coming. |
| Received | Everything arrived — the office finishes it (invoice · charges · payment · complete). |
| Completed | Done. |
| Cancelled | Cancelled. |

- A PO split off another shows "split from PO-…".
- The payment filter: **Unpaid**, **Partly paid**, **Paid**.

**Invoices, credits, charges and receipts**
**Draft** · **Confirmed** · **Cancelled**.
Filters: invoices — **Invoices**, **Credits**, **Unpaid only**, **Credit due only** · charges — **All kinds**, **Not fully allocated**.

<a id="purch-csv"></a>
## CSV downloads
<!-- screen: po.html · BUILD 2026-10-25 · po csv v1 ; purchasing.html · BUILD 2026-10-22 · pur v1c -->
<!-- who: office, accounting -->

- **↓ PO CSV** on a confirmed PO — the file you send to the supplier (see [Confirm a PO and send it](#purch-confirm)).
- On **Reorder Planner**: **↓ CSV** (the order list or all products, for one supplier or all), **↓ Dead Stock CSV** and **↓ Forecast CSV**.
- SKUs and barcodes open in Excel as text.

<!-- rulings: 88, 92, 99, 389, 391, 396, 400, 550, 606, 607, 616, 621, 691, 692, 697, 704, 707, 709, 711, 713, 714, 715, 719, 720, 723, 725, 732, 733, 734, 735 -->
