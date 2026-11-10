# Which teammate look items to adopt

**Mode:** grill · **Status:** ✅ Locked 2026-11-10 (by: me, extras by: delegated with "users first, HCI" rule)

## Context (research, 2026-11-10)

Three read-only audits compared teammate commit `22ca7e8` (`origin/ui/frontend-progress`, merge base `857f333`) with HEAD; local reports in `temp/design-audit/{stock-manager,sales-admin,shared}.md` (gitignored). Findings:

- No working feature is missing in any role. His screens restyled mock-era pages (many `onPressed: () {}`); HEAD replaced them with live data or deleted them on purpose (POS approvals `77142d6`, customer directory `9994ba9`/`33d18d8`).
- The real gaps are look-only. `app_dialog.dart` holds 8 widgets (`AppDialog`, `HexIconBadge`, `DialogSectionLabel`, `FormStepHeader`, `DetailRow`, `LineItemTile`, `TotalBar`, `InfoBanner`) used in 15 of his files; none exist at HEAD.
- The Oct 31 sync audit (`.superpowers/sdd/ui-refresh/teammate-sync-audit.md`) misjudged several rows (product form "same form", unused dialogs compared, missing top-products table, wide PO form already done at HEAD in `1a450d3`).
- Locks his code would break: Cinzel for 18 px+ headings (3 pinned tests, `metric_tile.dart`), D12 no discounts in reports, D6 `formatDate`, no em dashes, `formatPeso`/`formatQuantity` instead of `toStringAsFixed`, his StatusPill contrast, Cinzel below 18 px in some of his widgets.

## Decision

**Owner choices (by: me):**
- Keep **Cinzel** for 18 px+ headings and figures; his widgets are adapted to our type rule.
- Adopt the **dialog design family** across the 12 dialogs that map to his screens: add/edit product (numbered steps), product details, archive, category, supplier, purchase order, adjust stock ("System quantity → New quantity"), receiving, and the transaction/return detail sheet (`sales_document_sheet.dart`, gold total bar) for all roles. Tests stop finding dialogs by `AlertDialog` type where the shell replaces it.
- Screen extras: **table title + row-count pill** (`DataPanel`), **category cards** (3 px gold active/archived bar + three stat tiles), **PO "Received x / y"** summary, **one shared section heading** replacing the two private copies.
- Shell extras: **today's date in the page header** (through the test-pinned `appClock` and the shared format module; a weekday-capable formatter is added there, not hand-rolled arrays), **sidebar touches** (hexagon initials badge on the user card, readable hover, animated gold active bar).

**Delegated additions (users first):**
- Live helper on each selling unit ("1 Bag = 40 kg · ₱6.75 per kg").
- Confirmation naming the unit before removing an unused selling unit, stating it cannot be undone.
- `InfoBanner` neutral notes where users need guidance (e.g. stock arrives via purchase order + Receiving).
- Accessibility acceptance for every redesigned dialog: keyboard order follows the steps, no clipping at text scale 1.3 (real fonts), status in words not colour alone, motion respects reduced-motion settings, no low-contrast pill.
- Delete the five files unused at HEAD that the sales/admin audit listed.

## Not adopted

His slower splash/login pacing (2.4 s / 2.8 s), the animated login brand panel, the hexagon empty-state decoration, Open Sans figures, his fields removed on purpose (SKU, cost, initial stock on Add product), the mock customer directory and POS approvals.
