# Receivables Record Payment

**Mode:** grill · **Status:** RESOLVED 2026-10-18 · **Opened:** 2026-10-18
**Phase:** 6C — the missing write half of the already read-live receivables screen.

## The question

`sales/views/sales_receivables_page.dart` renders live `/ledgers/` rows, but its Action column is a disabled `Record payment` button. `POST /api/v1/ledger-payments/` exists and moves `balance_due`. Should POS wire it, and for whom?

## Facts, verified in code on 2026-10-18

- `CollectiblePaymentViewSet` carries `permission_classes = [IsPOSOrReadOnly]` (`backend_django/apps/collectibles/views.py:103`). Under `apps/users/permissions.py`, that means reads for any authenticated user and writes for Cashier, Store Manager, Admin and System Administrator.
- Ledger-entry writes are a separate, stricter path: the local `IsAdminOrReadOnly` in the same collectibles views file allows staff-only writes (`backend_django/apps/collectibles/views.py:21-29,38`). A Record payment writes a payment, not a ledger entry, so Cashier permission is enough.
- The client has no payment write today: `LedgerService` only reads ledgers, `SalesReceivablesViewmodel` only loads, and the page leaves `onPressed: null` beside a comment claiming Admin-only. That comment conflates ledger-entry writes with payment writes and is stale.
- `ENDPOINTS.md` agrees: collectible payments are Cashier / Store Manager / Admin for writes.
- `docs/SYSTEM_ATLAS.md` marks Collectibles CRUD writes Dead with no client screen; this decision flips only the `ledger-payments` POST to Live when built.

## Ruling (user, 2026-10-18): BUILD for Cashier+

Wire Record payment for POS roles (Cashier, Store Manager, Admin, System Administrator). Rejected: managers-only (it would mismatch the endpoint unless the backend permission is also tightened), and do-not-build (it would leave a reachable endpoint uncalled against the Destination unless explicitly ruled out of scope).

## File impact and build contract

- `flutter/lib/data/services/ledger_service.dart`: add the payment POST; surface overpayment refusal; no new endpoint, model or migration.
- Repository plus `SalesReceivablesViewmodel` action; enable the row button with loading and error states; correct the stale Admin-only comment when wired.
- Tests RED then GREEN for the post path; full suite green before handoff.

## Cost, stated plainly

More money-path UI and tests, and a cashier can take payments outside checkout. If wrong, restrict by role or remove the column.
