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

- **Active branch:** `feature/backend-integration` — 66 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice
  order is **locked** (Cashier journey) and the map reads **7 locked · 3 open**. **Phase 0 is complete in code
  as well as in decisions**: the staged `ProductVariant` swap finished all four steps, so the client model now
  mirrors the API exactly. Three decisions remain open, gating Phases 3, 5 and 6.
- **Last session:** `docs/sessions/2026-10-16-staged-model-swap-complete.md` — **finished the staged model swap**
  (deleted `sku`, `qrIdentifier`, `costPrice`, `sellingPrice`, `currentStock`, `storageLocation` and the
  `reorderLevel` getter), migrated all 16 readers onto batch stock, and took it through a fresh-context review.
  Tests 0-runnable → **65**. Earlier: `docs/sessions/2026-10-16-staged-swap-blockers-and-location-store.md`
  locked decision 10; `docs/sessions/2026-10-16-phase-0-decisions.md` locked the six Phase 0 decisions;
  `docs/sessions/2026-10-15-integration-map.md` opened the map.
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. 38 screens scored: 3 live · 27 mock · 8 dead. See
  `docs/SYSTEM_ATLAS.md`.
- **Next step:** **Phase 1** — wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`.
  No further design input is needed: `ApiClient.getList<T>` returning `Paged<T>`, `core/widgets/async_view.dart`
  (decision 07) and `assembleCatalogue` are all specified and locked, and the model layer they build on now
  exists. Note `ProductsViewmodel` and `PosTransactionViewmodel` are still **not registered** in `main.dart`.
  A salvageable earlier attempt at products/batches wiring sits in commit `22c7c26`
  (`planning/02-lost-work-recovery.md`).
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. 38 screens scored: 3 live · 27 mock · 8 dead. See
  `docs/SYSTEM_ATLAS.md`.
- **Next step:** **Phase 1** — wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`.
  Everything it needs now exists and is locked: `ApiClient.getList<T>` returning `Paged<T>`,
  `core/widgets/async_view.dart` (decision 07), and `assembleCatalogue`. Note `ProductsViewmodel` and
  `PosTransactionViewmodel` are still **not registered** in `main.dart`. A salvageable earlier attempt at
  products/batches wiring sits in commit `22c7c26` (`planning/02-lost-work-recovery.md`).
- **Open backend issue (found during review):** `apps/inventory/services.py::apply_stock_adjustment` silently
  discards a positive adjustment when no batch has `current_qty > 0`, so a count correction on a depleted
  variant is lost with no error. Out of scope for the client-only map; needs a backend issue.
