# 1. Sales

<!-- skeleton: manual-1a · sections 1-5 manual-1b · 6-10 manual-1b2 · 11-21 manual-1c · sections follow the order of the work, not the order of the screens -->
<!-- out of this chapter: Discount Rules and Issue coupons -> chapter 7 Settings · Finish on POS -> chapter 5 POS · Action Centre -> chapter 6 · counter orders (Hand over — ship and invoice…) stay in this chapter -->

<a id="sales-customers"></a>
## Find or add a customer
<!-- screen: customers.html · BUILD 2026-10-23 · cs v6 -->
<!-- who: sales, office -->

**What it is**
The **Customers** screen (**Sales ▾** › **Customers**) holds every customer: name, price terms, addresses, contacts, stores and order history.

**When**
Before a new order, when a customer calls with a change, or when a new customer buys for the first time.

**How to find a customer**
1. Open **Customers**. Type part of the name in **Search name**.
2. **Active only** is ticked at the start. Untick it to see customers that were turned off.
3. Tick **New — not reviewed** to see only new customers a manager has not checked yet.
4. Click a customer. You see **Price tier**, **Discount %**, **Payment term**, **Currency**, **Bill to**, **Default warehouse**, **Tax rule**, the **Stores** card, **Order history**, **Addresses** and **Contacts**.

**How to add a customer**
1. Press **+ New customer**.
2. Fill in **Name \*** (the only box you must fill), and **Default warehouse**, **Tax number**, **Tags** and **Note** if you know them.
3. Fill in the billing address. Leave **Shipping address is the same** ticked, or untick it and fill in the shipping address.
4. Fill in a contact: **Name**, **Phone**, **Email** and so on. **Marketing email** is **Unknown**, **Opt in** or **Opt out** — choose what the customer told you.
5. Press **Create**.
6. If IMS shows a ⚠ line, read it. For example "1 active customer(s) already have the name …" lists the customers with that name. If the new customer is really someone else, press **Confirm and save**. If it is the same customer, press **Cancel** and use the one that exists.
7. A ✕ line means nothing was saved. Fix what it says and press **Save** again.

**How to change a customer**
1. Open the customer and press **Edit** to change the name, notes, tax number or default warehouse.
2. In **Addresses** or **Contacts**, press **+ Add**, **Edit**, **Make default** or **Remove** on a row.

**Needs the master key**
- New customers start with the standard terms: Wholesale · 0% · C.B.S · CAD. A person with the master key changes them in **Edit** (price tier, discount, payment term, currency, accounts).
- **Reviewed** › **Mark reviewed** clears the "new — not reviewed by a manager" mark.
- **Bill to** › **Change** sends this customer's invoices to another customer.
- **Set parent** makes this customer a store of a head office. On a head office, **+ Add store** opens **Add a store to …**: pick the store, leave **Send its invoices to …** ticked to bill the head office, and press **Add store**. **Detach** takes a store off.
- **Deactivate** turns a customer off. **Activate** turns it back on.

**Managers and above**
- **Backorder emails**: **Turn on** / **Turn off** — whether the customer gets an email when backordered items can ship.
- **Final invoice emails**: **Make automatic** / **Make manual** — whether the invoice PDF is emailed by itself when it is issued.

**Good to know**
- **Split invoice by store** on a head office gives each store its own invoice when several stores ship together. It does not change who is billed.
- **Order history** shows orders in IMS and orders from before IMS.

**Watch out**
- Changing **Bill to** changes new orders only. "Orders already created keep the bill-to they were made with."
- A customer that is turned off cannot get a new order.

<a id="sales-new-order"></a>
## Start a new sales order
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**What it is**
A sales order starts as a **Draft**. You can change everything on a draft. Nothing is reserved in the warehouse yet.

**When**
When a customer orders by phone, by email or in person.

**How**
1. Open **Sales ▾** › **Sales Orders** and press **+ New sales order** (or **+ New** above the narrow list).
2. Type the customer's name in **Search customer by name** and click the customer. Only active customers are listed.
3. Choose the **Channel** (see below) and the **Warehouse**. The warehouse starts as the customer's default warehouse.
4. Press **Create**. The draft opens with its number, for example `SO-99001`.
5. If a ⚠ message appears after **Create**, read it — for example the customer has no shipping address.

**The three channels**
- **Warehouse** — picked and packed in the warehouse. Most orders.
- **Counter** — handed over at the counter. Managers and above: choose **Counter** here, **Confirm** the draft, then press **Hand over — ship and invoice…** when the customer takes the goods.
- **Service** — a service billed on its own, with no goods (for example a prep job). You add its lines with **Add a service** — see [Add lines](#sales-add-lines).

**The top of the draft**
"Tax, price tier, discount and addresses are copied from the customer. You can change them on the draft."
- **Warehouse**, **Order date**, **Required by**, **Reference** (the customer's PO number), **Payment term**, **Price tier**, **Customer discount %**, **Order discount %**, **Coupon**, **Carrier**, **Tax rule**, **Comments** and **Shipping notes** — click a value to change it.
- **Ship to…** changes the delivery address for this order only.
- **Tax rule** starts as **Auto — from ship-to province**.

**Watch out**
- Changing the province or country in **Ship to…** picks the tax rule again from the new address. A tax rule you set by hand is reset.
- The **Order date** decides which deals and coupons count. Change it only when the customer really ordered on another day.

<a id="sales-add-lines"></a>
## Add lines
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**What it is**
Lines are the products on the order. You can pick them one by one, or paste many at once from a spreadsheet.

**How — pick from a list**
1. On a draft, press **Add lines**.
2. Type a SKU, product name or barcode. Click the products you want. They move to the list below.
3. Type the **Qty** for each one.
4. For a free line, choose a reason in **Free?** (**sample**, **promotion**, **replacement** or **other**). **other** needs a **Note**.
5. Press **Check** to see what will happen, then **Add lines**.
- Managers and above: tick **Include sets (cases · packs)** to see case and pack SKUs. Without it, sell a case as its single SKU × the number in the case.

**How — paste from a spreadsheet**
1. Press **Paste lines**.
2. Paste one product per row: SKU, quantity and, if you want, a price. Columns copied from a spreadsheet work as they are. If you type commas between columns, write prices without thousands commas (1250.00, not 1,250.00).
3. Press **Check**. Each row gets a **Verdict**: **ok**, **merged into the existing line**, **not found**, **inactive product**, **no price — confirming is blocked until it gets one**, and so on.
4. Fix the rows that are not ok, press **Check** again, then **Add lines**.

**Prices**
- A line without a price gets the usual price: price tier, then the best discount (see [Discounts, deals and surcharges](#sales-discounts-deals)).
- A price you give is final. The order discount does not apply to that line.
- In the **Lines** table, change **Qty**, **Disc %** or **Unit** in the cell. **↺** puts the system price back. **✕** removes the line.
- **Price from** tells you where the price came from: **customer**, **deal · …**, **set discount**, **discount by hand**, **price set by hand** or **free · …**. Next to a price set by hand you see who set it and when, for example "by Staff C".
- Under the quantity, **available** shows what this warehouse has free now. It turns red when it is less than the quantity.

**Clear lines…**
Press **Clear lines…** to remove every line of a draft at once. The window says how many lines go. Charges stay, and a coupon stays and applies again when lines come back. Press **Remove … lines** to do it.

**Service orders**
On a **Service** draft, press **Add a service**. Choose the **Service**, type **Quantity** and **Unit price**, add a **Description** if you want, and press **Save**. The **Amount** is quantity × unit price.

**Watch out**
- "same SKU at another price — change that line instead": change the line that is already there.
- A combo is changed or removed on its combo line. The component lines under it follow.
- Web orders have no **Clear lines…**.

<a id="sales-discounts-deals"></a>
## Discounts, deals and surcharges
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**What it is**
IMS works out discounts by itself, in two layers.
1. **The line layer.** Each line gets **one** discount: the biggest of the customer's discount, a deal on that product, or the set discount. They are **not added together**.
2. **The order layer.** The whole order gets **one** order discount: the biggest of an order discount rule or a coupon. It comes **on top of** the line layer.

**Example**
Customer A has a customer discount of 10%. A deal gives 15% on product X. The list price of X is $20.00.
- The line gets 15% — the bigger one, not 25%. **Unit** = $17.00. **Price from** shows **deal · …**.
- A coupon gives 5% on the order. The 5% comes off after the line discount: **Net unit** = $16.15.

**Discounts set by hand**
- Type a % in a line's **Disc %** to set it by hand. Clear the box to go back to the system discount.
- A line with a price or discount set by hand gets no order discount. **Net unit** says so.
- Type a % in **Order discount %** to set it by hand. It beats rules and coupons. If a rule later gives more, IMS says "A discount rule now gives more than the order discount % set by hand — clear Order discount % to go back to the rules."

**Reprice**
1. Press **Reprice** to requote every system line with today's rules — order date, tier, customer discount, deals.
2. Lines with a manual price or discount stay as they are.
3. When deals change after the order was made, the button shows as **Reprice ●**. The list filter **Draft — reprice suggested** finds those orders.

**Surcharges**
A surcharge (for example a US tariff) is charged per unit on top of the price and shows as its own line on the invoice.
1. Press **+** in a line's **Surcharge** cell, or tick several lines and press **Set surcharge…**.
2. Type a **Name**, choose **Charge as**: **% of the unit price** or **$ per unit**, and the amount.
3. Press **Save on picked lines**. **Clear on picked lines** takes it off.

**Watch out**
- A surcharge is not part of the order discount. Free lines cannot carry one.
- When an order is divided or split, its order discount is **locked** at what the customer first ordered. Line changes and **Reprice** do not change it.
- Deals and order discount rules are made on the **Discount Rules** screen — see the Settings chapter.

<a id="sales-coupons"></a>
## Use a coupon
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales -->

**What it is**
A coupon is a code that gives an order discount. Each coupon belongs to one customer.

**How**
1. On a draft, type the code in the **Coupon** box and press **Apply**.
2. IMS shows the code with **applied · …%**, or **not used** and the reason.
3. To use another code, type it and press **Replace**.
4. To take the coupon off, press **✕** next to it. The customer can still use it on another order.

**Why a coupon is not used**

| IMS says | What to do |
|---|---|
| the order already gets a bigger discount | Nothing — the bigger discount wins. |
| the order is below the minimum amount of the coupon's deal | Add lines, or leave it. |
| the order discount % was set by hand | Clear **Order discount %** if the coupon should count. |
| it belongs to another customer | Check the customer. |
| it was already used on another order | It cannot be used twice. |
| it expired before the order date | The order date is after the coupon's last day. |
| it was voided · its deal is switched off · its deal no longer takes coupons | Ask your manager. |

**Good to know**
- A coupon counts if the **Order date** is on or before its last day — even when the order is confirmed later.
- The coupon is used up when the order is confirmed. If that order is cancelled or taken back to draft, the coupon can be used again.
- If the coupon is not used when the order is confirmed, IMS takes it off the order and the customer keeps it.

**Watch out**
- Coupons are made on the **Discount Rules** screen — see the Settings chapter.
<a id="sales-confirm"></a>
## Confirm an order
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, manager -->

**What it is**
Confirming turns a draft into a real order. At that moment IMS:
- reserves the stock in the order's warehouse,
- fixes the prices and discounts,
- uses up the coupon,
- moves anything it cannot reserve into a new order of its own — a **backorder** order or a **pre-order** order.

**When**
When the customer's order is final.

**How — Managers and above**
1. On a draft, press **Confirm…**. The window **Confirm SO-99001 — preview** opens. Nothing is saved yet.
2. Read each line: **Ordered**, **Result**, **Reserved**, **Backorder**, **Preorder**.
3. Tick **Preorder?** on a line that should wait as a pre-order — a promise to ship when the stock comes.
4. Tick **Confirm on hold — do not reserve stock for the whole order** when the order must wait (see [Hold](#sales-release)).
5. Press **Confirm**. If there is nothing to report, the window closes by itself. Otherwise it says "Confirmed — check the result above, then Close."

**Result words**

| Result | Meaning |
|---|---|
| allocated | The whole line is reserved. |
| partial | Part of the line is reserved. The rest moves to a backorder order. |
| backorder | Nothing could be reserved. The line moves to a backorder order. |
| preorder | The line moves to a pre-order order. |
| hold | The order was confirmed on hold. Nothing is reserved. |

**Example**
SO-99001 for Customer A asks for 30 of product X. The warehouse has 18 free.
- **Reserved** 18 · **Backorder** 12.
- The window says "Split off: SO-99001b backorder (1 line)".
- SO-99001 keeps the 18 and can go to the warehouse. SO-99001b holds the 12 and waits on the **Backorders** screen.

**Good to know**
- **Taken over backorders.** When you confirm a new order, IMS closes older open backorders of the same customer for the same product, oldest first. The window lists them under "Backorders taken over from earlier orders". The new order now carries that demand.
- A line with **no price** blocks confirming. Give it a price first.
- Staff without the manager role do not see **Confirm…**. Ask your manager to confirm.
- **Counter orders** — Managers and above: press **Confirm** on a counter draft. "Every line is reserved as it is — counter orders never split or backorder."
- **Service orders** — anyone who works on sales orders presses **Confirm** on a service draft. The invoice is then issued with **Invoice…** (see [Ship & invoice](#sales-ship-invoice)).

<!-- SCREENSHOT: sales-confirm-1 · Confirm preview window with Reserved, Backorder, Preorder columns and the "Split off" line -->

<a id="sales-release"></a>
## Send an order to the warehouse
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->

**What it is**
**Release to WMS** sends a confirmed order to the warehouse. It appears on the warehouse manager's **Split & Waves** screen. Its status becomes **Released to WMS**, then **Working** when picking starts.

**How**
1. Open a confirmed warehouse order.
2. Press **Release to WMS**. There is no question window — you can still take it back with **Recall from WMS** (see [Take an order back](#sales-undo)).

**When the button is grey**
Point at it to see why:
- "Release the hold first — an order on hold cannot go to the warehouse"
- "Proceed or clear the backorder / preorder lines first" — a backorder or pre-order order goes to the warehouse only after its stock is reserved (see [Backorders](#sales-backorders)).

**Hold — Managers and above**
A hold releases the order's reserved stock for other orders and keeps the order waiting.
1. On a confirmed order with reserved stock, press **Hold**.
2. IMS asks: "Put SO-99001 on hold? Reserved stock is released for other orders; the lines stay on the order. Release the hold later to reserve again." Press OK.
3. To end the hold, press **Release hold**. IMS reserves again as far as stock allows. The window **Hold released — SO-99001** shows the result. Whatever is short becomes a backorder order.

**Watch out**
- A hold is for the whole order, never one line.
- After **Release hold** you may get less than before — other orders may have taken the stock.

<!-- SCREENSHOT: sales-release-1 · a confirmed order with Release to WMS greyed and its reason showing -->

<a id="sales-undo"></a>
## Take an order back
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office, manager -->

**What it is**
Each step can be taken back one step at a time: from the warehouse to **Confirmed**, and from **Confirmed** to **Draft**.

**Recall from WMS**
1. On an order that is **Released to WMS**, press **Recall from WMS**.
2. IMS asks: "Recall SO-99001 from the warehouse? It goes back to Confirmed and leaves the WMS Split screen." Press OK.
- Once the warehouse starts (**Working**), the button is grey: "The warehouse is working on it — ask the warehouse manager to send it back first".

**Delete draft**
1. On a draft, press **Delete draft**.
2. IMS asks: "Delete draft SO-99001? It has never been confirmed, so it disappears — the number is not reused." Press OK.

**Unconfirm — Supervisors and admins**
1. On a confirmed order still in IMS, press **Unconfirm**.
2. IMS asks: "Unconfirm SO-99001? Reserved stock is released and split-off backorder/preorder orders come back into this one (supervisor)." Press OK.
3. The order is a draft again. Its backorder and pre-order orders from that confirmation (for example SO-99001b) are back inside it. Backorder lines it had taken over from older orders are reopened, and IMS says how many.
- A coupon used by the order can be used again.
- A confirmed service order goes back to draft the same way.

**When Unconfirm says no**

| IMS says (shortened) | What to do |
|---|---|
| only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) | Recall it, or ask the warehouse to roll it back first. |
| was itself split off at confirmation — unconfirm the original order … instead | Unconfirm the original (SO-99001, not SO-99001b). |
| has a hand-made split order … (cancel or merge it first) | Deal with the divided order first. |
| was split again after confirmation | Unconfirm only undoes the split made at confirmation. |
| Split order … was changed after the split | It is no longer possible — cancel or change the orders instead. |

**Counter orders — Managers and above**
Press **Reopen as draft**. "Reserved stock is released."

**Watch out**
- To close an order for good, see [Cancel an order](#sales-cancel).

<a id="sales-divide-merge"></a>
## Divide or merge orders
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->

**Divide — Managers and above**
Use it when part of an order should go on its own — for example Customer A wants 10 of the 30 boxes now and the rest next week.
1. On a confirmed order, press **Divide…**.
2. In **Move**, type how much of each line goes to the new order — a whole line or part of it.
3. Press **Check**, read the result, then press **Divide**. IMS shows "New order: …".
- The reserved stock goes with the lines. The new order keeps the same header (customer, terms, addresses).
- A combo moves in whole combos.

**Merge**
Use it when the customer sent several orders that should ship as one.
1. On a draft, press **Merge…**. The window lists the warehouse orders of the same customer, warehouse and currency that are still draft or confirmed.
2. Tick two or more and press **Preview**.
3. Read **Orders**, **Header from**, **Order date** and the lines, then press **Merge**. A **new draft** opens.

What a merge does:
- The header comes from the oldest order. Where headers differed, the window shows it — change it on the new draft.
- The **Order date** is the day of the merge.
- Line prices stay as they were, marked as set by hand. If today's price would be better, the window says so — change the line if you want.
- Freight does not move — add it again. Deposits move to the new order.
- The old orders close as merged. There is no undo.
- The new order is a draft, so nothing is reserved. **Confirm** it again to reserve the stock.

**Merge — Managers and above**
- An order that is already confirmed can be merged only by a manager ("A confirmed order is included — a manager has to do this merge.").
- On a confirmed order the **Merge…** button shows only to managers.

**Change warehouse — Managers and above**
1. On a confirmed order that has not gone to the warehouse, press **Change warehouse…**.
2. Choose **Move to** and press **Preview**, then **Change warehouse**.
- "Reservations here are released and taken again in the new warehouse. Whatever it does not have becomes a backorder order."

**Watch out**
- An order with an open backorder cannot be merged. Proceed the backorder first (see [Backorders](#sales-backorders)), then merge.

<!-- SCREENSHOT: sales-divide-merge-1 · Merge preview: Orders, Header from, Order date and the line list -->

<a id="sales-backorders"></a>
## Backorders
<!-- screen: so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: sales, office -->

**What it is**
A backorder is what a customer ordered but we could not reserve when the order was confirmed. It waits in its own order (for example SO-99001b) until the stock comes in. A pre-order waits the same way.
**Sales ▾** › **Backorders** has four tabs: **Arrivals** (opens first), **Insights**, **All backorders** and **Emails**.

**Arrivals**
- **Ready to ship now** at the top lists backorders that can ship from stock right now.
- Below it is the stock that came in and the customers waiting for it. Customers of the same branch come first. **Other branches** are grey — move the stock or the order's warehouse first.

**Proceed — Managers and above**
1. Press **proceed** on a row (on **Arrivals** or **All backorders**), or **Proceed backorder…** on the order itself.
2. The window **Proceed SO-99001b — reserve stock that is here now** shows **Reserved** and **Still backordered**. Press **Proceed**.
- Proceed works on the whole order — its other backorder lines are reserved too, as far as stock allows.
- After that the order can be sent with **Release to WMS**.

**All backorders**
Every backorder and pre-order line. Filter by **Open**, **Ended (backorders)** or **All**, by customer, supplier, brand, SKU, **Arrived since** and dates. **↓ CSV** downloads what the filters show.

**Insights**
How much we lose to backorders (**Lost sales**) and which SKUs keep missing. Click a SKU to see its orders.
- Managers and above: **mark…** takes a lost sale out of the count when it was not real demand (**Staff error**, **Duplicate entry**, **Test**, **Other**). **unmark** puts it back.

**Emails**
Arrival emails to customers, one run per branch on each scheduled morning. **Only runs with a problem** shows what needs a check.
- Managers and above: on an email that needs a check, **Close as sent**, **Send again** or **Cancel**.
- Whether a customer gets these emails is set on the customer — see [Find or add a customer](#sales-customers).

**How a backorder ends**

| Ended | Meaning |
|---|---|
| Taken over by a new order | The customer ordered the same product again and that order was confirmed. |
| Proceeded (stock reserved) | Stock came and a manager proceeded it. |
| Expired | 90 days after the original order date, nobody proceeded it. |
| Cancelled | Someone cancelled it. |
| Merged | It was merged into another order. |

**Watch out**
- Expiry counts from the **original** order date, not from the day it split.
- A backorder of a free line (for example a replacement) never expires and is never taken over. It ends only when it is proceeded or cancelled.

<!-- SCREENSHOT: sales-backorders-1 · Arrivals tab: Ready to ship now and the waiting customers under one arrival -->

<a id="sales-charges"></a>
## Shipping fees and other charges
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-ship-invoice"></a>
## Ship & invoice
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-pickup"></a>
## Pickup orders and tracking
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office, warehouse -->
<!-- TODO manual-1c -->

<a id="sales-print-email"></a>
## Print and email
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-invoices"></a>
## Sales invoices
<!-- screen: so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office, accounting -->
<!-- TODO manual-1c -->

<a id="sales-payments"></a>
## Customer payments and deposits
<!-- screen: so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: accounting, office -->
<!-- TODO manual-1c -->

<a id="sales-credits"></a>
## Credit notes
<!-- screen: so-credits.html · BUILD 2026-10-23 · cr v5 -->
<!-- who: accounting, office -->
<!-- TODO manual-1c -->

<a id="sales-web-orders"></a>
## Web orders
<!-- screen: shopify-orders.html · BUILD 2026-10-14 · wo v4d -->
<!-- who: office -->
<!-- TODO manual-1c -->

<a id="sales-cancel"></a>
## Cancel an order
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, manager -->
<!-- TODO manual-1c -->

<a id="sales-statuses"></a>
## What each status means
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: all -->
<!-- note for 1b: two columns — badge (Released to WMS, Working, Finalized, Invoice cancelled …) and filter (With warehouse, Finalized — waiting for the office, Waiting for pickup …) -->
<!-- TODO manual-1c -->

<a id="sales-csv"></a>
## CSV downloads
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 ; so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so-credits.html · BUILD 2026-10-23 · cr v5 ; so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: office, accounting -->
<!-- TODO manual-1c -->

<!-- rulings: 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 484, 488, 489, 490, 507, 514, 516, 517, 529, 532, 541, 545, 546, 590, 709, 713, 714, 715, 719, 720, 723 -->
