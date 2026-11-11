# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; **next build: `planning/pos-evolution/phase-5-plan.md`** (decision 18); last completed: `phase-4-plan.md` |
| UI-refresh plan (complete) + ledger | `temp/ui-refresh/TASKS.md` · `.superpowers/sdd/ui-refresh/progress.md` (both untracked) |
| QA how-to: run the app, roles, flows | `docs/testing/QA-PROFILE.md` |
| My knowledge gaps | `docs/learning/gaps.md` |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (6 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports}/` |
| Flutter MVVM client | `flutter/lib/features/` · models `flutter/lib/data/models/` · routes `flutter/lib/routes/routes.dart` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |

Every pointer must resolve; a broken pointer is fixed in the commit that breaks it.

## Test & lint

- Flutter: `cd flutter && flutter analyze && flutter test --concurrency=2` (8 GB RAM: keep concurrency 2; stop with `pkill -f "[f]lutter_tester"`).
- Goldens: `flutter test --tags golden --dart-define=RUN_GOLDENS=true --concurrency=2` (PNGs in gitignored `.superpowers/sdd/ui-refresh/goldens/`).
- Backend: `docker exec buildpro_backend python manage.py test --noinput` · `... manage.py check` · `... manage.py makemigrations --check --dry-run` (host python cannot reach `db`).

## Workflow

- Build a phase with **`execute-phase`**; end a session with **`wrap-up`** (session note + gaps + this file's status block).

## Current Status & Next Step

- **Branch:** `feat/pos-evolution-phase-4`; implementation committed `a94d464`, owner pushes (remote unverified). Phase 4 ✅ Done, owner closed with five Minors deferred; Phase 5 not started. Final recheck: backend 882 tests, check/drift clean; Flutter analyze/1771 tests/241 goldens passed.
- **Last session:** `docs/sessions/2026-11-11-pos-evolution-phase-4-build.md` (verification, review, QA, limits and learning topics; ownership check skipped).
- **Next:** `/skill:execute-phase Phase 5` (package purchasing, supplier payables, delivery, bodega-lite). Backend container returned externally; controller reran 882 tests/check/drift successfully. No predictions; phase-level review/isolated QA; CPMS v0.3 provisional, Phase 1c undecided.
- **Dev DB:** read-only recheck shows Phase 4 migrations applied after external container recreation/restart; assistant did not migrate/restart/reset. Seed/data state unverified; no further dev writes/reset/restart authorized. QA last verified on Phase 4 at API 8001/web 8091 (`buildpro_p1d_qa_*`); current container state unverified. QA server `--noreload` restart recipe in QA-PROFILE. Credential-bearing `temp/` evidence must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
