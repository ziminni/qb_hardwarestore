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

- **Active branch:** `feature/backend-integration` — **145 commits ahead of `origin/master`, unpushed.**
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice order is
  **locked** (Cashier journey) and the map reads **13 locked · 1 open** — 14 decision files: 13 settled, and only
  [Sales Stack Reconciliation](./planning/api-integration/decisions/05-sales-stack-reconciliation.md) open (Phase 6).
  *This block was wrong in FIVE separate ways until 2026-10-17 — it claimed 114 commits (144), 33 backend tests
  (46), 192 flutter tests (235), "Phases 0-3 COMPLETE, Phase 4 unlocked" (Phase 4 is done and reviewed), and named
  Phase 3 as the last session, because Phase 4 had no note at all. It was rewritten from the gate output rather
  than adjusted: a wrong index is worse than a missing one, because a missing one reads as unknown while a wrong
  one reads as verified.*
- **Phases 0, 1, 2, 3 and 4 are COMPLETE.** Phase 0's 7 rows are built (the map's "Phase 0 — status" table is the
  authority); Phase 1's products catalogue renders live API data; Phase 2 made the **server the authority for
  inventory state**; Phase 3 made the POS **complete a real sale**; Phase 4 built **customer master data** — the
  till selects and creates customers, a walk-in **cannot** go into utang, utang is shown at the counter, and
  `sales_receivables_page.dart` reads the real ledger.
- **Phase 5 is UNLOCKED and ready to build:**
  [Requisition UI Ownership](./planning/api-integration/decisions/09-requisition-ui-ownership.md) resolved
  2026-10-17 — POS builds the **downstream half** (approve · reject · verify token · release) and CPMS owns create
  and submit. Two screens: an approve/reject queue for the Store Manager, and verify+release for the Cashier. A
  release is a **sale** (`source=REQUISITION`, FIFO stock through the same allocator the checkout uses), and every
  approve/verify surface must show where the requisition came from, because POS did not originate it.
- **Last session:** `docs/sessions/2026-10-17-phase-4-customer-master-data.md` — built Phase 4, then had it
  reviewed and acted on the review. **Verified fresh:** `manage.py test` **46 OK**, `manage.py check` 0 issues,
  `flutter analyze` clean, `flutter test` **235/235**, tree CLEAN, Atlas score **8 live · 3 partial · 18 mock ·
  8 dead (37 rows)** recounted and asserted in BOTH artifacts.
- **The standard this session established:** a test is not accepted as covering a fix until it has been run
  against the code **without** the fix and seen to fail. Three tests were found that **could not fail** —
  including two payment tests that performed the balance arithmetic themselves, which is how a real money bug
  survived in the ledger for the life of the project.
- **Recorded debt (not a blocker):** the Phase 4 **screens** have no widget tests — `SalesReceivablesViewmodel`,
  `SalesReceivablesPage`, `LedgerRepository`, `PosCustomerPickerDialog`, `PosUtangPanel`, `PosTransactionPage._pay`
  (which holds the entire "submit nothing" invariant), and `selectedNavigationIndex` on any page, whose absence
  let a sidebar regression reach a commit.
- **Standing caveat:** `flutter run` has **never** been executed against the live backend. API contracts are
  probed; the pixels are unverified.
