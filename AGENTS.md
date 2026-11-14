# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; completion build order 6 → 7 → 8 → 9 → 3 → 2 (decisions 19–24); **active work: documentation/owner closure** (`planning/pos-evolution/phase-3-plan.md`); Windows Excel smoke test owner-verified with unchanged stock; Phase 2 built/verified, formal phase closure pending (`phase-2-plan.md`) |
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

- Feature commit `32167b3` is merged into freshly fetched `origin/master` through `7ddc999` (PR #23). Documentation follow-up branch: `docs/windows-installation-and-qa-close`; owner selected PR delivery, not direct master push.
- Owner verified native Windows/Excel export, Faucet price **225 → 1,000**, import and export/re-import, with stock unchanged. This closes that specific QA gap, not an exhaustive Windows or production-readiness certification. [Acceptance record](docs/sessions/pos-windows-installation-and-excel-acceptance.md); `README.md` owns installation, backups and run commands.
- Phase 2 implementation/reviews and Phase 3 implementation/file-flow verification are recorded in their plans; formal owner phase closure remains distinct. Phase 1c stays on hold. No backend source or database changes in this docs pass. Do not infer current development DB schema/state from the historical snapshot below.

### Historical pre-merge controller snapshot (superseded where noted above)

- **Branch:** `feat/pos-evolution-phase-3` from Phase 9 `22836ed`; uncommitted Phase 3 and Phase 2 work must be preserved. Phase 6 ✅ **Done — owner-closed 2026-11-13** (backend 1064, Flutter 2010 / 241 skipped, goldens 241, QA no confirmed defect; `phase-6-plan.md`). **Phase 7 (sales-order lifecycle) ✅ Done — owner-closed 2026-11-13** (review APPROVED, backend **1138** / Flutter **2039** / goldens **241**, QA 14/15 + Medium fixed + re-probed PASS; committed `c21a25e`, **owner pushes**; `phase-7-plan.md`).
- **Phase 8 (supplier returns, credit notes, supplier cheque clearing) ✅ Done — owner-closed 2026-11-13** (blanket completion authorization; review APPROVED no blockers, gates green backend **1219** / Flutter **2142** / goldens **241 unchanged**, QA **zero confirmed defects**; committed locally on this branch, **owner pushes**). Evidence: `phase-8-plan.md` Task close + `docs/sessions/2026-11-13-pos-evolution-phase-8-build.md`. **Phase 9 (per-location stock + transfers) ✅ Done — owner-closed 2026-11-14** (review APPROVED, gates backend **1306** / Flutter **2224** / goldens **241 with 8 intended masters**, isolated QA 8 groups PASS zero defects; `phase-9-plan.md` Task close + `docs/sessions/2026-11-14-pos-evolution-phase-9-close.md`). **Phase 2 (merged sidebar + combined dashboard) ✅ Built and verified 2026-11-14** (owner closure pending): all four stages independently APPROVED plus a whole-change review APPROVED; Flutter **936 passed / 166 skipped**, goldens **250** (241 unchanged + 9 new), backend no-change confirmed (**1365 tests OK**) on the disposable QA stack after migrating it to current head (it had fallen behind Phase 9; the protected main dev DB was not touched). Three real defects found and fixed during review: stale merged-sidebar goldens, a missing single-area `/dashboard` fence, an untested Sales-section failure path. Isolated QA did not complete a literal browser click-through (two attempts hit turn limits); accepted as sufficient for tonight given the real widget/integration test coverage plus a direct `APIClient` check of the one real server dependency — see `phase-2-plan.md` Task-close. **Current:** Phase 3 (Excel catalogue round-trip) implementation gates passed; browser/native file-flow closure is the one remaining POS gate before owner closure tonight. Fresh HTTPS fetch earlier succeeded without modifying the configured SSH remote; latest teammate frontend remains `22ca7e8`, adopted/superseded per decision 17. No push/master merge, no dev startup/migration/reset.
- **QA build override:** web must build host-root `--dart-define=API_BASE_URL=http://127.0.0.1:8001` (client paths already carry `/api/v1`). The earlier `…:8001/api/v1` suffix double-prefixed requests (`/api/v1/api/v1/…` → 404) and needed a session-only shim; that shim run stays historical only.
- **Dev DB:** read-only recheck shows Phase 4 migrations applied after external container recreation/restart; assistant did not migrate/restart/reset. Seed/data state unverified; no further dev writes/reset/restart authorized. Dev containers now stopped after host interruption; DO NOT start (entrypoint migrates). Only QA restored, isolated172.20.0.*; five Phase5 migrations applied there. Backend focused tests now use `docker exec buildpro_p1d_qa_backend ...` (disposable test DB); API/web refreshed to current source for Phase 5 live QA. QA server `--noreload` restart recipe in QA-PROFILE. Credential-bearing `temp/` evidence must never be committed.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only (`flutter run -d linux`); `.superpowers/` is gitignored, so ledgers and goldens live only on this machine; the editor hook re-formats staged Dart files, so re-stage after edits. Local `temp/p1b-qa/` includes credential-bearing artifacts: never stage it.
