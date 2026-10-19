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

- **Active branch:** `feature/backend-integration`, **unpushed.** For how far ahead it is run
  `git rev-list --count origin/master..HEAD` — a count written into this file is stale the moment the
  commit that writes it lands.
- **The Wayfinder map is COMPLETE.** `planning/api-integration/MAP.md` reads **20 locked · 0 open**,
  frontier and blocked empty, fog holding 4 owned deferrals, and the **Phase 6 roadmap** is written at its end.
- **Phase state is NOT stated here** — it is owned by the phase table in the active map, per-row and with
  evidence. Read that table; a copy here would be a second home, and this file's own rule forbids one.
- **Phase 6 is mid-build.** 6A.1 (Quotation), 6A.2 (SalesOrder), 6A.3 (return shape + migration 0004) and
  decision 19 (receivables Record payment for Cashier+, service + viewmodel + page) are built.
  **Next: 6D — the live run pass**, plus the pending seed-data build below. 6A.4 (restock rule),
  6B (reports + receiving) and 6C (live sales screens + review fix pass) are built.
- **Pending seed-data build (wayfinder-resolved 2026-10-19, not yet built):** the underpaid demo
  sale in `seed_demo.py` posts to Walk-in Customer; reclassify it to Maria Santos and reseed (see
  [Customer Master-Data Scope](./planning/api-integration/decisions/14-customer-master-data-scope.md),
  "Deliberately not covered"). Demo-only, no app code.
- **THE INVARIANT IS SUPERSEDED.** "No new endpoints, no model or migration changes" held exactly across
  the whole branch and Phase 6 breaks it deliberately — three decisions added backend work. The map's
  Notes & Invariants says so; do not treat the old rule as binding.
- **Last session:** `docs/sessions/2026-10-17-wayfinder-complete-and-phase-6-start.md` — completed the
  map (five decisions), wrote the Phase 6 roadmap, and built 6A.1. **Verified fresh at `6dee5c0`:**
  backend **52/52 OK**, `manage.py check` clean, `flutter analyze` clean, flutter **314/314**, tree CLEAN,
  and `GET /api/v1/quotations/` answering **200**.
- **The standard this project now holds:** a test is not accepted as covering a fix until it has been run
  against the code **without** the fix and seen to fail — and a mutation or a test that breaks
  **compilation/errors** proves nothing. **A claim not followed by its command output in the same message
  is unverified.**
- **Standing caveat:** `flutter run` has **never** been executed against the live backend. Contracts are
  probed over HTTP; the pixels are unverified.
- **`.superpowers/` is gitignored**, so the execution ledger's 82 ruled entries live only on this machine
  — which is why the plan workspace was NOT deleted.
