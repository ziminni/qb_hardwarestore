# planning/api-integration/MAP.md

**Slug:** `api-integration` · **Opened:** 2026-10-15
**Status:** 8 locked · 3 open. **Phase 0 is COMPLETE — all 7 rows built, then verified row-by-row against
the code rather than against the ledger, then reviewed on a fresh context and the two defects it found fixed.**
Phase 1 is unblocked; the three open decisions gate Phases 3, 5 and 6.

## Destination

Every screen reachable by a seeded role renders **live API data** with loading, error and empty states — no
`*_mock_data.dart` file survives, and no client-reachable endpoint is left uncalled. The client stops being a
mockup *of* the system and becomes a client *of* it.

## Phase 0 — status (verified 2026-10-16, after the build)

**7 of 7 rows done. Phase 1 is unblocked.** This table has been wrong twice in opposite directions, so it is
stated with evidence and was re-verified against the CODE after the build landed, not against the ledger: an
earlier session recorded "Phase 0 complete" while only 2 rows existed (it had conflated the staged
`ProductVariant` swap — the *Models* row, expanded by rulings R7/R8 into a phase-sized job — with all of
Phase 0), and the table then under-claimed for a session after the work had actually landed.

| Row | State | Evidence |
| :--- | :--- | :--- |
| **Models** | ✅ done | `ProductVariant` carries exactly the nine API fields plus a derived `barcode` getter; the six invented fields are deleted |
| **Assembler** | ✅ done | `lib/data/models/catalogue_item.dart`, `lib/data/services/catalogue_assembler.dart` |
| **Transport** | ✅ done | `lib/core/network/paged.dart` — `Paged<T>` + the pure `parsePaged` unwrapping the envelope in one place — and `ApiClient.getList<T>`. Commit `adac3bc`, 15 tests |
| **Presentation** | ✅ done | `lib/core/widgets/async_view.dart`, precedence loading > error > empty > data baked into the widget. Commit `f7359db`, 6 tests |
| **Routing** | ✅ done | `lib/features/auth/views/unsupported_role_page.dart`, `AppRoutes.unsupportedRole`, and a **pure** `AppRoutes.redirectFor` replacing the silent bounce to `/login`. Commit `3fd1cf1`, 20 tests |
| **Registration** | ✅ **dissolved — no code needed** | Neither viewmodel was ever unwired: `PosTransactionViewmodel` is provided at `pos_transaction_page.dart:35` and already takes the **live** viewmodels and listens to them, and `ProductsViewmodel` is provided at `products_page.dart` and is now live too. Decision 11 **supersedes** registering either in `main.dart` — they are screen-scoped view state, and a globally shared search box and half-finished till cart are unwanted. |
| **Cleanup** | ✅ done | **Decision 11**: `ProductsViewmodel` is view state only, reads the list live from `InventoryViewmodel`, and delegates every mutation, so the page calls each one ONCE and the two product-id authorities are gone. Commit `cd8dcef`, 20 tests |

Two defects were found by the fresh-context review of this work and both are fixed: `Paged.hasMore` reported
"more" for any short page (it used the row count instead of the envelope's `next` link), and the sign-out path
had no test proving it arrives anywhere. See rulings **R29** and the Task 6/7 entries in
`.superpowers/sdd/MAP/progress.md`.

What the swap delivered, for the reasoning only: `InventoryViewmodel` is batch-backed with FIFO deduction
mirroring `allocate_fifo`, all 16 readers consume batches and `CatalogueItem`, and `LocationHintStore` holds the
location hints. **131 tests pass; `flutter analyze` is clean.** Evidence and rulings:
`.superpowers/sdd/MAP/progress.md`; narrative: `docs/sessions/2026-10-16-staged-model-swap-complete.md`.

The rows below record what each remaining row must deliver:

⚠️ **One caveat carried forward:** the live `seed_demo` data still has **exactly one batch per variant** (8/8),
so FIFO crossing a batch boundary cannot be exercised from seeded data — only the mock can (variant 1 carries
two lots). See ruling **R14**.

What a coding session had to build first:

| Item | Deliverable |
| :--- | :--- |
| **Models** | Keep `Product` as-is. Rewrite `ProductVariant`; add `VariantUom` and `InventoryBatch`. Delete `sku` and `storageLocation`. Stop swallowing missing fields with `?? 0`. |
| **Transport** | `ApiClient.getList<T>` returning `Paged<T>`, unwrapping `.results`. |
| **Presentation** | New `flutter/lib/core/widgets/async_view.dart`. |
| **Assembler** | A catalogue assembler producing `CatalogueItem { product, variant, uom, price, stockOnHand }`, where `price = uom.defaultSellingPrice` and `stockOnHand = sum(batch.currentQty)`. |
| **Routing** | Give `site_foreman` no dashboard; route unmapped and role-less accounts to an explicit unsupported-role screen instead of `/login`. |
| **Registration** | ~~Register `ProductsViewmodel` and `PosTransactionViewmodel` in `main.dart`.~~ **Superseded by decision 11** — both are screen-scoped view state and neither belongs in `main.dart`. Nothing to do. |
| **Cleanup** | `products_page.dart` watches `InventoryViewmodel`, not its own viewmodel — decide which is correct before wiring. |

Then **Phase 1**: wire the products catalogue screen to `GET /api/v1/products/` + `GET /api/v1/batches/`.

> ⚠️ **Measured during execution (2026-10-16) — the Models row under-states its cost, and the task order inverts.**
> Swapping `product.dart` produces **332 analyzer errors across 17 files**. The 92 outside the mock data are not
> field renames: `inventory_viewmodel` derives stock status from `currentStock`/`reorderLevel` and
> `pos_transaction_viewmodel` prices its cart from `sellingPrice`/`currentStock`, so they consume the removed
> fields as **domain logic**.
>
> Required order: **catalogue assembler (`CatalogueItem`) → 16-file domain migration → `product.dart` swap**.
> The additive models (`VariantUom`, `InventoryBatch`, strict JSON readers) are already delivered and tested;
> the `product.dart` swap is deliberately not applied yet so the build stays green.
> Full reasoning and evidence: `.superpowers/sdd/MAP/progress.md` ruling **R7**.

> ✅ **Resolved 2026-10-16 — step 3's crux is not a product choice after all.** The question was how the mutable
> mock store (`InventoryViewmodel.adjustStock`/`sellStock`, which mutate `variant.currentStock`) should move
> stock onto batches. The backend already answers it, so it is **specified rather than guessed**:
> `apps/inventory/services.py::allocate_fifo` deducts **oldest batch first**, ordered by `receipt__receive_date`,
> taking `min(current_qty, remaining)` and raising when short; `apply_stock_adjustment` routes *removals*
> through that same FIFO and lands *additions* on the **newest** active batch, then re-checks low stock.
>
> The client's ordering key is `InventoryBatch.receiptId` — the only non-null date proxy available, because
> **every mock batch was materialised with `createdAt: null`** (20 of 20). `createdAt` is therefore unusable
> for ordering in the mock even though the live API populates it.
>
> ⚠️ **Coverage gap found while verifying this:** every variant has **exactly one batch** — in the mock
> (20 variants / 20 batches) *and* in `seed_demo` (8 / 8). **FIFO crossing a batch boundary cannot be
> exercised from any current data, mock or live.** Deduction correctness is therefore unprovable by the demo
> as it stands. Recommendation: give one variant a second batch when step 3 lands, so the path is testable
> rather than merely asserted. This does not block step 3 — the ordering rule is settled either way.

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
- [Stock Identifier and Location Hint Presentation](./decisions/10-stock-identifier-and-location-hint.md): **there is no SKU field anywhere in the backend** — the SKU column becomes a **Barcode** column fed by `VariantUom.barcode_qr`. Storage location becomes a **client-local hint persisted with `shared_preferences`**, keyed by variant id, explicitly not API data.
- [Product List Ownership in the Products Screen](./decisions/11-products-list-ownership.md): `ProductsViewmodel` becomes **view state only** (search, filters, paging, selection) and reads the list live from `InventoryViewmodel`; the duplicate list and the double mutation are deleted. Registering it in `main.dart` is **superseded** — it is screen-scoped, like `PosTransactionViewmodel`, which was never unwired.

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
