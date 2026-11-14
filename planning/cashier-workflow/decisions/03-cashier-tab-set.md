# Cashier Tab Set

**Status:** LOCKED 2026-10-20 (user) · **Mode:** grill · **Map:** [cashier-workflow](../MAP.md)

## Question

Which tabs does the cashier's sidebar hold? This fixes what [POS Navigation Wiring](./02-pos-navigation-wiring.md)
routes to and whether new backend work enters scope.

## Findings (verified 2026-10-20)

| Candidate | Backend today | Page today |
|---|---|---|
| New transaction (till) | `/transactions/` (`IsPOSOrReadOnly`) | ✅ `pos_transaction_page.dart` |
| Release materials | `/tokens/verify/`, `/tokens/release/` (`IsPOSRole`) | ✅ `material_release_page.dart` (unreachable) |
| Transaction history | `/transactions/` readable by cashier | ❌ only the `/sales/`-fenced page |
| Record payment (utang) | `/ledger-payments/` write (`IsPOSOrReadOnly`); decision 19 = "Cashier+" | ❌ only the `/sales/`-fenced page |
| Customers | — | ❌ screen deleted by [Customer Master-Data Scope](../../api-integration/decisions/14-customer-master-data-scope.md) |
| Held transactions | **none** — `SalesTransaction.Status` = COMPLETED · VOID · REFUNDED | ❌ |
| End of shift | **none** — no Shift / Z-reading model anywhere | ❌ |

## Ruling (user, 2026-10-20): Full till — six tabs

The cashier's sidebar holds, in this canonical order (the single source created by
[POS Navigation Wiring](./02-pos-navigation-wiring.md); index is `selectedNavigationIndex`):

| # | Tab | Status | Phase |
|---|---|---|---|
| 0 | New transaction | exists; home | 2 |
| 1 | Transaction history | page to build; backend ready | 2 |
| 2 | Release materials | exists; needs only routing | 2 |
| 3 | Record payment | page to build; backend ready; decision 19 | 2 |
| 4 | Held transactions | **new backend** — a held/parked sale | 3 |
| 5 | End of shift | **new backend** — Shift / Z-reading | 4 |

**Order rule — append, never insert.** The four backend-ready tabs occupy stable indices 0–3; the two
new-backend tabs are appended at 4 and 5. A build phase that adds a tab adds it at the END, so no existing
index renumbers and `sidebar_index_consistency_test.dart` never trips on an insertion. Phase 2 renders tabs
0–3; Phase 3 appends 4; Phase 4 appends 5.

**Customers is NOT a tab.** [Customer Master-Data Scope](../../api-integration/decisions/14-customer-master-data-scope.md)
deleted the standalone screen and put utang in the checkout panel; that decision is not reopened here.

Rejected: *backend-backed only* (drops Held + End of shift — the user wants a realistic till) and
*held client-only* (a parked sale that evaporates on app restart is a worse lie than no tab).

## Consequences — three questions graduate from Fog to the frontier

1. **[Cashier Reach to History & Receivables](./04-cashier-reach.md)** (grill) — how the cashier reaches the
   Transaction-history and Record-payment screens (tabs 2 and 4), given both live today only behind the
   `/sales/` fence that bounces role `pos`.
2. **[Held Sale Model](./05-held-sale-model.md)** (domain-model) — the server shape behind tab 1: a new
   `HELD` transaction status vs a separate parked-cart entity; how a held sale serializes, resumes into the
   till, and voids; what stock it does and does not reserve.
3. **[Shift / Z-Reading Model](./06-shift-z-reading.md)** (domain-model) — the server shape behind tab 5:
   open/close a shift, the cash-drawer count, and the end-of-day Z-reading totals; which transactions a
   shift owns.

## Cost if wrong

Two net-new backend features (Held Sale, Shift) are the bulk of the remaining work. If the capstone
timeline tightens, tabs 1 and 5 can be cut back to this decision's rejected "backend-backed only" set
without touching tabs 0/2/3/4 — the nav order is the single source, so dropping a tab is a one-line change
plus its consistency-test row.

## Build contract note

This decision adds no code by itself. It fixes the route list that
[POS Navigation Wiring](./02-pos-navigation-wiring.md) consumes; that build cannot start until tabs 2 and 4
have a reachable destination (decision 04) — tabs 1 and 5 may route to their new pages as those phases land.
`material_release_page.dart` moves to `selectedNavigationIndex: 2` under the canonical order (Release materials is index 2).
