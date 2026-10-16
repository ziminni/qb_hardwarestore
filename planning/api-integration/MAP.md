# planning/api-integration/MAP.md

**Slug:** `api-integration` · **Opened:** 2026-10-15
**Status:** Phase 0 **complete** — 6 locked · 3 open. Next: Phase 1 (products catalogue). Remaining decisions gate Phases 3, 5 and 6.

## Destination

Every screen reachable by a seeded role renders **live API data** with loading, error and empty states — no
`*_mock_data.dart` file survives, and no client-reachable endpoint is left uncalled. The client stops being a
mockup *of* the system and becomes a client *of* it.

## Phase 0 — Complete (2026-10-15)

All four Phase 0 decisions are locked, so Phase 1 can start. What a coding session must build first:

| Item | Deliverable |
| :--- | :--- |
| **Models** | Keep `Product` as-is. Rewrite `ProductVariant`; add `VariantUom` and `InventoryBatch`. Delete `sku` and `storageLocation`. Stop swallowing missing fields with `?? 0`. |
| **Transport** | `ApiClient.getList<T>` returning `Paged<T>`, unwrapping `.results`. |
| **Presentation** | New `flutter/lib/core/widgets/async_view.dart`. |
| **Assembler** | A catalogue assembler producing `CatalogueItem { product, variant, uom, price, stockOnHand }`, where `price = uom.defaultSellingPrice` and `stockOnHand = sum(batch.currentQty)`. |
| **Routing** | Give `site_foreman` no dashboard; route unmapped and role-less accounts to an explicit unsupported-role screen instead of `/login`. |
| **Registration** | Register `ProductsViewmodel` and `PosTransactionViewmodel` in `main.dart` — only 6 of 8 viewmodels are currently wired. |
| **Cleanup** | `products_page.dart` watches `InventoryViewmodel`, not its own viewmodel — decide which is correct before wiring. |

Then **Phase 1**: wire the products catalogue screen to `GET /api/v1/products/` + `GET /api/v1/batches/`.

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
- [Pagination Envelope Strategy](./decisions/03-pagination-envelope-strategy.md): one `ApiClient.getList<T>` returning `Paged<T>`; unwrap `.results` in exactly one place. No seeded list exceeds one page (max 8 vs `PAGE_SIZE = 50`), so paging is deferred.
- [Product & Variant Client Model Shape](./decisions/02-product-variant-client-model.md): mirror the API's four entities (`Product`, `ProductVariant`, `VariantUom`, `InventoryBatch`) plus one computed `CatalogueItem`; `sku` and `storageLocation` deleted.
- [Loading, Error and Empty State Convention](./decisions/07-loading-error-empty-convention.md): viewmodels follow the `auth_viewmodel` public-field convention; one shared `AsyncView` widget in a new `core/widgets/` owns loading/error/empty rendering.
- [Role to Dashboard Routing for All Six Roles](./decisions/04-role-dashboard-routing.md): a Site Foreman is a **CPMS-side identity, not a POS user** — `site_foreman` gets no POS dashboard, and unmapped roles route to an explicit screen instead of looping to `/login`.
- [Which Price the POS Charges](./decisions/08-pricing-rule.md): `VariantUom.default_selling_price` is what the customer is charged; `InventoryBatch.batch_selling_price` is display-only. Cost shows the latest batch's `unit_cost_landed`, labelled as such.

## Active Frontier (Open & Unblocked)

Ordered by the locked phase order: define the entity, then the transport, then the presentation. Resolve one
per session. Phase 0 is empty — the next three gate Phases 3, 5 and 6.

- [ ] [POS Checkout Client Contract](./decisions/06-checkout-client-contract.md) — domain-model · Phase 3
- [ ] [Requisition UI Ownership (POS side vs CPMS side)](./decisions/09-requisition-ui-ownership.md) — grill · Phase 5
- [ ] [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) — domain-model · Phase 6

## Blocked

Nothing is blocked. [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) was released
when the slice order locked and is now simply sequenced at Phase 6.

## Fog of War (Not Yet Specified)

In scope, but not sharp enough to state until the frontier advances.

- Goods receipt / receiving UI — Phase 2 is read-only stock; receiving is only required if the demo must create stock without `seed_demo`.
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
