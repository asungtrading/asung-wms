# 3. Inventory

<!-- sections 1-12 · manual-3a writes stock-availability, stock-products, stock-new-product, stock-families · the rest manual-3b · sections follow the order of the work, not the order of the screens -->

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
<!-- screen: products.html · BUILD pr v5f -->
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
- Products are never hidden — inactive products can still be found.
- To change many products at once, use [Product Sheet](#stock-sheet).

<a id="stock-new-product"></a>
## Add a new product, sets and combos
<!-- screen: products.html · BUILD pr v5f -->
<!-- who: office, manager -->

**What it is**
A **set** is a case or pack of the same product, for example a case of 6. Stock is counted in single units. A **combo** is one SKU made of different products; the components hold the stock.

**How — a new product (needs the master key)**
1. Press **+ New product**.
2. Fill in **Barcode(s)** ("one or more — the first is primary"), **Brand**, **SKU**, **Name**, **Category**, **Unit** and **Weight**. **Suggest** makes a SKU from the "Brand prefix + barcode digits".
3. Type the **Sale prices** for each tier.
4. Add the **Supplier**, **Supplier SKU**, **Cost** and, if there is one, **Fixed cost**.
5. To make sets at the same time, press **+ ×6**, **+ ×12** or **+ other**. "Leave the name of a set blank to get the usual name." For example DEMO-001 with a set of 6 → DEMO-001-6.
6. Press **Check & create**. Fix anything under "Not saved — fix these first", or pass the warnings with **Save anyway**.

**How — add a set to an existing product**
1. Open the single product and press **Add set**. **Sets now** shows the sets it already has (✓).
2. Press **+ ×6**, **+ ×12** or **+ other** for the new set, and type its case barcode if it has one (for example `0000000000017`).
3. Press **Check & add**.

**How — make a combo**
1. Open the product that will be the combo SKU and press **Make combo**.
2. Add each component SKU and how many go into one combo, then save in that window.
3. Later, **Edit components** changes them and **Release combo** turns it back into a normal product.

**Watch out**
- A set cannot become a combo, and a combo cannot have sets.
- Components are saved in their own window, separately from **Edit**.

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
<!-- screen: product-sheet.html · BUILD sheet v2b -->
<!-- who: office, manager -->
<!-- TODO manual-3b -->

<a id="stock-descriptions"></a>
## Descriptions, photos, tags and the web shop
<!-- screen: products.html · BUILD pr v5f ; ims-desc.js ; ims-shop.js -->
<!-- who: office, manager -->
<!-- TODO manual-3b -->

<a id="stock-adjustments"></a>
## Stock adjustments
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 -->
<!-- who: manager -->
<!-- TODO manual-3b -->

<a id="stock-bgrade"></a>
## B-grade stock
<!-- screen: stock-bgrade.html · BUILD 2026-10-23 · bgr v1 -->
<!-- who: manager -->
<!-- TODO manual-3b -->

<a id="stock-transfers"></a>
## Transfers between warehouses
<!-- screen: transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: office, warehouse -->
<!-- TODO manual-3b -->

<a id="stock-bin-moves"></a>
## Bin moves in the office
<!-- screen: stock-moves.html · BUILD 2026-09-28 · sm v1 -->
<!-- who: office, warehouse -->
<!-- TODO manual-3b -->

<a id="stock-statuses"></a>
## What each status means
<!-- screen: stock-adjustments.html · BUILD 2026-10-01 · adj thumb v1 ; transfers.html · BUILD 2026-10-21 · tf cost v1 -->
<!-- who: all -->
<!-- TODO manual-3b -->

<a id="stock-csv"></a>
## CSV downloads
<!-- screen: stock.html · BUILD 2026-10-25 · stk filt v1a -->
<!-- who: office, accounting -->
<!-- TODO manual-3b -->

<!-- rulings: 145, 176, 194, 200, 202, 209, 210, 247, 257, 258, 567, 578, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732 -->
