# 2026-11-06 — POS evolution Phase 1 build (foreman out, CPMS boundary)

## Focus

Grill Phase 1 to a plan, then build it with subagents (expressive-dev builds, hygiene-reviewer checks, one backend task at a time). Branch `feat/pos-evolution-phase-1` off `4e791eb`. The CPMS repo was **not** touched (its two uncommitted Flutter files date from 2026-10-30, before this work).

## What Was Built / Changed

Plan: `planning/pos-evolution/phase-1-plan.md` (decisions 01–08 + P1 payer link). Tasks 0–10 done; 11–12 open.

- **Models + migration (T1):** `Project.cpms_project_id`; `Requisition.cpms_request_id`, `requester_name`, `approver_name`, status `CLOSED`, user FKs dropped; `RequisitionItem.variant` → `variant_uom`; `CollectibleLedger.project`. Data migration copied names, Draft/Submitted → Cancelled, foreman deactivated, `Site Foreman` group deleted.
- **CPMS account + fence (T2):** `CPMS Service` group, `IsCpmsService`; `CpmsFencedJWTAuthentication` (default auth class) answers `403 CPMS_SCOPE` outside `/api/v1/integration/cpms/`; route sweep covers all 86 `/api/v1/` routes.
- **Integration endpoints (T2, T3, T6):** `customers/`, `materials/`, `requests/` (retry-safe import, `UNKNOWN_PAYER`, `UNKNOWN_MATERIAL`, `DUPLICATE_MATERIAL`, `TOKEN_TAKEN`), `requests/{id}/`, `requests/{id}/close/`, `projects/{id}/payables/`.
- **POS approving removed (T4, T8):** read-only requisitions for managers; approve/submit/reject, foreman scoping, approvals screens, sidebar entries, markers and tiles deleted; sidebar indices renumbered and pinned by a test.
- **Release what is there (T5, T9):** `releasable_qty` (whole units round to whole counts, measured to 0.01, never below 0); availability `FULL/SHORT/UNAVAILABLE/DONE`; one sale + one project-tagged ledger per release; PARTIAL keeps the token live; `NOTHING_TO_RELEASE`; `REQUISITION_CLOSED/RELEASED/CANCELLED` codes. Till shows per-line badges, "Releases N of M lines now", "Partially released".
- **Seed (T7):** no foreman; `cpms_service / demo1234`; CPMS-R-1001 APPROVED, 1002 RELEASED, 1003 PARTIAL. Dev DB flushed + migrated + reseeded.
- **Receivables + reports (T10):** ledger `project_name` caption + search; Closed / Partially released / Cancelled labels; `select_related('project')` on ledgers.
- **Docs (T11 draft):** `docs/integration/CPMS-CONTRACT.md` (new, untracked) and `ENDPOINTS.md` §3.6 rewrite + §3.7 (unstaged).

## Verification (2026-11-06, fresh)

| Command | Result |
|---|---|
| `docker exec buildpro_backend python manage.py test --noinput` | PASS — Ran 598, OK (baseline 497) |
| `... makemigrations --check --dry-run` | PASS — No changes detected |
| `flutter test --concurrency=2` | PASS — +1277 ~221 (baseline +1257 ~224) |
| `flutter test --tags golden --dart-define=RUN_GOLDENS=true --concurrency=2` | PASS — +221 (last run after T10 follow-ups) |
| `flutter analyze` | **FAIL — 1 info**: `curly_braces_in_flow_control_structures` at `test/data/services/ledger_service_test.dart:92` (not fixed during wrap-up) |
| Live | `cpms_service` login 200; `materials/` 200; `products/` 403 |

Ownership check: Q1 (data flow) partly answered, Q2 (concurrency) and Q3 (why server-side) answered by the agent at user request; all three logged as gaps.

## Mistakes & Gotchas

- **Editor auto-format after staging:** the hook ran `dart format` over 11 already-staged Flutter files; the re-wrap of a one-line `if` created the analyze info above. Re-stage after the last format, then re-run analyze.
- **Prose-parsing refusal:** the first T9 build matched CLOSED/RELEASED/CANCELLED by regex on English text; fixed with coded exceptions. `token_verify_view` also bypassed `_refusal()` and dropped codes.
- **`DONE` state:** a fully released line on a PARTIAL token read `FULL` with 0 releasable until fixed.
- **Sidebar renumbering:** deleting one admin menu item silently shifts every later page's highlight index.
- **Date-flaky test:** a reports test using `from=today&to=today` failed across midnight; uses the rolling 30-day window now.
- **`REQUISITION_CLOSED` is near-unreachable:** close spends the token, so a scan answers "Token has already been used." first.
- **Audit types reused:** import logs `REQ_APPROVE`, close logs `REQ_REJECT` (no migration); a dedicated type is a later choice.
- Lint hook blocks on pre-existing ruff findings in touched files (import order, `raise ... from None`); fix them when touching the file.

## Decisions

- P1 (by: me): CPMS names the payer by POS customer id from `GET customers/`.
- Legacy DRAFT/SUBMITTED/REJECTED close = 200 no-op (by: delegated, reviewer agreed).
- `ProjectViewSet` keeps its old read audience (any signed-in staff account).

## Next Step

Fix the analyze info (braces at `ledger_service_test.dart:91-92`), re-stage, then review `docs/integration/CPMS-CONTRACT.md` as product owner (Task 11). After approval: `/skill:execute-phase Phase 1` for Task 12 (gates + qa-tester browser/curl run + atlas refresh + MAP ✅), then commit.
