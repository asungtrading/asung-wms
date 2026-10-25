# IMS user manual — drafts

This folder holds the drafts of the IMS user manual, in English (`en/`) and Korean (`ko/`).
The readers are the people who use IMS every day: managers, admins, accounting, office, sales and warehouse staff — not developers.

## Where the drafts live

- The drafts stay here until the owner reads them and decides where the manual is published.
- ⚠️ This repository is public, and this site serves `docs/` as it is. **Anyone can read these files.**
  - Never write a real customer, supplier or staff name, email address, phone number, street address, or a real order number.
  - Use example names — **Customer A**, **Supplier B**, **Staff C** — and example numbers that start with 99: **SO-99001**, invoice **99001**, **PO-99001**.
- Hidden comments (`<!-- … -->`) are hidden only when the page is drawn. In the raw file anyone can read them. Write only screen names, build tags, roles and ruling numbers there — no internal notes about faults or open questions.
- The **Manual** button on IMS screens reads these files from the `main` branch on GitHub. A change shows there only after it is pushed.
- The manual never names the system used before IMS.
- The manual describes how IMS is designed to work, stated plainly. If IMS behaves differently, that is a fault to report — the draft is not changed to match a fault.

## Anchors

Every section starts with an anchor line, then the heading, then two hidden comments:

```
<a id="sales-ship-invoice"></a>
## Ship & invoice
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: office -->
```

- Anchor form: `area-task`, lower-case ASCII words joined by `-` (for example `start-sign-in`, `sales-ship-invoice`).
- English and Korean use **the same anchors in the same order**. Anchors are never made from the heading — the Korean heading would give a different anchor.
- `screen:` names the screen file(s) and the `*_BUILD` text the section was written against. Several screens are joined with ` ; `. A section that covers no single screen says `screen: none`.
- `who:` uses only these words: `manager`, `admin`, `accounting`, `office`, `sales`, `warehouse`, `all`. Screen role names (worker, supervisor) are not used here.
- Screenshots that are still to be taken are marked `<!-- SCREENSHOT: <anchor>-<n> · what to capture -->`.
- Each file ends with `<!-- rulings: … -->` — the ruling numbers the chapter relies on.

## Checking the anchors

```bash
bash scripts/check-manual-anchors.sh            # checks docs/manual
bash scripts/check-manual-anchors.sh <folder>   # checks a copy, for testing
```

It checks that `en/` and `ko/` have the same files, the same anchors in the same order, anchors in the right form with no repeats, links that point to real anchors, and that no file names the old system. Missing `screen:` or `who:` comments, or a `who:` word outside the list, give a warning only.
The last line is `ANCHORS_OK <files> <anchors>` (en and ko together) or `ANCHORS_FAIL <count>` with exit code 1.
Run it before every commit that touches `docs/manual/`. It needs bash and python3.
The pre-commit hook (`scripts/hooks/pre-commit`) also runs it on the staged copy whenever `docs/manual/` is staged, and stops the commit on `ANCHORS_FAIL` (needs `git config core.hooksPath scripts/hooks` once on each computer).

## Contents

| # | Chapter | English | Korean |
|---|---|---|---|
| 0 | Getting started | [en/00-getting-started.md](en/00-getting-started.md) | [ko/00-getting-started.md](ko/00-getting-started.md) |
| 1 | Sales | [en/01-sales.md](en/01-sales.md) | [ko/01-sales.md](ko/01-sales.md) |
| 2 | Purchasing | [en/02-purchasing.md](en/02-purchasing.md) | [ko/02-purchasing.md](ko/02-purchasing.md) |
| 3 | Inventory | [en/03-inventory.md](en/03-inventory.md) | [ko/03-inventory.md](ko/03-inventory.md) |
| 4 | WMS | [en/04-wms.md](en/04-wms.md) | [ko/04-wms.md](ko/04-wms.md) |
| 5 | POS | [en/05-pos.md](en/05-pos.md) | [ko/05-pos.md](ko/05-pos.md) |
| 6 | Action Centre | [en/06-action-centre.md](en/06-action-centre.md) | [ko/06-action-centre.md](ko/06-action-centre.md) |
| 7 | Settings | [en/07-settings.md](en/07-settings.md) | [ko/07-settings.md](ko/07-settings.md) |
| 8 | By role | [en/08-by-role.md](en/08-by-role.md) | [ko/08-by-role.md](ko/08-by-role.md) |
| 9 | FAQ | [en/09-faq.md](en/09-faq.md) | [ko/09-faq.md](ko/09-faq.md) |
| 10 | Glossary | [en/10-glossary.md](en/10-glossary.md) | [ko/10-glossary.md](ko/10-glossary.md) |
