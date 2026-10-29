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
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → active map: `planning/audit-remediation/MAP.md` |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (6 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports}/` |
| Flutter MVVM client (10 features) | `flutter/lib/features/` — shared models in `flutter/lib/data/models/` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |
| Route table (single source of navigation) | `flutter/lib/routes/routes.dart` |

Every pointer above must resolve. A pointer to a file that does not exist is a bug — fix or remove it in
the same commit that breaks it.

## Current Status & Next Step

- **Active branch:** `feature/backend-integration` — **pushed, in sync with `origin/`.** For how far ahead
  of `origin/master` it is run `git rev-list --count origin/master..HEAD`; a count written here stales on
  the next commit.
- **Active Wayfinder map: `planning/audit-remediation/MAP.md`** — audit gap remediation, 17 decisions locked, **all 6 phases BUILT** (Phase 6 Barcode labels & scanning closed 2026-10-29). Prior maps (cashier, stocker, sales-manager, admin) complete.
- **Phase state is NOT stated here** — it is owned by the phase table in the active map, per-row and with
  evidence. Read that table; a copy here would be a second home, and this file's own rule forbids one.
- **Seed reclassification: BUILT 2026-10-20** (commit `5f1c52a`). The underpaid demo sale now
  posts to Maria Santos; Walk-in OPEN ledgers are zero.
- **Inventory dashboard: BUILT 2026-10-20** (`cff80c1` + ranked-queue fix `9e18505`; 4 dashboard
  tests green). The stocker's home screen reads the live viewmodel with urgency ranking + overflow
  signal.
- **Mock-purge: BUILT 2026-10-20.** Admin Overview reads live sales/stock/alerts
  (`7b47db3` + false-zero fix `2d7171d`); user management reads live staff/search/filters/create
  (`9e15cd2` + fix pass `89ffb56`); orphan `pos_dashboard`/`sales_dashboard` views, their content
  widgets, `dashboard_mock_data.dart`, and the 7 orphaned pos/sales atomic widgets are deleted
  (zero consumers). The mock-purge epic is complete.
- **THE INVARIANT IS SUPERSEDED.** The old "no new endpoints, no model or migration changes" rule is
  not binding; audit-remediation phases add backend work deliberately (Phase 6 adds a `VariantUOM`
  constraint + backfill migration and a `?barcode=` filter).
- **Last session:** `docs/sessions/2026-10-29-audit-remediation-phase-6.md` — Phase 6 barcodes built + fix pass + browser re-check. **Gate:** backend **497/497** (`docker exec buildpro_backend python manage.py test`), flutter **839/839**, analyze clean.
  **Next:** `git push` (user); first real thermal print at 100% / actual size (hardware, user); optional SYSTEM_ATLAS refresh; reseed dev DB for a clean demo.
- **The standard this project now holds:** a test is not accepted as covering a fix until it has been run
  against the code **without** the fix and seen to fail — and a mutation or a test that breaks
  **compilation/errors** proves nothing. **A claim not followed by its command output in the same message
  is unverified.**
- **Standing caveat:** `flutter run -d linux` is now used by the user against the live backend (it
  surfaced the admin chart crash 2026-10-28); agent-side verification is still HTTP probes + widget
  tests + headless web E2E, so desktop pixels are user-verified only.
- **`.superpowers/` is gitignored**, so the execution ledger's 82 ruled entries live only on this machine
  — which is why the plan workspace was NOT deleted.
