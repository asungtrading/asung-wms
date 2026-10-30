# 5. POS (counter)

<!-- sections 1-8 written (manual-5) · sections follow the order of the work at the counter -->
<!-- out of this chapter: counter orders (Hand over — ship and invoice…) -> chapter 1 · returns -> chapter 1 credit notes · B-grade bins and prices -> chapter 3 -->

<a id="pos-start"></a>
## Start the POS
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 ; ims-auth.js · BUILD nav v10 -->
<!-- who: sales -->

**What it is**
**POS** is the counter screen. You sell to a customer who is standing at the counter, take the payment and hand the goods over. Every POS sale is a sales order on a customer account.

**Who**
Everyone who works on sales orders. There is no extra key for the POS and no step only for managers.

**How**
1. Press **POS** next to the Asung logo (see [Modes: IMS, WMS and POS](00-getting-started.md#start-modes)).
2. At the top left, choose this counter's store. "This counter's store — remembered on this device".
3. Press **+ New sale**.

**Good to know**
- The POS has no ☰ Menu. To reach other screens, press **IMS**.
- The store is kept on this tablet only. On another tablet, choose the store again. Nothing is lost — each sale keeps its own store.
- Stock comes from the store's warehouse.

**Watch out**
- Without a store you cannot start: "Pick this counter's store first (top left)."

<!-- SCREENSHOT: pos-start-1 · POS screen with the store chosen and + New sale -->

<a id="pos-sale"></a>
## Ring up a sale
<!-- screen: pos.html · BUILD 2026-10-26 · pos v1.14 ; combo hint BUILD 2026-10-30 · pos v1.17 ; ims-overdue.js · BUILD 2026-10-26 · overdue v1 -->
<!-- who: sales -->

**What it is**
A sale starts with the customer, then you scan the items. "Pick the customer first — every POS sale is on a customer account."

**How**
1. Press **+ New sale** (or **Customer…**). In **Customer for this sale**, type part of the name and click the customer.
   If the customer has invoices past their due date, the window **Overdue invoices** opens. Read it, ask about payment, and press **OK** — it does not stop the sale (see [Start a new sales order](01-sales.md#sales-new-order)).
2. Scan a barcode or type a SKU, then press Enter. The newest item goes on top, and its photo shows large at the top right.
3. If the code does not match, press **Find…** and search by SKU or name. "Nothing matched that code exactly — pick from the list."
4. Change the quantity with **−** and **+**, or type the number. **✕** takes the item off.
5. When everything is scanned, press **Confirm — show the amount** (see [Take the payment](#pos-pay)).

**A customer buying for the first time**
IMS does not sell without a customer account. Make the account first: press **IMS**, then **Sales ▾** › **Customers** (see [Find or add a customer](01-sales.md#sales-customers)). Then come back and press **Customer…**.

**Good to know**
- The bar at the top shows the customer, the price tier and the payment term. Chips show **Credit**, **Open invoices** and **Overdue**. They are for your eyes only — they do not stop the sale.
- A set that is not sold as a set goes on as single units: for example "DEMO-001-6 is not sold as a set — added DEMO-001 × 6 instead".
- A combo shows its parts in small rows under it.
- If an item you scan is also sold as part of a combo, a chip shows "Also sold as combo …" with **Use combo**. **Use combo** adds one combo and takes the same items off the sale — as many as go into one combo, newest lines first. Free lines and B-grade lines are not touched. It is only a suggestion; nothing changes until you press it.
- More than the warehouse has asks first: "Only … available in this store's warehouse (on hand minus what other orders hold). Sell … anyway?"

**Watch out**
- "No tax rule — pick one before Confirm." Choose the **Tax rule** that shows under the warning.
- "A line has no price — Confirm is blocked until it gets one." Give it a price (see [Prices and discounts](#pos-prices)).
- "This SKU is already on the sale at another price — change that line's quantity instead."

<!-- SCREENSHOT: pos-sale-1 · a draft sale with the customer bar, three items and the big photo -->

<a id="pos-prices"></a>
## Prices, discounts and coupons
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**What it is**
Prices come from the customer's price tier, the customer's discount and deals — the same as on a sales order. The POS shows where each discount came from, in large type.

**What the line shows**
- **Sale** — a deal. The usual price is struck through.
- **Customer discount** — the customer's own discount.
- **Set discount** — the discount of a set.
- **Discount by hand** or **price set by hand** — someone changed it at the counter. The line shows who and when.

**How — change one item's price**
1. On a draft sale, press **✎** next to the price.
2. Type a **Price each**, or a discount in **or Discount %** — one of the two, not both. "A price or discount set here is final for this item — the order discount does not apply to it. Your name is kept on the line."
3. Press **Save**. **Back to the usual price** returns the item to the tier price, customer discount and deals.

**Example**
The list price of DEMO-001 is 10.00. Type 8.50 in **Price each** — the item sells at 8.50. Or type 20 in **or Discount %** — it sells at 8.00.

**Coupons**
The **COUPON** box shows only when the customer has a coupon they can use, or a coupon is already on the sale.
1. Press **Use** next to the coupon (or type a code and press **Apply**).
2. One coupon per sale. **Use instead** or **Replace** swaps it. **✕** takes it off — "The customer can still use it later."
- If the coupon does not win, it shows **not used** and the reason. At **Confirm**, a coupon that was not used is taken off: "The coupon was not used, so it was taken off — the customer can still use it."

**Watch out**
- "The price must be above 0 — a free item needs a reason (Sales Orders screen)."

<a id="pos-bgrade"></a>
## Sell B-grade
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**What it is**
B-grade is the same product with a damaged package, kept in a B-grade bin with its own price (see [B-grade stock](03-inventory.md#stock-bgrade)). It is sold only at the POS, and it is a final sale.

**How**
1. Scan the item as usual.
2. On the item, press **B** — "Sell as B-grade — damaged package, from a B-grade bin, final sale".
3. If the item is in more than one B-grade bin: "Pick the one it came from — each bin has its own price." A bin with no price cannot be picked.
4. If the quantity is more than 1, type how many are B-grade. The rest stay as a regular item.

The item now shows "B-grade · bin … · Final sale — no return, no refund".

**Good to know**
- The B-grade price is final. No customer discount, deal, coupon or **✎** applies, and no surcharge is added. Tax is added.
- **✕B** turns it back into a regular item at the regular price.
- A second B-grade item from the same bin joins the first: "It was added to the B-grade line already on this sale."

**Watch out**
- More than the books show asks first: "The books have only … B-grade in bin …. Sell … anyway?" If you sell, the bin goes below 0 — tell whoever counts it.

<a id="pos-pay"></a>
## Take the payment
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: sales -->

**What it is**
**Confirm — show the amount** fixes the sale and shows what to pay. Then you record each payment.

**How**
1. Press **Confirm — show the amount**. Every item is held for this sale as it is — the POS does not check the shelf here. The right side shows **Items**, **Tax**, **Total** and **To pay**.
2. Let the customer pay at the terminal. Record it after the terminal approves.
3. Press the method: **Cash**, **Debit**, **Credit** or **e-Transfer**.
4. **Amount** is filled with what is left to pay. Change it if the customer pays part. Add the **Reference** (slip or approval no.).
5. Press **Record**.

**Split payment**
"A split payment is just two payments — record each one." For example, 30.00 on **Debit**, then the rest on **Cash**.

**Cash**
Type **Cash given** to see the change. "Record the amount kept, not the cash handed over (change is not recorded)."

**Good to know**
- Money on account and open credit notes pay the sale by themselves. The right side shows **Credit / on account**.
- After **Confirm**, the scan box says "Confirmed — Reopen to add or change items". To add or change items, press **Reopen to change items** — "Payments already taken stay on it."

<!-- SCREENSHOT: pos-pay-1 · a confirmed sale with the four payment buttons and To pay -->

<a id="pos-finish"></a>
## Finish and print the invoice
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 ; ims-doc.js -->
<!-- who: sales -->

**What it is**
**Finish** hands the goods over and issues the invoice in one step.

**How**
1. Press **Finish — hand over and invoice**.
2. The window **Finish SO-99001** shows **Total**, **Paid for this sale**, **Credit / money on account used** and **Nothing left to pay** — or **Still owed — goes on the invoice**.
3. Press **Finish**.
4. The screen shows the invoice number (for example 99001) and **Paid in full** or **Still owed**.
5. Press **Print invoice** to print it for the customer. Or open it on **Sales Invoices**.
6. Press **+ New sale** for the next customer.

**Good to know**
- "Finish hands the goods over and issues the invoice now. It does not stop you if something is still owed — that stays on the invoice." The rest is paid on the customer's payment term.
- The invoice is the customer's paper. There is no separate till slip.
- If more goes out than the books show, Finish still goes; the [Action Centre](06-action-centre.md#action-sold-short) shows it.

**Watch out**
- After Finish, the sale cannot be changed at the POS. A return goes through a credit note (see [Credit notes](01-sales.md#sales-credits)). B-grade items are final sale.

<a id="pos-park"></a>
## Park a sale and pick it up again
<!-- screen: pos.html · BUILD 2026-10-26 · pos v1.14 -->
<!-- who: sales -->

**What it is**
**Park** sets a confirmed sale aside so you can serve the next customer — "it stays open at this store". Its items stay held for it.

**How**
1. On a confirmed sale, press **Park**. The screen is cleared.
2. The sale shows in **Parked and open at this store**, with **Customer**, **State**, **Amount** and **Paid**.
3. To go on, click the sale. "Click to pick it up at this counter." Any counter at this store can pick it up.

**Delete a draft**
A draft that was never confirmed can be deleted — for example a sale started by mistake.
1. On the open draft press **Delete draft** at the top, or press **✕** on its row in **Parked and open at this store** (it does not open the sale).
2. IMS asks "Delete draft …? It has never been confirmed, so it disappears — the number is not reused." Press **OK**.
- A confirmed sale has no **Delete draft** and no **✕**. If IMS refuses, it says why.
- **Delete draft** on **Sales Orders** does the same thing.

**Good to know**
- Drafts you have started show here too, as "draft — scanning".
- Parking is not a status. The sale stays confirmed.

**Watch out**
- "A confirmed sale not finished by the end of the day shows on the manager list." Here it shows as "confirmed from … — not finished". Finish it, or reopen it and take the items off. The manager list is the [Action Centre](06-action-centre.md#action-pos).

<a id="pos-statuses"></a>
## What each status means
<!-- screen: pos.html · BUILD 2026-10-23 · pos v1.12 -->
<!-- who: all -->

The sale number at the top shows its status, for example "SO-99001 · draft".

| Status | Meaning |
|---|---|
| draft | You are scanning. Items, prices and coupons can change. |
| confirmed | The amount is fixed and the items are held. Take payments, then **Finish**. **Reopen to change items** goes back to draft. |
| fulfilled | Finished — the goods are handed over and the invoice is issued. |

On **Sales Orders** a POS sale has the tag **POS**. The badges are the same as for other orders — see [What each status means](01-sales.md#sales-statuses).

**Closing the day**
Counting the cash and closing the card terminal happen outside IMS. To check the day's payments: on **Sales ▾** › **Customer Payments**, choose the method (**All methods** lists them), set both dates to the day, and press **↓ CSV** (see [Customer payments and deposits](01-sales.md#sales-payments)).

<!-- rulings: 159, 225, 283, 546, 547, 629, 886, 633, 634, 635, 640, 644, 647, 648, 709, 713, 714, 715, 719, 720, 723, 725, 732, 735, 736, 737, 769, 773 -->
