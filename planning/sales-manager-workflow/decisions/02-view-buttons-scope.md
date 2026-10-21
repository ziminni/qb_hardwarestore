# D-02 View Buttons Scope

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

Quotations, Sales Orders, and Transactions pages each have a `TextButton(onPressed: () {}, child: const Text('View'))` that is a silent no-op. What should View open, and is there any write scope (edit, delete, status change)?

## Options Considered

**A — Read-only bottom sheet / side panel:** Tap View → `showModalBottomSheet` with the full document (customer, items, totals, status). No new route. No writes.

**B — New detail page at `/sales/quotations/:id` etc.:** Full-page view with back button. 3 routes + 3 page files. Same read-only data.

**C — Leave as no-op, focus elsewhere.**

## Decision: Option A (read-only bottom sheet)

Bottom sheet showing read-only document detail. No create, edit, delete — those have no decided scope and the backend has no create/update actions wired for these from the sales role.

## Data contract

**Quotation** — `GET /api/v1/quotations/` already returns `items[]` nested (QuotationItemSerializer). Flutter `SalesQuotation` model currently lacks `items`. Add `List<QuotationLineItem>` to the model + parser. Display: `quotation_no`, `customer` (name from viewmodel.quotations — already resolved), `status`, `valid_until`, `notes`, items with `qty × unit_price`.

`QuotationItemSerializer` returns `variant_uom` as int id — not human-readable. Resolve name by looking up `context.read<InventoryViewmodel>()` (app-scoped) `variantUomCode` from the already-loaded catalogue. No backend change needed.

**SalesOrder** — `GET /api/v1/sales-orders/` returns `items[]` nested. Flutter `SalesOrderRecord` model lacks `items`. Add `List<SalesOrderLineItem>` + parser. Display: `order_no`, `customer`, `status`, `notes`, items.

**SaleTransaction** — Flutter model already has `items` (List<TransactionLineItem>) + `payments`. Bottom sheet is cheapest for transactions: just display existing fields.

## Files affected

- `flutter/lib/data/models/sales_module.dart` — add `QuotationLineItem`, `SalesOrderLineItem`, items fields on `SalesQuotation` + `SalesOrderRecord`
- `flutter/lib/features/sales/views/sales_quotations_page.dart` — wire View → `_showQuotationSheet`
- `flutter/lib/features/sales/views/sales_orders_page.dart` — wire View → `_showOrderSheet`
- `flutter/lib/features/sales/views/sales_transactions_page.dart` — wire View → `_showTransactionSheet`

## Invariants

- Bottom sheet must be scrollable (items list can be long).
- No form fields, no submit button — strictly read-only.
- Empty items list shows "No items" text, not a crash.
- Loading variant names from `InventoryViewmodel` may be empty if the user navigates before load — show the numeric id as fallback, not a crash.

## Cost if wrong

Sheet opens but shows an id instead of a name for quotation/order items — cosmetic. Full name lookup is a future polish, not a correctness issue.
