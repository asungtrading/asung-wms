# 7. Settings

<!-- sections 1-3 written (manual-7a) · sections 4-11 follow in manual-7b · sections follow the work of admins and managers -->
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
| **Shopify Stores** | the `shopify` key | admins add and pair stores |
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
- A forgotten password needs nothing from you. The person presses **Forgot your password?** on the sign-in screen (see [Sign in](00-getting-started.md#start-sign-in)).

**Watch out**
- The email is the login. It is shown, not changed.

<!-- SCREENSHOT: set-staff-1 · a person open on Staff with Role, Access and Location -->

<a id="set-master"></a>
## Lists: brands, units, payment terms, bins, carriers, services
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
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
<!-- TODO manual-7b -->

<a id="set-coupons"></a>
## Coupons
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->
<!-- TODO manual-7b -->

<a id="set-surcharge"></a>
## Surcharge groups
<!-- screen: surcharge-groups.html · BUILD 2026-10-02 · sg v1 -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-documents"></a>
## Documents
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b ; ims-doc.js -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-mail"></a>
## Backorder emails
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-drive"></a>
## Google Drive
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-shopify"></a>
## Shopify stores
<!-- screen: shopify-stores.html · BUILD 2026-10-20 · ss v3a -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-system-check"></a>
## System Check
<!-- screen: system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: all -->
<!-- TODO manual-7b -->

<!-- rulings: 150, 151, 166, 534, 538, 636, 709, 713, 714, 715, 719, 720, 721, 723, 725, 732 -->
