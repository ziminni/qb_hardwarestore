# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; completion build order 6 → 7 → 8 → 9 → 3 → 2 (decisions 19–24); **active build: `planning/pos-evolution/phase-6-plan.md`** (owner authorized); last closed: `phase-5-plan.md` |
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

- **Branch:** `feat/pos-evolution-phase-6` from planning `80d7174` (includes Phase 5 `864a667`). Phase 6 ✅ **Done — owner-closed 2026-11-13** under a blanket "complete it all" authorization: review APPROVED, final gates green (backend **1064**, Flutter **2010** / 241 skipped, goldens **241**), isolated QA no confirmed defect, one Low cosmetic clip fixed RED-first. Committed locally on this branch; **owner pushes**. Evidence/gotchas in `planning/pos-evolution/phase-6-plan.md` Task close and session note `docs/sessions/2026-11-12-pos-evolution-phase-6-build.md`.
- **Next:** Phase 7 (sales-order lifecycle) is **In Progress** under the same authorization — build → review → gates → isolated QA → docs on `feat/pos-evolution-phase-6` (or a fresh `feat/pos-evolution-phase-7` branch); then 8 → 9 → 3 → 2. No push, no dev startup/migration/reset. Dev containers stay stopped; QA artifacts isolated, its settings restored.
- **QA build override:** web must build host-root `--dart-define=API_BASE_URL=http://127.0.0.1:8001` (client paths already carry `/api/v1`). The earlier `…:8001/api/v1` suffix double-prefixed requests (`/api/v1/api/v1/…` → 404) and needed a session-only shim; that shim run stays historical only.
- **Dev DB:** read-only recheck shows Phase 4 migrations applied after external container recreation/restart; assistant did not migrate/restart/reset. Seed/data state unverified; no further dev writes/reset/restart authorized. Dev containers now stopped after host interruption; DO NOT start (entrypoint migrates). Only QA restored, isolated172.20.0.*; five Phase5 migrations applied there. Backend focused tests now use `docker exec buildpro_p1d_qa_backend ...` (disposable test DB); API/web refreshed to current source for Phase 5 live QA. QA server `--noreload` restart recipe in QA-PROFILE. Credential-bearing `temp/` evidence must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
