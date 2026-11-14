# Sales Stack Reconciliation

**Mode:** domain-model · **Status:** RESOLVED 2026-10-17 · **Opened:** 2026-10-15
**Phase:** 6 — released when [First Vertical Slice & Ordering Lens](./01-first-vertical-slice.md) locked the
slice order.

## The question

The `sales` feature holds two parallel stacks with no shared model. Which one survives, and what happens to
the other?

## Why it matters

| File | Covers |
| :--- | :--- |
| `features/sales/viewmodels/sales_module_viewmodel.dart` (129 lines) | customers, quotations, orders, receivables |
| `features/sales/viewmodels/inventory_sales_viewmodel.dart` | dashboard, transactions, returns, reports |

`data/models/sales_module.dart` and `data/models/sales.dart` describe overlapping concepts. Wiring the API
against both would double the work and leave two competing sources of truth. Quotations and sales orders have
**no backend model at all**, so part of this stack cannot be wired to anything.

## Needs a domain sketch

- Which screens does the team actually intend to ship for the sales role?
- Do quotations and orders get dropped, or do they need backend models (which would move them Out of Scope
  for a client-only epic)?
- Which model file becomes canonical, and what happens to the other?

## Resolution

**Ruling (user, 2026-10-17): quotations and orders get REAL backend models.** The sales role ships all
seven screens, and the three the server cannot serve today (quotations, orders, returns) are given the
backend they need rather than deleted or left as mock.

### The facts that framed it

The two "competing" stacks are not symmetric:

| Stack | Serves | Backend support |
| :--- | :--- | :--- |
| `sales_module_viewmodel.dart` + `models/sales_module.dart` | **only** quotations + orders (3 files) | **none** — 0 hits for quotations in `ENDPOINTS.md`, no orders endpoint |
| `inventory_sales_viewmodel.dart` + `models/sales.dart` | dashboard, transactions, returns, reports (8 lib files; model used by 14) | `/transactions/*`, `/transactions/daily_report/`, `/ledgers/*` |

So this was never two equal stacks: it is **one live stack and one stack that exists solely for two
screens the server cannot serve.** Returns is also mock (`"Return recorded in mock data."`) with no
endpoint. The invariant forbade new endpoints, and the Destination requires every reachable screen to
render live data — which together forced a choice.

### What this decision costs, stated plainly

- **It BREAKS the map's binding invariant.** "No new endpoints, and no model or migration changes" held
  exactly across the whole branch (`0052468..HEAD`: 0 migrations, 0 models.py, 0 urls.py). Phase 6 adds
  models, migrations, serializers and endpoints. The invariant is therefore **superseded for Phase 6**,
  not quietly ignored — the map's Notes & Invariants records the change.
- **Phase 6 is no longer client-side.** It becomes a backend phase before it can be a UI phase, so the
  epic grows: `apps/sales/` (or `apps/pos/`) gains `Quotation`, `QuotationItem`, `SalesOrder`,
  `SalesOrderItem`, their serializers, viewsets, routes and two migrations, and only then do the three
  screens get wired.
- **`sales_module_viewmodel.dart` + `models/sales_module.dart` become the CANONICAL quotation/order
  stack** rather than the deleted one — the opposite of what a delete-the-dead-stack resolution would
  have done. `inventory_sales_viewmodel.dart` + `models/sales.dart` remain canonical for
  dashboard/transactions/reports.

### The rejected alternatives, and why

- *Ship only the four the server supports, delete the rest* was the only option that satisfied the
  Destination without touching the backend, and it was recommended. It was rejected because the sales
  role is meant to demonstrate a full quotation-to-order flow, and a capstone that silently drops two
  of seven screens shows less than one that builds the missing backend.
- *Keep them as "not available in this build" screens* would have left three screens permanently
  unreachable from live data, knowingly failing the Destination while keeping both stacks alive — the
  worst of both.

### What this decision does NOT settle

Returns still has no endpoint. It is **not** covered by this ruling, and is carried into Phase 6's
roadmap as an open question: either a returns endpoint joins the new backend work, or the two returns
pages (`sales_returns_page.dart`, `inventory_returns_page.dart`) are consolidated onto the transactions
the server already exposes.

**Superseded: [Customer Returns](./15-customer-returns.md) locked this 2026-10-17** — a return is a
`SalesTransaction` with `source='RETURN'`, negative amounts and an optional `original_transaction` FK;
the two pages consolidate into ONE under Sales; roadmap tasks 6A.3 (built) and 6A.4 own the rest.
The "Unresolved" line below is history, not an open question — kept so the audit trail survives.

_Unresolved — Phase 6. Both sales stacks are in scope, so one must be chosen before anything is wired._
