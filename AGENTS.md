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

- **Active branch:** `feature/backend-integration` — 37 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice
  order is **locked** (Cashier journey); six decisions remain open and resolve one per session, in the order
  listed on that map's frontier.
- **Last session:** `docs/sessions/2026-10-15-integration-map.md` — opened the integration map and locked the
  Cashier-journey slice order; corrected the atlas tally to 8 dead of 38 rows. Planning only; no app source
  changed. (Earlier the same day: `docs/sessions/2026-10-15-system-atlas-and-docs-consolidation.md` — atlas
  built, 5 obsolete root docs removed.)
- **Current state (verified):** the backend is feature-complete; the client consumes almost none of it.
  Of 10 feature modules only `auth` reaches the API. 38 screens scored: 3 live · 27 mock · 8 dead. See
  `docs/SYSTEM_ATLAS.md`.
- **Next step:** resolve `planning/api-integration/decisions/02-product-variant-client-model.md` — the
  product/variant model shape gates Phase 1. Do not write client code until the Phase 0 decisions are locked.
  The three constraints that shape them: `product.dart` reads 7 fields the backend never sends, only 6 of 8
  viewmodels are registered in `main.dart`, and every list response is a paginated envelope. A salvageable
  earlier attempt sits in commit `22c7c26` (`planning/02-lost-work-recovery.md`).
