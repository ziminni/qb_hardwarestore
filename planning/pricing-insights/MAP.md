# POS pricing, reporting, and operations

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Research and source audit | None; owner delegated recommended policy | ✅ Done |
| 2 | Selling-price history and line/cart discounts | Price history independent; allocations must reconcile approvals and returns | 🟡 In Progress |
| 3 | Reporting visuals and grouped partial payments | Use server facts; don’t guess missing legacy allocations/costs | 🟡 In Progress |
| 4 | Cashier dispatch and role workflow verification | Native smoke pending in phase 5 | ✅ Done |
| 5 | Integrated QA, migration and demo instructions | Phases 2–4 | [ ] Pending |

## Research-backed design direction

- [Square: apply discounts](https://squareup.com/help/us/en/article/5362-apply-discounts) separates line and whole-sale discounts. For BuildPro, a line discount applies only to the designated item; a cart discount applies proportionally to eligible lines after line discounts. Cashiers can explicitly leave cement (or any other line) out. Don’t touch excluded lines, VAT, delivery charges, or tender fees. Cap/approval considers combined concessions, not each entry in isolation. Persist exact applied centavos on sale lines; partial refunds use the original sale and previously reversed amounts, not today’s prices. Historical orders keep their agreed price.
- Example: cement ₱600 excluded, tools ₱300, fasteners ₱100. A ₱40 cart discount allocates ₱30 to tools and ₱10 to fasteners. Cement stays ₱600. A line discount can instead target cement when allowed. Use deterministic centavo rounding and exact reconciliation, including tiny baskets.
- [Shopify sales reports](https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/sales-report) distinguish discounts, net sales, reversals, and gross profit. [IAS 2](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/) discusses FIFO as a cost formula and recognising inventory expense when sold. BuildPro operational gross profit should report net merchandise sales excluding VAT minus recorded merchandise cost; keep payment/delivery charges, taxes, collections and overhead separate. Mark incomplete cost coverage and ambiguous legacy allocation rather than presenting a guess as audited profit. This is a reporting convention, not statutory certification.
- [Square reporting](https://squareup.com/help/us/en/article/5381-in-app-summaries-and-reports) separates sales summary, trends, and payment methods. Prioritize dated sales/margin and discount/return trends, product/category breakdowns, and inventory location and stock risks. Every visual needs readable amounts, date range, and missing-data state; prefer existing API data and components before adding new graphs/endpoints.
- [Microsoft customer aging](https://learn.microsoft.com/en-us/dynamics365/finance/accounts-receivable/customer-aging) distinguishes outstanding balances by date. Keep open and part-paid accounts actionable; show original charge, paid, balance, and dated payment ledger separately. Payment receipt pending review or uncleared cheque is not settlement. A later collection is not a second sale.
- Cashier can already schedule from checkout according to prior contract. Proposed dispatch: permit Cashier to mark only their own eligible scheduled sales out for delivery; retain wider queue and final status powers for existing authorized roles. Check status under lock, retain audit, and keep Bodega pickups, supplier arrivals and dispatch separate.

## Baseline audit (POS `df03a3a`)

- `apps/pos/services.py` validates cart discounts against gross goods, stores them at transaction level, and ignores client unit prices. Sale lines snapshot charged price, not discount allocation. Linked returns currently proportionally refund against the original basket’s goods net/gross; they do not know which products received a discount. Do not claim current reports distribute discounts per item.
- `apps/pos/models.py` and `apps/inventory/services.py` capture quantities and source batches, not immutable COGS. Stock valuation is not cost of goods sold. Future margin needs historical costs on signed deductions and documented legacy coverage.
- `apps/reports/views.py` legacy `gross_sales` sums signed `grand_total`, including applicable tax and fees. `apps/reports/admin_dashboard.py` product ranking uses pre-discount subtotals. Keep compatibility keys, but label invoice and merchandise totals separately before adding profit visuals.
- First receivables change: **Part-paid** filter keeps overdue partially settled debts visible without changing aging status, ledger entries, or settlement. Focused page and payment tests: 21 passed.
- Reports now label signed invoice totals correctly and show a daily invoice trend for the last seven reported dates of the selected range. Reports/routing tests: 32 passed. This is not a profit chart.
- Cashier → Deliveries shows their own slips. Cashier can start only their own direct till sales; authorizations for delivery completion, failure, and order dispatch were not widened. Backend role/scope tests: 19 passed. Flutter delivery/navigation tests: 78 passed; targeted analysis clean.

## Price history checkpoint

`GET /api/v1/variant-uoms/{id}/price-history/` is paginated, inventory-role only, and sorted newest first. Records timestamp, old and new shelf prices, actor (if retained), and Catalogue/Excel/Admin source. Changes are written in the same transaction; no synthetic events for existing prices, seeds, or unchanged updates. Historical receipts retain their posted price. Deleting an unused unit also deletes that unit's history; referenced units remain protected. Migration 0022 is additive.

Verified: direct API price edits, unchanged suppression, role refusal, Excel import and rollback, 11 focused backend tests, and no migration drift. Django admin writer is wired but not directly exercised; product history UI, line discounts, partial refunds, and cost snapshots remain in Phase 2.

## Discount allocation checkpoint

`apps/pos/discount_allocation.py` allocates integer centavos proportionally to eligible line balances after item discounts. Leftover centavos go to the largest remainders, with checkout line order breaking ties. It rejects discounts larger than the relevant balance. Seven unit tests cover exclusions, rounding, zero and full discounts, and invalid amounts.

Checkout now stores each line's share of the existing sale-level discount (`SalesItem.cart_discount_amount`, migration 0019; NULL for undiscounted or older sales). Totals, VAT and approval are unchanged. Item-level discounts, per-line exclusions, and refunds reading the stored shares are still to do; keep the legacy refund path for sales without shares.

## Cashier discount limits

A cashier discounts alone up to the Admin's per-sale cap (`discount_cap_percent`, default 10%). New optional `shift_discount_cap_percent` (migration 0020, NULL = off, set via `PATCH /store-settings/`) limits a shift's cumulative discount as a percent of goods sold that shift, this sale included, excluding returns and voids. Over either limit the till gets `DISCOUNT_OVER_CAP` and asks a manager to approve. Tests: `ShiftDiscountLimitTests` (4). The Admin Settings screen now has a "Shift discount limit (%)" field (empty = no limit).

## Line discounts (backend)

Each checkout line may carry `discount {kind, value, reason}`: it comes off that line, the sale discount is measured on what remains and shared over remaining balances (`item_discount_amount` migration 0021, `cart_discount_amount`). `discount_amount` stays the combined total, so VAT, change, reports and refunds are untouched; the cap, approval and shift limit use the combined percent. Fulfilments take none. Tests: `LineDiscountTests` (7). The till now has a per-line discount dialog (combined-percent approval, narrow layout covered, 500 till tests pass); held carts do not store line discounts, so Hold is disabled with a caption while one exists. Goldens not run.

## Never-discounted products (cement)

`Product.allow_discount` (inventory migration 0023, default true, on the products API). Checkout refuses a line discount on such a product (`INVALID_DISCOUNT`), measures a PERCENT sale discount on the discountable lines only, shares the sale discount over those lines (excluded lines get 0.00), and refuses a sale discount on a cart of only such goods. Tests: `NonDiscountableProductTests` (6). Not covered: Excel catalogue import does not carry the flag; any inventory-role user can edit it through the products API (could be restricted to Admin).

## Refunds on stored shares

A return against a sale that stored discount shares refunds each selling unit's own net (subtotal less line discount less sale-discount share), rounded cumulatively per unit so partial returns sum exactly to the line net, still capped by the sale's remaining net (`_stored_share_refund`). Sales without stored shares keep the old basket ratio. Lines of one selling unit on a sale are pooled (an average), so mixed prices within ONE unit are still approximate. Tests: `ReturnOfLineDiscountTests` (3) plus 108 return/restock/payment tests passed.

Also fixed a pre-existing restock bug found by these tests: two sale lines drawing from one batch made `_restock_returned` think the batch was exhausted ("Cannot return more than the original sale drew") and could drop a stock increment. Draws are now totalled per batch.

Still to do: cost snapshots for profit, receipt display of line discounts, full suite, commit.

## Guardrails

Use POS source based on the fetched Windows workflow branch, not dirty main. Use real CPMS branch only for interface smoke where needed; no unrelated feature changes. No live store data, credentials, backups, or same-name Compose stacks in tests. Keep at most two agents active, one heavy test/build at a time. Record exact tests, migration behavior, remaining native-platform and hardware checks.
