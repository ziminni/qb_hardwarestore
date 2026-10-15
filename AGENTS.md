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
| Unbuilt work, decisions, roadmap | `planning/` — read `planning/MAP.md` first |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (6 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports}/` |
| Flutter MVVM client (10 features) | `flutter/lib/features/` — shared models in `flutter/lib/data/models/` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |
| Route table (single source of navigation) | `flutter/lib/routes/routes.dart` |

Every pointer above must resolve. A pointer to a file that does not exist is a bug — fix or remove it in
the same commit that breaks it.

## Current Status & Next Step

- **Active branch:** `feature/backend-integration` — 33 commits ahead of `origin/master`, unpushed.
- **Last session:** `docs/sessions/2026-10-15-system-atlas-and-docs-consolidation.md` — built the system atlas
  and consolidated the docs (removed 5 obsolete root files). Documentation only; no app source changed.
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. See the Truth Matrix in `docs/SYSTEM_ATLAS.md`.
- **Next step:** before writing any API call — (1) fix `flutter/lib/data/models/product.dart`, which reads 7
  fields the backend never sends; (2) register `ProductsViewmodel` and `PosTransactionViewmodel` in
  `flutter/lib/main.dart`, since only 6 of 8 viewmodels are wired; (3) read the paginated envelope
  (`response.data['results']`, not `response.data`). Then wire `products` → `inventory` per
  `planning/01-api-integration.md`. A salvageable earlier attempt sits in commit `22c7c26`
  (`planning/02-lost-work-recovery.md`).
