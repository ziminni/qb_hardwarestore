# POS Evolution MAP

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Foreman out, CPMS boundary: requisitions become a read-only copy of CPMS-approved requests; projects known for utang/payables; cashier token release stays | ✅ [Requisitions after the foreman](./decisions/01-requisitions-after-foreman.md) · ✅ [How approved requests reach the POS](./decisions/02-request-transport.md) · ✅ [Projects and their payables](./decisions/03-projects-and-payables.md) · ✅ [What CPMS sends for each item](./decisions/04-request-item-matching.md) · ✅ [Releasing when stock is short](./decisions/05-short-stock-release.md) · ✅ [Closing a partly released request](./decisions/06-closing-partial-requests.md) · ✅ [How CPMS learns what was released and owed](./decisions/07-cpms-sees-releases.md) · ✅ [Migrating today's foreman data](./decisions/08-foreman-data-migration.md) | ✅ Done 2026-11-07 ([plan](./phase-1-plan.md); contract v0.1 provisional) |
| 1b | Store accepts/declines pushed requests (whole or per line, with reason); release only after Accept; expected amount readable by CPMS | ✅ [The store accepts or declines a pushed request](./decisions/09-store-accepts-requests.md) · ✅ [Declining single lines of a request](./decisions/10-line-level-decline.md) · ✅ [When the project starts to owe](./decisions/11-when-utang-starts.md) · ✅ [Request states after Accept](./decisions/13-request-states-after-accept.md) · ✅ [Historical release amounts after the Phase 1b upgrade](./decisions/14-historical-release-amounts.md) | ✅ Done 2026-11-08 — [all tasks verified](./phase-1b-plan.md#execution-checklist); contract v0.2 provisional; core live QA passed, remaining QA/cosmetic limits explicitly owner-accepted ([handoff](./phase-1b-plan.md#handoff--known-limits)); not deployed |
| 1c | Payment receipts from CPMS: PM uploads amount + reference + photo, Store Manager approves (posted to project utang, partial allowed) or declines | ✅ [Paying project utang with an uploaded receipt](./decisions/12-payment-receipts.md) · [ ] Receipt storage and allocation | [ ] Pending |
| 1d | Design sync with teammate `ui/frontend-progress` + real product packaging units: Add product "How is this product sold?", mock tracking removed, storage location back, chosen look items | ✅ [How a product is sold](./decisions/15-product-packaging-units.md) · ✅ [Selling units after creation, unit list and whole numbers](./decisions/16-units-on-existing-products.md) · ✅ [Which teammate look items to adopt](./decisions/17-teammate-look-adoption.md) | ✅ Done 2026-11-11 ([plan](./phase-1d-plan.md), closed with accepted limits) |
| 4 | Front counter (panel feedback): VAT breakdown, capped discount, split + cheque payments, table pager, barcode masterlist, area switcher for multi-role accounts, role flow docs | ✅ [Panel feedback 2026-11](./decisions/18-panel-feedback-2026-11.md) | 🟡 In Progress ([plan](./phase-4-plan.md)) |
| 5 | Back office (panel feedback): PO by package, supplier payables, customer delivery + fee, bodega "stored at" | ✅ [Panel feedback 2026-11](./decisions/18-panel-feedback-2026-11.md) | [ ] Pending ([plan](./phase-5-plan.md)) |
| 2 | Multiple roles per account: sidebar and dashboard built from the union of the account's permissions (area-switcher lite moved into Phase 4) | fog | [ ] Pending |
| 3 | Excel import/export: template export, edit, re-import; fresh-store bulk load of current materials | fog | [ ] Pending |

## Destination

CPMS project requests receive a store answer before release; project debt and receipt payments are traceable in the POS, without a foreman login. Later: multiple roles per account and catalogue/stock Excel round-tripping.

## Notes & Invariants

- **Server is the trust boundary** (audit-remediation invariant): role checks, import validation and stock rules live in Django, Flutter is UX.
- **Proof rule (AGENTS.md):** a test counts only after it fails without the fix.
- **Multi-role head start (verified 2026-11-03):** `has_role` already accepts any of a user's groups (`apps/users/permissions.py:73-84`); only `UserSerializer.get_role` reports the first group (`apps/users/serializers.py:34-51`) and the Flutter shell routes on that single role (`flutter/lib/routes/routes.dart` `redirectFor`).
- **Excel today:** no Excel/CSV package in `flutter/pubspec.yaml` or backend requirements; no import/export endpoint.
- **CPMS is a separate repo** (`../qb_project_management_system/`). Phase 1 defines the POS side and a contract doc; editing CPMS needs the product owner to lift that boundary explicitly.

## Decisions So Far

- [Requisitions after the foreman](./decisions/01-requisitions-after-foreman.md): POS keeps a read-only copy of CPMS-approved requests (project, items, token, requester name as text); POS Approvals screens and the foreman role go; cashier token release stays. (by: me)
- [How approved requests reach the POS](./decisions/02-request-transport.md): CPMS pushes each approved request to a new POS import endpoint with its own revocable service account; retry-safe; the till never calls CPMS. Locked "for now". (by: me)
- [Projects and their payables in the POS](./decisions/03-projects-and-payables.md): contractor stays the payer with one credit limit; `Project` gets a CPMS id, utang gets an optional project link, so receivables total per contractor or per project. (by: me)
- [What CPMS sends for each requested item](./decisions/04-request-item-matching.md): POS publishes a read-only list of selling units (name, unit, POS code; no stock or prices) to the CPMS account; CPMS sends POS codes + quantities; unavailable items must be handled at release. (by: me)
- [Releasing when stock is short](./decisions/05-short-stock-release.md): release what is in stock (one sale + one project-tagged utang), the rest stays open on the same token as Partially released; the remainder can be closed and what was released stays payable. (by: me)
- [Closing a partly released request](./decisions/06-closing-partial-requests.md): only CPMS closes the remainder, by a retry-safe call on the same service account; POS marks it closed and the token dead, released utang untouched, no new POS screen. (by: me)
- [How CPMS learns what was released and owed](./decisions/07-cpms-sees-releases.md): CPMS reads per request (released/outstanding) and per project (utang total, paid, balance) from the POS on demand; the POS makes no outbound calls. (by: me)
- [Migrating today's foreman data](./decisions/08-foreman-data-migration.md): copy names to text fields and drop the user FKs; Draft/Submitted become Cancelled; foreman account deactivated (audit rows protect it), group deleted; seed rewritten as CPMS pushes. (by: delegated)
- [The store accepts or declines a pushed request](./decisions/09-store-accepts-requests.md): pushed requests wait for a Store Manager's Accept/Decline (reason required); no stock reservation; token releases only after Accept; CPMS reads the status; CPMS prints the token-only QR, POS prints no slip. (by: me)
- [Declining single lines of a request](./decisions/10-line-level-decline.md): Accept may mark lines Not available with a reason; whole Decline when nothing can be served; short accepted lines still go through partial release. (by: me)
- [When the project starts to owe](./decisions/11-when-utang-starts.md): utang only at release; an accepted request exposes a non-debt expected amount to CPMS. (by: me)
- [Request states after Accept](./decisions/13-request-states-after-accept.md): WAITING → ACCEPTED/DECLINED (or CPMS withdraw → CLOSED), then PARTIAL/RELEASED/CLOSED as built; lines Available/Not available at Accept; no undo; live expected amount; APPROVED rows become ACCEPTED; Store Manager + Admin queue. (by: me)
- [Historical release amounts after the Phase 1b upgrade](./decisions/14-historical-release-amounts.md): preserve all history; old released requests expose a null expected amount until verified reconciliation, new releases track exact totals. (by: me)
- [Paying project utang with an uploaded receipt](./decisions/12-payment-receipts.md): online payments arrive from CPMS as amount + reference + photo, Store Manager approves (partial OK) or declines with reason; cash stays at the counter. (by: me)
- [How a product is sold: packaging units replace the old tracking step](./decisions/15-product-packaging-units.md): Add product step 2 saves real extra selling units ("Bag = 40 kg"); storage location returns; mock tracking section deleted; still no initial stock. Reopens decision 18's no-add-unit rule. (by: me)
- [Selling units after creation, the standard unit list and whole-number rules](./decisions/16-units-on-existing-products.md): add units to existing products, remove only never-used ones; migration adds a standard unit list with a whole-number flag the server enforces on sale/hold/return/release. (by: me)
- [Panel feedback after the presentation](./decisions/18-panel-feedback-2026-11.md): all 12 comments answered in Phases 4 (front counter) and 5 (back office); VAT-inclusive 12%, Admin-capped cashier discount, cheque pending until cleared, bill at receiving, delivery on till + sales order, bodega as a stored-at label, area switcher. (by: me + delegated defaults)
- [Which teammate look items to adopt](./decisions/17-teammate-look-adoption.md): keep Cinzel; dialog design family on 12 dialogs; table row counts, category cards, PO received summary, shared section heading, header date, sidebar touches; HCI additions delegated. (by: me + delegated)

## Active Frontier


- [ ] Receipt storage and allocation (Phase 1c) — grill + research: image storage and size/type limits, which ledger rows a payment applies to, overpayment, what CPMS sees after a decline

## Blocked

_(none yet)_

## Fog of War

- **Multi-role model:** keep Django groups as roles, or move to finer permissions; how the dashboard merges tiles from several roles; who may grant which roles (Phase 5 `USER_ADMIN_FORBIDDEN` / `LAST_ADMIN`).
- **Excel scope:** which data (products, selling units, prices, categories, suppliers, stock); match key on re-import (barcode? SKU?); server-side parsing and validation.
- **Excel vs locked stock rule:** audit-remediation locked "first stock arrives via purchase order + Receiving, Add product creates catalogue only". A fresh-store import with quantities reopens that rule.

## Out of Scope

- Editing the CPMS repo until the product owner lifts the boundary (reaffirmed 2026-11-06). CPMS-side: foreman free-text requests, PM matching, QR printing, notifying PM/foreman/client, the read-only **client** user.
- Camera scanning, payment gateways, discounts/VAT (unchanged from audit-remediation).
