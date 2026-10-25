# 0. Getting started

This chapter is for everyone who uses IMS: managers, admins, accounting, office, sales and warehouse.
Read it once before the other chapters. Each part is short.

- [What IMS is](#start-what-is-ims)
- [Sign in](#start-sign-in)
- [Modes: IMS, WMS and POS](#start-modes)
- [The menu](#start-menu)
- [Lists and details](#start-list-detail)
- [Search, filters, pages and CSV](#start-search-filter)
- [Roles and keys](#start-roles-keys)
- [Dates and times](#start-dates-times)
- [The build tag](#start-build-tag)
- [Getting help](#start-getting-help)

<a id="start-what-is-ims"></a>
## What IMS is
<!-- screen: none -->
<!-- who: all -->

**What it is**
IMS is the system Asung built for itself. Sales, purchasing, stock and the warehouse all live in one place.
A sales order, the stock it takes, the invoice and the payment are all in IMS, and they all talk to each other.

**What is in it**
- **Sales** — customers, sales orders, invoices, customer payments, credit notes, backorders, web orders.
- **Purchasing** — purchase orders, supplier invoices and credits, charges, supplier payments, receipts.
- **Inventory** — stock in each branch, products, stock adjustments, transfers, bin moves.
- **WMS** — the warehouse screens: picking, packing, fulfillment, receiving, bin moves.
- **POS** — the counter screen for sales to account customers (see [POS](05-pos.md#pos-start)).

**Good to know**
- One thing happens in one place. When the warehouse finishes an order, the office sees it at once. You do not copy anything by hand.
- The numbers you see are live. If a number looks wrong, tell your manager — see [Getting help](#start-getting-help).

<a id="start-sign-in"></a>
## Sign in
<!-- screen: index.html · BUILD 2026-09-30 · door v1 ; ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**What it is**
You sign in with your company email and a password. Your manager or the IMS administrator makes your account first. You cannot make one yourself.

**When**
The first time you open IMS on a computer or tablet. After that IMS remembers you on that device until you press **Sign Out**.

**How**
1. Open IMS in your web browser. You see the **Sign In** card with the Asung logo.
2. Type your company email in **Email**.
3. Type your password in **Password**.
4. Press **Sign In** (or press Enter).
5. IMS opens your first screen. Which screen that is depends on your work — see [Modes](#start-modes).

**Forgot your password**
1. On the **Sign In** card, type your email in **Email** first.
2. Press **Forgot your password?**
3. IMS says: "A reset link has been sent to your email. Please check your inbox."
4. Open the email and click the link. IMS opens and says "Set your new password to continue."
5. Press **Set password**, type the new password twice, and press **Change**.
6. IMS says "Password changed. Opening…" and takes you to your first screen.

**Change your password**
1. Press **Change Password** at the top right of any IMS screen.
2. Type the new password in **New password** and again in **Confirm new password**. It must be at least 6 characters.
3. Press **Change**. IMS says "Password changed successfully."

**Messages you may see**

| Message | What it means | What to do |
|---|---|---|
| Sign-in failed: check your email or password. | The email or password is wrong. | Try again, or use **Forgot your password?** |
| This account is not registered. Please contact your administrator. | Your email has no IMS account. | Ask your manager. |
| This account is inactive. | Your account was turned off. | Ask your manager. |
| No screens are open to your account yet. Please contact your administrator. | You can sign in, but no screen is given to you yet. | Ask your manager to give you keys — see [Roles and keys](#start-roles-keys). |
| You don't have access to this screen. Please contact your administrator. | You opened a screen you have no key for. IMS signs you out. | Sign in again and use the menu. Ask your manager if you need that screen. |

**Watch out**
- Some screens sign you out if you have no key for them. This happens most when someone sends you a link to a screen. Sign in again — your own screens are still there.
- On a shared tablet, press **Sign Out** when you finish. The next person then signs in as themselves.

<!-- SCREENSHOT: start-sign-in-1 · the Sign In card (logo, Email, Password, Sign In, Forgot your password?) -->

<a id="start-modes"></a>
## Modes: IMS, WMS and POS
<!-- screen: ims-auth.js · BUILD nav v10 ; dashboard.html · BUILD 2026-09-30 · db v1 -->
<!-- who: all -->

**What it is**
IMS has three modes. Each mode is a set of screens for one kind of work.

| Mode | For | First screen |
|---|---|---|
| **IMS** | Office work: sales, purchasing, stock, settings | **Overview** |
| **WMS** | Warehouse work: picking, packing, receiving | The first warehouse screen you have |
| **POS** | The counter (see [POS](05-pos.md#pos-start)) | **POS** |

**How**
1. Look at the top left, next to the Asung logo. You see the mode buttons **IMS**, **WMS** and **POS**.
2. Press a mode to go to its first screen. The mode you are in is marked.
3. Press the Asung logo to go back to the first screen of your mode.

**Good to know**
- You only see the modes you can use. If you can use only one, there are no mode buttons at all.
- When you sign in, IMS opens the first mode you have, in the order IMS, WMS, POS.
- **Overview** is the first IMS screen. It says "Overview — coming soon" for now.

<a id="start-menu"></a>
## The menu
<!-- screen: ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**What it is**
In IMS mode, the menu runs along the top of the screen. Each word opens a list of screens.

| Menu | Screens in it |
|---|---|
| **Purchasing ▾** | Purchase Orders · Purchase Invoices & Credits · Charges · Supplier Payments · Purchase Receipts · Suppliers · Reorder Planner |
| **Sales ▾** | Sales Orders · Web Orders · Sales Invoices · Customer Payments · Credit Notes · Backorders · Customers |
| **Inventory ▾** | Stock Availability · Products · Product Sheet · Families · Stock Adjustments · B-grade Stock · Transfers · Bin Moves (office) |
| **Action Centre** | One screen — no list opens (see [Action Centre](06-action-centre.md#action-start)) |
| **Settings ▾** | Settings · Surcharge Groups · Staff · Discount Rules · Shopify Stores · System Check (see [Settings](07-settings.md#set-start)) |

**How**
1. Press a menu word, for example **Sales ▾**.
2. Press the screen you want, for example **Sales Orders**.

**The tab row**
On the document screens of **Purchasing** and **Sales**, a second row of tabs sits under the menu. The tabs are the other document screens of the same menu. Use them to move sideways — for example from **Sales Orders** to **Sales Invoices** — in one click.

**Why some menus or screens are missing**
You only see the screens you have a key for. A menu word appears only when you have at least one screen in it. This is normal — it is not an error. See [Roles and keys](#start-roles-keys).

**In WMS mode**
The warehouse screens show as tabs, and the **☰ Menu** button lists the same screens.
On WMS screens, **Manual** is at the end of the **☰ Menu**.

<a id="start-list-detail"></a>
## Lists and details
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; customers.html · BUILD 2026-10-23 · cs v6 -->
<!-- who: all -->

**What it is**
Many screens — for example **Sales Orders**, **Sales Invoices**, **Customer Payments**, **Credit Notes**, **Customers** and **Discount Rules** — work in two ways.

1. **The wide list.** When you open the screen, a big list fills the whole screen. Use it to search and pick.
2. **List and detail.** When you pick one row, the screen splits. A narrow list stays on the left. The one you picked opens on the right.

**How**
1. Open the screen. You see the wide list.
2. Click a row. Its detail opens on the right, with the narrow list on the left.
3. Click another row in the narrow list to open that one instead.
4. Press **☰ List** at the top of the detail to hide or show the narrow list. Hide it when you need more room.
5. Press **‹ All orders** (on other screens: **‹ All invoices**, **‹ All payments**, **‹ All credit notes**, **‹ All customers**, **‹ All deals**) to go back to the wide list.

**Good to know**
- Links between screens open the right one directly. For example, an order's invoice number opens that invoice on **Sales Invoices**.
- If a link opens "That sales order is gone — it was deleted, or the link is old.", the link is out of date. Go back to the list and search again.
- Some screens have only one list and no detail split, for example **Backorders** and **Web Orders**. Each chapter shows how its screens work.

<!-- SCREENSHOT: start-list-detail-1 · Sales Orders split view: narrow list on the left, an order on the right, ☰ List and ‹ All orders marked -->

<a id="start-search-filter"></a>
## Search, filters, pages and CSV
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: all -->

**What it is**
Every wide list has a bar on top. The bar has a search box, filters, a **Clear** button and often a **↓ CSV** button.

**How to search**
1. Click the search box. The grey words in it tell you what it searches. On **Sales Orders** that is "SO number · invoice number · customer · reference".
2. Type part of what you look for, for example `99001` or part of a customer name.
3. Stop typing. The list updates by itself after a moment.

**How to filter**
1. Choose a value in a filter, for example a status, a date range or a payment state.
2. The list shows only the rows that match every filter and the search together.
3. Press **Clear** to take all filters and the search away.

**Pages**
- A list shows one page at a time. The line at the bottom says which rows you see.
- Press **→** for the next page and **←** for the page before. The narrow list on the left works the same way.
- Small search lists inside a window — for example when you look for a customer or a product to add — show only the first matches. If you see "Showing the first matches — type more to narrow." (or "Showing the first 60 — type more to narrow."), type more in the search box.

**↓ CSV**
1. Set the filters and the search the way you want.
2. Press **↓ CSV** on the wide list.
3. A spreadsheet file downloads. It has every row that matches your filters — all pages, not only the one on screen.

**Watch out**
- CSV follows your filters. If the file looks short, check the filters first.
- Some details have their own CSV buttons (for example **↓ Lines CSV** on an order). Those download only that one document. The chapter for that screen explains them.

<a id="start-roles-keys"></a>
## Roles and keys
<!-- screen: staff.html · BUILD 2026-10-20 · st v3a ; stock.html · BUILD 2026-10-23 · stk filt v1 -->
<!-- who: all -->

**What it is**
What you can see and do in IMS depends on two things: your **role** and your **keys**.
Your manager sets both on the **Staff** screen (see [Staff](07-settings.md#set-staff)). You see your name and role at the top right of every screen.

**Roles**
There are four roles, from first to highest: **worker**, **manager**, **supervisor**, **admin**.
A higher role can do more. Some buttons work only for a manager or higher. When this manual says "ask your manager", it means a person with a higher role.

**Keys**
A key opens one area of IMS. Each key has three levels:

| Level | What you can do |
|---|---|
| **none** | You do not see the screens. |
| **read** | You see the screens, but you cannot change anything. |
| **write** | You see the screens and can work in them. |

The keys, with the words the **Staff** screen shows:

| Key | Opens |
|---|---|
| `sales` | Sales orders, customer addresses and contacts — also invoices, payments, credits, backorders, web orders, customers, POS and the [Action Centre](06-action-centre.md#action-start) |
| `purchasing` | Purchase orders, invoices, charges, payments — also the Reorder Planner |
| `receiving` | Receiving and putaway (the office **Purchase Receipts** screen) |
| `master` | Settings, suppliers, products, families, supplier products, prices, product tags, deals |
| `staff` | Adding and editing people (below your own rank) |
| `transfer` | Transfers — warehouse to warehouse |
| `cost` | Inventory cost — stock value, layer values, unit costs |
| `picking` · `packing` · `fulfillment` · `wms_receiving` · `stock_move` | The warehouse screens of the same names |

Some keys are for managers and above only: `shopify`, `wms_manage`, `wms_receiving_confirm`, `stock_adjust`. The `doc_template` key (document layouts) is for supervisors and admins. Several keys are off for everyone until a manager switches them on for a person.

**Examples**
- A person without the `cost` key does not see the **Value** column on **Stock Availability**. The column is simply not there (see [Find stock](03-inventory.md#stock-availability)).
- A person with `sales` at **read** can open a sales order but has no buttons to change it.
- **Stock Availability** and **System Check** need no key. Everyone who can sign in sees them.

**Branches**
A worker or manager may be set to work in only some branches. A supervisor or admin works in every branch.

**Watch out**
- If a screen or button you need is missing, it is a key, not a fault. Ask your manager for the key.
- You cannot change your own keys.

<a id="start-dates-times"></a>
## Dates and times
<!-- screen: none -->
<!-- who: all -->

**What it is**
IMS keeps time in Toronto time. Every time you see — "made at", "changed at", "sent at" — is Toronto time.
"Today" in IMS is today in Toronto. An invoice issued today gets Toronto's date.

**For Edmonton staff**
- Edmonton is 2 hours behind Toronto. A time IMS shows as 15:00 is 13:00 in Edmonton.
- After 22:00 in Edmonton, it is already the next day in Toronto. Work done then gets the next day's date. Keep this in mind for late invoices and late receipts.

**Plain dates**
A date without a time (for example a due date or an order date) is just a date. It does not move with the time zone.

<a id="start-build-tag"></a>
## The build tag
<!-- screen: ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**What it is**
At the top of each screen, next to the logo, there is small grey text. It is the **build tag** — the version of that screen.
There are two tags:
- The screen's own tag, for example `2026-10-22 · so csv v3`.
- The menu's tag, for example `nav v10`.

**When**
Whenever you report a problem.

**How**
1. Look at the small grey text at the top.
2. Copy both tags into your message, or take a screenshot of the whole screen with the top showing.
3. Add what you pressed, what you expected and what happened.

**Why**
The tags tell us exactly which version you were using. A problem report with the tags is much faster to fix.

<!-- SCREENSHOT: start-build-tag-1 · the top bar of one screen with both build tags marked -->

<a id="start-getting-help"></a>
## Getting help
<!-- screen: none -->
<!-- who: all -->

**In the screens**
1. Press **Manual** at the top right of any IMS screen. This manual opens in a new tab, so you do not lose your work.
2. Press **English** or **한국어**. IMS remembers your choice.
3. Pick a chapter and a section from the list on the left, or type in **Find a section**.
- On WMS screens, open **☰ Menu** and press **Manual** at the end.
- A **?** button on each screen is coming soon. It will open the section for that screen directly.

**In this manual**
Each chapter covers one area. The chapters and their sections are in the list on the left.
Chapter 1 is [Sales](01-sales.md).
To find your work by role, see [By role](08-by-role.md#role-start).
Common questions are in [FAQ](10-faq.md#faq-sign-in).
This manual describes how IMS works. If IMS does something different from what this manual says, that is a problem worth reporting.

**Who to ask**
1. First, your manager.
2. If your manager cannot fix it, your manager asks the IMS administrator.

**What to send**
- The screen name and both build tags (see [The build tag](#start-build-tag)).
- The order, invoice or other number you were working on (for example `SO-99001`).
- A screenshot of **System Check** (see [System Check](07-settings.md#set-system-check)).
- What you pressed, what you expected, and what happened instead.

<!-- rulings: 149, 153, 158, 160, 163, 169, 242, 567, 578, 709, 710, 712, 713, 714, 715, 725, 731 -->
