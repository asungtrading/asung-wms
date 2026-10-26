# 7. Settings

<!-- sections 1-11 written (manual-7a · 7b) · sections follow the work of admins and managers -->
<!-- out of this chapter: what each key opens -> chapter 0 Roles and keys · B-grade stock -> chapter 3 -->

<a id="set-start"></a>
## What is in Settings
<!-- screen: ims-auth.js · BUILD nav v13 ; system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: manager, admin -->

**What it is**
**Settings ▾** holds the lists and switches the rest of IMS uses: staff, brands, bins, carriers, deals, document layouts and the web shops. Most people only look; a few can change.

**Who can change what**

| Screen | You see it with | You can change it with |
|---|---|---|
| **Settings** — lists | the `master` key | the `master` key at write |
| **Settings** — Backorder emails · Documents · Google Drive | the `master` key | different for each part — see its section |
| **Surcharge Groups** | the `master` key | admins only |
| **Staff** | the `staff` key | the `staff` key at write, for people below your role |
| **Discount Rules** | the `master` key | the `master` key at write |
| **Shopify Stores** | the `shopify` key | the `shopify` key at write — check, link and push · admins add, change and pair stores |
| **System Check** | no key | — it only shows |

For the keys themselves, see [Roles and keys](00-getting-started.md#start-roles-keys).

**The sections**
- [Staff](#set-staff)
- [Lists: brands, units, payment terms, bins, carriers, services](#set-master)
- [Discount rules and deals](#set-deals) · [Coupons](#set-coupons)
- [Surcharge groups](#set-surcharge)
- [Documents](#set-documents) · [Backorder emails](#set-mail) · [Google Drive](#set-drive)
- [Shopify stores](#set-shopify)
- [System Check](#set-system-check)

<a id="set-staff"></a>
## Staff
<!-- screen: staff.html · BUILD 2026-10-20 · st v3a -->
<!-- who: manager, admin -->

**What it is**
**Staff** (**Settings ▾** › **Staff**) lists everyone who can sign in: name, email, role, keys and branches.

**Who**
A person with the `staff` key at write. "You can only create and edit people below your own rank." An admin can edit everyone.
- Without the key: "Read only — you need the 'staff' permission to change people."
- Someone at or above your role: "Read only — this person is at or above your own rank."
- Yourself: "Read only — you cannot edit your own record. Ask someone above you." An admin can edit their own name and note, but not their own role, status, keys or branches — "you would lock yourself out".

**How — add a person**
1. Press **+ Add staff**.
2. Type **Name** and **Email** (for example Staff C, staff.c@example.com). "This becomes the login email."
3. Choose the **Role**. You can only choose roles below your own.
4. Press **Create account**.
5. "Account created — hand these over once." Press **Copy** and give the email and the temporary password to the person. "This temporary password is shown only now. It cannot be retrieved later."
6. Press **Done**.

The new person signs in and sets their own password with **Change Password** (see [Sign in](00-getting-started.md#start-sign-in)).

**How — change a person**
1. Click the person in the list.
2. Change **Name**, **Role**, **Active** or **Note**.
3. **Access** — the keys:
   - Tick **WMS**, **IMS** or both to show that mode's keys. "With none ticked every screen shows."
   - For each key choose **none**, **read** or **write**.
4. **Location** — the branches. Tick the branches this person works in. "None ticked = every warehouse." It counts only for a manager or worker; a supervisor or admin works in every branch.
5. Press **Save**. **Revert** drops the changes.

**Good to know**
- "There is no delete — inactive people keep their row." To stop someone signing in, untick **Active**.
- If you untick a mode under **Access**, its keys are set to none when you save. The form warns in yellow first.
- The `cost` key also decides who sees supplier costs, price formulas and the cost columns in **↓ Export…**. It is off unless you switch it on. The person sees the change after reloading the screen.
- A forgotten password needs nothing from you. The person presses **Forgot your password?** on the sign-in screen (see [Sign in](00-getting-started.md#start-sign-in)).

**Watch out**
- The email is the login. It is shown, not changed.

<!-- SCREENSHOT: set-staff-1 · a person open on Staff with Role, Access and Location -->

<a id="set-master"></a>
## Lists: brands, units, payment terms, bins, carriers, services
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: manager, admin -->

**What it is**
**Settings** (**Settings ▾** › **Settings**) shows the lists on the left. Click a list to open it. Everyone with the `master` key sees them; the `master` key at write changes them.

**Every list**
- **Search** finds by name (or code). **Active only** hides what is switched off.
- ← and → move through the pages, 100 rows at a time.
- **Source** shows where a row came from: "manual" (made in IMS) or "before IMS".

**The lists**

| List | What it is for | You can |
|---|---|---|
| **Brand** | Product brands | add · switch off and on |
| **Category** | Product categories | add · switch off and on |
| **Unit** | Units of measure | add · switch off and on |
| **Currency** | Currencies | look only |
| **Payment Term** | Customer and supplier payment terms | add · switch off and on |
| **Account** | Accounts, by code | look only |
| **Warehouse** | Branches | look only |
| **Bin** | Shelf places in each branch — "Thousands of bins — search for the one you need" | add · switch off and on · mark B-grade |
| **Carrier** | "Picked at Ship & invoice — the kind decides email and tracking" | add · edit |
| **Service** | "Billed on service orders as quantity × unit price — tax follows the order" | add · edit |

Currency, Account and Warehouse are look only. Tax rules are picked on customers and orders, not kept here. If one of these needs to change, ask the IMS administrator.

**How — add to a list**
1. Open the list and press **+ Add** (for example **+ Add brand**).
2. Type the **Name**. "It cannot be renamed later — check the spelling first."
3. Fill the other boxes, if the list has them, and press **Add**.
- If the name is already there but switched off, IMS says so: untick **Active only**, find it and switch it on instead.

**How — switch off**
1. Press **Switch off** on the row. "Nothing is deleted — records that already use it keep it."
2. To use it again, press **Switch on**.

Names cannot be changed. To rename, switch the old one off and add a new one.

**Payment Term**
- **Net days** — "Days until the invoice is due — 0 = due on the invoice date."
- **Discount days** and **Discount %** — the early-payment discount, for example 10 days and 2% for 2% 10 Net 30. Fill both or neither.
- **Split** — "Paid in parts, e.g. 50% COD & 50% Net 30 — Net days is the later part".

**Unit**
"A set's unit is its pack number — a 12-pack set uses the unit 12."

**Bin**
- Choose the **Warehouse**, then the **Name** — "use the spelling on the shelf label".
- **Staging** — "A staging spot (dock, receiving area), not a shelf".
- **Mark B-grade** makes it a B-grade bin. "The bin must be empty in the books first." **Unmark B-grade** makes it a regular bin again — move its B-grade stock out first (see [B-grade stock](03-inventory.md#stock-bgrade)).

**Carrier**
1. Press **+ Add carrier**, or **Edit** on a row.
2. **Kind**: **Carrier — tracking number · shipping email**, **Pickup — customer collects** or **Delivery — our truck**. "The kind cannot change — it decides what old orders did."
3. For a carrier: **Shopify name** ("exactly as in Shopify's carrier list") and **Tracking link** ("{number} is replaced by each tracking number").
4. **Active** off = "not offered at Ship & invoice (old orders keep the name)". Press **Save**.

**Service**
1. Press **+ Add service**, or **Edit** on a row.
2. **Name** — "customers see this name on the invoice". It cannot change later.
3. **Unit price** — "Filled in when the service is picked on an order; staff can change it on the line." **Sales account** — the account it is booked to.
4. Press **Save**.

<!-- SCREENSHOT: set-master-1 · Settings with the lists on the left and Payment Term open -->

<a id="set-deals"></a>
## Discount rules and deals
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->

**What it is**
**Discount Rules** (**Settings ▾** › **Discount Rules**) holds the deals. A deal is a **Line discount** (a % off certain products) or an **Order discount** (a % off the whole order from a set amount). How the discounts meet on an order is in [Discounts, deals and surcharges](01-sales.md#sales-discounts-deals). This section is about making them.

**Who**
Everyone with the `master` key sees the deals. The `master` key at write makes and changes them.

**How — find a deal**
1. Choose **Live (on · not ended)**, **Off or ended** or **All**, and **Line discounts** or **Order discounts**.
2. Type in **Search deal name**. Click a deal to open it.
3. **Price check…** shows what one customer would pay for one product: choose **Customer**, **Product**, **Quantity** and **Order date**, then **Check**. "Line discounts only — the biggest one wins."

**How — make a line discount**
1. Press **+ New line discount**. Type the **Name**. Tick **Active**.
2. **From** and **To** — "Empty dates = always on. Dates are checked against the order date."
3. Under **Lines**, press **+ Add line**. Type the **Discount (%)**.
4. **Minimum**: **None**, **At least** a number each, or **Full case**.
5. Add what the line covers: **Applies to** or **Except**, then **Brand**, **Category**, **Tag** or **Product**, and press **Add**.
6. **Customers** (optional): **Only** or **Not**, then **Customer**, **Branch** or **Price tier**, and press **Add**. "No customer rules — every active customer."
7. Press **Create deal**.

**Example**
A line with **Discount (%)** 30, **Minimum** **At least** 6 each, **Applies to** **Product** DEMO-001. An order line of 6 or more DEMO-001 gets 30% off; 5 gets nothing from this deal.

**How — make an order discount**
1. Press **+ New order discount**. Type the **Name**, tick **Active**, set **From** and **To**.
2. Under **Amount tiers**, press **+ Add tier**. Type **Order total from ($)** and **Discount (%)**. Add more tiers for bigger orders.
3. Tick **Coupon required** if only orders with a coupon get it (see [Coupons](#set-coupons)).
4. Add **Customers** rules if needed, and press **Create deal**.

**How — change or switch off**
1. Open the deal and press **Edit**. "Change what you need, then save once — the server checks everything first."
2. To stop a line, press **Turn off** on it. "Lines that orders already used are turned off, not deleted."
3. To stop the whole deal, untick **Active**.
4. Press **Save**. IMS shows **What changes**, or **Please confirm** with warnings — then **Save anyway**.

**Good to know**
- **Paste lines…** adds many products at once — one per row: SKU, discount %, at least. For example `DEMO-001  30%  6`. "Nothing is added until you check the list."
- Customer rules: "Same kind = any of them · different kinds = all of them · a "Not" rule always wins."
- **Open orders using it** shows how many open orders the deal touches. After a change, those drafts suggest **Reprice** (see [Discounts, deals and surcharges](01-sales.md#sales-discounts-deals)).
- A deal cannot be deleted. Switch it off.

**Watch out**
- If someone else saved the deal after you opened it, nothing is saved. Press **Load the latest version** and make your change again.

<!-- SCREENSHOT: set-deals-1 · a line discount in Edit with Lines, Minimum and Applies to -->

<a id="set-coupons"></a>
## Coupons
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->

**What it is**
A coupon is a code for one customer on one order discount. "One code per customer · used once · on this deal only." Using a coupon on an order is in [Use a coupon](01-sales.md#sales-coupons).

**Who**
The `master` key at write.

**How — issue coupons**
1. Open an **Order discount** deal with **Coupon required** ticked.
2. Under **Coupons**, press **Issue coupons**.
3. Type part of a customer name and press **Find**. Click each customer to add.
4. **Expires on** — "empty = no limit · checked against the order date".
5. **Code prefix** — optional, 2–8 letters or digits.
6. Press **Issue n coupons**. The list shows each customer and code. Press **Copy list** to send the codes, then **Done**.

**How — void a coupon**
1. Press **Void** next to the code. "It can never be used after this." Add a note if you like.
2. If the coupon was on draft orders: "Voided. It was taken off … draft order(s)."

**Good to know**
- The heading shows how many are **unused**, **used** and **voided**.
- To change a coupon's last day, void it and issue a new one.

<!-- SCREENSHOT: set-coupons-1 · Issue coupons with customers picked and Expires on -->

<a id="set-surcharge"></a>
## Surcharge groups
<!-- screen: surcharge-groups.html · BUILD 2026-10-02 · sg v1 -->
<!-- who: admin -->

**What it is**
A surcharge group is a charge added per unit to certain products — for example a tariff. Products in an active group carry it on new sales order and POS lines.

**Who**
The `master` key sees the groups. Only admins change them.

**How — make a group**
1. Press **New group**.
2. **Name** — "This name is printed on the order line and the invoice."
3. **Charge as**: **% of the unit price** or **$ per unit**, and the amount.
4. Press **Check**, then **Save**.

**How — put a product in a group**
On the product, press **Edit** and choose the **Surcharge group** (see [Find and change a product](03-inventory.md#stock-products)).

**How — switch a group off or on**
- **Turn off**: "New sales order and POS lines stop picking this surcharge up. Products stay in the group, so turning it back on brings it back. Lines already on draft orders keep what they have."
- **Turn on**: "New sales order and POS lines for the products in this group pick the surcharge up again from now on."

**Good to know**
- The list shows **Products** in each group and **Open draft lines** that carry it.
- A surcharge on one order line can also be set by hand (see [Discounts, deals and surcharges](01-sales.md#sales-discounts-deals)).

<a id="set-documents"></a>
## Documents
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c ; ims-doc.js -->
<!-- who: admin -->

**What it is**
**Settings** › **Documents** sets what invoices, credit notes, sales orders, Ship Ready and internal receipts look like: the company details, the logo, the layout and the words.

**Who**
- Company details, logo, wording and columns: an admin, a supervisor or someone with the `master` key.
- Layouts — upload and **Use this version**: an admin, or a supervisor with the Document templates key.

**How — company details**
1. Fill **Name**, **HST no.**, **Website**, both branches (**Label**, **Street**, **City · province · postal**, **Phone**, **Email**), **Terms & conditions** and **Date format**.
2. Press **Save company details**. "Both branches print at the top of every document. A branch with no street is left out."
3. **Logo**: choose a PNG or JPEG up to 2 MB and press **Upload logo**. **Remove logo** prints the company name instead.

**How — choose the layout**
1. Under **Document**, choose the kind.
2. **Layout in use** shows the version printing now, and the list of versions.
3. To see one, type a number under **Preview** and press **Preview the layout in use** or **Preview the layout in the box**. "Uses a real document. Nothing is saved or sent."
4. On a version that **Passed**, press **Use this version**. "Documents already printed or sent do not change."

To go back to an older layout, press **Use this version** on the older version. "Older versions are kept — nothing is deleted."

**How — add a new layout version**
1. Upload the layout file you were given, or paste it in the box.
2. Type what changed and press **Check**. Fix anything that is not accepted.
3. Press **Save as new version**. "Saving does not change what prints until you press Use this version."

**How — wording and columns**
1. **Title**, and the switches **UPC column**, **Line comments** and **Account code on freight lines**.
2. **Email subject** and **Email message** — the subject and message of the email that carries this document. Sending is on [Print and email](01-sales.md#sales-print-email).
3. Press **Save wording & columns**.

**Watch out**
- "This document cannot print until a layout is in use."

<!-- SCREENSHOT: set-documents-1 · Documents with Layout in use, the version list and Preview -->

<a id="set-mail"></a>
## Backorder emails
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: admin -->

**What it is**
**Settings** › **Backorder emails** controls the emails that tell customers their backordered goods have arrived.

**Who**
Each setting shows who can change it: "Only an admin can change this." or "Only a manager with the master permission can change this." Each one shows who changed it last.

**How**
1. **Emails** — **Turn on** or **Turn off**. On: "Runs start on the scheduled mornings and emails go out." Off: "Emails that are already waiting stay waiting until this is on."
2. **Test mode — send every email to** — an address here gets every email instead of the customer. Leave it empty for real customers.
3. **Sent from** — the address customers see. It must be set up as a "Send mail as" address in the company mailbox.
4. **Sender name** and **Replies go to** ("Empty = replies go to the "sent from" address").
5. **Schedule** — for each branch tick **Send for this branch**, the days, the hour and the time zone. Press **Save schedule**.
6. **Part of a line that came in** — the % of the backordered quantity that must arrive before the customer gets an email. Press **Save**.

**Good to know**
- "Each branch runs once on each checked morning at that hour in its own time." "Holidays are not skipped."
- Stock from a purchase receipt or a transfer counts toward the %. "Stock from returns, adjustments or counts is emailed only when the whole line can ship. Each line is emailed once."

<a id="set-drive"></a>
## Google Drive
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: admin -->

**What it is**
**Settings** › **Google Drive** sends a kept copy of invoices, credit notes and PO documents to the company's shared drive (see [Upload the supplier's documents](02-purchasing.md#purch-documents)).

**Who**
Only an admin changes it. Others see "Only an admin can change this."

**How**
1. **Start date** — pick a date and press **Save**. "Invoices and credit notes issued on or after" this date "get a kept copy (the PDF as it looked when issued) and go to Drive." **Clear** stops new copies.
2. **Send to Drive** — **Turn on** or **Turn off**. On: "Waiting files go to the shared drive every minute." Off: copies are still made and wait.
3. **Shared drive** — the id of the shared drive, and **Open in Drive**. "Change it only for a test drive."

**Queue**
Shows how many files of each kind went, how many are waiting, and a **Failed** list with the file, the error and how many tries.

**Good to know**
- With **Start date** empty, nothing is kept for Drive and nothing is queued.
- A failed file is tried again by itself. If it keeps failing, tell the IMS administrator.
- **System Check** shows the same summary (see [System Check](#set-system-check)).

<!-- SCREENSHOT: set-drive-1 · Google Drive with Start date, Send to Drive and Queue -->

<a id="set-shopify"></a>
## Shopify stores
<!-- screen: shopify-stores.html · BUILD 2026-10-20 · ss v3a -->
<!-- who: admin, manager -->

**What it is**
**Shopify Stores** (**Settings ▾** › **Shopify Stores**) connects IMS to each web shop: which prices it shows, which warehouse sends its stock, and which products are linked.

**Who**
- The `shopify` key at read: look only.
- The `shopify` key at write: **Check connection**, link products and push them.
- Admins: **New store**, **Edit**, **Turn off** / **Turn on**, and pairing locations.

**How — a store (admins)**
1. Press **New store**. Give the **Code** ("It cannot be changed later"), the **Label**, the **Shopify address**, the **Price tier** and **Compare-at tier**.
2. **Sell when out of stock**: **Allow** (take orders at zero stock) or **Don't allow** (stop at zero stock).
3. Choose **Send tags** and leave **Key name** as it is unless told otherwise.
4. Press **Check**, then **Save**.

**How — check and pair locations**
1. Press **Check connection**. **Shopify says** lists the store's locations.
2. Admins: for each Shopify location choose the IMS warehouse and press **Pair**. "Stock for this location will come from that warehouse, and orders shipped from it will be marked shipped from this location."
3. **Unpair** stops it.

**How — link existing products (once, before the first push)**
1. Under **Link existing products**, press **Read products from Shopify**. "It only reads Shopify, nothing is changed there."
2. Press **Plan**. **Show lines** shows each Shopify product and the decision; **Download CSV** gives all of them.
3. Press **Apply links**. "Stock is sent right away." Product details are not sent yet.

**How — push product details**
1. Under **Push linked products**, press **Show what is left**. It lists brands and how many products are left.
2. Press **Send…** on a brand. Check a few in Shopify.
3. When they look right, press **Send all left (n)…**.
- "Sending pushes IMS product details (title, description, price, photos, tags, variants) to Shopify." They reach Shopify over the next minutes.

**Good to know**
- Products are switched on for a store on the product's Shopify card (see [Descriptions, photos, tags and the web shop](03-inventory.md#stock-descriptions)).

<!-- SCREENSHOT: set-shopify-1 · a store with Location pairs and Push linked products -->

<a id="set-system-check"></a>
## System Check
<!-- screen: system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: all -->

**What it is**
**System Check** (**Settings ▾** › **System Check**) shows how IMS sees you. Everyone can open it.

**What it shows**
- **Signed in as** — your name, email and role.
- **Access** — your modes, your keys (read or write), the keys you do not have, and your warehouses.
- **Screens open to you** — every screen you can open, as links.
- **Google Drive** — start date, on or off, waiting and failed (see [Google Drive](#set-drive)).
- **Database connection** — whether IMS can reach its data.
- **Build** — the build tags (see [The build tag](00-getting-started.md#start-build-tag)).

**When**
When a screen or button is missing, or IMS does not open as it should.

**How**
1. Open **System Check**.
2. Take a screenshot of the whole page.
3. Send it with your question (see [Getting help](00-getting-started.md#start-getting-help)).

<!-- rulings: 150, 151, 166, 231, 232, 283, 330, 331, 332, 343, 493, 518, 521, 526, 534, 538, 555, 563, 564, 636, 668, 687, 692, 707, 708, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732, 738, 764 -->
