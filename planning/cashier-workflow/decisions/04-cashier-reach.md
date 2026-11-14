# Cashier Reach to History & Receivables

**Status:** LOCKED 2026-10-20 (user) · **Mode:** grill · **Map:** [cashier-workflow](../MAP.md)

## Question

Tabs 2 (Transaction history) and 4 (Record payment) from [Cashier Tab Set](./03-cashier-tab-set.md) have
live backends but their only pages today sit behind the `/sales/` fence, which bounces role `pos`
(`routes.dart` redirectFor). How does the cashier reach them?

## Findings (verified 2026-10-20)

- `InventorySalesViewmodel` (transaction history) is **globally provided** in `main.dart:48`, so any page can
  `context.watch` it. The list body in `sales_transactions_page.dart` is reusable as-is.
- `SalesReceivablesViewmodel` is **page-scoped** — `sales_receivables_page.dart:32-33` creates it with
  `create: (_) => (viewmodel ?? SalesReceivablesViewmodel())..load()`. A POS page provides it the same way;
  no `main.dart` change.
- Both viewmodels hit endpoints the cashier is already authorized for: `/transactions/` (read) and
  `/ledger-payments/` (write, decision 19). The backend does not need the fence — only the client fence
  blocks the cashier.
- Precedent for the rejected option: [Approve Queue Route Gate](../../api-integration/decisions/20-approve-queue-route-gate.md)
  admitted role `sales` to two `/admin/` routes by exact-match exemption.

## Ruling (user, 2026-10-20): POS-native pages

Build two thin pages under the POS shell that **reuse the existing viewmodels and services**:

- `/pos/history` → `PosTransactionHistoryPage`: POS shell + the existing transaction-list body, consuming
  the global `InventorySalesViewmodel`.
- `/pos/receivables` → `PosReceivablesPage`: POS shell + the existing receivables body + Record-payment
  action, self-providing `SalesReceivablesViewmodel` (`..load()`), exactly as the sales page does.

Both render the **POS sidebar** (the [canonical tab set](./03-cashier-tab-set.md)) so the cashier never
leaves the POS workflow.

Rejected: a `/sales/` fence exemption for role `pos`. It is one routing line, but it drops the cashier into
the **sales shell** with the sales sidebar — they would see sales-only tabs and could wander out of the POS
workflow. Mixing shells contradicts [POS Navigation Wiring](./02-pos-navigation-wiring.md), which made the
POS shell its own skeleton.

## Cost if wrong

Two wrapper pages instead of one routing line. If they drift from the sales equivalents, a reader fixes a
bug twice. Mitigation: they reuse the same viewmodels/services and, where practical, the same body widgets —
only the shell wrapper differs. Reversible: delete the two pages and add the fence exemption instead.

## Build contract (for the executing session)

- New routes `/pos/history`, `/pos/receivables` in `routes.dart`, inside the POS role's reachable set (not
  behind `/sales/`). `navigatePos` (decision 02) maps tab 2 → `/pos/history`, tab 4 → `/pos/receivables`.
- `PosTransactionHistoryPage`: `DashboardShell` + existing transaction-list body + global
  `InventorySalesViewmodel`; load-on-open with the shared `LiveLoadErrorBanner` + retry (decision 07).
- `PosReceivablesPage`: `DashboardShell` + existing receivables body incl. the Record-payment flow;
  self-scoped `SalesReceivablesViewmodel()..load()`. Honour [Receivables Record Payment](../../api-integration/decisions/19-receivables-record-payment.md):
  the cashier can post a payment. No new data layer.
- **RED-first tests:** (1) a routing test — role `pos` reaches `/pos/history` and `/pos/receivables` and is
  still bounced from `/sales/*` and `/admin/*` (fails today: no such routes); (2) a widget test — the POS
  receivables page renders live rows (not mock) and exposes Record payment; (3) extend
  `sidebar_index_consistency_test.dart` for the two new routes.
- This decision, plus [POS Navigation Wiring](./02-pos-navigation-wiring.md), makes **tabs 0/2/3/4 fully
  reachable** — the cashier's non-new-backend workflow. Tabs 1 and 5 wait on
  [Held Sale Model](./05-held-sale-model.md) and [Shift / Z-Reading Model](./06-shift-z-reading.md).
- Verify live on WSL: as `cashier`, tabs 0/2/3/4 all open live POS-shell screens; Record payment posts and
  the ledger reflects it.
