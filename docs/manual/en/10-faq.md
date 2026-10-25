# 10. FAQ

<!-- questions gathered from chapters 0-8 (Watch out · Good to know · screen messages) · no new facts · real questions are added over time (ruling 740) -->

Not here? Ask your manager. Questions people really ask are added to this chapter.

<a id="faq-sign-in"></a>
## Signing in, screens and keys
<!-- screen: none -->
<!-- who: all -->

### Why was I signed out?
Some screens sign you out if you have no key for them — most often when someone sends you a link to a screen. Sign in again; your own screens are still there (see [Sign in](00-getting-started.md#start-sign-in)).

### Why is a screen or button missing?
It is a key, not a fault. Ask your manager for the key (see [Roles and keys](00-getting-started.md#start-roles-keys)).

### I forgot my password. What do I do?
Press **Forgot your password?** on the sign-in screen. Nobody else has to do anything (see [Sign in](00-getting-started.md#start-sign-in)).

### Can I change my own keys?
No. A person above you changes them on **Staff** (see [Roles and keys](00-getting-started.md#start-roles-keys) and [Staff](07-settings.md#set-staff)).

### Why is my CSV shorter than I expected?
CSV follows your filters. Check the filters first (see [Search, filters, pages and CSV](00-getting-started.md#start-search-filter)).

### Why are times two hours off in Edmonton?
IMS shows Toronto time. After 22:00 in Edmonton it is already the next day in Toronto (see [Dates and times](00-getting-started.md#start-dates-times)).

### What do I send when something goes wrong?
The screen name and both build tags, the number you were working on, what you did and what happened, and a screenshot of **System Check** (see [Getting help](00-getting-started.md#start-getting-help)).

<a id="faq-sales"></a>
## Sales
<!-- screen: none -->
<!-- who: sales, office -->

### Why can't I add the same SKU again?
"same SKU at another price — change that line instead": change the line that is already there (see [Add lines](01-sales.md#sales-add-lines)).

### Why didn't the coupon work?
IMS shows **not used** and the reason — for example a bigger discount already wins, or the coupon expired before the order date (see [Use a coupon](01-sales.md#sales-coupons)).

### Why didn't Reprice change the order discount?
When an order is divided or split, its order discount is locked at what the customer first ordered (see [Discounts, deals and surcharges](01-sales.md#sales-discounts-deals)).

### Why can't I cancel an order that is at the warehouse?
Recall it first, or ask the warehouse to send it back, then cancel. Only managers and above see **Cancel order…** (see [Cancel an order](01-sales.md#sales-cancel)).

### Why can't I merge these orders?
An order with an open backorder cannot be merged. Proceed the backorder first (see [Divide or merge orders](01-sales.md#sales-divide-merge)).

### How do I give money back to a customer?
Not with a charge — "A charge cannot be negative — money back is a credit note." (see [Shipping fees and other charges](01-sales.md#sales-charges) and [Credit notes](01-sales.md#sales-credits)).

### The customer takes items off a packed order. What do I do?
Ship & invoice as usual, then a manager makes a credit note for what was taken off, back to the bin where it sits (see [Ship & invoice](01-sales.md#sales-ship-invoice)).

### An issued invoice has the wrong price. How do I fix it?
If only the price was too high, make a credit note with the reason **Price adjustment** — the customer keeps the goods. If the whole invoice is wrong, managers and above **Cancel invoice…** and **Reissue…** (see [Credit notes](01-sales.md#sales-credits) and [Sales invoices](01-sales.md#sales-invoices)).

### Why is a new customer on the Action Centre?
Customers made by sales start on the default terms; a manager reviews them (see [New customers to review](06-action-centre.md#action-new-customers)).

<a id="faq-purchasing"></a>
## Purchasing
<!-- screen: none -->
<!-- who: office, accounting -->

### How do I undo a supplier payment?
A payment has no cancelled state. **Delete** is "the only way to undo one" — what it settled goes back to being owed (see [Pay suppliers](02-purchasing.md#purch-payments)).

### Why is Confirm refused on a charge?
Confirm is refused until the shares add up to the charge (see [Freight, duty and other charges](02-purchasing.md#purch-charges)).

### I changed lines after sending the PO. Now what?
Download **↓ PO CSV** again and send the new file (see [Confirm a PO and send it](02-purchasing.md#purch-confirm)).

### I deleted a draft PO. Is its number used again?
No — "The number … is not given to another order — it stays empty." (see [Start a PO](02-purchasing.md#purch-new-po)).

### Why didn't the documents go to Google Drive?
They go only after an admin switches Drive on, and only from the start date set there (see [Upload the supplier's documents](02-purchasing.md#purch-documents) and [Google Drive](07-settings.md#set-drive)).

### When do received goods count in stock?
See [Warehouse](#faq-warehouse).

<a id="faq-stock"></a>
## Stock and products
<!-- screen: none -->
<!-- who: office, manager -->

### How do I undo a stock adjustment?
A confirmed adjustment cannot be undone or deleted. Fix a mistake with a new adjustment (see [Stock adjustments](03-inventory.md#stock-adjustments)).

### Why isn't B-grade stock in Available?
B-grade stock is left out of **On hand** and **Available** and is sold only at the POS (see [B-grade stock](03-inventory.md#stock-bgrade)).

### Why don't I see the Value column?
It needs the `cost` key. Without it the column is not there (see [Roles and keys](00-getting-started.md#start-roles-keys)).

### Why can't a set become a combo?
A set cannot become a combo, and a combo cannot have sets (see [Add a new product, sets and combos](03-inventory.md#stock-new-product)).

### Why did a SKU leave its family?
A SKU added to another family moves out of the old one — you are asked to confirm first (see [Families](03-inventory.md#stock-families)).

### Less arrived on a transfer than was sent. What now?
Someone with the Stock adjustments key presses **Settle in transit** and chooses **Lost** or **Returned to sender** (see [Transfers between warehouses](03-inventory.md#stock-transfers)).

### What is "Sold without stock"?
A sale that took more than the books showed — the goods were there, the count was not. Count the shelf, fix the stock, then a manager marks it checked (see [Sold without stock](06-action-centre.md#action-sold-short)).

<a id="faq-warehouse"></a>
## Warehouse
<!-- screen: none -->
<!-- who: warehouse -->

### The item is really not on the shelf. What do I press?
Press **⚠ Not enough stock**. A shortage you do not declare is counted as your mistake (see [When an item is short](04-wms.md#wms-pick-short)).

### Why doesn't "Pick complete" work?
Not while a line is short — "There are short lines. Press 'Complete as incomplete'." (see [When an item is short](04-wms.md#wms-pick-short)).

### Two of us picked the same order. How?
If you put a pick list back on the board, close the batch on your screen too (**Hold (later)**) (see [Pick an order](04-wms.md#wms-picking)).

### "Unknown barcode" at receiving. What now?
"Unknown barcode — ask the office to register the product": the product is not set up yet (see [Receive a PO or a transfer](04-wms.md#wms-receiving)).

### Why is my bin name refused?
"… is not a bin at … — ask the office to add it" (see [Put away](04-wms.md#wms-putaway) and [Lists: brands, units, payment terms, bins, carriers, services](07-settings.md#set-master)).

### How do I reopen a receipt I completed?
After **Complete**, only a manager can reopen it (see [Put away](04-wms.md#wms-putaway)).

### When do received goods count in stock?
Only after the receipt is confirmed — on the receiving screen or **WMS Admin** by managers and above with the receiving-confirm key, or on **Purchase Receipts** in the office (see [Put away](04-wms.md#wms-putaway) and [Receipts in the office](02-purchasing.md#purch-receipts)).

### Why can't I move stock between bins?
It needs the Bin moves key, switched on person by person. Ask a manager (see [Move stock between bins](04-wms.md#wms-bin-moves)).

<a id="faq-pos"></a>
## POS (counter)
<!-- screen: none -->
<!-- who: sales -->

### Why can't I start a sale?
"Pick this counter's store first (top left)." (see [Start the POS](05-pos.md#pos-start)).

### The customer has no account. Can I still sell?
No. Make the customer account first, then press **Customer…** (see [Ring up a sale](05-pos.md#pos-sale) and [Find or add a customer](01-sales.md#sales-customers)).

### Why is Confirm blocked?
A line has no price, or there is no tax rule. Give the line a price, or pick the **Tax rule** under the warning (see [Ring up a sale](05-pos.md#pos-sale)).

### Why can't I set the price to 0?
"The price must be above 0 — a free item needs a reason (Sales Orders screen)." (see [Prices, discounts and coupons](05-pos.md#pos-prices)).

### The customer wants to return something. What do I do?
After Finish the sale cannot be changed at the POS. A return is a credit note. B-grade items are final sale (see [Finish and print the invoice](05-pos.md#pos-finish) and [Credit notes](01-sales.md#sales-credits)).

### The customer cannot pay it all now. Can I still finish?
Yes. Finish does not stop you; what is still owed stays on the invoice (see [Finish and print the invoice](05-pos.md#pos-finish)).

### I left a sale unfinished. Where is it?
In **Parked and open at this store**. One not finished by the end of the day also shows on the Action Centre (see [Park a sale and pick it up again](05-pos.md#pos-park) and [POS not finished](06-action-centre.md#action-pos)).

### How do I close the day at the counter?
Counting cash and closing the card terminal happen outside IMS. To check the day's payments, use **Customer Payments** and **↓ CSV** (see [What each status means](05-pos.md#pos-statuses)).

<a id="faq-settings"></a>
## Settings
<!-- screen: none -->
<!-- who: manager, admin -->

### Why can't I rename a brand?
Names cannot be changed. Switch the old one off and add a new one (see [Lists: brands, units, payment terms, bins, carriers, services](07-settings.md#set-master)).

### Why can't I edit this person on Staff?
You can only edit people below your own role, and not yourself (see [Staff](07-settings.md#set-staff)).

### How do I remove a staff member?
There is no delete. Untick **Active** (see [Staff](07-settings.md#set-staff)).

### A staff member forgot their password.
See [Signing in, screens and keys](#faq-sign-in).

### Why won't a document print?
"This document cannot print until a layout is in use." (see [Documents](07-settings.md#set-documents)).

### My deal did not save — someone else saved it.
Press **Load the latest version** and make your change again (see [Discount rules and deals](07-settings.md#set-deals)).

### How do I change a coupon's last day?
Void it and issue a new one (see [Coupons](07-settings.md#set-coupons)).

<!-- rulings: 42, 709, 713, 714, 715, 719, 723, 725, 732, 736, 737, 739, 740 -->
