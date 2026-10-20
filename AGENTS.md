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
  frontier and blocked empty, fog holding 3 owned deferrals, and the **Phase 6 roadmap** is written at its end.
- **Phase state is NOT stated here** — it is owned by the phase table in the active map, per-row and with
  evidence. Read that table; a copy here would be a second home, and this file's own rule forbids one.
- **Phase 6 is built (branch unpushed).** 6A.1–6A.4, 6B (reports + receiving), 6C (live sales
  screens + review fix pass), decision 19 (receivables Record payment), the seed reclassification,
  and the 6D live end-to-end pass (boot hang + till mock catalogue fixed live, #21 verified against
  the server, all Phase 6 screens proven live) are done. **Next: push decision**, then the
  mock-purge follow-up below.
- **Seed reclassification: BUILT 2026-10-20** (commit `5f1c52a`). The underpaid demo sale now
  posts to Maria Santos; Walk-in OPEN ledgers are zero.
- **Inventory dashboard: BUILT 2026-10-2x** (`cff80c1` + ranked-queue fix `9e18505`; 4 dashboard
  tests green). The stocker's home screen reads the live viewmodel with urgency ranking + overflow
  signal.
- **Pending mock-purge build (surfaced across the 6D/dashboard passes, not yet built):** Admin
  Overview (`admin_dashboard.dart`: metrics, quick actions, recent activity, alerts — all
  `DashboardMockData`), plus dead-code deletion (orphan `pos_dashboard`/`sales_dashboard` views and
  their content widgets, referenced by nothing). Same established pattern: viewmodel-first,
  load on open, banner + retry, RED-first tests.
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
