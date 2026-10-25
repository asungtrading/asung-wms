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
<!-- TODO manual-1b2 -->

<a id="sales-release"></a>
## Send an order to the warehouse
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

<a id="sales-undo"></a>
## Take an order back
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office, manager -->
<!-- TODO manual-1b2 -->

<a id="sales-divide-merge"></a>
## Divide or merge orders
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

<a id="sales-backorders"></a>
## Backorders
<!-- screen: so-backorders.html · BUILD 2026-10-22 · bo csv v1 -->
<!-- who: sales, office -->
<!-- TODO manual-1b2 -->

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

<!-- rulings: 277, 282, 283, 284, 298, 311, 312, 321, 322, 324, 329, 507, 517, 529, 532, 541, 545, 546, 590, 709, 713, 714, 715, 719 -->
