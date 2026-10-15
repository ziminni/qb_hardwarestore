# planning/api-integration/MAP.md

**Slug:** `api-integration` · **Opened:** 2026-10-15
**Status:** Active Frontier open — 4 decisions queued, 0 locked.

## Destination

Every screen reachable by a seeded role renders **live API data** with loading, error and empty states — no
`*_mock_data.dart` file survives, and no client-reachable endpoint is left uncalled. The client stops being a
mockup *of* the system and becomes a client *of* it.

## Notes & Invariants

Rules every session on this map must respect. Facts that already have a home are linked, never restated.

| Invariant | Detail |
| :--- | :--- |
| **Client-side epic only** | The backend is feature-complete. No new endpoints, no model or migration changes. If a task appears to need one, re-read `docs/SYSTEM_ATLAS.md` §3 before changing anything. |
| **Every list is paginated** | `{count, next, previous, results}` with `PAGE_SIZE = 50`. Read `.results`. Contract: `ENDPOINTS.md` §1. |
| **One data path, no new shapes** | `View → ViewModel → Repository → Service → ApiClient`. The only correct example is `features/auth/viewmodels/auth_viewmodel.dart`; `sales_module_viewmodel.dart` is the mock shape being replaced. |
| **Demo data comes from `seed_demo`** | Products with stock batches, customers, completed sales, an unpaid utang, and an APPROVED requisition with a minted token. Setup: `README.md`. |
| **Every wired screen needs three states** | loading, error, empty. Every list today is synchronous and has none. |
| **`flutter analyze` must stay clean** | `flutter/test/widget_test.dart` (untracked, broken template) is currently the sole error — see `planning/04-cleanup.md`. |
| **Six roles exist, five are seeded** | Canonical names: `apps/users/permissions.py`. Demo logins: `README.md`. |

## Decisions So Far

None yet.

## Active Frontier (Open & Unblocked)

- [ ] [First Vertical Slice & Ordering Lens](./decisions/01-first-vertical-slice.md) — grill
- [ ] [Product & Variant Client Model Shape](./decisions/02-product-variant-client-model.md) — domain-model
- [ ] [Pagination Envelope Strategy](./decisions/03-pagination-envelope-strategy.md) — research
- [ ] [Role to Dashboard Routing for All Six Roles](./decisions/04-role-dashboard-routing.md) — grill

## Blocked

- [ ] [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) — domain-model (Blocked by: [First Vertical Slice & Ordering Lens](./decisions/01-first-vertical-slice.md))

## Fog of War (Not Yet Specified)

In scope, but not sharp enough to state until the frontier advances.

- Requisition and material-token release UI shape — waits on the routing decision (a foreman must be able to log in at all) and on the slice order.
- Goods receipt / receiving UI — only required if the demo must create stock without `seed_demo`.
- Collectibles / utang screens — overdue list and aging report.
- Reports: three screens (`reports/views/inventory_reports_page.dart`, `sales/views/sales_reports_page.dart`, `admin/views/reports_page.dart`) over one backend surface; consolidation and wiring are entangled.
- Customer master-data screens.
- Failure behaviour of POS checkout — network loss mid-sale, insufficient stock.

## Out of Scope

Ruled past the destination. Do not reopen without a new map.

- CPMS / cross-system integration.
- Production hardening: env-based secrets, `settings.py` split, tightening `ALLOWED_HOSTS` and CORS.
- An API-backed Settings page — agreed deferral, and it has no backend contract.
- New backend endpoints or schema changes.
