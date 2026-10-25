# 4. WMS (warehouse)

<!-- sections 1-12 written (manual-4a · 4b) · sections follow the order of the work, not the order of the screens -->

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
<!-- screen: wms-manager.html · BUILD 2026-09-29 · wm v1.2 ; wms-picklist.js -->
<!-- who: manager -->

**What it is**
When the office presses **Release to WMS**, the order appears on **Split & Waves** under **Released to WMS**. The manager turns it into pick work: a big order is split into batches, and small orders are grouped into a wave.

**How — Managers and above: split a big order**
1. Open **Split & Waves** and keep **Split** selected.
2. Pick an order on the left.
3. Set **max lines per batch** and **max units**. "Both values are ceilings applied together — a batch is cut when adding the next line would exceed either limit." A single line larger than max units becomes its own batch.
4. Press **Preview** to see the batches, then **Create batches** and confirm.
5. The pick lists print, one per batch — for example `SO-99001-1`, `SO-99001-2`. Put them on the board.

**How — Managers and above: group small orders into a wave**
1. Press **Group**.
2. "Tap orders to add them to the wave — up to 10 totes, one warehouse." Choose at least 2 orders.
3. "Selection order = tote number" — the first order you tap goes into tote 1.
4. Press **Create wave** and confirm. One pick list prints for the whole wave, for example `W-1025-1`.

**Good to know**
- Filter by warehouse (**All**, TOR, EDM) or by price tier (**All tiers**).
- Transfers between warehouses show with the tag **Transfer** and are split the same way.
- Packing and fulfillment check every tote of a wave as its own order.

<!-- SCREENSHOT: wms-waves-1 · Split with max lines and max units filled and the batch preview -->

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
- Transfers between warehouses are picked the same way (see [Transfers between warehouses](03-inventory.md#stock-transfers)). The transfer number shows where the order number is, and the destination warehouse where the customer name is.
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
<!-- screen: wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 ; wms-packing.js -->
<!-- who: warehouse -->

**What it is**
**Fulfillment** puts checked orders into pallets and boxes, prints the packing lists, and finishes the warehouse's part with **✓ Finalize order(s)**.

**When**
An order appears here only when all its batches are checked on **Packing** — "it appears here when ALL are packed".

**How**
1. Press **Select orders ▾**, tick the "Orders to ship together", and press **Start working selected orders**. You can also scan a pick list.
2. Press **+ Pallet** or **+ Box**. Type **L**, **W**, **H** and **Weight** for each unit. **+ Nest box** puts a box on a pallet.
3. Put products into a unit: "Drag, tap, or scan products into a pallet or box." Tap a pallet or box first to make it the target.
4. Scanning works in two ways: **Scan qty** (one scan, one unit) or **Move all** (one scan moves all of that product still unassigned). **↩ Undo last scan** takes the last one back.
5. When nothing is left under **Unassigned products**, print: **🖨 Box list**, **🖨 Pallet list**, a store's **🖨 List**, or **🖨 All stores (at once)**.
6. Press **✓ Finalize order(s)** and confirm. "Finalized orders leave the fulfillment board." The office now does **Ship & invoice** (see [Ship & invoice](01-sales.md#sales-ship-invoice)).

**Transfers** (see [Transfers between warehouses](03-inventory.md#stock-transfers))
- A sale and a transfer cannot be worked together: "A sale and a transfer cannot be on the same workbench — finish or clear one first".
- A finalized transfer leaves at once: "… left for … — in transit".
- A transfer that was short is closed with what was sent — it does not make a backorder.

**Good to know**
- **Delete** on a unit returns its products to unassigned.
- "A box can only go on a pallet."

<!-- SCREENSHOT: wms-fulfillment-1 · Fulfillment board with a pallet, a nested box and Unassigned products -->

<a id="wms-receiving"></a>
## Receive a PO or a transfer
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 -->
<!-- who: warehouse, manager -->

**What it is**
Receiving counts what arrived against the PO or the transfer. Then you put it away (see [Put away](#wms-putaway)).

**When**
Only POs whose supplier invoice the office has confirmed can be received (see [Record the supplier's invoice](02-purchasing.md#purch-invoice)): "No POs with a confirmed invoice to receive — the office confirms the supplier invoice first."

**How**
1. Open **Receiving**. Scan the PO barcode, or press **↻ POs** and choose one (for example PO-99001 from Supplier B). Press **Start** (or **Resume**).
2. Scan each item. "box scan = ×factor units" — a box barcode counts the whole box.
3. If an item will not scan, press **Enter quantity** and type it.
4. Sort the list by **PO order**, **SKU**, **Product** or **Zone / Last bin** to match how you walk.
5. When everything is counted, press **Putaway →**.

**What can happen**

| Case | What IMS says | Result |
|---|---|---|
| More than the invoice | "exceeds expected quantity … More than the invoice — the extra is put away and the office decides it (off-invoice)" | Put it away. The office decides. |
| An item not on the PO | "not on this PO. Add as OFF-INVOICE …? Put it away as usual — the office accepts or rejects it later." | Same. |
| Less than the invoice | "Anything not counted is kept as short — the order stays open so the rest can be received on it later" | The PO stays open for the rest. |
| Two people typed the same line | **Quantity conflict** — **Keep theirs**, **Use mine** or **Recount** | Choose one. |
| A transfer | "Complete = arrival … anything not received stays in transit for the office to settle." | The office settles the rest on **Transfers** (see [Transfers between warehouses](03-inventory.md#stock-transfers)). |

**Good to know**
- **Hold (later)** and **Resume** work as in [Pick an order](#wms-picking).
- **⚑** reports (wrong barcode, image) work as in picking.
- If the office rejects an item, the line says "Rejected — take it off the shelf". Take it off and press **Removed**.
- The office sees the same receipt on **Purchase Receipts** (see [Receipts in the office](02-purchasing.md#purch-receipts)).

**Watch out**
- Count everything that arrived before you finish. "Unknown barcode — ask the office to register the product" means the product is not set up yet.

<!-- SCREENSHOT: wms-receiving-1 · a receiving line with the "exceeds expected quantity" question -->

<a id="wms-putaway"></a>
## Put away
<!-- screen: wms-receiver.html · BUILD 2026-10-21 · rc v1.9 ; wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: warehouse, manager -->

**What it is**
Put away places the received items in their bins. "The suggested bin is where this product was last kept."

**How**
1. After **Putaway →**, "Walk the route below and place items at each bin."
2. Each product shows its **Last bin**, or **No last bin**. Press **Assign bin** (or **Change**) to choose another: "Scan the bin barcode — or pick from the list below".
3. Put the items in the bin and tap **Placed**.
4. When everything is placed, press **Complete** and confirm. The receipt is finished in the warehouse.

**Confirm receipt — needs the receiving-confirm key**
The goods count in stock only after the receipt is confirmed. "This writes the stock ledger and cannot be undone here." It can be done in three places:
- On this screen, **Confirm receipt** — for a manager whose `wms_receiving_confirm` key is switched on.
- On **WMS Admin** › **Receiving**, **Confirm into stock** — same key.
- On **Purchase Receipts** in the office (see [Receipts in the office](02-purchasing.md#purch-receipts)).
The window says whether the PO "stays open" for more or "closes on confirm".

**Watch out**
- A bin name IMS does not know: "… is not a bin at … — ask the office to add it".
- **← Receiving** goes back to counting. After **Complete**, only a manager can reopen the receipt ("ask a manager to reopen it").

<!-- SCREENSHOT: wms-putaway-1 · the putaway route with Last bin and Placed -->

<a id="wms-bin-moves"></a>
## Move stock between bins
<!-- screen: wms-mover.html · BUILD 2026-10-05 · mv v2.3 -->
<!-- who: warehouse -->

**What it is**
**Bin Moves** moves stock from one bin to another in the same warehouse.

**How**
1. "Scan the FROM bin" (or press **List**). **Show what is here** lists what the bin holds.
2. "Scan the product", type the quantity (**All** for everything) and press **Add to list** — or **Add all in this bin**.
3. "Scan the bin you put it in" (the TO bin).
4. Press **Move**. IMS shows the move number and "from → to". **Start over** clears the list.

**Good to know**
- **Recent moves in this warehouse** shows the last moves.
- Stock that is "Picked, not shipped" or "Waiting for pickers" cannot move.

**Watch out**
- Moving stock needs the Bin moves key, switched on person by person: "You can look at bin moves but not make them — moving stock needs the Bin moves key. Ask a manager to switch it on for you."

<a id="wms-stock-lookup"></a>
## Look up stock
<!-- screen: wms-stock.html · BUILD 2026-10-20 · ws v1a -->
<!-- who: warehouse -->

**What it is**
**Stock Lookup** shows where a product is and how much. "Scan or type — both branches are shown." Anyone who can open WMS can use it.

**How**
1. Scan a barcode, or type a SKU or name.
2. For each branch you see the bins, **Available**, **Allocated to sales orders** and **Held for transfers out**. Tap them to see which order or transfer holds the stock.
3. Press **Recent movements** to see what came in and went out.

**Good to know**
- The **Value** line shows only for people with the `cost` key.
- "Opening stock from the starting count is not listed as a movement here."
- The office sees the same numbers on [Stock Availability](03-inventory.md#stock-availability).

<a id="wms-admin"></a>
## WMS Admin
<!-- screen: wms-admin.html · BUILD 2026-10-05 · wa v1.17 -->
<!-- who: manager -->

**What it is**
**WMS Admin** is the warehouse manager's screen. It has nine tabs: **Status**, **Health**, **Discrepancy**, **Receiving**, **Reports**, **Rollback**, **Finalized**, **Stats** and **Trace**. Managers and above open it.

**Rollback — take an order back one stage**
"There is no one-click void — undo one stage at a time and check the goods on the shelf at each step."
1. Open **Rollback** and find the order. **Current stage** shows where it is.
2. Press the button for that stage: **↩ Undo Finalize**, **↩ Undo Fulfillment**, **↩ Undo Pack**, **↩ Reset Pick** or **↩ Undo Split**. A wave has **Undo Wave**.
3. Each window lists what it removes — for example "Undo split for … Deletes ALL batches for this order … The order returns to Released to WMS — the office can recall it from there". Press OK.
4. Repeat until the order is at **Released to WMS**. The office then presses **Recall from WMS** (see [Take an order back](01-sales.md#sales-undo)).
- "On a pallet — Undo Fulfillment first." · "Finalized — undo finalize first."
- If your access is limited to some warehouses, you only see and roll back their orders.

**Reports — problems the workers flagged**
"wrong location · barcode changed · image differs · not enough stock (from picking/packing)"
1. Open **Reports** and check each one on the shelf.
2. For not enough stock, **Adjust stock** opens a stock adjustment for that product (for people with the stock adjustment key — see [Stock adjustments](03-inventory.md#stock-adjustments)).
3. Press **Mark resolved** when it is dealt with.

**Receiving — receipts waiting for the office**
- **Completed — awaiting office confirmation**: **Review**, **Reopen** ("Complete is undone and the receipt can be changed again in the receiving screen") or **Confirm into stock** (see [Put away](#wms-putaway)).
- **Off-PO / off-invoice items waiting for a decision** and **Awaiting putaway** ("stock the pickers cannot find").

**The other tabs**
- **Status** — orders in progress and **Live now**: who holds which batch. **Release** returns a batch whose holder is away to the waiting pool, progress kept.
- **Discrepancy** — mistakes by worker (short pick, over-pick …). **✓ Resolved** closes one.
- **Finalized** — reprint a finalized order's packing list: **🖨 Print**, **⬇ PDF**, **⬇ CSV**.
- **Health** — checks that must always hold. "a red card means the rule broke and needs review" — tell the IMS administrator.
- **Stats** — batches, times and mistakes for **Today**, **This week**, **This month** or **All**.
- **Trace** — who worked on an order, when and where.

<!-- SCREENSHOT: wms-admin-1 · Rollback with Current stage and the Undo buttons -->

<a id="wms-statuses"></a>
## Warehouse statuses
<!-- screen: wms-picker.html · BUILD 2026-10-20 · pk v1.5b ; wms-fulfillment.html · BUILD 2026-10-01 · fu v1.3 ; so.html · BUILD 2026-10-25 · so cf words v1 -->
<!-- who: all -->

**Sales orders**

| Warehouse screens | Sales screens | Meaning |
|---|---|---|
| Released to WMS | Released to WMS | Waiting on **Split & Waves**. |
| Working | Working | Being picked, checked or packed. |
| Finalized | Finalized | Warehouse done — the office's turn for **Ship & invoice**. |
| Shipped | Invoice cancelled | The same status. The goods have left; the invoice was cancelled and must be issued again. |
| Fulfilled | Fulfilled | Done. |
| Cancelled | Cancelled | Closed. |

See also [What each status means](01-sales.md#sales-statuses).

**Transfers**
Confirmed · Released to WMS · Working · **In transit** · **Receiving** · **Received** · Cancelled.
A transfer has no **Finalized**. When the warehouse finalizes it, it goes straight to **In transit**.

<!-- rulings: 17, 20, 21, 25, 72, 74, 83, 84, 88, 224, 567, 578, 600, 709, 713, 714, 715, 719, 720, 723, 725, 728, 731 -->
