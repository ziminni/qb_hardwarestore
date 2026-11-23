# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports, Docker & tunnel | `README.md` · `docs/SETUP.md` |
| Daily role operations & workflows | `docs/DAILY-OPERATIONS.md` · `docs/ROLE-FLOWS.md` |
| Profit, markup, FIFO COGS & discounts guide | `docs/PROFIT-AND-DISCOUNTS.md` |
| Remote Bodega Android APK & offline outbox | `docs/MOBILE-BODEGA.md` · `docs/offline-sync-design.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Active & completed plans / decisions | **Active Plan:** `planning/store-ops-round-2-plan.md` (All 3 phases complete); index: `planning/MAP.md` |
| QA how-to & three-client smoke test | `docs/testing/QA-PROFILE.md` · `docs/three-client-smoke-test.md` |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (8 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports,bodega,sms,integration}/` |
| Flutter MVVM client | `flutter/lib/features/` · models `flutter/lib/data/models/` · routes `flutter/lib/routes/routes.dart` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |

Every pointer must resolve; a broken pointer is fixed in the commit that breaks it.

## Test & lint

- Flutter: `cd flutter && flutter analyze && flutter test --concurrency=2` (8 GB RAM: keep concurrency 2; stop with `pkill -f "[f]lutter_tester"`).
- Backend (via Docker): `docker compose exec backend python manage.py test --noinput` · `docker compose exec backend python manage.py check` · `docker compose exec backend python manage.py makemigrations --check --dry-run`.

## Workflow

- Work directly in `/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system` on `master` (never create persistent worktrees under `temp/`).
- Build a phase with **`execute-phase`**; end a session with **`wrap-up`**.

## Current Status & Next Step

- **Branch:** `master` (synced with `origin/master`). All temporary worktrees and merged feature branches have been cleaned up.
- **Completed in Store Operations Rounds 1 & 2 (`planning/store-ops-2026-11/MAP.md` & `planning/store-ops-round-2-plan.md`):**
  1. **Official Receipt (OR) Tagging & Auto-Reset:** `Attach OR?` toggle on the till auto-resets to untoggled (`false`) and clears after every completed sale, hold, or cart clear; historical sales can attach/reprint OR numbers; VAT reports and Excel exports split OR-tagged vs. untagged sales using generic `OR-tagged` labels.
  2. **Discounts, Returns/Exchanges & Numeric Validation:** Mutual exclusion between per-line and whole-sale discounts; returns/exchanges workflow with custom replacement quantity input in both the item picker and Step 3 lines; shared numeric input formatters (`lib/core/format/numeric_input.dart`) across POS dialogs.
  3. **Held Carts & Cash Drawer:** Optional note prompt when holding a transaction, rich held-cart cards (hold `#`, timestamp, customer, item breakdown, reservation expiry, sticky note), immediate removal from the Held tab upon resume, PHP denomination counter at shift close, Z-reading tender/opening breakdowns, and custom cash-out categories.
  4. **History Date Filters & Requisition Step 2:** Local-timezone custom date range filter on both Transaction History and Payment History; redesigned Requisition Step 2 (`_RequisitionLines`) with spaced `Ordered`, `Still to give`, and highlighted `Give now` columns.
  5. **Store Payables Proof, Deliveries Authority & Bodega Handoff, and Stocker Sidebar:** Optional proof attachment (`0025_supplierpayment_proof_attachment`) on supplier payments with `No proof attached` warning badge and post-payment `Attach / Update proof` action; Cashiers authorized to **Start / Deliver / Fail** all store deliveries; Bodega-shelved deliveries surfaced in the Bodega Checker's queue as **For Delivery** loads; Stock Manager sidebar cleaned up (`Sales` and `Payables` removed; `Returns` moved under **Purchasing** as `Supplier returns`).
- **Next:** Ready for Windows desktop smoke test (`git pull --ff-only origin master` + `docker compose up -d --build backend` + `flutter run -d windows`).
