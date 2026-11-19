# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** Follow the pointers; never paste a copy of a fact that already has a home.

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| Architecture & Live/Mock matrix (+ cockpit) | `docs/SYSTEM_ATLAS.md` · `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → `planning/pos-evolution/MAP.md`; completion build order 6 → 7 → 8 → 9 → 3 → 2 (decisions 19–24); **active work: documentation/owner closure** (`planning/pos-evolution/phase-3-plan.md`); Windows Excel smoke test owner-verified with unchanged stock; Phase 2 built/verified, formal phase closure pending (`phase-2-plan.md`) |
| UI-refresh plan (complete) + ledger | `temp/ui-refresh/TASKS.md` · `.superpowers/sdd/ui-refresh/progress.md` (both untracked; held on the other machine, not on this Mac) |
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

- **Branch:** `master` at `dc2dc18` (PR #28), level with `origin/master`. `feature/backend-integration` (UI refresh through `700171c`, incl. Z2 `4a853b2`) is fully merged into it. Uncommitted local `flutter/macos/` Pod/Xcode changes are this Mac's own.
- **Last session:** `docs/sessions/2026-11-16-full-verification-cash-limit-and-tunnel.md` (POS Phase 1c, cash-out limit, CPMS tunnel; backend 1409 OK, Flutter 2446 OK). Earlier phase history: `docs/sessions/` and `planning/pos-evolution/`.
- **Dev DB (this Mac):** backed up 2026-11-17 to `~/BuildProBackups/pos-20261117-162406.dump`, then backend rebuilt and all pending migrations applied on start; `showmigrations` 0 unapplied, `makemigrations --check` clean, `/api/health/` ok. Existing data kept (seed skipped).
- **Next:** owner closure of POS Phases 2 and 3 (`planning/pos-evolution/`). UI-refresh follow-ups need the untracked ledgers copied from the other machine first. Blocked on user: reseed dev DB, teammate's 7 design items, adjustments "By" column, offline web till, "Movements" tab rename.
- **Proof standard:** a test covers a fix only after it fails without the fix; a claim without its command output in the same message is unverified.
- **Caveats:** desktop pixels are user-verified only; `.superpowers/` and `temp/` are gitignored, so ledgers, goldens and QA evidence live only on the machine that made them. The editor hook re-formats staged Dart files, so re-stage after edits. Credential-bearing `temp/` evidence must never be staged.
