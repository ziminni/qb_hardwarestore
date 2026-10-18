# planning/api-integration/MAP.md

**Slug:** `api-integration` · **Opened:** 2026-10-15
**Status:** 19 locked · **0 open** — the frontier was reopened on 2026-10-17 to clear two questions buried in closed decisions, and both are now resolved in those decisions. A later audit found one more deferred note in decision 09; it is now [Receivables Record Payment](./decisions/19-receivables-record-payment.md), so fog has no unrecorded items.**frontier, blocked and fog are ALL EMPTY.** The map is complete; the roadmap below is the hand-off. **Phase state lives in the phase table below, which is the single home for it** — per-row, with evidence. Phase 5 was unlocked by [Requisition UI Ownership (POS side vs CPMS side)](./decisions/09-requisition-ui-ownership.md), resolved 2026-10-17. Phase 0's 7 rows
are built and were verified row-by-row against the code (the "Phase 0 — status" table below is the authority; it
has been wrong twice in opposite directions, so it is stated with per-row evidence); Phase 1's products catalogue
renders live API data (commits `6070442`…`557dfd3`); Phase 2 made the server the authority for inventory state
(commits `938547e`…`794e83a`), which required the backend changes the old "client-side only" invariant forbade — see
that row's correction. [POS Checkout Client Contract](./decisions/06-checkout-client-contract.md) was resolved
2026-10-16, so **Phase 3 is ready to build**. The two open decisions gate Phases 5 and 6.

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
| **Client-side epic only** | ⚠️ **SUPERSEDED TWICE — read this before trusting it.** **Phase 6 supersedes the endpoint/model half entirely:** resolving [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) on 2026-10-17 ruled that quotations and orders get REAL backend models, serializers, endpoints and migrations, so Phase 6 adds what this row forbade. **PARTLY SUPERSEDED IN PHASE 2.** The backend *was* feature-complete for Phases 0-1, but Phase 2 needed two backend changes and they are done, not pending: `seed_demo` now generates the alerts and adjustments both screens read (the endpoints were empty and nothing wrote a `SystemAlert`), and the adjustments write path was broken — a 400 from a serializer that demanded a `user` it then overwrote, and a 500 plus a partial write from `select_for_update` outside a transaction. Still true and still binding: **no NEW endpoints, and no model or migration changes.** If a task appears to need either, re-read `docs/SYSTEM_ATLAS.md` §3 before changing anything. |
| **Every list is paginated** | `{count, next, previous, results}` with `PAGE_SIZE = 50`. Read `.results`. Contract: `ENDPOINTS.md` §1. |
| **One data path, no new shapes** | `View → ViewModel → Repository → Service → ApiClient`. The only correct example is `features/auth/viewmodels/auth_viewmodel.dart`; `sales_module_viewmodel.dart` is the mock shape being replaced. |
| **Demo data comes from `seed_demo`** | Products with stock batches, customers, completed sales, an unpaid utang, and an APPROVED requisition with a minted token. Setup: `README.md`. |
| **Every wired screen needs three states** | loading, error, empty. Every list today is synchronous and has none. |
| **`flutter analyze` must stay clean** | It **is** clean today, over the whole tree (verified 2026-10-16: "No issues found!"). `flutter/test/widget_test.dart` is no longer the untracked broken counter template this row used to describe — it is **tracked** and is a real smoke test that imports `app.dart` (not `main.dart`), supplies the required `auth` argument, and asserts an unauthenticated launch lands on `LoginPage`. See `planning/04-cleanup.md`. |
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
- [Phase 1 Live Data Home and Mock Retention](./decisions/12-phase-1-live-data-home.md): Phase 1 loads `GET /api/v1/products/` + `GET /api/v1/batches/` into **`InventoryViewmodel`**, which is the product list's only home — so the catalogue, inventory screens and POS catalogue all go live in one move with no consumer rewrites. `InventoryMockData` is **retained** for what the API cannot yet serve (movements, adjustments, tracking, suppliers), and the Add/Edit/Archive paths stay memory-only until their phase.
- [Inventory Data Authority for Phase 2](./decisions/13-inventory-data-authority.md): the **server is the single authority** for inventory state — the low-stock screen reads `GET /api/v1/alerts/` and the movements screen reads `GET /api/v1/adjustments/` (with adjustments POSTed, not invented locally). The client's `_movements` log is deleted, and the derived status column is aligned to the server's exact predicate (`<` with a `threshold > 0` guard) so the list and the alert screen cannot contradict each other. Requires **one backend change: `seed_demo` demo data** (2 below-threshold variants, ~5 adjustments), because both endpoints are empty and no seed command writes a `SystemAlert`. Built in `938547e`…`794e83a`.
- [POS Checkout Client Contract](./decisions/06-checkout-client-contract.md): the POST response **is** the finished transaction (nested items, payments and receipt), so the receipt screen needs no second fetch; the cart is keyed by the **real `VariantUom.id`** (`variant_id` in the payload is a misnomer, and the cart's synthesized `variant.id * 100 + index` would target the wrong unit); a walk-in sale still **sends the Walk-in Customer's id**, because the FK is not nullable; the cart is cleared **only** on a 201; insufficient stock becomes a **400 with a stable `INSUFFICIENT_STOCK` code** rather than today's 500 (one backend change, approved); and an underpaid sale stops at a **confirmation step** before submitting, since creating a debt is consequential and the receipt prints after the fact. **Built** in `102c121`…`1415664`; verified live against the running server.
- [Customer Master-Data Scope (POS side)](./decisions/14-customer-master-data-scope.md): the POS **selects AND creates** customers mid-sale on a **minimal record (name + type)** — no backend permission change is needed, because `CustomerViewSet` inherits `IsPOSOrReadOnly`, so a Cashier may already POST. **A walk-in is not a customer record**: anonymous sales reuse the seeded `Walk-in Customer` and **cannot go into utang**, because an anonymous walker is not collectable — the live database already carries **₱4,900 booked against Walk-in**, which is that old behaviour's consequence. If a walker wants to owe, the cashier names them on the spot. Utang (balance, aging, a **credit-limit warning that is advisory, never a hard block**) is shown in a **customer detail panel at the till**. `sales_customers_page.dart` is **deleted** and `sales_receivables_page.dart` **wired** to `/ledgers/`. Requires fixing **three real backend defects** — `Customer` has no `full_name` (one wrong assumption copied from `User`), which **500s `/ledgers/aging/`** and silently returns `customer_name: null` on every ledger row.
- [Product Images](./decisions/18-product-images.md): leave `image_url` blank — the placeholder widget already exists, and a remote URL fails offline where a placeholder does not.
- [Receiving Stock Through the UI](./decisions/17-receiving-ui.md): BUILD the receiving screen (PO -> receipt -> process -> FIFO batches). The only scope decision needing NO backend work; the inventory sidebar goes 11 -> 12 entries.
- [The Reports Surface](./decisions/16-reports-surface.md): ONE admin/manager Reports screen over the four `/reports/*` endpoints; the sales and inventory report screens are deleted, because `/reports/*` is `IsManagerRole` and those two roles are refused.
- [Customer Returns](./decisions/15-customer-returns.md): a customer return is a `SalesTransaction` with `source='RETURN'` and NEGATIVE amounts plus an optional `original_transaction` FK; restock into the original batch when linked, else the newest active one. The reports need NO change because they already sum transactions and a negative one nets out.
- [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md): **quotations and orders get REAL backend models** — the sales role ships all seven screens, and Phase 6 becomes a BACKEND phase (see its own cost note; the invariant below is superseded for it).
- [Requisition UI Ownership (POS side vs CPMS side)](./decisions/09-requisition-ui-ownership.md): POS builds the DOWNSTREAM half — approve, reject, verify token, release materials; CPMS owns create and submit. A release is a SALE (`source=REQUISITION`, FIFO stock), and every approve/verify surface must show where the requisition came from, since POS did not originate it.
- [Receivables Record Payment](./decisions/19-receivables-record-payment.md): BUILD Record payment for Cashier+ — `POST /api/v1/ledger-payments/` already permits Cashier writes, so the disabled button’s Admin-only comment is stale; this is the write half of the read-live receivables screen, owned by Phase 6C.

## Phase order (locked 2026-10-15 — from [First Vertical Slice & Ordering Lens](./decisions/01-first-vertical-slice.md))

The route. Decision 01 holds the full reasoning; this table is the **index of it**, so a session can answer
"what is next" without re-surveying the plan. Every phase names its ticket — a locked decision, an open one, or
an explicit Fog entry. **No phase may be a gap**: Phase 4 was one until 2026-10-16, named only in decision 01's
phase table and tracked in neither the frontier nor the fog.

| Phase | Scope | State | Ticket |
| :--- | :--- | :--- | :--- |
| 0 | Substrate (model, transport, presentation, routing, cleanup) | ✅ **done** | The 8 Phase 0 decisions; see the status table above |
| 1 | Products module (the `ProductVariant` hub) | ✅ **done** | [Phase 1 Live Data Home and Mock Retention](./decisions/12-phase-1-live-data-home.md) — locked; built in `6070442`…`557dfd3` |
| 2 | Inventory: stock list, low stock, movements | ✅ **done** | [Inventory Data Authority for Phase 2](./decisions/13-inventory-data-authority.md) — locked; built in `938547e`…`794e83a` |
| 3 | POS checkout + receipt (the money path) | ✅ **done** | [POS Checkout Client Contract](./decisions/06-checkout-client-contract.md) — resolved 2026-10-16; built in `102c121`…`1415664` |
| 4 | Customers master data (the `Customer` hub) | ✅ **done** (8 of 8 tasks) | [Customer Master-Data Scope (POS side)](./decisions/14-customer-master-data-scope.md) — **decision** resolved 2026-10-16; Task 1 (the three `full_name` defects) built in `df908a9` |
| 5 | Requisitions + material-token release | ✅ **done** (transport, approve/reject queue and the routed release counter; reviewed (Critical none, 3 Important fixed) and verified LIVE) | [Requisition UI Ownership (POS side vs CPMS side)](./decisions/09-requisition-ui-ownership.md) — **locked** 2026-10-17 |
| 6 | Admin, reports, sales | ❓ **gated** | [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) — open |

**Phases 0, 1 and 2 are complete.** Phase 2 was built in `938547e`…`794e83a` and finished with the live
end-to-end pass that earned its keep: POSTing the Flutter client's real request body to the running server found
**two defects that reading and widget tests had both missed** — an HTTP 400 (the serializer demanded a `user` it
then overwrote with `request.user`) and an HTTP 500 plus a **partial write** (`allocate_fifo` used
`select_for_update` outside a transaction, so the adjustment row committed while the stock never moved). Both are
fixed. Everything from Phase 3 up waits on a frontier decision.

**Phases 0-3 are complete.** Phase 3 was built in `102c121`…`1415664`: the POS now completes a real sale against
`POST /api/v1/transactions/`. Resolving decision 06 also **sharpened the Phase 4 question**, which has graduated
out of the fog into the frontier below (checkout cannot run without a customer, so "which slice of customer CRUD
the POS needs" is now stateable). The one remaining decision gates Phase 6.

## Active Frontier (Open & Unblocked)

**EMPTY.** The two reopened items were resolved on 2026-10-17 and written back into the decisions that deferred
them: [Customer Returns](./decisions/15-customer-returns.md) now rules the two returns pages consolidate
into ONE under Sales, and [The Reports Surface](./decisions/16-reports-surface.md) rules four tabs, one
report each. **A closed decision's note is not a record** — that lesson is why they were found at all. No open frontier items remain.


Ordered by the locked phase order: define the entity, then the transport, then the presentation. Resolve one
per session. Phases 0-3 have their tickets and **Phase 4's and Phase 5's are now resolved too**; the one item below gates
Phase 6.


## Blocked

Nothing is blocked. [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) was released
when the slice order locked and is now simply sequenced at Phase 6.

## Fog of War (Not Yet Specified)

**EMPTY of UNRECORDED items as of 2026-10-18** — but read this carefully. Every in-scope area is either
a locked decision, an explicit Out of Scope entry, or built. **Two questions that were deferred inside
closed decision files were found by an audit on 2026-10-17 and moved to the Active Frontier**, because a
note inside a closed decision is not a record — it is a note nothing enforces. The last two items graduated here:
[Receiving Stock Through the UI](./decisions/17-receiving-ui.md) (build it — no backend needed) and
[Product Images](./decisions/18-product-images.md) (leave blank; the placeholder is honest). Two earlier
items were removed because they described **completed** work, which a list of unknowns must not do.
One minor polish item is recorded here so no note hides in a closed file: the approve-queue
project filter ([Requisition UI Ownership](./decisions/09-requisition-ui-ownership.md), "Not decided
here") is undecided UI only — the service already follows pages. Too small to gate anything, so it
stays fog, not frontier. A later audit found a third such note — decision 09’s receivables payment-posting UI — and it was resolved the same turn as [Receivables Record Payment](./decisions/19-receivables-record-payment.md), so it never became an open frontier item.

## Out of Scope

Ruled past the destination. Do not reopen without a new map.

- CPMS / cross-system integration.
- Production hardening: env-based secrets, `settings.py` split, tightening `ALLOWED_HOSTS` and CORS.
- An API-backed Settings page — agreed deferral, and it has no backend contract.
- New backend endpoints or schema changes.

---

# Final Implementation Roadmap (Phase 6)

The map is complete: **19 decisions locked, 0 open, nothing blocked, fog empty.** This is the hand-off —
what remains to be BUILT, in order, with the evidence each step must produce.

**Phase 6 is a BACKEND-FIRST phase.** It was described as "Admin, reports, sales" — a UI phase — and
three decisions changed that. The old invariant ("no new endpoints, no model or migration changes") is
superseded in three places, and Phase 6 is materially larger than the map implied when it opened.

## 6A — Backend (must come first: the screens cannot be wired to endpoints that do not exist)

| # | Work | Decisions | Ends when |
| :--- | :--- | :--- | :--- |
| 6A.1 | `Quotation` + `QuotationItem`, serializer, viewset, `/api/v1/quotations/*`, migration | [Sales Stack Reconciliation](./decisions/05-sales-stack-reconciliation.md) | a quotation can be created and read back over HTTP |
| 6A.2 | `SalesOrder` + `SalesOrderItem`, serializer, viewset, `/api/v1/sales-orders/*`, migration | Sales Stack Reconciliation | an order can be created and read back over HTTP |
| 6A.3 | `SalesTransaction.source` gains `RETURN`; a nullable `original_transaction` FK (PROTECT); migration | [Customer Returns](./decisions/15-customer-returns.md) | a return posts negative amounts and restocks the right batch |
| 6A.4 | The restock rule: original batch when the FK is set, else the **newest active** batch | Customer Returns | both branches have a test each |

**Verification for 6A:** `manage.py test` green, `manage.py check` clean, and a live HTTP probe per
endpoint — the same discipline Phases 0–5 used. **Two migrations minimum.**

## 6B — Screens on endpoints that already exist (no backend work)

| # | Work | Decisions | Ends when |
| :--- | :--- | :--- | :--- |
| 6B.1 | ONE Reports screen (admin/manager) over the four `/reports/*` endpoints; delete `sales_reports_page.dart` and `inventory_reports_page.dart` + their routes and sidebar entries | [The Reports Surface](./decisions/16-reports-surface.md) | the screen renders live data; the two deleted routes are gone |
| 6B.2 | Receiving screen: PO → goods receipt → process → FIFO batches. Inventory sidebar 11 → **12** entries | [Receiving Stock Through the UI](./decisions/17-receiving-ui.md) | stock can ENTER through the UI, not only via `seed_demo` |

**6B.2 carries a known trap:** inserting a sidebar entry moves the index of every inventory page after
it. `sidebar_index_consistency_test.dart` exists for exactly that regression and has already caught it
once — run it first, not last.

## 6C — Wire the surviving sales screens

Dashboard · transactions · receivables (read-live; plus [Receivables Record Payment](./decisions/19-receivables-record-payment.md)’s Record-payment write) · reports. The quotations and orders screens are
wired in 6A.1/6A.2, and `sales_module_viewmodel.dart` + `models/sales_module.dart` are the **canonical**
stack for them.

## 6D — Owed from earlier phases, not part of Phase 6

1. **A live end-to-end pass with `flutter run` against the live backend.** Every contract in Phases 0–5
   is probed over HTTP; **the pixels are unverified**, and that is the last honest gap. It should start
   by exercising the `#21` underpayment path, which is verified against a **stub**, not the server.
2. **The branch is unpushed** (178+ commits). Pushing is a shared-branch side effect and needs a
   decision, not a default.

## The scope warning, kept here on purpose

Four decisions in one session each answered "build it properly": quotations and orders got a backend,
returns got a migration, receiving got a screen, and reports got two screens deleted. Only the images
decision was a "don't build". **Phase 6 is now the largest phase in the epic**, and it is the one to
sanity-check against the deadline before 6A starts — because 6A.1 and 6A.2 are the first backend models
this project has added since the epic began.
