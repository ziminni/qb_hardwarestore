# 2026-11-11 — POS evolution Phase 4 build and handoff

## Focus

Front-counter panel feedback, decision 18. Implementation committed as `a94d464` on `feat/pos-evolution-phase-4`; owner handles push (remote status not verified). Ownership check skipped at owner's request; learning topics recorded in `docs/learning/gaps.md`, not claimed as assessed knowledge.

## What Was Built / Changed

- Server-backed Admin VAT settings and discount cap; cashier reasoned discounts; one-use five-minute manager approval, login-style lockout and password-free failure audit.
- VAT-inclusive net totals, per-sale VAT rate and net returns; split tenders and pending customer cheques with manager Clear/Bounce decisions.
- Server `change_given`, cash-only change and non-cash overpayment refusal; Z-reading subtracts change. Migration 0014 derives legacy change from tenders, capped at cash; old return rows excluded.
- Multiple staff roles with picker, remembered active area, header switcher and role fences; shared 25-row table paging; barcode PDF/CSV masterlist with spreadsheet-formula escaping.
- Role-flow docs, README, ENDPOINTS, QA profile and both atlases refreshed. Scope remained POS only; no CPMS edits.

## Verification

Before wrap-up: controller passed 882 backend tests, Django check and migration-drift check; Flutter analyzer, 1771 ordinary tests and 241 goldens passed. Whole-phase review and final cash-change delta review APPROVED. Final reviewer independently reran 14 backend and 11 Flutter tests.

Fresh wrap-up run (logs: local `temp/p4/wrap-up/`):

| Command | Result |
| --- | --- |
| `git status --short`; `git diff --stat` | Clean before wrap-up docs; HEAD `a94d464` |
| `docker exec buildpro_backend python manage.py test --noinput --parallel 1` | INCOMPLETE, exit 137 after discovering 882 tests; container subsequently unavailable |
| `docker exec buildpro_backend python manage.py check` | BLOCKED: `Error response from daemon: No such container: buildpro_backend` |
| `docker exec buildpro_backend python manage.py makemigrations --check --dry-run` | BLOCKED: same missing container |
| `cd flutter && flutter analyze` | PASS, no issues |
| `flutter test --concurrency=2` | PASS, 1771 tests; 241 golden tests skipped for separate run |
| `flutter test --tags golden --dart-define=RUN_GOLDENS=true --concurrency=2` | PASS, 241 goldens |

Earlier isolated QA passed discounts, approvals/lockout, net refunds/VAT reports, cheque decisions/debt, role switching/revocation, settings, pager and barcode download/export. Final change recheck passed all five scenarios. Controller reconciled Z-reading: cash 2774.25 minus change 515.00 = cash sales 2259.25; minus cash refunds 311.25 = expected drawer 1948.00 (opening float 0).

The initial wrap-up backend run was incomplete. On the subsequent execute-phase continuation, `buildpro_backend` was already running again (external recovery); the same full backend command passed **882 tests in 574.262s**, system check reported no issues, and migration-drift check reported no changes. Evidence: `temp/p4/recheck/backend.log`. No assistant container recovery, migration or data reset was performed.

## Mistakes & Gotchas

- QA `runserver --noreload` served old mounted code twice: initial new-route 404s, then null `change_given` inserts after migration. Broad process lookup matched its own shell; exact Python argv lookup and verified fresh startup fixed the QA process. Recipe in QA-PROFILE.
- Cash-change defect predated split tenders: raw cash tender was counted as drawer takings. Legacy backfill must cap derived change at cash taken, or a historical electronic overpayment can produce negative drawer cash.
- Flutter goldens require `--dart-define=RUN_GOLDENS=true`; an environment variable alone skipped all tests.
- Django imports are container-only; host diagnostics are not runtime proof. Standard Django migration class lists trigger existing Ruff RUF012 warnings.
- Bundled font lacks peso glyph; golden rendering does not prove native font fallback. Atlas HTML JS syntax checked, browser rendering not rechecked. Real browser text scaling, native Save/printing and production deployment remain unverified.

## Decisions

- Owner authorized staging/commit; committed implementation as `a94d464`; no push by assistant.
- Assistant did not migrate/restart/reseed dev. Container returned externally after the interrupted run; read-only `showmigrations` now shows Phase 4 pos 0011–0014, users 0003–0004 and collectibles 0003 applied. Seed/data state remains unverified.
- Five nonblocking review Minors remain for disposition: broad user-view exception catch, requisitions importing private money helper, no-change settings PATCH audit, missing nonzero JSON-to-receipt change test, and legacy VOID rows receiving cosmetic backfilled change (Z filters completed sales).
- Owner explicitly selected “Close and defer”: Phase 4 ✅ Done 2026-11-11 with all five nonblocking Minors deferred. Backend recheck passes; Phase 5 not started.

## Next Step

First action: `/skill:execute-phase Phase 5`; owner closed Phase 4 with five Minors deferred. Backend recheck is complete; no container recovery is needed now. No automatic dev reset, deployment, push or Phase 5 execution.
