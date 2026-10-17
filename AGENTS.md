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
  commit that writes it lands, which is how "114" survived four phases.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The
  slice order is **locked** (Cashier journey) and the map reads **13 locked · 1 open** — 14 decision
  files, with only
  [Sales Stack Reconciliation](./planning/api-integration/decisions/05-sales-stack-reconciliation.md)
  open (Phase 6).
- **Phases 0, 1, 2, 3 and 4 are COMPLETE.** Phase 4 (customer master data) shipped and was then
  reviewed; every Important finding was fixed, including a real money bug — `POST /ledger-payments/`
  never moved `balance_due` and accepted overpayment.
- **Phase 5 is IN PROGRESS (1 of 4).**
  [Requisition UI Ownership](./planning/api-integration/decisions/09-requisition-ui-ownership.md)
  resolved 2026-10-17: POS builds the **downstream half** (approve · reject · verify token · release)
  and CPMS owns create and submit. Task 1, the transport, is built with **no create or submit
  method at all** — a service without `createRequisition` cannot grow a button needing a Site
  Foreman. Next: the **approve/reject queue**, actions gated on status, showing where each
  requisition came from.
- **Last session:** `docs/sessions/2026-10-17-phase-5-and-coverage.md` — resolved decision 09, built
  Phase 5's transport, and paid down the Phase 4 test-coverage debt (flutter 235 → 291). **Verified
  fresh at `a9f74ec`:** backend **46/46 OK**, `manage.py check` clean, `flutter analyze` clean,
  flutter **291/291**, tree CLEAN, Atlas **8 live · 3 partial · 18 mock · 8 dead (37 rows)**.
- **THE DECISION WAITING FOR A HUMAN:** `#21` — `PosPaymentDialog` refuses any amount below the
  total, so `_pay`'s underpayment branch can never run. Decision 06 §4's confirmation, the whole
  three-way walk-in flow built as Phase 4 T6, and the server's `WALK_IN_CANNOT_OWE` path from the
  till are **all unreachable**. Either the validator is wrong or that UI is. It also decides the
  remaining test work.
- **The standard this project now holds:** a test is not accepted as covering a fix until it has been
  run against the code **without** the fix and seen to fail — and a mutation that breaks
  **compilation** proves nothing, because Flutter reports it as `loading <file>`.
- **Standing caveat:** `flutter run` has **never** been executed against the live backend. API
  contracts are probed; the pixels are unverified — which is why an undefended `SystemBrand` row
  took a widget test to find.
- **`.superpowers/` is gitignored**, so the execution ledger and its ~80 ruled entries live only on
  the machine that wrote them.
