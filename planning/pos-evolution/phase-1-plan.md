# Phase 1 Plan — Foreman Out, CPMS Boundary

**Spec:** [MAP](./MAP.md) row 1. **Branch:** proposed `feat/pos-evolution-phase-1` off `feature/backend-integration` (`4a853b2`). **Baseline:** re-measured in Task 0 (last known: backend 497, flutter 1243 + 224 goldens, analyze clean).
**Locked (2026-11-03):** decisions [01](./decisions/01-requisitions-after-foreman.md)–[08](./decisions/08-foreman-data-migration.md). **P1 locked 2026-11-03 (by: me):** CPMS sends the POS customer id, read from `GET customers/`.

## Destination & Scope

The POS has no foreman and no approval screens. CPMS, through one revocable service account, can: read the material list, push approved requests (retry-safe), close an open remainder, and read what was released and what each project owes. The cashier scans the token and releases what is in stock; the rest stays open on the same token. Every release's utang carries its project.

**Out of scope:** any edit to `../qb_project_management_system/` (we ship a contract doc, CPMS builds against it later); outbound POS calls; Phases 2 (multi-role) and 3 (Excel); new POS screens for closing.

## Wire contract (summary — full text in `docs/integration/CPMS-CONTRACT.md`, Task 11)

All under `/api/v1/integration/cpms/`, JWT login as the service account, every other POS endpoint refuses it.

| Method + path | Body / answer | Notes |
|---|---|---|
| `GET customers/` | `[{id, name}]` active contractor / construction-firm customers | payer for `project.payer`; no balances or limits (P1) |
| `GET materials/` | `[{code, product, unit}]` active units of active products | no stock, price, cost (dec. 04) |
| `POST requests/` | `{cpms_request_id, token, project:{cpms_project_id, name, payer}, requester_name, approver_name, notes, items:[{code, quantity}]}` | same `cpms_request_id` again → `200` existing copy, unchanged; new → `201`; unknown code → `400 UNKNOWN_MATERIAL`; unknown or non-contractor payer → `400 UNKNOWN_PAYER`; token already held by another request → `409 TOKEN_TAKEN` (dec. 02, 04) |
| `POST requests/{cpms_request_id}/close/` | — | `APPROVED`/`PARTIAL` → `CLOSED`, token dead; already `RELEASED`/`CLOSED` → `200` no-op (dec. 06) |
| `GET requests/{cpms_request_id}/` | status + per line `requested, released, outstanding` | (dec. 07) |
| `GET projects/{cpms_project_id}/payables/` | `{total, paid, balance}` from that project's ledger rows | (dec. 07) |

## Domain & File Impact

**Backend**

- `apps/requisitions/models.py` — `Project.cpms_project_id` (unique, nullable); `Requisition`: + `cpms_request_id` (unique, nullable for legacy), `requester_name`, `approver_name` (text), status + `CLOSED`; − `requested_by`, `approved_by` FKs. `RequisitionItem`: `variant` → `variant_uom` (FK `VariantUOM`); `quantity`/`released_qty` are in that selling unit.
- `apps/collectibles/models.py` — `CollectibleLedger.project` (nullable FK `Project`, `PROTECT`).
- `apps/requisitions/migrations/`, `apps/collectibles/migrations/` — schema + `RunPython` per decision 08 (names copied; legacy items → their variant's factor-1 unit, quantities unchanged because base = factor 1; Draft/Submitted → Cancelled; foreman deactivated and ungrouped; `Site Foreman` group deleted).
- `apps/users/permissions.py` — `ROLE_CPMS_SERVICE = 'CPMS Service'`, `IsCpmsService`; drop `ROLE_SITE_FOREMAN`, `IsForemanOrManager*`.
- New `apps/integration/` (views, serializers, urls, tests) — the six endpoints above; registered in `config/urls.py`.
- `apps/requisitions/services.py` — drop `submit/approve/reject_requisition`; `verify_token` returns per-line `availability` (`FULL` / `SHORT` + available / `UNAVAILABLE`); `release_materials` releases what is there (Task 5); `close_requisition`; `import_request`.
- `apps/requisitions/views.py`, `serializers.py`, `urls.py` — requisitions + items become read-only for managers; no create/submit/approve/reject, no foreman scoping; verify/release stay cashier.
- `apps/collectibles/serializers.py` — ledger row exposes `project` name.
- `apps/users/management/commands/seed_demo.py` — no foreman; `cpms_service` account; three requests as if CPMS pushed them (approved, partial, released).
- `apps/reports/views.py` `requisition_history_view` — knows `CLOSED`; no `requested_by` use.

**Flutter**

- Delete: `features/admin/views/requisitions_page.dart`, `viewmodels/admin_requisitions_viewmodel.dart`, `widgets/admin_requisition_{list,details_dialog,token_panel}.dart`, `features/sales/views/sales_requisitions_page.dart`, their tests/goldens.
- `routes/routes.dart` (two routes + `salesTwinOf` arm), `core/layout/admin_skeleton_layout.dart`, `sales_skeleton_layout.dart`, `features/sales/widgets/sales_navigation.dart` (sidebar entries + "requisitions awaiting" marker).
- Tiles: `dashboard/viewmodels/admin_overview_viewmodel.dart`, `dashboard/widget/admin_needs_attention_panel.dart`, `sales/viewmodels/sales_dashboard_alerts_viewmodel.dart`, `sales/views/sales_dashboard_page.dart`.
- `data/models/requisition.dart`, `data/services/requisition_service.dart`, `data/repositories/requisition_repository.dart` — read + verify + release only; per-line availability; `requesterName`.
- `features/pos/viewmodels/material_release_viewmodel.dart`, `views/material_release_page.dart`, `widgets/pos_release_step_panel.dart` — per-line Full / Short (n available) / Unavailable before confirm; result says Released or Partially released.
- `features/admin/viewmodels/admin_users_viewmodel.dart` (drop `Site Foreman` from assignable), `features/auth/views/unsupported_role_page.dart` (drop foreman branch; generic "no POS role" stays).
- `features/admin/views/reports_page.dart` Requisitions tab — `CLOSED` label, requester as text.
- Receivables row (`sales_receivables_content.dart`) — project caption under customer when set.

**Docs** — `docs/integration/CPMS-CONTRACT.md` (new), `ENDPOINTS.md`, `docs/SYSTEM_ATLAS.md` + html, session note, MAP row 1.

## Open before Task 3

- [x] **P1 — How CPMS names the payer.** Locked: recommended option. `Project.customer` is required, and decision 03 keeps the contractor as payer, but nothing says how a CPMS push identifies the POS customer. Recommended: CPMS sends the POS customer id, read from a fourth read-only endpoint `GET customers/` (contractor/firm customers: id + name only); unknown id → `400 UNKNOWN_PAYER`. Alternative: the Store Manager links each CPMS project to a customer in the POS first (needs a screen).

## Phased Execution Checklist

- [x] **Task 0 — 🤖 Baseline.** 2026-11-03 on `4e791eb`: backend 497 OK · analyze clean · flutter 1257 passed, 224 skipped · goldens 224 passed.
- [x] **Task 1 — 🤖 Models + migration (dec. 03, 04, 08), RED first.** Migration test on a DB seeded with today's shapes: names copied, Draft/Submitted → Cancelled, items point at factor-1 units, foreman inactive and groupless, group gone, `makemigrations --check` clean. Unit tests for the new uniques.
- [x] **Task 2 — 🤖 Service account + fence, RED first.** `CPMS Service` group, `IsCpmsService`; test: CPMS account gets 403 on a sweep of every non-integration `/api/v1/` route, staff get 403 on every integration route, deactivated CPMS account → 401.
- [x] **Task 3 — 🤖 Material list + import (dec. 02, 04, P1), RED first.** Known/unknown code, unknown/walk-in payer 400, retry returns same copy (one row), token clash 409, project upsert by `cpms_project_id`, no stock/price keys in the material list.
- [x] **Task 4 — 🤖 Remove POS-side requesting and approving (dec. 01), RED first.** create/submit/approve/reject → 405/404; manager list read-only; cashier verify/release unchanged; `ROLE_SITE_FOREMAN` gone from source.
- [x] **Task 5 — 🤝 Release what is there (dec. 05), RED first.** I write tests + skeleton; **you write the per-line quantity rule** (`releasable_qty(line, available_base)`: whole vs measured unit, conversion factor). Then 🤖: one sale + one project-tagged ledger per release, `PARTIAL` keeps token live, last line → `RELEASED` + token used, nothing releasable → `400 NOTHING_TO_RELEASE` with no writes, `CLOSED` → refused, concurrent double release still one deduction.
- [x] **Task 6 — 🤖 Close + read-back (dec. 06, 07), RED first.** Close from APPROVED/PARTIAL, no-op repeats, released utang untouched; request status lines; project payables match ledger sums after a payment.
- [x] **Task 7 — 🤖 Seed rewrite (dec. 08).** No foreman, `cpms_service`, three pushed requests; reseed dev DB (flush + migrate + seed_demo) and recount.
- [x] **Task 8 — 🤖 Flutter: remove approvals UI (dec. 01), RED first.** Routes gone (typed URL bounces), no sidebar entries/markers/tiles for any role, `Site Foreman` not assignable; goldens regenerated and viewed.
- [x] **Task 9 — 🤖 Flutter: partial release at the till (dec. 05), RED first.** Per-line availability shown before confirm; Partially released result; second scan of the same token releases the rest; `NOTHING_TO_RELEASE` / closed-request messages.
- [x] **Task 10 — 🤖 Flutter: project on receivables + reports `CLOSED`.**
- [x] **Task 11 — 🧑 Approve the CPMS contract.** Accepted provisionally 2026-11-07 (unread by the owner): contract marked v0.1 provisional with change rules and a change log. 🤖 drafts `docs/integration/CPMS-CONTRACT.md` + `ENDPOINTS.md` from the built endpoints (curl examples, error codes); you review it as product owner before Phase 1 is called done.
- [x] **Task 12 — 🤖 Phase gate + QA.** 2026-11-07: qa-tester live run passed apart from 2 defects, both fixed RED-first (seeded CPMS-R-1001 sat on the drained low-stock variant → now Full; unknown addresses showed GoRouter's debug page → router `onException` sends them to the user's dashboard). Gates: backend 599 OK, analyze clean, flutter +1284 ~221, goldens +221; dev DB reseeded; atlas refreshed. Full backend + flutter + goldens; qa-tester live: CPMS calls by curl as `cpms_service` (list, push, retry, close, read-back), cashier full + partial + second release, manager receivables shows project, no role sees approvals; atlas refresh; MAP row 1 ✅.
