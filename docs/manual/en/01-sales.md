# 1. Sales

<!-- sections 1-21 written (manual-1a ~ 1d) · sections follow the order of the work, not the order of the screens -->
<!-- out of this chapter: Discount Rules and Issue coupons -> chapter 7 Settings · Park -> chapter 5 POS · Action Centre -> chapter 6 · counter orders (Hand over — ship and invoice…) stay in this chapter -->

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
3. Tick **New — not reviewed** to see only new customers a manager has not checked yet. They also show on the [Action Centre](06-action-centre.md#action-new-customers).
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
- Under the quantity, **available** shows what this warehouse has free now. It turns red when it is less than the quantity (see [Find stock](03-inventory.md#stock-availability)).

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
- Deals and order discount rules are made on the **Discount Rules** screen — see [Discount rules and deals](07-settings.md#set-deals).

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
- Coupons are made on the **Discount Rules** screen — see [Coupons](07-settings.md#set-coupons).
<a id="sales-confirm"></a>
## Confirm an order
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
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
| Reserved | The whole line is reserved. |
| Partly reserved | Part of the line is reserved. The rest moves to a backorder order. |
| Backordered | Nothing could be reserved. The line moves to a backorder order. |
| Preorder | The line moves to a pre-order order. |
| On hold | The order was confirmed on hold. Nothing is reserved. |

**Example**
SO-99001 for Customer A asks for 30 of product X. The warehouse has 18 free.
- **Reserved** 18 · **Backorder** 12.
- The window says "Split off: SO-99001a backorder (1 line)".
- SO-99001 keeps the 18 and can go to the warehouse. SO-99001a holds the 12 and waits on the **Backorders** screen.

**Good to know**
- **Taken over backorders.** When you confirm a new order, IMS closes older open backorders of the same customer for the same product, oldest first. The window lists them under "Backorders taken over from earlier orders". The new order now carries that demand.
- A line with **no price** blocks confirming. Give it a price first.
- Staff without the manager role do not see **Confirm…**. Ask your manager to confirm.
- **Counter orders** — Managers and above: press **Confirm** on a counter draft. "Every line is reserved as it is — counter orders never split or backorder."
- **Service orders** — anyone who works on sales orders presses **Confirm** on a service draft. The invoice is then issued with **Invoice…** (see [Ship & invoice](#sales-ship-invoice)).

<!-- SCREENSHOT: sales-confirm-1 · Confirm preview window with Reserved, Backorder, Preorder columns and the "Split off" line -->

<a id="sales-release"></a>
## Send an order to the warehouse
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: sales, office -->

**What it is**
**Release to WMS** sends a confirmed order to the warehouse. It appears on the warehouse manager's **Split & Waves** screen (see [Split orders into batches and waves](04-wms.md#wms-waves)). Its status becomes **Released to WMS**, then **Working** when picking starts.

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
- Once the warehouse starts (**Working**), the button is grey: "The warehouse is working on it — ask the warehouse manager to send it back first" (see [WMS Admin](04-wms.md#wms-admin)).

**Delete draft**
1. On a draft, press **Delete draft**.
2. IMS asks: "Delete draft SO-99001? It has never been confirmed, so it disappears — the number is not reused." Press OK.

**Unconfirm — Supervisors and admins**
1. On a confirmed order still in IMS, press **Unconfirm**.
2. IMS asks: "Unconfirm SO-99001? Reserved stock is released and split-off backorder/preorder orders come back into this one (supervisor)." Press OK.
3. The order is a draft again. Its backorder and pre-order orders from that confirmation (for example SO-99001a) are back inside it. Backorder lines it had taken over from older orders are reopened, and IMS says how many.
- A coupon used by the order can be used again.
- A confirmed service order goes back to draft the same way.

**When Unconfirm says no**

| IMS says (shortened) | What to do |
|---|---|
| only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) | Recall it, or ask the warehouse to roll it back first. |
| was itself split off at confirmation — unconfirm the original order … instead | Unconfirm the original (SO-99001, not SO-99001a). |
| has a hand-made split order … (cancel or merge it first) | Deal with the divided order first. |
| was split again after confirmation | Unconfirm only undoes the split made at confirmation. |
| Split order … was changed after the split | It is no longer possible — cancel or change the orders instead. |

**Counter orders — Managers and above**
Press **Reopen as draft**. "Reserved stock is released."

**Watch out**
- To close an order for good, see [Cancel an order](#sales-cancel).

<a id="sales-divide-merge"></a>
## Divide or merge orders
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
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
A backorder is what a customer ordered but we could not reserve when the order was confirmed. It waits in its own order (for example SO-99001a) until the stock comes in. A pre-order waits the same way.
Shortages found in the warehouse become backorders too — see [When an item is short](04-wms.md#wms-pick-short).
**Sales ▾** › **Backorders** has four tabs: **Arrivals** (opens first), **Insights**, **All backorders** and **Emails**.

**Arrivals**
- **Ready to ship now** at the top lists backorders that can ship from stock right now.
- Below it is the stock that came in and the customers waiting for it. Customers of the same branch come first. **Other branches** are grey — move the stock or the order's warehouse first.

**Proceed — Managers and above**
1. Press **proceed** on a row (on **Arrivals** or **All backorders**), or **Proceed backorder…** on the order itself.
2. The window **Proceed SO-99001a — reserve stock that is here now** shows **Reserved** and **Still backordered**. Press **Proceed**.
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
- A pre-order never expires and is never taken over either. It waits until it is proceeded or cancelled.

<!-- SCREENSHOT: sales-backorders-1 · Arrivals tab: Ready to ship now and the waiting customers under one arrival -->

<a id="sales-charges"></a>
## Shipping fees and other charges
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office -->

**What it is**
A charge is an amount-only line on the order — freight, a packing fee and so on. It goes on the invoice under the products.

**When**
Freight is usually added at **Ship & invoice**, when you know the real cost. Add it earlier when the customer agreed a price in advance.

**How**
1. On a draft, press **Add a charge**.
2. **Name** starts as "Freight". Change it if this is another kind of charge.
3. Type the **Amount** (0 or more).
4. **Discount**: **none**, **%** or **$**, and the number.
5. **Description** if you want, and the **Account**. A new charge starts on **_99_** (freight sales). Pick another account when the charge is not freight.
6. Press **Save**. **✎** changes a charge, **✕** removes it.

**After packing — needs the master key too**
On a **Finalized** order, a person who works on sales orders **and** has the master key can still press **Add a charge** (for example a packing fee). "The charge goes on the invoice when you Ship & invoice — the Ship & invoice window shows it."

**Good to know**
- Before **Ship & invoice**, freight on a warehouse order shows the tag **estimate**: "Before Ship & invoice the freight is an estimate — Ship & invoice updates this line with the actual freight".
- "Tax follows the order's tax rule."
- A discount shows as its own line on the invoice — freight and freight discount are kept apart.

**Watch out**
- "A charge cannot be negative — money back is a credit note."
- Some web orders already paid their freight at checkout. **Add a charge** is not offered on those after packing.

<a id="sales-ship-invoice"></a>
## Ship & invoice
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office -->

**What it is**
When the warehouse finishes an order, its status is **Finalized**. The office then presses **Ship & invoice**: the goods leave the books and the invoice is issued, in one step.

**When**
As soon as a **Finalized** order is ready to go — freight quoted, carrier chosen.

**How — one order**
1. Open the **Finalized** order and press **Ship & invoice…**.
2. At the top, **What the warehouse packed** lists each pallet or box with size and weight — use it for the freight quote (see [Fulfillment](04-wms.md#wms-fulfillment)). "⚠ … unit(s) have no dimensions — ask the warehouse before quoting freight."
3. Freight: change the amount of a charge already on the order to the real freight, or type **Freight amount** for a new line. Empty means no freight line.
4. Choose the **Carrier** and type the **Tracking number** (several boxes: separate with commas). Add **Shipping notes** if needed.
5. Press **Preview**. Read **What will happen**: for each line **Ordered**, **Ships** and **Short**, the charges, and the invoice.
6. Press **Ship & invoice** and confirm. This cannot be undone here.
7. The result shows **Invoice**, **Amount due** and **Still owed**, with **Print invoice** and **Email invoice…** buttons.

**Several orders on one invoice**
1. In the same window, open **Other packed orders for …** — finalized orders of the same bill-to and currency (up to 30).
2. Tick the orders that ship together. Each one gets its own freight, carrier, tracking number and notes.
3. **Preview**, then **Ship & invoice**. "Orders invoiced together go on one invoice for this bill-to (or one per store, if the customer is set to split by store)."

**Carrier types**
- A carrier: "A tracking number is needed."
- **Pickup**: "the customer collects it. No tracking number." See [Pickup orders and tracking](#sales-pickup).
- **Delivery** (our truck): no tracking number.

**Counter orders — Managers and above**
1. On a confirmed counter order, press **Hand over — ship and invoice…**.
2. The window shows each line, the bin it comes from and the totals: **Invoice total**, **Paid for this order**, **Credit / balance used**, **Amount due**.
3. Press **Ship and invoice**. "Nothing blocks the hand-over — whatever is not paid stays as an unpaid invoice."

**Good to know**
- Packed less than ordered: "the rest goes to a backorder order" (see [When an item is short](04-wms.md#wms-pick-short)).
- **Put back to the shelf**: a combo ships whole or not at all. If a combo cannot go complete, the list shows the extra components to put back in their bins.
- Payments already taken for an order attach themselves to its invoice.
- If something in the window changes after **Preview**, press **Preview** again.

**Watch out — the customer wants to take items off a packed order**
1. Ship & invoice the order as usual. The invoice shows the packed quantity.
2. Managers and above: make a credit note from that invoice for the quantity taken off. For each line set **Back to stock** to **to bin** and keep the bin where the goods sit. For **Reason** choose **Other** and write in **Note** that the customer took it off before shipping. See [Credit notes](#sales-credits).
3. The goods never left the warehouse — leave them on the shelf.
- Example: 30 packed, the customer takes off 5 → invoice 30 · credit note 5 · shipped 25. The stock matches what really left, and the customer gets two documents: the invoice and the credit note.
- If the customer's **Final invoice emails** is automatic, the invoice is emailed first. Tell the customer in advance.

<!-- SCREENSHOT: sales-ship-invoice-1 · Ship & invoice window with freight, carrier, tracking and "Other packed orders for …" open -->

<a id="sales-pickup"></a>
## Pickup orders and tracking
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: office, warehouse -->

**What it is**
An order shipped with the carrier **Pickup** waits for the customer. Its tag is **waiting for pickup** until they take it.

**How — the customer took it**
1. Find the order. The list filter **Waiting for pickup** shows all of them.
2. Press **Picked up**.
3. IMS asks "Mark SO-99001 as picked up by the customer? … This cannot be undone here." Press OK. The tag becomes **picked up**.
- On a web order, Shopify is told too — no email to the customer.

**How — fix a carrier or tracking number**
1. On a shipped order sent by a carrier, press **Fix tracking…**.
2. Change **Carrier** or **Tracking number** (several boxes: separate with commas).
3. Press **Preview**, then **Save**.
- On a web order, Shopify is updated too — no email to the customer.

**Watch out**
- **Pickup** and **Delivery** have no tracking number. The box is locked when you choose them.
- **Fix tracking…** changes the carrier name and the tracking numbers only. It cannot turn a carrier order into a pickup.

<a id="sales-print-email"></a>
## Print and email
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office -->

**What it is**
Each document prints with the layout in use, or goes by email with its PDF attached.

| Document | Where | Buttons |
|---|---|---|
| Sales order | An open order with no invoice yet | **Print order** · **Email order…** |
| Ship Ready (PROFORMA) | Inside the **Ship & invoice** window, after **Preview** | **Ship Ready (proforma)** · **Email Ship Ready…** |
| Invoice | After **Ship & invoice**, and on **Sales Invoices** | **Print invoice** · **Email invoice…** / **Email to customer…** |
| Delivery receipt | **Sales Invoices** | **Print delivery receipt** |

**How — print**
1. Press the print button. The document opens ready to print or to save as PDF.

**How — email**
1. Press the email button. The window shows who it is **From**, and **To**, **Subject** and **Message** filled in.
2. Change them if you want. "The PDF of this … is attached, made with the layout in use."
3. Press **Send**. "The email goes out within a minute or two."

**Ship Ready**
- It shows what will ship and the money, before the invoice exists. Press **Preview** in the **Ship & invoice** window first — it prints exactly what the preview shows.
- One page set per invoice group. Nothing is saved when you print it.
- **Email Ship Ready…** works only when the preview makes one invoice: "One email carries one PDF — with more than one invoice, print the Ship Ready instead".

**Invoice note**
On **Sales Invoices**, press **Edit** next to **Note**. "Note on the document (customers see it)". It prints on the invoice. "Up to 2,000 characters. Leave it empty to remove the note."

**Automatic invoice emails**
When a customer's **Final invoice emails** is **automatic** (see [Find or add a customer](#sales-customers)), the invoice PDF is emailed when the invoice is issued. You can still send another one by hand.

**Good to know**
- The invoice's **Emails** section shows every email: when, to whom, status (**waiting to send**, **sent**, **failed** …) and who sent it — or "automatic".
- An email still waiting can be stopped with **Cancel**. A reason is required.
- The delivery receipt is for local deliveries — the driver gets it signed. It is not emailed.

<a id="sales-invoices"></a>
## Sales invoices
<!-- screen: so-invoices.html · BUILD 2026-10-22 · inv csv v5 -->
<!-- who: office, accounting -->

**What it is**
**Sales ▾** › **Sales Invoices** lists every invoice. One invoice can hold several orders of the same bill-to. Invoice numbers look like `99001`.

**How to find an invoice**
1. Search by "Invoice · customer · SO number · reference".
2. Filter by state: **Open — still owed**, **Overdue**, **Open with no due date**, **Paid in full**, **Cancelled**, **All** — and by issue date.
3. Click an invoice. You see **Bill to**, **Issued**, **Due**, **Currency**, **Orders** (click one to open it), the lines, **Payments**, **Credits applied** and **Emails**.

**Cancel invoice… — Managers and above**
Cancel only when the whole document is wrong. For part of it, make a credit note instead.
1. Press **Cancel invoice…**.
2. IMS asks: "Cancel invoice 99001? Its orders go back to shipped and wait for a new invoice." Type the reason (required) and press OK.
3. The orders show **Invoice cancelled**. The goods stay shipped.

**When Cancel says no**
- "… payment allocation(s) applied by hand — detach them first (or issue a credit note instead)"
- "… credit note allocation(s) applied by hand — detach them first"
Payments and credits that attached themselves are released by themselves.

**Reissue… — Managers and above**
1. Open the cancelled invoice and press **Reissue…**.
2. IMS asks: "Issue a new invoice for SO-99001, dated today (Toronto)? Tax rates are taken as of today." Press OK.
3. The new invoice opens with a new number. Cancelled numbers are never used again.

**Good to know**
- "⚠ No due date — the order had no payment term. It is not counted as overdue."
- **↓ CSV** downloads the invoices that match the filters. **↓ Lines CSV** downloads their lines, one row per line.

<!-- SCREENSHOT: sales-invoices-1 · an invoice's detail with Orders, Payments, Credits applied and Emails -->

<a id="sales-payments"></a>
## Customer payments and deposits
<!-- screen: so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: accounting, office -->

**What it is**
A payment is money the customer gave us. IMS keeps where it went: to an invoice, held for an order, or on the customer's account.

**How — a deposit before the invoice**
1. On a draft order, press **Take a deposit…**. On a confirmed or finalized order with no invoice yet, press **Take a payment…**.
2. "No invoice yet — the payment is recorded against this order and attaches itself when the invoice is issued."
3. Choose **Method**, type **Amount**, **Paid on**, **Reference** (card slip, cheque number …) and **Note** if needed.
4. **Account** can stay on "Default for this method and branch".
5. Press **Record payment**. The money is **Held for orders** until the invoice comes.

**How — pay an invoice**
1. On the order or on **Sales Invoices**, press **Take a payment…**. The window says "Applied to invoice 99001 · still owed …" and fills the amount.
2. Check the amount and press **Record payment**.

**How — money on account**
1. On **Sales ▾** › **Customer Payments**, press **+ Record a payment**, pick the customer and fill the payment.
2. "It attaches itself to the next invoice they get — or open it here and attach it by hand."
3. To attach by hand: open the payment, press **Attach to invoices…**, press **Suggest (oldest first)** or type amounts, then **Attach**.

**Example**
Customer A pays $500.00 on account. The next invoice 99001 is $188.77. When it is issued, $188.77 attaches itself and $311.23 stays on account.

**Managers and above**
- **Refund…** (on **Customer Payments**): "A refund first pays off credit notes owed to the customer, then money on account. It cannot be more than both together." Press **Record refund**.
- **Void payment…**: for a payment entered by mistake. "Everything it paid or covered is released — nothing is deleted." A reason is required.
- **detach** on an invoice's payment line takes that payment off the invoice. The money goes back on account.

**Payment tags**
On the **Sales Orders** list each invoiced order shows **unpaid**, **partly paid**, **paid** or **overdue Nd** (N days late). The filter **Any payment** · **Unpaid** · **Partly paid** · **Overdue** · **Paid** finds them.

**Good to know**
- The **Customer Payments** filter: **Active**, **Not attached — money on account**, **Held for orders**, **Refunds**, **Voided**, **All**.
- A payment has no status to change. A wrong payment is voided, not edited.

<a id="sales-credits"></a>
## Credit notes
<!-- screen: so-credits.html · BUILD 2026-10-25 · cr v5a -->
<!-- who: accounting, office -->

**What it is**
A credit note gives money back to the customer for an invoice — for goods that come back, a price that was too high, freight, or a mistake. It can also put goods back in stock. Credit numbers look like `CR-99001`.

**How — Managers and above**
1. On **Sales Invoices**, open the invoice and press **Raise a credit note…** (or **+ New credit note** on **Credit Notes** and search the invoice).
2. **Credit note**: choose the **Reason** — **Customer return**, **Damaged**, **Billing error**, **Price adjustment** or **Other** (Other needs a **Note**). Check **Credit date** and **Goods come back to** (the branch).
3. **Products**: type **Return** for each line. **Can return** shows how much is left to credit.
4. **Back to stock**: **to bin** puts the goods back. The bin box starts with "the bin the product sits in now (usual bin first)". Or choose **not restocked** (**Damaged**, **Not returned**, **Other**) to keep them out of stock.
5. **Freight and charges**: type the freight to give back, if any. Its discount comes back by itself.
6. Press **Preview**, read the amounts and tax, then **Issue credit note**.

**Price adjustment**
The customer keeps the goods and gets the difference back. In **Price adjustment — past sale price**, type **Qty to adjust** and **New unit price**. "No stock moves." Choose the reason **Price adjustment**.

**Restocking fee**
When the sale is more than 60 days old, IMS shows a notice and suggests a 20% fee. To charge it, tick **Charge a fee** (you can change the %) and choose the **Fee account**. It is never added by itself.

**Goods taken off before shipping**
This is the second step of [the customer wants to take items off a packed order](#sales-ship-invoice).
1. Make the credit from that invoice for the quantity taken off — 30 packed, 5 taken off → credit 5.
2. **Back to stock**: **to bin**, keep the bin where the goods sit.
3. **Reason**: **Other** · **Note**: "Removed by the customer before shipping".

**A sale with no IMS invoice**
For an invoice from before IMS, press **Credit with a reference number…** in the new credit window. Pick the **Customer** and type the **Reference number** (the invoice number on the paper — required), **Invoice date**, and for each product the **Unit price paid**.

**Using the credit**
- Credits attach themselves to the customer's next invoice when it is issued.
- To attach by hand: open the credit, press **Attach to invoices…**, **Fill oldest first** or type amounts, then **Attach**.
- To pay it out as money: **Refund on Customer Payments →** (managers and above).

**Managers and above**
- **Cancel credit note…**: "Returned stock goes back out of the bins it came into. It must not be attached to anything first." A reason is required.
- **detach** takes a credit off an invoice.

**Good to know**
- Unit price and tax come from the invoice — you do not type them.
- **Print credit note** and **Email to customer…** work like the invoice (see [Print and email](#sales-print-email)).

<!-- SCREENSHOT: sales-credits-1 · New credit note window: Products with Return and Back to stock, Restocking fee unticked -->

<a id="sales-web-orders"></a>
## Web orders
<!-- screen: shopify-orders.html · BUILD 2026-10-14 · wo v4d -->
<!-- who: office -->

**What it is**
Orders from the web shop come in by themselves. Within a minute IMS makes a sales order from each one. **Sales ▾** › **Web Orders** shows what came in and what needs a person.

**Status**

| Status | Meaning |
|---|---|
| Waiting | "Ready — the system makes the sales order within a minute" |
| Needs review | "The system stopped — pick what it could not decide" |
| Done | "Sales order made" |
| Error | "The system could not make the sales order" |
| Cancelled | "Cancelled in Shopify" |

**How — Needs review**
1. Filter **Needs review** and open the order.
2. Customer: press the right customer, or **Pick the customer…** / **Another customer…** to search. "The next orders from this Shopify customer will go to this customer by themselves."
3. Lines: "Type the right SKU, or tick leave out. The order is made without left-out lines." Press **Save line choices**.
4. The order goes back to **Waiting**, and the sales order is made within a minute.
- Managers and above: **Process waiting now** does it at once instead of waiting.

**Warnings**
A web order or its sales order can carry warnings. The warning says what to do. When it is done, press **Mark checked**. **Reopen** opens it again. Ones you will often see:
- "Discount differs from IMS rules" · "List price differs from IMS" — the Shopify price is kept.
- "Freight not added (decided at shipping)" — add it at **Ship & invoice**.
- "Not confirmed — needs a fix on the sales order"
- "Cancelled in Shopify — check the sales order"
- "Refunded in Shopify — make a credit note in IMS if needed"
- "Paid in Shopify, but IMS will not ship part of it — refund that part in Shopify" — a note is needed to mark it checked.
- "Pickup order — no province for tax; pick a tax rule on the sales order"
- "Changed in Shopify after the sales order was made"

**On the sales order**
A web order's sales order has the tag **Shopify** and a card with the Shopify details, including **Paid in Shopify**.

**Watch out**
- The web order itself is not edited here. Make changes on the sales order.
- The Shopify discount is kept on the lines.

<a id="sales-cancel"></a>
## Cancel an order
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: sales, manager -->

**What it is**
Cancelling closes a confirmed order for good. A draft is not cancelled — use **Delete draft** (see [Take an order back](#sales-undo)).

**How — Managers and above**
1. On a confirmed order still in IMS, press **Cancel order…**.
2. Type the **Reason** (required) and press **Check**.
3. Read the result: "Orders that will be cancelled (split-off orders go with it)". For example SO-99001 and SO-99001a go together.
4. If the order had taken over backorders from older orders, choose **Reopen** or **Keep closed**. You must choose one.
5. Press **Cancel the order**.

**What happens**
- Reserved stock is released for other orders.
- A coupon used by the order can be used again.
- The order shows **Cancelled**. There is no undo.

**Watch out**
- An order at the warehouse cannot be cancelled. Recall it first, or ask the warehouse to send it back (see [Take an order back](#sales-undo)).
- Staff without the manager role do not see **Cancel order…**. Ask your manager.

<a id="sales-statuses"></a>
## What each status means
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->

**Status — badge and filter**
The badge is the coloured label on an order. The filter is the **Status** list on **Sales Orders**. Warehouse screens: see [Warehouse statuses](04-wms.md#wms-statuses).

| Badge (colour) | Filter | Meaning |
|---|---|---|
| Draft (grey) | Draft | The office is writing it. |
| Confirmed (blue) | Confirmed | Confirmed — next: release to the warehouse. |
| Released to WMS (purple) | With warehouse | Waiting for the warehouse manager. |
| Working (purple) | With warehouse | The warehouse is picking or packing. |
| Finalized (orange) | Finalized — waiting for the office | Ready — the office must **Ship & invoice**. |
| Invoice cancelled (dark orange) | — | Shipped, but its invoice was cancelled — issue the invoice again. |
| Fulfilled (green) | Fulfilled | Done. |
| Cancelled (red) | Cancelled | Closed without shipping. A merged order shows "merged". |

Other filters: **Open** (everything not finished), **Draft — reprice suggested**, **Waiting for pickup**, **All**.

**Tags next to the badge**
- **unpaid** · **partly paid** · **paid** · **overdue Nd** — see [Customer payments and deposits](#sales-payments)
- **waiting for pickup** · **picked up** — see [Pickup orders and tracking](#sales-pickup)
- **reprice** — prices may be out of date; open the order and press **Reprice**
- **split** — the order was split off another one
- **Shopify** — a web order · **Counter** · **Service** · **POS** — the channel (see [POS](05-pos.md#pos-start))

**Days to fulfil**
A fulfilled order shows how long it took from the day it was made to the day it was fulfilled: **same day** (green), 1 to 3 days (amber), more than 3 days (red).

<a id="sales-csv"></a>
## CSV downloads
<!-- screen: so.html · BUILD 2026-10-25 · so cf words v1 ; so-invoices.html · BUILD 2026-10-22 · inv csv v5 ; so-payments.html · BUILD 2026-10-22 · pay csv v2 ; so-credits.html · BUILD 2026-10-25 · cr v5a ; so-backorders.html · BUILD 2026-10-25 · bo cf words v1 -->
<!-- who: office, accounting -->

**What it is**
Most sales screens can download a spreadsheet (CSV).

| Screen | Wide list | One document |
|---|---|---|
| Sales Orders | **↓ CSV** | **↓ Lines CSV** |
| Sales Invoices | **↓ CSV** · **↓ Lines CSV** | **↓ Invoice CSV** |
| Customer Payments | **↓ CSV** | **↓ Payment CSV** |
| Credit Notes | **↓ CSV** | **↓ Credit CSV** |
| Backorders | **↓ CSV** | — |

**How**
1. Set the filters and search on the wide list.
2. Press **↓ CSV**. Every row that matches the filters downloads — all pages, not only the one on screen.
3. On one document, the CSV button downloads that document only.

**Good to know**
- Barcodes and SKUs open in Excel as text, exactly as they are — long numbers do not turn into 1.23E+12 and leading zeros stay.
- The GP columns (gross profit) appear in **↓ Lines CSV** only for people with the `cost` key.
- These files are for internal use. Send customers the printed documents (see [Print and email](#sales-print-email)).

<!-- rulings: 245, 246, 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 349, 357, 433, 436, 437, 438, 443, 449, 452, 455, 467, 469, 473, 484, 488, 489, 490, 507, 514, 516, 517, 526, 529, 532, 540, 541, 545, 546, 549, 590, 602, 609, 610, 612, 628, 709, 713, 714, 715, 719, 720, 723, 724, 725, 726, 727, 729 -->
