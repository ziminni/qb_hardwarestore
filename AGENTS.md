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

- **Active branch:** `feature/backend-integration` — 51 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice
  order is **locked** (Cashier journey) and the map reads **7 locked · 3 open**. Phase 0's *decisions* are
  locked but its *code* is mid-flight: the staged `ProductVariant` swap is at step 2 of 4 — steps 1 and 2 are
  committed, step 3 is unblocked by decision 10, step 4 pends. Three decisions remain open, gating Phases 3, 5
  and 6.
- **Last session:** `docs/sessions/2026-10-16-staged-swap-blockers-and-location-store.md` — unblocked ruling
  R9 by locking decision 10 (the SKU column becomes a **Barcode** column, because **no SKU field exists in the
  backend**; storage location becomes a **persisted client-local hint**) and delivered `LocationHintStore`.
  Earlier: `docs/sessions/2026-10-16-phase-0-decisions.md` locked all six Phase 0 decisions;
  `docs/sessions/2026-10-15-integration-map.md` opened the map.
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. 38 screens scored: 3 live · 27 mock · 8 dead. See
  `docs/SYSTEM_ATLAS.md`.
- **Next step:** finish **staged-swap step 3** — migrate the 13 reader-only files onto `CatalogueItem`,
  relaying the Barcode column into the 4 inventory tables and wiring `LocationHintStore` into the 3 location
  sites. The crux is `InventoryViewmodel`, a mutable mock store whose `adjustStock`/`sellStock` mutate
  `variant.currentStock` and must move onto batches instead. Then **step 4** deletes `sku`, `storageLocation`,
  `costPrice`, `sellingPrice`, `currentStock` and the `reorderLevel` getter. Only then does **Phase 1**
  (products catalogue → `GET /api/v1/products/` + `GET /api/v1/batches/`) begin — no further design input is
  needed for it: `ApiClient.getList<T>` returning `Paged<T>`, `core/widgets/async_view.dart`, and
  `assembleCatalogue` are all specified and locked. A salvageable earlier attempt at products/batches wiring
  sits in commit `22c7c26` (`planning/02-lost-work-recovery.md`).
