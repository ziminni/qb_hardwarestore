# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; completion build order 6 → 7 → 8 → 9 → 3 → 2 (decisions 19–24); **next build: `planning/pos-evolution/phase-6-plan.md`** (not yet authorized); last closed: `phase-5-plan.md` |
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

- **Branch:** `feat/pos-evolution-phase-5` off Phase 4 closeout `9828b9b`; Phase 4 ✅ Done with five Minors deferred. Phase 5 ✅ Done, owner-closed 2026-11-12; BAG error-text fix reviewed and freshly widget-verified. Committed locally as `864a667`; owner pushes. Latest gates, review and QA evidence: `planning/pos-evolution/phase-5-plan.md` Task 9.
- **Last session:** `docs/sessions/2026-11-12-pos-evolution-phase-5-build.md` (build/recovery, historical gates/QA and owner closure).
- **Next:** Owner pushes `feat/pos-evolution-phase-5`. Completion phases 6 → 7 → 8 → 9 → 3 → 2 are planned (decisions 19–24, plans `phase-{6,7,8,9,3,2}-plan.md`) on `feat/pos-evolution-completion-planning`; Phase 1c on hold (needs CPMS). Start only on owner request: `/skill:execute-phase Phase 6`. No dev startup/migration/reset authorized.
- **Dev DB:** read-only recheck shows Phase 4 migrations applied after external container recreation/restart; assistant did not migrate/restart/reset. Seed/data state unverified; no further dev writes/reset/restart authorized. Dev containers now stopped after host interruption; DO NOT start (entrypoint migrates). Only QA restored, isolated172.20.0.*; five Phase5 migrations applied there. Backend focused tests now use `docker exec buildpro_p1d_qa_backend ...` (disposable test DB); API/web refreshed to current source for Phase 5 live QA. QA server `--noreload` restart recipe in QA-PROFILE. Credential-bearing `temp/` evidence must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
