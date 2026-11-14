# Sales-order lifecycle: edit, cancel, fulfil to sale

**Status:** Locked 2026-11-12 (by: me — owner answers; defaults marked *delegated*)
**Phase:** 7

## Context

Phase 5 shipped a create-only order form. Research (2026-11-12) found:

- `SalesOrder` statuses are `CONFIRMED / PROCESSING / READY / COMPLETED` with no transition rules; `SalesOrderViewSet` is a plain `ModelViewSet`, so PUT/PATCH/DELETE (including `status`) are open to POS roles with no audit, and deleting an order with a delivery raises `ProtectedError` → 500 (`backend_django/apps/pos/views.py:996-1006`).
- Order lines carry only `qty` + `unit_price` (client-editable), no discount/VAT; checkout (`process_sale`, `apps/pos/services.py:739+`) ignores client prices and prices from the catalogue.
- An order's delivery fee lives only on its `Delivery` row because no fulfil path existed (`apps/pos/models.py:676-683`; the one-document check at `:742-749` must be loosened so a delivery can keep its order link once moved to the first sale).
- No stock reservation exists anywhere (held carts and project requests deliberately reserve nothing).

## Decisions

1. **Price:** the sale charges the **order's agreed line price**. A line below the catalogue price counts as a discount: within the Admin cap it is allowed; above the cap it needs a one-time manager approval **when the order is saved** (create or edit), reusing the Phase 4 discount-approval token. Fulfilment then needs no new approval. (by: me)
2. **Stock:** **no reservation.** Stock is checked and taken only when a fulfilment is rung. The order view shows a live per-line "enough / short" hint. (by: me)
3. **Partial fulfilment:** allowed. Each fulfilment is its own sale and receipt; the order tracks fulfilled vs remaining per line, and becomes `COMPLETED` when nothing remains or the remainder is cancelled. (by: me)
4. **Roles:** Store Manager/Admin **edit or cancel** (reason required, audited) only while nothing has been fulfilled; after a partial fulfilment they may only cancel the remainder. A **cashier fulfils at the till** (open shift, normal payment rules incl. split/cheque/utang), opening the order like a held cart. (by: me)

## Delegated defaults (owner may override)

- **Statuses:** `CONFIRMED → PARTIAL → COMPLETED`, plus `CANCELLED`. Legacy `PROCESSING`/`READY` rows read as `CONFIRMED`; no new writes use them. Status is never client-writable; transitions are server actions under a row lock.
- **Delivery fee:** charged once, on the **first** fulfilment sale; the existing `Delivery` row is re-linked to that sale. Later fulfilments carry no fee.
- **Customer:** fulfilment uses the order's named customer (walk-in orders are already impossible).
- **VAT:** order prices are VAT-inclusive like shelf prices; VAT is split on the sale exactly as at the till.
- **DELETE:** removed for orders; cancellation replaces it.
- **Quotation → order conversion:** out of scope for Phase 7 (orders can still name the quotation they came from).

## Consequences

- New order-line field for fulfilled quantity; sale lines link back to the order line (for remaining-qty arithmetic and returns).
- `process_sale` gains an order-fulfilment entry that keeps all checkout guards (shift, FIFO, VAT, payments, idempotency) but takes prices from the order line.
- Returns of a fulfilment sale follow the normal return rules; they do not reopen the order.
- Supersedes the Phase 5 read-only pins in `sales_read_only_actions_test.dart` for orders only (quotations stay read-only).

## Follow-up rulings (2026-11-12)

- **Price guard per line** (by: me): any single line discounted beyond the Admin cap needs manager approval at save; no whole-order averaging.
- Delegated (plan Phase 7): the same approval rule applies to every role; fulfilment takes no extra discount; cancelling an unfulfilled order marks its SCHEDULED delivery FAILED.
