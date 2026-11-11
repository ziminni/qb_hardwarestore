# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; **active build: `planning/pos-evolution/phase-4-plan.md`** (decision 18), then `phase-5-plan.md`; last completed: `phase-1d-plan.md` |
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

- **Branch:** `feat/pos-evolution-phase-1d` (off Phase 1b `1a15920`, not pushed). Phase 1b ✅ Done; **Phase 1d ✅ Done 2026-11-11** (closed with accepted limits): packaging units, server whole-number rule, remove unused unit, teammate dialog design + extras. Do not push; owner pushes.
- **Last session:** `docs/sessions/2026-11-11-pos-evolution-phase-1d-build.md`.
- **Next:** owner pushes Phase 1d; then Phase 1c payment receipts planning (open decisions). CPMS contract v0.3 provisionally accepted. No predictions; at most two builders; backend sequential; Phase 1c still undecided.
- **Dev DB:** Phase 1b unchanged, 0008 pending by owner choice; no dev writes/resets authorized (backend restart auto-migrates). Disposable Phase 1d QA still running: `buildpro_p1d_qa_{db,backend,web}`, isolated network/volume, API 8001/web 8091; seeded/reset only QA. Credentials/scanner tokens in local `temp/p1d/qa/seed.log` must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
