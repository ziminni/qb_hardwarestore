# QA Profile — BuildPro POS / Inventory

**Status: Phase 1d QA passed on an isolated stack 2026-11-11 (closure pending owner); contract v0.3 provisionally accepted. Phase 1b closed 2026-11-08 with owner-accepted QA limits.**

Phase 1d (packaging units, server whole-number rule, unit removal, dialog family): evidence in local gitignored `temp/p1d/qa/` (`report.md`, `browser/`, `repro/`, `stocker/`, `mgr/`). The [Phase 1d plan](../../planning/pos-evolution/phase-1d-plan.md) Task 13 owns results and triage.

Phase 1b Tasks 0–10 are complete. The [Phase 1b plan](../../planning/pos-evolution/phase-1b-plan.md) owns final gate evidence and accepted limits; automated tests are not live QA evidence. Task 5 fresh-seed and repeat-seed scenarios passed on the Django test database. [Contract v0.2](../integration/CPMS-CONTRACT.md) was provisionally accepted by the owner on 2026-11-08; core isolated live QA passed and the owner explicitly chose “Close with limits (Recommended)”; missing checks are not counted as passed.

## How to run

- Canonical setup, commands and normal ports: [README setup](../../README.md#1-start-the-backend), [ports](../../README.md#ports), [client connection](../../README.md#connecting-the-client).
- **Dev is the demo DB** (Phase 1b, reseeded 2026-11-09; see [README](../../README.md#2-load-demo-data)). QA writes on dev need owner approval each time: even login failures/audits and refresh rotation write state, and probes consume seeded tokens.
- The backend entrypoint runs `migrate` on every start. No implicit flush, reseed or cleanup.

### Isolated stack

Phase 1d stack is **running** as `buildpro_p1d_qa_{db,backend,web}` on `buildpro_p1d_qa_net` / volume `buildpro_p1d_qa_pgdata` (API 8001, web 8091) until the owner approves removal. Same recipe as below; web built with `--dart-define=API_BASE_URL=http://127.0.0.1:8001`.

**Harness traps (agent-browser on Flutter web):** enable semantics by JS-dispatched click on `flt-semantics-placeholder`; click the semantics-box **centre** of a button (edge clicks hit the dialog barrier and look like "dialog closed"); click then `keyboard type`, not `fill`; scroll with dispatched `WheelEvent`. CSS `zoom` makes the canvas wider than the window and clips everything: it is **not** a 1.3 text-scale test.

**Stale QA server trap (Phase 4):** the QA backend runs `runserver --noreload`, so new code on the mounted source is NOT loaded. After code changes or migrations: restart only that process inside `buildpro_p1d_qa_backend` (no `kill` binary: use `python -c "import os,signal; os.kill(PID, signal.SIGTERM)"`, then `docker exec -d ... runserver 0.0.0.0:8000 --noreload`), check a new route answers 401 rather than 404, and rebuild the web into `temp/p1d/qa/web/`. Symptom of forgetting: new routes 404 and writes 500 (e.g. a new NOT NULL column inserted as null). Find the PID by exact argv (`python -c` over `/proc/*/cmdline` checking `argv[:2]==['python','manage.py']`), never `grep runserver`/`case *runserver*`: that matches the search shell itself, so the old server survives and the new one dies with "port already in use". Confirm `/tmp/runserver.log` starts with "Performing system checks".

Phase 1b stack (removed 2026-11-09):

Phase 1b live QA (2026-11-08) ran on an owner-approved isolated stack, removed with owner approval 2026-11-09; evidence stays in local gitignored `temp/p1b-qa/` (report: `report.md`). Recipe if needed again: [settings.py](../../backend_django/config/settings.py) hardcodes host `db`, so **environment DB overrides will not redirect the app**; isolate by network instead. Separate network (no dev Compose attachment), PostgreSQL container aliased `db` on its own volume with no published port, backend from the same image with source read-only on that network only (API :8001), static web build on :8091. Confirm zero public tables and that `db` resolves away from `buildpro_db` before `migrate` + `seed_demo`.

Production rollback is backup/forward-fix, not reversing the no-op data migration (see contract rollout section).

## Test accounts (seeded, non-production)

Use [README demo accounts](../../README.md#demo-accounts) for all five usernames, passwords and role capabilities; do not maintain a second credential list here. Use [README fresh-seed scenarios](../../README.md#2-load-demo-data) for expected R1001–R1005 states and token instructions. R1001–R1005 scenarios and repeat-seed safety are test-DB-verified; dev was reseeded to them 2026-11-09 (later probes may have changed them).

## API conventions

[ENDPOINTS §1](../../ENDPOINTS.md#1-base-url--authentication) owns JWT/header, refresh, pagination and error handling. [ENDPOINTS §3.6](../../ENDPOINTS.md#36-appsrequisitions--projects-the-cpms-copy-tokens) owns staff review/scanner routes; [§3.7](../../ENDPOINTS.md#37-appsintegration--the-cpms-boundary-machine-caller-only) and the [CPMS contract](../integration/CPMS-CONTRACT.md) own the six service endpoints and refusal policy. Follow pagination beyond 50 rows; unknown response fields are ignored and unknown business codes remain refusals, showing detail.

## Domain rules and repeat-QA checklist

Completed QA covered scale 1.0 at all three widths. Owner-accepted limits: live browser 1.3 blocked; till 1.3 unverified; live timeout/unknown-outcome and simultaneous Close-vs-Review not injected. Queue/dialog 1.3 widget coverage is not live browser proof. The sidebar label truncation at 1440 was fixed by renaming it "Project requests" (verification: see plan); the Review wrap at 1100 was fixed 2026-11-09. See the plan Handoff for the closure decision.

For repeat QA, run browser QA with the **agent-browser skill**, not ad hoc browser tooling. Cover widths **1440 / 1100 / 760** at text scales **1.0 / 1.3**, including keyboard/focus, scrollable list/dialog, long reasons, visible actions and status text not color alone. Record actual commands, results, screenshots and skips; automated goldens do not establish live large-text behavior.

| Probe | Expected invariant |
| --- | --- |
| Role fences / Admin twin | Manager and Admin can open sidebar Project requests at their respective routes; cashier/stocker cannot. CPMS token cannot use staff actions (`403 CPMS_SCOPE`); staff cannot call integration endpoints. Retired approvals/generic writes stay unavailable. |
| Queue, search and badge | Default WAITING, oldest-first. Create >50 disposable rows; search across all selected-status pages by request/CPMS id/project/contractor/requester. Badge counts all WAITING independently of search/filter and updates after a decision. Failed refresh must not assert zero or silently truncate a queue (>2000 selected rows fails loudly). |
| Import / retry / read | New import 201 WAITING, null line answers and amount. Same id retry 200 current stored status, including DECLINED, with no rewrite or second mutation. Read-back/close never echo token, per-unit price, stock or internal released amount. CPMS supplies the import token credential; that input is not a read-back leak. |
| Mixed Accept | Every line explicitly true/false; false needs reason, at least one true. All-false Accept refused; whole Decline is separate. Acceptance reserves no stock/debt. CPMS approver remains distinct from POS reviewer. False line reason remains visible at till and CPMS. |
| Full / partial / rescan | Fresh R1001 FULL; short eligible lines leave PARTIAL and same token works after restock. Open shift required, FIFO and unit rounding preserved. Completing only true lines produces RELEASED with no “return on same token” advice, even with false-line positive outstanding. No false-line stock/sale. |
| Whole Decline | Required trimmed reason; all lines false, token spent without cashier. Verify and Release return REQUISITION_DECLINED before generic used-token error; WAITING gives REQUISITION_WAITING. No stock/debt mutation. |
| CPMS withdrawal | WAITING close → CLOSED, amount stays null; accepted/partial close preserves quantities/debt and abandoned shortfall budget. DECLINED close is no-op with reasons; CANCELLED remains 409. Repeated close is mutation-safe, not a promise of frozen live-price response. |
| Stale / concurrent decision | Double tap/submission guard; two reviewers or review vs close yield one decision, loser 409/reload. Verify is advisory; concurrent Close/Release must not release after closure. Timeout/unknown outcome reloads detail before actions re-enable; failed refresh keeps actions blocked. Saved decision + list-refresh failure must not invite a second decision. |
| Whole units (1d) | Server `is_whole` flag rules everywhere: 1.5 BAG refused in till dialog ("Use a whole number for BAG"), and by API for sale/hold/return/release/quote/order/PO/receiving/adjustment with `WHOLE_UNIT_QUANTITY`; CPMS fractional push refused, nothing stored; stored-id retry still 200. KG to 2 decimals. |
| Packaging units (1d) | Tile Adhesive KG + BAG (25 kg) prices independent; mixed sale totals exact; return refunds by line. Add/remove extra unit from details; Remove hidden for base and any used unit; confirm names unit and says it cannot be undone. Base price field shows base-unit price. No opening stock in Add product. Location shown with "Saved on this device only". |
| Budget vs debt | 10 at 10.00, release 4 → 40.00 payables; price remaining 6 at 12.00 → 112.00 budget. Payment changes payables only. Closed-after-accept keeps budget, not release permission. Round outstanding sum once HALF_UP. Historical unknown stays null after more release; UI says unavailable, not zero. |

## Out of bounds

- Dev or production writes, migrations, reseeds and resets without owner approval; no automatic flush or destructive cleanup.
- CPMS repository changes, real external services/payments, outbound integration, new config/scripts or reconciliation tooling.
- Phase 1d live QA did not test genuine browser text scale 1.3 (goldens only) or concurrent unit-removal races (deterministic PostgreSQL tests only).
- Phase 1b closure accepts the documented missing checks, not a claim they passed. Contracts stay provisional; closure does not authorize deployment, commits, dev writes or Phase 1c execution.
