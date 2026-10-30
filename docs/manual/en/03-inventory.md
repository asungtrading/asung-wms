# 3. Inventory

<!-- sections 1-12 written (manual-3a · 3b) · sections follow the order of the work, not the order of the screens -->

<a id="stock-availability"></a>
## Find stock (Stock Availability)
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: all -->

**What it is**
**Stock Availability** (**Inventory ▾** › **Stock Availability**) shows how much of each product is in each branch, where it sits and what is holding it. Anyone who can sign in can open it.

**How**
1. Search by "SKU, name, brand or barcode", for example `DEMO-001`.
2. Choose the branch, or **Both branches**. Narrow with **All brands**, **All categories** and **All suppliers**.
3. Each product shows **On hand**, **Allocated**, **Transfer res.**, **Available**, **On order**, **In transit**, **Last movement** and **On sale %**.
4. Press **▸** on a row to see its sets, its bins and recent movements. Click the product to open it on the right.
5. In the detail, **Allocated** and **Transfer res.** can be pressed to "Show the sales orders holding this stock" or the transfers.

**What the numbers mean**
- **On hand** — what is on the shelves in this branch.
- **Allocated** — reserved for confirmed sales orders.
- **Transfer res.** — held for transfers to the other branch.
- **Available** — what is free to sell now.
- **On order** — on confirmed POs, not received yet.
- **In transit** — on the way from the other branch.
- Example: On hand 50, Allocated 18, Transfer res. 5 → Available 27.

**Good to know**
- **Zero stock** also shows products with nothing on hand, nothing allocated and nothing on order. **On sale** shows products with a current deal.
- Stock in B-grade bins is not in **On hand** or **Available** — "sold at the POS only". It shows as a small note on the row.
- In the movements, "Balance is shown at the end of each day." **Full history ›** opens all of it. "Loaded history — not an IMS document" marks movements from before IMS.
- **↓ CSV** downloads every product that matches the filters.
- With the `cost` key you also see **Value** and **Layer qty (EA)**, and **Stock value total** adds up the value of everything that matches.
- In the warehouse, the same numbers are on [Stock Lookup](04-wms.md#wms-stock-lookup).

<!-- SCREENSHOT: stock-availability-1 · Stock Availability with one product's ▸ open: sets, bins and movements -->

<a id="stock-products"></a>
## Find and change a product
<!-- screen: products.html · BUILD pr v5i -->
<!-- who: office, manager -->

**What it is**
**Products** (**Inventory ▾** › **Products**) holds every product: name, brand, category, unit, prices, suppliers, barcodes, sets, family, photos and tags.

**How to find a product**
1. Open **Products** and type in **Search SKU or name**.
2. **Singles** shows single products; **Sets only** shows cases and packs. **Active only** starts ticked.
3. Click a product. Its cards open on the right: prices for each sale tier, **Suppliers**, **Barcodes**, **Sets of this product**, **Family**, **Photos** and **Tags**.

**How to change a product — needs the master key**
1. Press **Edit**. "Change several fields, then save once."
2. Change what you need — name, brand, category, unit, prices, suppliers, barcodes.
3. Press **Check & save**. IMS checks first:
   - "Not saved — fix these first" lists what must change.
   - Warnings can be read and passed with **Save anyway**.

**Good to know**
- A set with no price of its own shows **calculated** — it follows the single product's price.
- **Last change before IMS** shows when the product was last changed before IMS.
- A product's surcharge group is picked on its card in **Edit** (see [Surcharge groups](07-settings.md#set-surcharge)).
- Products are never hidden — inactive products can still be found.
- The kind list starts on **Singles**, so sets do not show in the search. To find a set, choose **Sets only** (or **All**).
- To change many products at once, use [Product Sheet](#stock-sheet).
- **↓ Export…** on the wide list downloads the products that match the filters, with the columns you pick — see [↓ Export…](00-getting-started.md#start-search-filter).
- Supplier costs (**Fixed cost**, **Latest cost**) show only to people with the `cost` key. Without it the cost boxes are not on the product, in **Edit** or in **+ New product**.

<a id="stock-new-product"></a>
## Add a new product, sets and combos
<!-- screen: products.html · BUILD pr v5k ; combos.html · BUILD 2026-10-30 · cb v1a -->
<!-- who: office, manager -->

**What it is**
A **set** is a case or pack of the same product, for example a case of 6. Stock is counted in single units. A **combo** is one SKU made of other products; the components hold the stock.
Which one to use: if the bundle is sold by scanning its own case or pack barcode, make it a **set**. If the bundle is sold only through the barcodes of its single items, make it a **combo** — for example "two of A for the price of one".

**How — a new product (needs the master key)**
1. Press **+ New product**.
2. Fill in **Barcode(s)** ("one or more — the first is primary"), **Brand**, **SKU**, **Name**, **Category**, **Unit** and **Weight**. **Suggest** makes a SKU from the "Brand prefix + barcode digits".
3. Type the **Sale prices** for each tier.
4. Add the **Supplier**, **Supplier SKU**, **Cost** and, if there is one, **Fixed cost**. Without the `cost` key only **Supplier** and **Supplier SKU** are there — a person with the key adds the costs later.
5. To make sets at the same time, press **+ ×6**, **+ ×12** or **+ other**. "Leave the name of a set blank to get the usual name." For example DEMO-001 with a set of 6 → DEMO-001-6.
6. Press **Check & create**. Fix anything under "Not saved — fix these first", or pass the warnings with **Save anyway**.

**How — add a set to an existing product**
1. Open the single product and press **Add set**. **Sets now** shows the sets it already has (✓).
2. Press **+ ×6**, **+ ×12** or **+ other** for the new set, and type its case barcode if it has one (for example `0000000000017`).
3. Press **Check & add**.

**How — make a combo (needs the master key)**
1. Open **Inventory ▾** › **Combos** and press **New combo** (the **New combo** button on **Products** opens the same window).
2. Fill in **SKU** (a new SKU, not used before), **Name**, **Brand**, **Category**, **Unit** and, if you have them, **Barcode(s)**, **Weight** and **Note**.
3. Type the combo's own **Sale prices** — not the sum of its components.
4. Under **Components**, add each component SKU with its **Qty per combo** (**+ component** adds a row). A combo needs two or more components — or one component with a **Qty per combo** of 2 or more.
5. Press **Check & create**. The new SKU and its components are saved together.

**How — change or release a combo (needs the master key)**
1. Open **Inventory ▾** › **Combos** and find the combo by its SKU or name, or by a component SKU. **Show released** also lists released combos.
2. **Edit components** changes the components or how many go into one combo. Press **Check & save**.
3. **Release combo…** turns all component rows off, and the SKU sells as a plain product from then on. Type the SKU and press **Release**.
4. **Open in Products** opens the same SKU on the product page — prices, barcodes, photos and the web shop are changed there.

**Watch out**
- An existing product cannot become a combo. A combo is always a new SKU made with **New combo**.
- **Release cannot be undone.** A released SKU can never become a combo again. To sell the same bundle later, make a new combo SKU.
- A combo has no sets, no supplier and no family. A set cannot be a combo.
- On the product page a combo shows its components for reading only, with **Open in Combos**.
- The web shop gets the number of whole combos the components can make at each location — the same number a sales order shows.

<!-- SCREENSHOT: stock-new-product-1 · New product window with sale prices, supplier and + ×6 set -->

<a id="stock-families"></a>
## Families
<!-- screen: families.html · BUILD fam v5c -->
<!-- who: office, manager -->

**What it is**
A family groups products that are variants of one thing — the same item in different colours or sizes. It decides whether they show as one product with options in the web shop. It does not change stock or ordering. Many products are in no family, and that is normal.

**How to find a family**
1. Open **Inventory ▾** › **Families** and search by family SKU or name.
2. Click a family to see its **Options** (for example Color, Size) and its **Products**.

**How — needs the master key**
- **New family from existing SKUs**: type the **Family SKU** (or leave it blank for "first variant SKU + FAM"), **Family name** and up to three **Options** ("Option 1 — e.g. Color"). Find the SKUs to add and press **Check and create**.
- **New family (new SKUs)**: opens the New family window on **Products** — for SKUs that do not exist yet, made together with the family.
- **Add member…** adds a product to a family. Set its option values (for example Color = Red) and press **Check and add**.
- **Remove** takes a product out of the family.

**Watch out**
- "A SKU already in another family moves out of it into this one — you will be asked to confirm. If that old family is on Shopify, the SKU drops from that Shopify product until this new family is listed."
- "Two members of one family cannot have the same option values."

<a id="stock-sheet"></a>
## Change many products at once (Product Sheet)
<!-- screen: product-sheet.html · BUILD sheet v2c -->
<!-- who: office, manager -->

**What it is**
**Product Sheet** (**Inventory ▾** › **Product Sheet**) shows many products as a table, one row per product. You change them like a spreadsheet and save them together. It needs the master key to save.

**How — change products**
1. Choose **Edit products**. Pick filters — search, **Brand**, **Category**, **Supplier**, **Singles** or **Sets only** — and press **Load**. Up to 300 rows load; **Next 300** loads more.
2. Click a cell to change it. Enter goes down. You can change name, brand, category, unit, sale prices for each tier, the default supplier's SKU and cost, active, discontinued and the set discount %.
3. To paste from Excel, copy a block and paste it into the first cell. "Paste follows the visible columns from left to right — line up your Excel columns with what you see. SKU always stays." **Columns** chooses which columns you see.
4. Press **Save**. "Not saved — fix these first (rows in red)" lists what to fix; warnings can be passed with **Save anyway**.

**How — new products**
1. Choose **New products**. **+ 20 rows** adds empty rows.
2. Type or paste the new products, then **Save**.

**Price formula**
"Filter by a supplier and press Load to use a price formula."
Without the `cost` key the bar says "Price formulas work from supplier costs, so they need the cost permission." The **Fixed cost** and **Landed · GP** columns are not there either.
1. Filter by one supplier (for example Supplier B) and press **Load**.
2. Choose a formula, or **— new formula —**. Its boxes are **Cur**, **Duty %**, **Freight · other ×** and **Margin ÷**. ★ marks the supplier's usual formula.
3. Choose the ending: **.49 · .99** or **.x9 all**.
4. Press **Preview**, then **Apply** to fill the prices. **Save as new** or **Update this formula** keeps the formula for next time.
- "Sets are not priced by a formula."
- "Costs are in the supplier's currency (Cur) — not converted."

**Good to know**
- To see what one supplier sells, filter by that **Supplier** and press **Load**.
- **Open these in Edit** opens the loaded products in edit mode.
- **Discard** drops changes you have not saved.

<!-- SCREENSHOT: stock-sheet-1 · Product Sheet filtered by one supplier with the price formula boxes -->

<a id="stock-descriptions"></a>
## Descriptions, photos, tags and the web shop
<!-- screen: products.html · BUILD pr v5f ; ims-desc.js ; ims-shop.js ; families.html · BUILD fam v5c -->
<!-- who: office, manager -->

**Description**
The description is what the web shop shows for the product. It is written and kept in IMS.
1. On the product, press **Edit description**.
2. Write it with **Text**, **H2**, **H3**, **• List**, **1. List**, **Link** and **Clear format** — or **HTML** to edit the code.
3. Press **Save**.
- "Pasted text is cleaned the same way. YouTube and Facebook videos are kept; other embedded boxes are dropped."
- An empty description asks first: "Save an empty description? The site will show none."
- The card shows "Last edited … by …".

**Photos, tags and barcodes** — needs the master key
1. Press **Edit** on the product.
2. **Upload photos** adds photos. **Make primary** chooses the main one. "This set has no photo of its own — the single's primary photo is shown."
3. Tags: "Tags are case-sensitive — pick from the list to keep one spelling. ✕ takes a tag off when you save."
4. Barcodes: add one in **Add a barcode**. "A new barcode can be made primary after saving."
5. Press **Check & save**. "Save checks every change on this page — prices, suppliers, barcodes and tags included."

**The web shop (Shopify card)** — managers and above (Shopify key)
Each store has a row on the product's Shopify card.
1. **Turn on** — "Send this to the Shopify store".
2. **Send now** sends it at once and shows the result. **Send stock now** sends the stock numbers.
3. **Turn off** — "Stop sending — the Shopify product becomes Archived (not deleted)".
4. **Choose photo** picks the first photo on Shopify.
- A product in a family shows "Sent to Shopify as a variant of its family". Switch it on with the Shopify card on its family (**Inventory ▾** › **Families** — see [Families](#stock-families)).
- "Sets are not sent to Shopify. Only a set marked sellable can be switched on."
- Without the key: "You can see this, but turning it on or off needs the Shopify permission."

<a id="stock-adjustments"></a>
## Stock adjustments
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: manager -->

**What it is**
A stock adjustment corrects the stock book to what is really on the shelf — after a count, a loss or damage.

**Who**
Admins, and managers or supervisors with the Stock adjustments key switched on. Others with the screen can only look: "Read-only — adjusting stock needs the Stock adjustments key."

**How**
1. Press **New adjustment**. Choose the **Warehouse** and write a **Note**. "One adjustment is one warehouse. The note cannot be changed later."
2. Press **Add line**. Choose the **Product** and the **Bin**.
3. **What to do**:
   - **Shelf holds** — type what is on the shelf; IMS works out the change.
   - **Add (+) or take (−)** — type the change itself.
4. Choose the **Reason**: **Found — more than the books**, **Lost / missing**, **Damaged / thrown out**, **Count difference** or **Other (note needed)**. Give a **Unit cost** when you add stock and know it.
5. Add more lines, then press **Confirm**.

**Example**
The book says 43 of DEMO-001 in a bin. The shelf has 40. Choose **Shelf holds** and type 40 — the change is −3. Or choose **Add (+) or take (−)** and type −3. Both give the same result.

**Good to know**
- From a "Not enough stock" report, **Adjust stock** on WMS Admin opens an adjustment already filled from where it was picked (see [WMS Admin](04-wms.md#wms-admin)).
- Adding stock with no known cost warns "These go into the books at cost 0".
- **Delete draft** removes an adjustment that is not confirmed.

**Watch out**
- A confirmed adjustment cannot be undone or deleted. Fix a mistake with a new adjustment.

<!-- SCREENSHOT: stock-adjustments-1 · Add a line with What to do = Shelf holds and the Change to the book -->

<a id="stock-bgrade"></a>
## B-grade stock
<!-- screen: stock-bgrade.html · BUILD 2026-10-23 · bgr v1 -->
<!-- who: manager -->

**What it is**
B-grade stock is damaged-package goods kept under the same SKU in a B-grade bin. It is left out of **On hand** and **Available**, is never picked for regular orders, and is sold at the POS only at its B-grade price. A bin is made a B-grade bin in **Settings** (see [Lists](07-settings.md#set-master)).

**Who**
The same people as stock adjustments — admins, and managers or supervisors with the Stock adjustments key.

**How — move stock to B-grade**
1. On **Inventory ▾** › **B-grade Stock**, press **Move to B-grade**.
2. Choose the **Product**, the **From bin**, the **To B-grade bin** and the **Quantity**, then save.
3. Press **Set price**. Type a price, or **% off Wholesale**. "Every unit of this SKU in this bin takes the new price."

**Good to know**
- **Reprice** changes the price. **Move back** returns stock to a regular bin.
- B-grade stock with no price cannot be sold at the POS (see [Sell B-grade](05-pos.md#pos-bgrade)).
- Moving does not change the cost.

<a id="stock-transfers"></a>
## Transfers between warehouses
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: office, warehouse -->

**What it is**
A transfer moves stock from one warehouse to the other. It goes through the warehouse like a sales order. It needs the transfer key.

**How**
1. On **Inventory ▾** › **Transfers**, press **New transfer**. Choose from and to, then **Add line** or **Paste lines**.
2. Press **Confirm**. Stock at the from warehouse is held for it (**Transfer res.**).
3. Press **Release to WMS**. The warehouse picks, checks and packs it (see [Pick an order](04-wms.md#wms-picking) and [Fulfillment](04-wms.md#wms-fulfillment)).
4. When the warehouse finalizes it, it leaves — **in transit**.
5. The to warehouse counts it on **Receiving** and completes it — **received** (see [Receive a PO or a transfer](04-wms.md#wms-receiving)). No office confirm is needed.

**When it does not match — needs the Stock adjustments key**
- **Less arrived**: press **Settle in transit**. For each line choose **Lost** or **Returned to sender** (back into a bin at the from warehouse), then **Save settlement**.
- **More arrived than was sent**: the to warehouse took only what was sent. Press **Decide** and choose **… sent more** or **Found at …**, then **Save decision**. "These may go into the books at cost 0."

**Good to know**
- If the pickers could not find everything, only what was picked leaves. The rest is closed on this transfer — make a new transfer for it.
- **Add freight charge** puts freight onto the cost of what arrived.
- Before release: **Back to draft**, **Delete draft**, **Cancel transfer**. After release: **Recall from warehouse**.

<!-- SCREENSHOT: stock-transfers-1 · a transfer in transit with Settle in transit -->

<a id="stock-bin-moves"></a>
## Bin moves in the office
<!-- screen: stock-moves.html · BUILD 2026-09-28 · sm v1 -->
<!-- who: office, warehouse -->

**What it is**
**Bin Moves (office)** moves stock between bins in one warehouse as a document: write it, then confirm it. The warehouse does the same by scanning on [Bin Moves](04-wms.md#wms-bin-moves).

**How**
1. Press **New move**. Choose the **Warehouse** and write a **Note** ("One move is one warehouse. The note cannot be changed later.").
2. **Add line**: **Product**, **From bin**, **To bin**, **Quantity**.
3. Press **Confirm**.

**Good to know**
- Stock that is "Picked, not shipped" or "Waiting for pickers" cannot move.
- When stock moves, pick plans that pointed at it move too ("Pick plans moved with this stock").
- It needs the Bin moves key: "Read-only — moving stock needs the Bin moves key."

<a id="stock-statuses"></a>
## What each status means
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 ; stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: all -->

**Transfers** (office screen)

| Status | Meaning |
|---|---|
| draft | Being written. |
| confirmed | Stock at the from warehouse is held for it. |
| at warehouse | Released — waiting on Split & Waves. |
| picking | The warehouse is working on it. |
| in transit | It left the from warehouse. |
| receiving | The to warehouse is counting it. |
| received | It arrived. |
| cancelled | Cancelled. |

The warehouse screens use their own words for the same steps — see [Warehouse statuses](04-wms.md#wms-statuses).

**Adjustments and bin moves**
**Draft** · **Confirmed**.

<a id="stock-csv"></a>
## CSV downloads
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: office, accounting -->

- **↓ CSV** on [Stock Availability](#stock-availability) downloads every product that matches the filters.
- **Product Sheet** works the other way: paste from Excel into the table (see [Product Sheet](#stock-sheet)).

<!-- rulings: 49, 50, 53, 83, 145, 176, 194, 200, 202, 204, 205, 206, 209, 210, 247, 257, 258, 885, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 567, 578, 629, 631, 632, 637, 638, 642, 644, 645, 646, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732, 735, 759, 762, 763 -->
