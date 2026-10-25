# 4. WMS (warehouse)

<!-- sections 1-12 · manual-4a writes wms-start, wms-picking, wms-pick-short, wms-packing · the rest manual-4b · sections follow the order of the work, not the order of the screens -->

<a id="wms-start"></a>
## Get into WMS
<!-- screen: ims-auth.js · BUILD nav v12 -->
<!-- who: warehouse, manager -->

**What it is**
WMS is the warehouse mode of IMS. Its screens are made for tablets and barcode scanners: picking, checking, packing, receiving and moving stock.

**How**
1. Sign in as usual (see [Sign in](00-getting-started.md#start-sign-in)).
2. If you also use IMS or POS, press **WMS** next to the Asung logo.
3. The screens sit in a row of tabs: **Split & Waves** · **Picking** · **Packing** · **Fulfillment** · **Receiving** · **Bin Moves** · **Stock Lookup** · **WMS Admin**. You only see the ones you have a key for.
4. Your first screen is **Split & Waves** if you are a manager, otherwise **Picking**.
5. **☰ Menu** lists the same screens. **Manual** at the end of it opens this manual in a new tab.

**Scan or press**
- "Scan" means: point the scanner at the barcode. The screen keeps its scan box ready, so you do not need to tap it first.
- "Press" means: tap the button on the screen.
- A pick list (the paper) has its own barcode. Scanning it opens that batch on the screen.

**Good to know**
- **🗺 Map** opens the warehouse map in a new tab. The stock on the map is updated once a day.
- WMS screens have no **Change Password** button. Change your password on an IMS screen.
- **Sign Out** is at the top right. On a shared tablet, sign out when you finish.

<a id="wms-waves"></a>
## Split orders into batches and waves
<!-- screen: wms-manager.html · BUILD 2026-09-29 · wm v1.2 -->
<!-- who: manager -->
<!-- TODO manual-4b -->

<a id="wms-picking"></a>
## Pick an order
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b -->
<!-- who: warehouse -->

**What it is**
Picking takes the items off the shelves for one batch (part of an order) or one wave (several small orders on one route). Each batch has a printed pick list with a barcode such as `SO-99001-1`. A wave's barcode looks like `W-1025-1`.

**When**
When your manager has made batches on **Split & Waves** and the pick lists are on the board.

**How**
1. Open **Picking**. You see **My In Progress**, **Waiting Batches** and **Waiting Waves — one route, sort into totes**.
2. Take a pick list from the board and scan its barcode (or press **Start** on a waiting batch). The batch is now yours.
3. The screen shows one line at a time (**Single**) or all lines (**List**). Each line shows the bin, the product and its photo.
4. Go to the bin and scan each item. "single scan = barcode-unit quantity" — scanning a case barcode counts the whole case.
5. If an item will not scan, press **Enter quantity** and type it.
6. Press **Next →** to go on. **← List** goes back to the list of batches.
7. When every line is complete, press **Pick complete**.

**Hold and take over**
- **Hold (later)**: "Your progress is saved and the batch returns to the waiting list. You or another worker can resume it later."
- **Resume** opens your own held batch again.
- A batch left by someone who went away shows **Take over**. Scanning its pick list also takes it over. What they picked is kept.
- If someone else takes your batch, your screen shows "⚠ Ownership changed". Press **Reload**. Quantities you typed after that were not saved.

**Problems with an item**
- **⚑ Wrong location** — the item is not where the list says. IMS asks where you found it.
- **⚑ Barcode changed** — the barcode on the item is different.
- **⚑ Image differs** — the photo does not match the product.
Each one goes to the manager's list. You keep picking.

**Good to know**
- **🖨 Print** reprints the pick list.
- Transfers between warehouses are picked the same way. The transfer number shows where the order number is, and the destination warehouse where the customer name is.
- A line marked "Part of a combo" is picked like any item. The combo is put together later.

**Watch out**
- If you put a pick list back on the board, close the batch on your screen too (**Hold (later)**). Otherwise two people can end up picking the same order.

<!-- SCREENSHOT: wms-picking-1 · Picking in Single view: bin, product photo, scan box, Hold (later) and Pick complete -->

<a id="wms-pick-short"></a>
## When an item is short
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; wms-confirm-modal.js -->
<!-- who: warehouse -->

**What it is**
Sometimes the shelf does not have enough. What you do depends on why.

| What you find | What to do | What it means |
|---|---|---|
| The planned bin is empty, but the item is somewhere else | Press **⇄ Different bin**, tick **This bin was empty (tell the manager)** and pick from another bin | The manager is told. You still pick the full quantity. |
| The item is really not there | Press **⚠ Not enough stock** | A stock problem, not your mistake. It goes to the manager to check the shelf. |
| You still have to finish with less | Press **Complete as incomplete** | The order goes on with less. The office ships what was picked, and the rest becomes a backorder. |

**How — not enough stock**
1. Pick what you can find.
2. On that line press **⚠ Not enough stock**.
3. IMS asks "Declare NOT ENOUGH STOCK on the shelf? Needed 30, you could only find 18. This is NOT counted as a picker mistake …". Press OK.
4. The button shows **✓ Not enough stock**. Press it again to cancel the declaration.

**How — pick from another bin**
1. On the line press **⇄ Different bin**. The window **Pick from a different bin** shows the **Planned** bin and lists the other bins with stock.
2. If the planned bin was empty, tick **This bin was empty (tell the manager)**.
3. Choose a bin, or type its name in "Other bin — type its name" and press **Select**.
4. Press **Pick from …** and scan as usual.

**How — finish short**
1. Press **Complete as incomplete**.
2. If a short line was not declared, a window asks you to type the short quantity: "Type the short quantity to enable End". Then press the **End** button.

**Example**
SO-99001-1 needs 30 of product X. The shelf has 18. Pick 18, press **⚠ Not enough stock**, then **Complete as incomplete**. At **Ship & invoice** the 12 become a backorder order, and the customer keeps the price they were quoted.

**Watch out**
- A shortage you do not declare is counted as your mistake. Press **⚠ Not enough stock** whenever the shelf really is short.
- **Pick complete** does not work while a line is short — "There are short lines. Press 'Complete as incomplete'."

<a id="wms-packing"></a>
## Check a picked order (Packing)
<!-- screen: wms-packer.html · BUILD 2026-10-20 · pa v1.6b ; wms-confirm-modal.js -->
<!-- who: warehouse -->

**What it is**
**Packing** checks a picked batch by scanning every item again. The target is the quantity the customer ordered. Putting items into boxes and on pallets comes after, on **Fulfillment**.

**How**
1. Open **Packing**. You see **My In Progress** and **Pack Queue** — batches whose picking is complete.
2. Scan the pick list (or choose a batch). The batch is now yours.
3. Scan every item in **Verify: scan a barcode…**. Each line fills toward the ordered quantity. If an item will not scan, press **Enter quantity** and type it.
4. If the picker was short, the screen says "⚠ Pick incomplete — Find and fill the quantities below from other locations". Get the missing items from another bin and scan them.
5. Press **Complete pack**.
6. When every batch of the order is checked, IMS says the order "is ready to be finalized" — it moves on to **Fulfillment**.

**Too many scanned**
If a line goes over, the screen shows "⚠ Over-scan — count the items". Count what is really there and choose for that line:
- **Picker brought extra — N items are here** — there really are too many. Put the extra back. It is recorded as a picker mistake.
- **I scanned twice — only N are here** — the count is right; you scanned one twice. It is not counted as anyone's mistake.
- **← Go back and recount** if you are not sure.

**Good to know**
- **Search SKU / product…** finds a line quickly. **Clear** empties the search.
- **Hold (later)**, **Resume** and taking over work as in [Pick an order](#wms-picking).
- **⚠ Not enough stock** works here too, after you have checked the shelf.

**Watch out**
- Choose **I scanned twice** honestly. It protects the picker from a mistake that was not theirs, and it is not held against you.
- If a line is still short when you press **Complete pack** and nobody declared it, you have to type the short quantity before you can finish.

<!-- SCREENSHOT: wms-packing-1 · Packing with the "Over-scan — count the items" choices open -->

<a id="wms-fulfillment"></a>
## Pack into boxes and pallets (Fulfillment)
<!-- screen: wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-receiving"></a>
## Receive a PO or a transfer
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse, manager -->
<!-- TODO manual-4b -->

<a id="wms-putaway"></a>
## Put away
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-bin-moves"></a>
## Move stock between bins
<!-- screen: wms-mover.html · BUILD 2026-10-05 · mv v2.3 -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-stock-lookup"></a>
## Look up stock
<!-- screen: wms-stock.html · BUILD 2026-10-20 · ws v1a -->
<!-- who: warehouse -->
<!-- TODO manual-4b -->

<a id="wms-admin"></a>
## WMS Admin
<!-- screen: wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: manager -->
<!-- TODO manual-4b -->

<a id="wms-statuses"></a>
## Warehouse statuses
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->
<!-- note for 4b: pair table with the sales chapter — same status: warehouse screens Shipped · sales screens Invoice cancelled (manual-4a review reply) -->
<!-- TODO manual-4b -->

<!-- rulings: 17, 20, 21, 25, 83, 224, 709, 713, 714, 715, 719, 720, 723, 725, 728, 731 -->
