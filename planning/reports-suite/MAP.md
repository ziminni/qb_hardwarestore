# Reports Suite — MAP

## Phase Progress
| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| P1 Sales reports | Item-wise, hourly, cashier-wise, bill-wise, returns/exchanges, discounts, voids; KPIs ABV, ASP, markdown % | — | ✅ Done (pushed 22176ff; demo = verify; QA 4 PASS + 1 deferred Medium) |
| P2 Inventory reports | Movement (add sales-out/transfers/returns), GRN, STN, FIFO/batch age, shrinkage, adjustments, reorder, dead stock, fast/slow; KPIs turnover, OOS %, shrinkage %, fill rate | — | [ ] Pending |
| P3 Export | PDF + Excel for every report | — | [ ] Pending |

## Destination
One Reports area (Admin + Manager): pick report → date range/filters → on-screen table/chart → export PDF or Excel. All figures computed server-side from existing data.

## Notes & Invariants
- Existing endpoints: `backend_django/apps/reports/views.py` (sales-summary, vat-summary, inventory-valuation, stock-movements, requisition-history), `admin_dashboard.py`.
- Returns/exchanges are NEGATIVE `SalesTransaction` rows (source RETURN/EXCHANGE); status COMPLETED/VOID/REFUNDED.
- COGS = `SalesItemDeduction.qty × unit_cost`; NULL cost = missing history, report as missing, never ₱0.
- Discounts: `SalesItem.item_discount_amount`, `cart_discount_amount`; approvals in `DiscountApproval`.
- Shrinkage source: `StockAdjustment` types SHRINKAGE, DAMAGE, CORRECTION, RETURN.
- Existing Excel export: `flutter/lib/features/admin/reports_excel_export.dart` (formula-safe). `pdf`/`printing` already in pubspec.
- Report money from `grand_total` is "Invoice total" in UI (includes returns, fees), not gross sales.

## Decisions So Far
- Phase order: sales first, then inventory, then export for all (by: me, 2026-11-23).
- Report screen shape: catalogue home (cards grouped Sales / Inventory / KPIs) + one shared viewer page (date range + filters, KPI tiles, table/chart, PDF/Excel buttons); existing 4 tabs fold in as catalogue entries (by: me, 2026-11-23).
- Expiry: add `Product.tracks_expiry` flag (default False) + optional Expires date at receiving (only shown when flagged); expiry report = expired + expiring in 30/60/90 days, KPI Near-expiry %. Lands in P2 (by: me, 2026-11-23).
- Cycle count: report built from CORRECTION adjustments (date, product, location, user, qty + peso variance, shrinkage %); no count-session feature. Limit: matching counts leave no record (by: me, 2026-11-23).
- [Export layout](./decisions/01-export-layout.md): A4 letterhead PDF (store header, period/filters, KPIs first, repeated column headings, Page X of Y) + multi-sheet Excel (`Summary` sheet + detail sheets, formula-safe), borrowing the overview-first pattern from a Philippine POS BackOffice reference (by: me, 2026-11-23).
- [Role visibility per report](./decisions/02-role-visibility.md): Admin & Store Manager see all Sales + Inventory reports (`IsManagerRole`); Stock Manager sees the Inventory reports catalogue + PDF/Excel export (`IsInventoryRole`), with Sales/Profit/Cashier reports hidden/403; Cashier keeps shift X/Z-reading only (by: me, 2026-11-23).
- [Dead-stock & fast/slow mover thresholds](./decisions/03-mover-thresholds.md): dead stock = zero completed sales in trailing window (default 90 days, adjustable) with on-hand > 0; fast = top 20% SKUs, slow = sold-at-least-once bottom 20% over the report range (by: me, 2026-11-23).
- [Large-range pagination vs export limits](./decisions/04-large-range-limits.md): on-screen DRF pagination at 50/page; PDF up to 5,000 rows, Excel up to 10,000 rows, both with a stated truncation notice instead of silent drops (by: me, 2026-11-23).

## Active Frontier (Open & Unblocked)
(none — all decisions locked)

## Blocked
(none)

## Fog of War
(none — all items sharpened to Active Frontier)

## Implementation Roadmap
P1 Sales reports (🤖 backend + viewer, 🧑 KPI tile copy):
- [x] Item-wise / hourly / cashier-wise endpoints + tests (🤖) — APPROVED, re-run 6/6 OK
- [x] Bill-wise / returns & exchanges / discounts / voids endpoints + tests (🤖) — APPROVED, re-run 10/10 OK
- [x] KPIs ABV, ASP, markdown % on summary (🤖) — APPROVED, re-run 6/6 OK (incl. VAT-period regression); tile wording: plain words — 'Average bill value · Invoice total ÷ bills', 'Average selling price · Net ÷ units sold', 'Markdown · Discounts ÷ gross' (🧑 locked, me 2026-11-23)
- [x] Viewer mappings for the 7 new P1 endpoints + KPI tiles with locked wording (🤖) — APPROVED after 1 fix round, re-run 11/11 OK
- [x] Verify one filtered period with a return: viewer = PDF = Excel to the centavo (🤝 deferred to stakeholder demo; Excel/PDF for new reports land in P3)
- [x] QA P1 authed flows (luna): 4 PASS (7 endpoints live, KPIs, null-cost, cashier 403); signed-returns live check BLOCKED (empty live table, unit-pinned); 1 Medium deferred — unknown query params return 200 not 400 (standard DRF behavior, fixing touches existing endpoints; needs its own decision)
- [x] Catalogue home + shared viewer (filters, tiles, table/chart, PDF/Excel buttons) (🤖) — APPROVED, re-run 9/9 OK
- [x] Sidebar repoint: sales + inventory Reports rows → catalogue routes, update affected routing tests (🤖 follow-up from C review) — APPROVED, re-run 115/115 OK
P2 Inventory reports (🤖 backend + UI, 🧑 receiving copy):
- [x] Movement fix (sales-out, transfers, returns in/out) + GRN / STN / FIFO age / shrinkage / adjustments (🤖) — APPROVED, re-run 9/9 OK; follow-up: mirror missing-cost counter instead of ₱0.00 fallback in _landed_cost_map
- [x] Reorder (low-stock threshold) / dead stock (03 rule) / fast-slow / cycle count from CORRECTIONs (🤖) — APPROVED, re-run 15/15 OK with batch A
- [x] `Product.tracks_expiry` + optional Expires at receiving + expiry report + Near-expiry % (🤖) — APPROVED, re-run 48/48 OK; label 'Expiry (optional, cement/paint only)'; known shortcut: Bodega-shelved lines lose expiry
- [x] Inventory role gating: all inventory read endpoints under `IsInventoryRole`; stocker catalogue = Inventory section only (🤖) — APPROVED, re-run 19/19 OK
P3 Export for all (🤖 builder, 🤝 print check):
- [x] Letterhead PDF builder per 01-export-layout (🤖) — APPROVED, summary wired; other reports keep P3-disabled buttons — re-run 32/32 OK
- [ ] Multi-sheet Excel for the 7 new P1 + new P2 endpoints, extending `reports_excel_export.dart` (🤖)
- [ ] Empty-result 'No matching records' + 5k/10k truncation notices (🤖)

## Out of Scope
- Footfall, conversion rate (no door counter).
- Card payment report (Card hidden in till).
- Wastage/dump % separate from DAMAGE adjustments.
