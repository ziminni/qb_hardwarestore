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

- **Branch:** `feat/pos-evolution-phase-4` (off Phase 1d `c8ef41f`). Phase 1d ✅ Done; **Phase 4 🟡 built, gates + isolated QA passed, awaiting owner closure** (decision 18: front-counter panel feedback); Phase 5 pending. Owner pushes; no commit without authorization.
- **Last session:** `docs/sessions/2026-11-11-pos-evolution-phase-1d-build.md`.
- **Next:** owner closes Phase 4 (3 review Minors to decide, see plan Task 9) and authorizes commit; then Phase 5 (package purchasing, supplier payables, delivery, bodega-lite). No predictions; max 3 builders on disjoint files, backend sequential; controller serializes full gates. Phase 1c still undecided; CPMS v0.3 provisional.
- **Dev DB:** Phase 1b unchanged, inventory 0008 + Phase 4 pos 0011–0014/users migrations pending by owner choice; no dev writes/resets authorized (backend restart auto-migrates). Disposable Phase 1d QA still running: `buildpro_p1d_qa_{db,backend,web}`, isolated network/volume, API 8001/web 8091, now on Phase 4 code + migrations; its server is `runserver --noreload`, so restart it after code changes (QA-PROFILE recipe). Seeded/reset only QA. Credentials/scanner tokens in local `temp/p1d/qa/seed.log` must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
