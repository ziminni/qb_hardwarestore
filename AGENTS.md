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

- **Active branch:** `feature/backend-integration` — 79 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice
  order is **locked** (Cashier journey) and the map reads **8 locked · 3 open**. **Phase 0 is COMPLETE** — all 7
  of its rows are built, and the map's "Phase 0 — status" table is the authority. It has been wrong twice in
  opposite directions, so it is stated with per-row evidence and was re-verified against the CODE, not against
  the ledger. The map now carries the **7-phase route** with each phase's ticket attached, so "what is next" is
  answerable from the index alone: **Phases 1 and 2 need no new decisions and can be built now**, while Phases
  3, 5 and 6 wait on the three open decisions.
- **Last session:** `docs/sessions/2026-10-16-phase-0-complete.md` — built the five remaining Phase 0 rows
  (transport: `Paged<T>` + the pure `parsePaged` + `ApiClient.getList<T>`; `AsyncView`; the unsupported-role
  screen plus a pure `redirectFor`; `ProductsViewmodel` reduced to view state; Registration dissolved by
  decision 11), then took the work through a fresh-context review that falsified `Paged.hasMore` and found the
  sign-out path untested — both fixed. Tests **65 → 131**; `flutter analyze` clean. Earlier:
  `docs/sessions/2026-10-16-staged-model-swap-complete.md` finished the staged model swap;
  `docs/sessions/2026-10-16-staged-swap-blockers-and-location-store.md` locked decision 10;
  `docs/sessions/2026-10-16-phase-0-decisions.md` locked the six Phase 0 decisions;
  `docs/sessions/2026-10-15-integration-map.md` opened the map.
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. 38 screens scored: 3 live · 27 mock · 8 dead. See
  `docs/SYSTEM_ATLAS.md`.
- **Next step:** **Phase 1** — wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`.
  Everything it needs now exists and is locked: `ApiClient.getList<T>` returning `Paged<T>`,
  `core/widgets/async_view.dart` (decision 07), and `assembleCatalogue`. Neither `ProductsViewmodel` nor
  `PosTransactionViewmodel` belongs in `main.dart` — decision 11 makes them screen-scoped view state, like the
  POS screen's existing pattern. A salvageable earlier attempt at products/batches wiring sits in commit
  `22c7c26` (`planning/02-lost-work-recovery.md`).
- **Open backend issue (found during review):** `apps/inventory/services.py::apply_stock_adjustment` silently
  discards a positive adjustment when no batch has `current_qty > 0`, so a count correction on a depleted
  variant is lost with no error. Out of scope for the client-only map; needs a backend issue.
