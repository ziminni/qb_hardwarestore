---
date: 2026-10-25
slug: audit-remediation-phase-4
---

# 2026-10-25 — Audit remediation Phase 4: Stock Manager

## Focus

Build Phase 4 of `planning/audit-remediation/MAP.md` from `phase-4-plan.md`: make every Stock Manager screen live on the server, add purchasing, and raise low-stock alerts on sales. **User decision:** a new product's first stock arrives through a purchase order that the Stock Manager creates and receives; "Add product" creates the catalog item only.

## What Was Built / Changed

| Commit | Change |
|---|---|
| `f4253b9` | Catalog: no DELETE (405, was a 500 on `PROTECT`), `Category.is_active` (migration `inventory.0005`), selling-unit integrity (`INVALID_SELLING_UNIT`, `DUPLICATE_BASE_UNIT`, `SELLING_UNIT_IN_USE`), `INVALID_VARIANT`, one audit row per write (price old → new) |
| `96ef2df` | Purchase orders: nested create, `place/`, `cancel/`, `status` action-only, edit only while DRAFT, receive only ORDERED/PARTIAL (`PO_NOT_ORDERED`, `PO_NOT_RECEIVABLE`) |
| `92db10a` | Low-stock check on sale, held-cart complete and release; deduplicated per (variant, type, unresolved) under the variant lock |
| `f94db36` | Goods receipts and stock adjustments are append-only (processed-receipt DELETE was a 500) |
| `da985e6`, `15eb1ba`, `18983a9` | Flutter: live product/category CRUD (create chain product → variant → selling unit), `InventoryMockData` deleted, suppliers/PO screens, Receiving history, Reorder → prefilled PO, alert Resolve |
| `4146332` | PO row locked for receive, process and edit; `process/` re-checks status; a no-op PATCH writes no audit row |
| `e7dd705` | A parse failure is an error, not an empty catalog; loading/error states on stock, low-stock, movements and till; PO paging |
| `8a9bb3d` | Resolve offered by role **code** (was hidden from every role live) |
| `a3ac47d` | `AppScrollBehavior`: mouse drag-scroll + always-visible horizontal scrollbar (17 wide tables; Actions unreachable at 1366px) |
| `c17fd30` | Receiving shows the server's status and received qty after record and process |

## Mistakes & Gotchas (Do Not Repeat)

- **Test fixtures must mirror the wire.** The Resolve test built `Role(name: 'Stock Manager', displayName: 'Stock Manager')`, but the server sends `name: 'inventory'`. The page compared against labels, passed every test, and was dead live. Compare role **codes** (the same codes `dashboardForRole` uses).
- **Flutter web + a plain mouse cannot scroll a horizontal table** with the stock scroll behavior. The fix belongs at app level (`AppScrollBehavior`), not per table.
- A list reload doesn't refresh a selected object: re-point the selection at the fresh copy, matched against the **unfiltered** list.
- The opencode-go subscription hit its usage limit (429 `GoUsageLimitError`) for every model; `model` overrides still route there because `defaultProvider` is opencode-go. Per the user's choice the controller (Opus) ran the browser E2E itself.
- Browser automation of Flutter web: enable semantics with pointer events on `flt-semantics-placeholder`; `fill` doesn't reach Flutter text fields, so click, then Ctrl+A, then type. Re-snapshot before every ref use, because refs go stale on re-render. Don't `read` a screenshot in the same tool batch that writes it. A reload logs out unless "Remember me" was ticked.

## Decisions

Rulings are in `.superpowers/sdd/audit-remediation/progress.md` (`P4` lines): catalog deletes → 405; category archive column; selling unit frozen once sold; PO lifecycle via actions; alert dedup under lock with no auto-resolve; stock records append-only; `IsInventoryRole` = Stock Manager + Store Manager + Admin (decision 06 "as built").

Deferred minors:
- The alert message keeps the quantity at creation, and a partial delivery below threshold raises it.
- Times show in UTC.
- The delivery sheet shows the date as "00:00".
- Receiving/delivery lines show only the variant name.
- The Archived metric card doesn't open the archive.
- The supplier switch reports `checked=false` while active.
- The Draft badge is low contrast.
- Inventory Simulator is still mock.
- `VariantUOM` has no `is_active`.
- Price edits re-price parked carts.
- The sold-unit check is unlocked.
- Bulk archive does N reloads.
- Stock movements list adjustments only.

## Wins & Next Step

- Gate: backend **456/456**, migrations clean, flutter **738/738**, analyze clean. Hygiene backend + Flutter fix-passed. API QA B1–B6 PASS.
- Browser E2E at 1920 and 1366:
  - The stocker added QA4UI Bolt; it survived reload.
  - PO-14 went draft → placed, then received 8 → PARTIAL and 12 → COMPLETE; stock 20 @ ₱12.50, with history and View sheet.
  - Price edited to ₱30; archive and restore worked; category create/rename/archive/restore and the supplier toggle all persisted.
  - A cashier sold 15 at ₱30 → one LOW_STOCK alert, which the stocker resolved (resolver + time). Reorder prefilled a PO.
  - All 37 role pages load with no error text. Direct refresh shows a spinner, then data.
  - Cashier return regression OK.
- Dev DB has QA rows (product 9 "QA4UI Bolt", category 7, PO-14, transactions up to `TRX-20261025-0009`). Re-seed for a clean demo.
- **Next:** `git push` (user). Phase 5 (Store Manager / Admin: user edit/deactivate/assign-role UI, overdue filter, unlinked-return manager screen, dashboard aggregation limits, Inventory Simulator removal).
