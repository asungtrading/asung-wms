# 6. Action Centre

<!-- sections 1-6 written (manual-6) · one section per tab, in the order of the tabs -->
<!-- out of this chapter: the work itself stays in its own chapter — sales orders and customers -> chapter 1 · stock adjustments -> chapter 3 · POS -> chapter 5 -->

<a id="action-start"></a>
## What the Action Centre is
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, sales -->

**What it is**
The **Action Centre** collects things a manager should look at: sales that went out without stock in the books, unpaid pay-now invoices, POS sales not finished, counter orders and new customers. It shows them; the work is done on the usual screens.

**Who**
Everyone who works on sales orders can open it. Managers and above: **Mark checked…** on **Sold without stock**.

**When**
Managers open it once a day.

**How**
1. In IMS mode, press **Action Centre** on the menu (between **Inventory ▾** and **Settings ▾**).
2. Press a tab. The red number on a tab is how many are waiting.
3. **All branches** chooses one branch.
4. Click an order, invoice or customer to open it on its own screen.

**The tabs**
- [Sold without stock](#action-sold-short)
- [Unpaid at hand-over](#action-unpaid)
- [POS not finished](#action-pos)
- [Counter orders](#action-counter)
- [New customers to review](#action-new-customers)

<!-- SCREENSHOT: action-start-1 · Action Centre with the five tabs and their badges -->

<a id="action-sold-short"></a>
## Sold without stock
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**What shows here**
Sales that sold more than the books showed in that branch. "These sold more than the book showed in that branch — the goods were there, the count was not."

- **Not checked yet** — all of them, however old. The tab's red number counts these.
- **Checked** — the last 30 days, with who checked it, when and the note.

Each row shows **Sold on**, **Order**, **Customer**, **SKU**, **Branch**, **Qty short** and **Cost** (**cost unknown** when IMS has no cost for it).

**How**
1. Click the order number. The order opens on **Sales Orders** — this includes POS sales.
2. Count the shelf. Fix the stock the usual way with a stock adjustment (see [Stock adjustments](03-inventory.md#stock-adjustments)).
3. Managers and above: press **Mark checked…** and write what you found ("counted, fixed, reason").

**Good to know**
- "Checking does not change stock." Fix the stock first, then mark it checked.
- A stock adjustment needs the Stock adjustments key. If you do not have it, ask someone who does.
- This is not the same as **Not enough stock** in the warehouse. That one is a picker who could not find the goods (see [WMS Admin](04-wms.md#wms-admin)).

<a id="action-unpaid"></a>
## Unpaid at hand-over
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, accounting -->

**What shows here**
Invoices of customers whose payment term says pay before or on delivery — for example C.B.S or C.O.D — that still have money owed. "The customer's term says pay before or on delivery …, but the goods went out with money still owed."

Each row shows **Invoice**, **Issued** (and how many days ago), **Customer**, **Term**, **Orders**, **Total**, **Paid · credited** and **Still owed**. The oldest is on top.

**How**
1. Click the invoice number. It opens on **Sales Invoices**.
2. Take the payment and record it (see [Customer payments and deposits](01-sales.md#sales-payments)).

**Good to know**
- "It drops off this list once it is paid."
- This tab always shows every branch.

<a id="action-pos"></a>
## POS not finished
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager, sales -->

**What shows here**
POS sales that were confirmed but not finished. "A confirmed POS sale holds its stock until it is finished."

- "not finished — from an earlier day" — these are on top. The tab's red number counts these.
- "today · parked or at the counter" — still being served or parked (see [Park a sale and pick it up again](05-pos.md#pos-park)).

Each row shows **Sale**, **Customer**, **Branch**, **Confirmed** (when and who), **Amount** and **Paid**.

**How**
"Open it on POS to finish it, reopen it, or cancel it on Sales Orders."
1. Click the sale number. It opens on **POS**.
2. Finish it (see [Finish and print the invoice](05-pos.md#pos-finish)), or reopen it and change it.
3. If the customer is not coming back, cancel it on **Sales Orders** (see [Cancel an order](01-sales.md#sales-cancel)).

<a id="action-counter"></a>
## Counter orders
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**What shows here**
Counter orders of the last 30 days. "Counter orders take stock out without going through the warehouse screens — this list is how a manager sees them."

Each row shows **Order**, **Status**, **Ordered**, **Customer**, **Branch** and **Handed over** (when and who).

**How**
- Click the order number to open it on **Sales Orders**. Handing over is described in [Ship & invoice](01-sales.md#sales-ship-invoice).

**Good to know**
- This tab has no red number. It is a list to look through, not a list of things to fix.
- For an order older than 30 days, search on **Sales Orders**.

<a id="action-new-customers"></a>
## New customers to review
<!-- screen: manager-list.html · BUILD 2026-10-25 · ml v1.3 -->
<!-- who: manager -->

**What shows here**
Customers made in IMS that a manager has not reviewed yet. "Customers made by sales start on the default terms (Wholesale · 0% · C.B.S · CAD)."

Each row shows **Customer**, **City**, **Created** (when and who), **Terms now**, **Orders** and **First order**. The oldest is on top.

**How**
1. Press **Open**. The customer opens on **Customers**.
2. Needs the master key: change the terms if needed, and press **Reviewed** › **Mark reviewed** (see [Find or add a customer](01-sales.md#sales-customers)).

**Good to know**
- "Changing a money term counts as reviewed too."
- The customer drops off this list once reviewed.
- **Branch** follows the customer's default warehouse.

<!-- SCREENSHOT: action-new-customers-1 · New customers to review with Terms now and Open -->

<!-- rulings: 152, 165, 240, 709, 713, 714, 715, 719, 720, 723, 725, 732, 735 -->
