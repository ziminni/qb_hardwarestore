# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** A fact lives in exactly one file and is linked from everywhere else.
Do not duplicate schemas, endpoint lists or status tables here — follow the pointers below instead of
grepping the codebase, and never paste a copy of a fact that already has a home.

## Where Everything Lives

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| System architecture & Live/Mock matrix | `docs/SYSTEM_ATLAS.md` |
| Interactive architecture cockpit | `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → active map: `planning/api-integration/MAP.md` |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (6 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports}/` |
| Flutter MVVM client (10 features) | `flutter/lib/features/` — shared models in `flutter/lib/data/models/` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |
| Route table (single source of navigation) | `flutter/lib/routes/routes.dart` |

Every pointer above must resolve. A pointer to a file that does not exist is a bug — fix or remove it in
the same commit that breaks it.

## Current Status & Next Step

- **Active branch:** `feature/backend-integration` — 101 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice
  order is **locked** (Cashier journey) and the map reads **11 locked · 2 open**. **Phases 0, 1 and 2 are COMPLETE
  and Phase 3 is unlocked** — Phase 0's 7 rows are built (the map's "Phase 0 — status" table is the authority, and
  it was re-verified against the CODE after being wrong twice in opposite directions), Phase 1's products catalogue
  renders live API data, Phase 2 made the **server the authority for inventory state**, and
  [decision 06](./planning/api-integration/decisions/06-checkout-client-contract.md) resolved 2026-10-16 to unlock
  **Phase 3**. The map carries the **7-phase route** with each phase's ticket attached, so "what is next" is
  answerable from the index alone. Resolving decision 06 also **graduated the Phase 4 question out of the Fog of
  War** into a real frontier item ([decision 14](./planning/api-integration/decisions/14-customer-master-data-scope.md));
  Phases 5 and 6 wait on the other two.
- **Last session:** `docs/sessions/2026-10-16-phase-2-inventory-authority.md` — **built Phase 2**: the server now
  owns inventory state. The low-stock screen reads `/api/v1/alerts/`, the movements screen reads
  `/api/v1/adjustments/`, and the adjust dialog POSTs rather than mutating local batches. Decision 13 was locked
  first. 190 lines of invented fixture-seeding were deleted. **The live end-to-end pass found two production
  defects that reading and widget tests had both missed** — an HTTP 400 (the serializer demanded a `user` it then
  overwrote with `request.user`) and an HTTP 500 with a **partial write** (`allocate_fifo` used
  `select_for_update` outside a transaction, so the adjustment row committed while the stock never moved).
  **161 tests pass; `flutter analyze` is clean; `manage.py check` reports 0 issues.** Verified fresh in the
  closing message: analyze clean, **161/161**, tree clean, **101** commits ahead. Two backend changes went past
  decision 13's "seed_demo only" scope and both are recorded: `user` is read-only on the adjustment serializer,
  and `perform_create` is atomic. **`docs/SYSTEM_ATLAS.md` was refreshed for the two rows Phase 2 changed** (their
  grades did not move, so the tally is unchanged). Earlier: `docs/sessions/2026-10-16-map-repair-and-tracker-reconciliation.md` repaired the map's
  route in the index and reconciled the task tracker; `docs/sessions/2026-10-16-phase-0-complete.md` built the
  five remaining Phase 0 rows and had `Paged.hasMore` falsified by review;
  `docs/sessions/2026-10-16-staged-model-swap-complete.md` finished the staged model swap;
  `docs/sessions/2026-10-16-staged-swap-blockers-and-location-store.md` locked decision 10;
  `docs/sessions/2026-10-16-phase-0-decisions.md` locked the six Phase 0 decisions;
  `docs/sessions/2026-10-15-integration-map.md` opened the map.
- **Current state (verified):** 38 screens scored **6 live · 4 partial · 20 mock · 8 dead** — see
  `docs/SYSTEM_ATLAS.md`, which is the authority. Phases 0–2 are built: auth, products, stock, low stock and stock
  movements all read the server.
- **Next step:** **Phase 3 — POS checkout (the money path).** Its ticket
  [decision 06](./planning/api-integration/decisions/06-checkout-client-contract.md) was **resolved 2026-10-16**, so
  the phase is ready to build with no new decisions. The contract is pinned in that file; the first task is a
  **correction, not a feature**: the cart synthesizes `variantUomId: record.variant.id * 100 + index`, but the API
  resolves that field as a real `VariantUOM` id, so cart lines must be keyed by `variant.sellingUoms[].id` or stock
  is deducted from the wrong unit. Two things were approved that go beyond client-side wiring: a **400 +
  `INSUFFICIENT_STOCK`** mapping for the failure path that currently returns a 500, and (already done in Phase 2)
  the adjustment serializer/view fixes. Also worth doing first: adopting `django-stubs` as a dev dependency
  (proven to let both type-checker rules stay on with zero suppressions).
- **Known unfixed, carried forward:** the products toolbar overflows — `A RenderFlex overflowed by 9.7 pixels on
  the right` from `products_toolbar.dart:113` and `products_catalog_overview.dart:156` — pre-existing, visible at
  ~1600px window widths, found while testing Phase 1 and deliberately not fixed (UI work outside that phase's
  scope). The products page's Add / Edit / Archive paths are **memory-only** until a later phase wires the writes
  (decision 12's accepted cost). And **`flutter run` against the live backend has still not been executed** — the
  API contract is verified by probing the server, and the wiring by widget tests, but not the running app.
- **Open backend issue (found during review):** `apps/inventory/services.py::apply_stock_adjustment` silently
  discards a positive adjustment when no batch has `current_qty > 0`, so a count correction on a depleted
  variant is lost with no error. Out of scope for the client-only map; needs a backend issue.
