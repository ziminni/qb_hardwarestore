# Sales Stack Reconciliation

**Mode:** domain-model · **Status:** BLOCKED · **Opened:** 2026-10-15

**Blocked by:** [First Vertical Slice & Ordering Lens](./01-first-vertical-slice.md) — only matters once the
slice order reaches the sales module.

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

_Unresolved — blocked until the slice order determines whether sales is in scope._
