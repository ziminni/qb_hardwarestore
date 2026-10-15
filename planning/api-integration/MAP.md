# planning/api-integration/MAP.md

**Slug:** `api-integration` · **Opened:** 2026-10-15
**Status:** 1 locked · 6 open. Phase 0 next. Immediate decision: [Product & Variant Client Model Shape](./decisions/02-product-variant-client-model.md).

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

- [First Vertical Slice & Ordering Lens](./decisions/01-first-vertical-slice.md): **Cashier journey** — products → inventory → POS checkout → customers → requisitions → admin, walked in dependency order, one demoable outcome per phase.

## Active Frontier (Open & Unblocked)

Ordered by the locked phase order: define the entity, then the transport, then the presentation. Resolve one
per session.

- [ ] [Product & Variant Client Model Shape](./decisions/02-product-variant-client-model.md) — domain-model · Phase 0, gates Phase 1
- [ ] [Pagination Envelope Strategy](./decisions/03-pagination-envelope-strategy.md) — research · Phase 0
- [ ] [Loading, Error and Empty State Convention](./decisions/07-loading-error-empty-convention.md) — grill · Phase 0
- [ ] [Role to Dashboard Routing for All Six Roles](./decisions/04-role-dashboard-routing.md) — grill · Phase 0, needed again at Phase 5
- [ ] [POS Checkout Client Contract](./decisions/06-checkout-client-contract.md) — domain-model · Phase 3
- [ ] [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) — domain-model · Phase 6

## Blocked

Nothing is blocked. [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) was released
when the slice order locked and is now simply sequenced at Phase 6.

## Fog of War (Not Yet Specified)

In scope, but not sharp enough to state until the frontier advances.

- Goods receipt / receiving UI — Phase 2 is read-only stock; receiving is only required if the demo must create stock without `seed_demo`.
- Requisition and material-token release UI shape — Phase 5; waits on the routing decision and on products being live.
- Collectibles / utang screens — overdue list and aging report.
- Customer master-data screens — which slice of customer CRUD the POS actually needs.
- Reports: three screens (`reports/views/inventory_reports_page.dart`, `sales/views/sales_reports_page.dart`, `admin/views/reports_page.dart`) over one backend surface; consolidation and wiring are entangled.
- Product image handling — `image_url` is in the serializer, but whether the demo renders images at all is unspecified.

## Out of Scope

Ruled past the destination. Do not reopen without a new map.

- CPMS / cross-system integration.
- Production hardening: env-based secrets, `settings.py` split, tightening `ALLOWED_HOSTS` and CORS.
- An API-backed Settings page — agreed deferral, and it has no backend contract.
- New backend endpoints or schema changes.
