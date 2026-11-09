# QA Profile — BuildPro POS / Inventory

**Status: Phase 1b closed 2026-11-08 with owner-accepted QA limits; contract v0.2 provisional**

Phase 1b Tasks 0–10 are complete. The [Phase 1b plan](../../planning/pos-evolution/phase-1b-plan.md) owns final gate evidence and accepted limits; automated tests are not live QA evidence. Task 5 fresh-seed and repeat-seed scenarios passed on the Django test database. [Contract v0.2](../integration/CPMS-CONTRACT.md) was provisionally accepted by the owner on 2026-11-08; core isolated live QA passed and the owner explicitly chose “Close with limits (Recommended)”; missing checks are not counted as passed.

## How to run

- Canonical setup, commands and normal ports: [README setup](../../README.md#1-start-the-backend), [ports](../../README.md#ports), [client connection](../../README.md#connecting-the-client).
- **Do not use the existing dev database for writes without explicit approval.** It still has Phase 1 schema/data. No Phase 1b migration/seed/live QA has been performed on it for this draft. Even login failures/audits and refresh rotation can write state; use the isolated stack for authenticated probes.
- The backend entrypoint applies migrations. Do not rebuild/restart the running dev backend as a shortcut to QA. No implicit flush, reseed or cleanup.

### Disposable stack — QA complete, modified data retained

Inspection of [settings.py](../../backend_django/config/settings.py) confirms the connection is hardcoded, including host `db`; match its other connection values when creating the isolated database. **Environment DB overrides will not redirect this application.** Use network isolation rather than assuming `DATABASE_URL`/`DB_HOST` works.

The owner approved isolated QA on 2026-11-08. Actual setup:

- Network `buildpro_p1b_qa_net`, disconnected from the dev Compose network; PostgreSQL container `buildpro_p1b_qa_db`, alias `db`, separate volume `buildpro_p1b_qa_pgdata`, no published database port.
- API container `buildpro_p1b_qa_backend`, image `qb_pos_inventory_system-backend`, current source mounted read-only, attached only to the QA network. API: **http://127.0.0.1:8001**.
- Before migration, the QA database had zero public tables; backend DNS `db` matched the QA database and differed from `buildpro_db`. Isolation details are recorded in local `temp/p1b-qa/setup.txt`.
- `docker exec buildpro_p1b_qa_backend python manage.py migrate --noinput` and `... seed_demo` both exited 0. Fresh seed: 5 users, 8 batches, 7 transactions, 3 open utang ledgers. Dynamic scanner tokens are in `temp/p1b-qa/seed.log`, not contract examples.
- Web build `/tmp/qb-p1b-qa-web` uses `API_BASE_URL=http://127.0.0.1:8001`; container `buildpro_p1b_qa_web` serves it with `python -m http.server 8091 --bind 0.0.0.0 --directory /web`. Frontend: **http://127.0.0.1:8091**. API health and web both answered 200 after readiness.
- Independent browser/API probes wrote only this isolated database. Final report and artifacts are under local `temp/p1b-qa/report.md`: core flows PASS, no Critical/Important defect in tested scope. QA consumed tokens and changed stock/prices/sales/debt/payments; this stack is no longer pristine. Rerunning seed will not reset those scenarios.

Keep disposable data/evidence until review; obtain approval before destructive cleanup. Existing dev writes remain unapproved. Production rollback is backup/forward-fix, not reversing the no-op data migration (see contract rollout section).

## Test accounts (seeded, non-production)

Use [README demo accounts](../../README.md#demo-accounts) for all five usernames, passwords and role capabilities; do not maintain a second credential list here. Use [README fresh-seed scenarios](../../README.md#2-load-demo-data) for expected R1001–R1005 states and token instructions. Existing dev fixtures are not those post-migration scenarios. R1001–R1005 scenarios and repeat-seed safety are test-DB-verified; no running dev migration or reseed was performed.

## API conventions

[ENDPOINTS §1](../../ENDPOINTS.md#1-base-url--authentication) owns JWT/header, refresh, pagination and error handling. [ENDPOINTS §3.6](../../ENDPOINTS.md#36-appsrequisitions--projects-the-cpms-copy-tokens) owns staff review/scanner routes; [§3.7](../../ENDPOINTS.md#37-appsintegration--the-cpms-boundary-machine-caller-only) and the [CPMS contract](../integration/CPMS-CONTRACT.md) own the six service endpoints and refusal policy. Follow pagination beyond 50 rows; unknown response fields are ignored and unknown business codes remain refusals, showing detail.

## Domain rules and repeat-QA checklist

Completed QA covered scale 1.0 at all three widths. Owner-accepted limits: live browser 1.3 blocked; till 1.3 unverified; live timeout/unknown-outcome and simultaneous Close-vs-Review not injected. Queue/dialog 1.3 widget coverage is not live browser proof. The sidebar label truncates at 1440 (minor, accepted); the Review wrap at 1100 was fixed 2026-11-09. See the plan Handoff for the closure decision.

For repeat QA, run browser QA with the **agent-browser skill**, not ad hoc browser tooling. Cover widths **1440 / 1100 / 760** at text scales **1.0 / 1.3**, including keyboard/focus, scrollable list/dialog, long reasons, visible actions and status text not color alone. Record actual commands, results, screenshots and skips; automated goldens do not establish live large-text behavior.

| Probe | Expected invariant |
| --- | --- |
| Role fences / Admin twin | Manager and Admin can open Requests from projects at their respective routes; cashier/stocker cannot. CPMS token cannot use staff actions (`403 CPMS_SCOPE`); staff cannot call integration endpoints. Retired approvals/generic writes stay unavailable. |
| Queue, search and badge | Default WAITING, oldest-first. Create >50 disposable rows; search across all selected-status pages by request/CPMS id/project/contractor/requester. Badge counts all WAITING independently of search/filter and updates after a decision. Failed refresh must not assert zero or silently truncate a queue (>2000 selected rows fails loudly). |
| Import / retry / read | New import 201 WAITING, null line answers and amount. Same id retry 200 current stored status, including DECLINED, with no rewrite or second mutation. Read-back/close never echo token, per-unit price, stock or internal released amount. CPMS supplies the import token credential; that input is not a read-back leak. |
| Mixed Accept | Every line explicitly true/false; false needs reason, at least one true. All-false Accept refused; whole Decline is separate. Acceptance reserves no stock/debt. CPMS approver remains distinct from POS reviewer. False line reason remains visible at till and CPMS. |
| Full / partial / rescan | Fresh R1001 FULL; short eligible lines leave PARTIAL and same token works after restock. Open shift required, FIFO and unit rounding preserved. Completing only true lines produces RELEASED with no “return on same token” advice, even with false-line positive outstanding. No false-line stock/sale. |
| Whole Decline | Required trimmed reason; all lines false, token spent without cashier. Verify and Release return REQUISITION_DECLINED before generic used-token error; WAITING gives REQUISITION_WAITING. No stock/debt mutation. |
| CPMS withdrawal | WAITING close → CLOSED, amount stays null; accepted/partial close preserves quantities/debt and abandoned shortfall budget. DECLINED close is no-op with reasons; CANCELLED remains 409. Repeated close is mutation-safe, not a promise of frozen live-price response. |
| Stale / concurrent decision | Double tap/submission guard; two reviewers or review vs close yield one decision, loser 409/reload. Verify is advisory; concurrent Close/Release must not release after closure. Timeout/unknown outcome reloads detail before actions re-enable; failed refresh keeps actions blocked. Saved decision + list-refresh failure must not invite a second decision. |
| Budget vs debt | 10 at 10.00, release 4 → 40.00 payables; price remaining 6 at 12.00 → 112.00 budget. Payment changes payables only. Closed-after-accept keeps budget, not release permission. Round outstanding sum once HALF_UP. Historical unknown stays null after more release; UI says unavailable, not zero. |

## Out of bounds

- Existing dev or production writes, migrations, reseeds and resets without approval; no automatic flush or destructive cleanup.
- CPMS repository changes, real external services/payments, outbound integration, new config/scripts or reconciliation tooling.
- Phase 1b closure accepts the documented missing checks, not a claim they passed. Contract v0.2 stays provisional; closure does not authorize deployment, commits, dev writes or Phase 1c execution.
