# QA Profile — BuildPro POS / Inventory

**Status: Phase 5 (back office) ✅ Done — owner-closed 2026-11-12. Owner confirmed editable order-line prices with catalogue defaults, requested the BAG validation-text fix and authorized a local commit after fresh controller verification, not push. BAG fix is independently approved and freshly widget-verified; committed locally as `864a667`. Historical gates/QA below predate that fix. Live QA: buying/payables lane completed, the delivery/location lane's initial pass completed, and the create-only sales-order lane completed, all with no confirmed defect (one Low cosmetic in the order dialog); Store/hint follow-ups and production-font PDF generation passed. Owner decisions 2026-11-12 added the create-only sales-order form, confirmed the delivery-fee rules and accepted the recorded verification limits — so browser/native/physical printing, visual PDF legibility, genuine browser 1.3 text scaling and exhaustive keyboard traversal remain accepted limits, not passed checks. Phase 4 ✅ done and owner-closed (five Minors deferred); Phase 1d ✅ done 2026-11-11; Phase 1b closed 2026-11-08 with owner-accepted QA limits; contract v0.3 provisionally accepted 2026-11-11.**

The [Phase 5 plan](../../planning/pos-evolution/phase-5-plan.md) owns current gate evidence and triage, and this page does not restate moving totals. What it does own is the **boundary between the kinds of evidence** in Phase 5:

| State | What it means | Where the evidence is |
| --- | --- | --- |
| **Final verification — BAG follow-up complete** | Quantity `InputDecoration.errorMaxLines: 4`; real 760 / 1.3 layout regression asserts `RenderParagraph.didExceedMaxLines == false`. Expressive-dev witnessed RED (expected false, actual true), then GREEN: 18 focused / 200 sales tests. Reviewer `bfce393e` APPROVED, no blockers. Fresh controller: backend **1027 OK (851.654s)**, check clean, migration drift **No changes detected**, analyze clean, ordinary **1987 passed / 241 skipped**, goldens **241 passed unchanged**. Widget verification only, not fresh browser QA or printing proof. | local, gitignored `temp/p5/closeout/{backend,analyze,flutter,golden}.log`; plan Task 9 |
| **Historical automation — completed before BAG follow-up** | Full backend suite **1027 tests OK**, `check` clean, no migration drift; `flutter analyze` clean; full ordinary Flutter suite **1986 passed / 241 goldens skipped**; goldens run separately **241 PASS**. The Phase 5 build changed **52 intended captures** (four of those inspected visually — an accepted sampling limit); the create-only sales-order form changed exactly **5 `m3-orders-*` captures, all five inspected**. | local, gitignored `temp/p5/**` (`temp/p5/full/{flutter-final.log,analyze-final.log}`); plan Task records |
| **Live QA — buying/payables lane COMPLETED** | The isolated QA lane for packages, receiving and supplier payables ran end to end with **no confirmed defects**. Reported in local `temp/p5/qa/buy/report.md`. | local, gitignored — **not committed**; details below |
| **Live QA — delivery/location lane completed with print limit** | No confirmed defects. Store-default refusal/restoration and local shelf-hint follow-ups passed. Controller separately generated an 80 mm PDF with production fonts and verified text; browser/native printing, visual PDF legibility, genuine browser 1.3 text scaling and exhaustive keyboard traversal remain owner-accepted limits, not passed checks. | local `temp/p5/qa/delivery/{report.md,pdf-controller-verification.md,api/live.jsonl}` — **not committed** |
| **Historical live QA — create-only sales-order lane COMPLETED** | Controller API probes **12/12 PASS**; browser QA all PASS with no confirmed defect; one **Low cosmetic** (whole-unit inline error truncates to “Enter a …”). Covers create with delivery, fractional/blank/3-decimal refusals, double-click, read-only View sheet and 760 layout. Evidence: local `temp/p5/qa/order-form/{probe_api.py,browser-report.md,api/*.jsonl,screenshots/}`. | local, gitignored — **not committed**; details below |
| **Owner decisions — RECORDED 2026-11-12** | The sales-order entry is **create-only** (named customer, catalogue lines, optional Deliver; **no** edit, delete, status change or fulfil-to-sale UI, Order View sheet stays read-only). The delivery-fee rules are **owner-confirmed**: zero fee allowed; discount cap and return refund exclude the fee; a fee is not refunded; a sales-order fee lives only on its Delivery row. The recorded verification limits are **accepted**, not passed. Later owner decision closed Phase 5, confirmed editable catalogue-default unit prices and requested the BAG validation-text fix; fresh controller verification is complete; committed locally as `864a667`; owner pushes. | [Phase 5 plan](../../planning/pos-evolution/phase-5-plan.md) F3 row and Task 9; [session note](../sessions/2026-11-12-pos-evolution-phase-5-build.md) |

Anything under `temp/` is **local and uncommitted**: cite it as local evidence, never as a repository artifact. Automated tests are not live QA evidence, and a green suite is not a coverage claim. **Owner closure is distinct from QA proof:** Phase 5 is owner-closed; the three historical live-QA lanes and the Low truncation below predate the requested BAG fix. Fresh controller widget verification is complete; no new live browser QA is claimed. Recorded verification limits remain accepted missing checks, not passes.

### Phase 5 live QA — buying / payables lane (completed, local evidence)

Run on the isolated QA stack against current source with **no confirmed defects**; QA source was left unchanged, dev stayed stopped, and the isolated records were retained. Evidence: `temp/p5/qa/buy/report.md` (local, uncommitted).

| Step | Result |
| --- | --- |
| PO by package in the browser | A line of **10 BAG**, factor 25, unit cost 250; three **partial receipts of 2 + 3 + 5** produced **250 base units at 10 each** — the package-ordered quantity and the base-unit landed cost both matched |
| PO discount and net | Gross **2500**, discount **100**, net **2400**, as displayed and stored |
| Bills created at Receiving | **Three** bills — **480 / 720 / 1200** — one per processed receipt, summing to the discounted 2400 |
| Settlement on the first bill | **100 CASH + 80 BANK + 300 CHEQUE = 480** settled the first bill; the separate 400 payment on bill two brought total paid to 880 |
| Concurrent payments on the second bill | A simultaneous pair of 400 payments produced **one 201** and **one 400 `OVERPAYMENT`** — the losing request changed nothing |
| Independent read-only ORM check (controller) | **3 bills**, discount **100**, total **2400**, paid **880**, balance **1520** — all PASS |
| Screens reviewed | PO form and the Payables page at **760** width |
| Tiny-unit edge | A **0.001 conversion factor was refused at 2 decimals**, so the probe used a **0.0001 KG** receipt instead — recorded as observed behaviour, not a defect |

Not covered by this lane and not claimed: deliveries and storage locations (separate lane, below), the create-only sales-order form (separate lane, below), large-text widths beyond the two screens listed, and paper printing of any slip or receipt.

### Phase 5 live QA — delivery / location lane (follow-up completed with print limit)

Run on the same isolated stack with **no confirmed defects**; evidence `temp/p5/qa/delivery/report.md` and `temp/p5/qa/delivery/api/live.jsonl` (local, uncommitted).

| Step | Result |
| --- | --- |
| Cashier sale with delivery, in the browser | Goods **225**, discount **11.25**, delivery fee **20** → total **233.75** |
| VAT / tender arithmetic | VAT **25.04** over the fee-inclusive total, cash **250**, change **16.25** — the receipt added up |
| API goods refund | **213.75** (225 − 11.25), i.e. the fee is **not** part of a goods refund |
| Fee in the money paths | The **cheque and utang** checks include the fee, so the customer's debt and the pending-cheque claim both see the fee-inclusive total |
| Guards | Role, own-scope and delivery **status** guards all PASS (a cashier cannot move a delivery; a foreign slip is not readable) |

**Follow-up:** inactive default Store now verified live: omitted-location create returns400 `INVALID_STORAGE_LOCATION` with no product/audit writes; Store restored active in `finally`. Device-only shelf note is separate from server `stored_at`, which stayed unchanged. Browser print trigger produced no captured preview/download. Controller separately called the production OpenSans PDF builder using the recorded live delivery: one80mm page with document/date/contact/address/unit/quantity/pickup/fee text verified (`pdf-controller-verification.md`). **Not established (owner-accepted limits, not passed):** browser/native/physical printing, visual PDF legibility, genuine browser 1.3 text scaling and exhaustive keyboard traversal.

### Phase 5 live QA — create-only sales-order form (completed, local evidence)

Run on the same isolated stack (`buildpro_p1d_qa_{db,backend,web}`, API :8001, web :8091) against current source with **no confirmed defect**. Controller API probes: `temp/p5/qa/order-form/probe_api.py`, **12/12 PASS**. Browser QA: `temp/p5/qa/order-form/browser-report.md` with screenshots and sanitized `api/*.jsonl` — local, uncommitted.

| Step | Result |
| --- | --- |
| Form catalogue and prior regressions | **PASS** — unit menu reads “Product · UNIT (Name)” (e.g. `Tile Adhesive Standard · BAG (Bag)`); an archived product is not offered; customer choices exclude Walk-in; switching product/unit updates the line heading |
| Store Manager create with delivery | **PASS** — `SO-20261112-0006` written **CONFIRMED** with lines 2 BAG × ₱275 and 2.5 KG × ₱12 (total ₱580); delivery `DEL-20261112-0009` is SCHEDULED, fee 30.00, linked to that order; order and delivery read back 200 |
| Fractional whole unit | **PASS** — 1.5 BAG shows `BAG is sold in whole numbers…`, form stays open and **no request** is sent |
| Delivery refusals | **PASS** — blank address/contact/phone and a 3-decimal fee (`10.005`) refuse in the form with **no request** |
| Double-click Create | **PASS** — exactly one `POST /api/v1/sales-orders/` 201 and exactly one stored row |
| Read-only surfaces | **PASS** — the order View sheet says “A saved record, read only.” with no edit/delete/status action; Quotations has no create action |
| 760 width and keyboard | **PASS** — long line, unit, quantity and Deliver fields fit without horizontal clipping; recorded Tab order reaches the form controls in sequence |
| Roles | **PASS by API probe** — a Stock Manager reads sales orders and its **POST answers 403**; the page probe was skipped because Sales orders is not in the Stock Manager sidebar (its “Sales” page is) |
| Historical Low cosmetic | The whole-unit inline error truncated to “Enter a …” in the dialog. Owner-requested fix now independently approved and widget-verified at 760 / 1.3; no fresh browser rerun |

**Limits:** no browser 1.3 text scale or 1100 px pass, and no browser printing/slip output check. **Pre-existing server gap, unchanged:** a direct API call can still create an order or quotation line naming an archived product's selling unit; the client filters but the server does not refuse it.

## How to run

- Canonical setup, commands and normal ports: [README setup](../../README.md#1-start-the-backend), [ports](../../README.md#ports), [client connection](../../README.md#connecting-the-client).
- **Dev is the demo DB** and its containers are **STOPPED after the host restart**. Do not treat a dev restart as safe: the entrypoint runs `migrate` on every start and would apply the pending Phase 5 migrations (`inventory` 0009–0011, `pos` 0015, `users` 0005) to the demo database. That needs owner approval each time; even login failures/audits and refresh rotation write state, and probes consume seeded tokens. Dev's last known state is the Phase 4 schema; seed state unverified.
- The backend entrypoint runs `migrate` on every start. No implicit flush, reseed or cleanup.

### Isolated QA stack (the only migrated database)

Phase 5 QA runs on `buildpro_p1d_qa_{db,backend,web}` on `buildpro_p1d_qa_net` (**`172.20.0.*`**), API **:8001**, web **:8091**, volume `buildpro_p1d_qa_pgdata`, restored by the assistant after the host restart and migrated to current source. Same recipe as below; web built with `--dart-define=API_BASE_URL=http://127.0.0.1:8001`. Verify the network before any QA write: QA containers on `172.20.0.*` only, dev (whenever the owner starts it) on `qb_pos_inventory_system_default` (`172.19.0.*`).

**Harness traps (agent-browser on Flutter web):** enable semantics by JS-dispatched click on `flt-semantics-placeholder`; click the semantics-box **centre** of a button (edge clicks hit the dialog barrier and look like "dialog closed"); click then `keyboard type`, not `fill`; scroll with dispatched `WheelEvent`. CSS `zoom` makes the canvas wider than the window and clips everything: it is **not** a 1.3 text-scale test.

**Stale QA server trap — exact-PID rule:** the QA backend runs `runserver --noreload`, so new code on the mounted source is NOT loaded. After code changes or migrations, restart only that process inside `buildpro_p1d_qa_backend` (no `kill` binary): find the PID by exact argv (`python -c` over `/proc/*/cmdline` checking `argv[:2]==['python','manage.py']`), then `python -c "import os,signal; os.kill(PID, signal.SIGTERM)"`, then `docker exec -d ... runserver 0.0.0.0:8000 --noreload`. **Never** `grep runserver` / `case *runserver*`: that matches the search shell itself, so the old server survives and the new one dies with "port already in use". Check a new route answers 401 rather than 404, confirm `/tmp/runserver.log` starts with "Performing system checks", and rebuild the web into `temp/p1d/qa/web/`. Symptom of forgetting: new routes 404 and writes 500 (e.g. a new NOT NULL column inserted as null).

Phase 1d stack evidence stays in local gitignored `temp/p1d/qa/` (`report.md`, `browser/`, `repro/`, `stocker/`, `mgr/`). Phase 1b stack was removed 2026-11-09 with owner approval; its evidence stays in `temp/p1b-qa/` (`report.md`). Recipe if needed again: [settings.py](../../backend_django/config/settings.py) hardcodes host `db`, so **environment DB overrides will not redirect the app**; isolate by network instead (separate network, PostgreSQL container aliased `db` on its own volume, no published port, backend from the same image with source read-only, static web on :8091). Confirm zero public tables and that `db` resolves away from `buildpro_db` before `migrate` + `seed_demo`.

Production rollback is backup/forward-fix, not reversing the no-op data migration (see contract rollout section).

## Test accounts (seeded, non-production)

Use [README demo accounts](../../README.md#demo-accounts) for all five usernames, passwords and role capabilities; do not maintain a second credential list here. Use [README fresh-seed scenarios](../../README.md#2-load-demo-data) for expected R1001–R1005 states and token instructions. R1001–R1005 scenarios and repeat-seed safety are test-DB-verified. QA runs on its own seeded database; the dev copy was reseeded 2026-11-09 (later probes may have changed it, and its containers are now stopped).

## API conventions

[ENDPOINTS §1](../../ENDPOINTS.md#1-base-url--authentication) owns JWT/header, refresh, pagination and error handling. [ENDPOINTS §3.6](../../ENDPOINTS.md#36-appsrequisitions--projects-the-cpms-copy-tokens) owns staff review/scanner routes; [§3.7](../../ENDPOINTS.md#37-appsintegration--the-cpms-boundary-machine-caller-only) and the [CPMS contract](../integration/CPMS-CONTRACT.md) own the six service endpoints and refusal policy. Phase 5 adds `supplier-bills`, `supplier-payments`, `suppliers/payables`, `deliveries` and `storage-locations`; `POST /supplier-payments/` records a payment; `POST /supplier-bills/` and `POST /deliveries/` are 405 because receipts and sales/orders create those records. Bill/payment PUT/PATCH/DELETE are also 405. Follow pagination beyond 50 rows; unknown response fields are ignored and unknown business codes remain refusals, showing detail.

## Domain rules and repeat-QA checklist

Completed live QA before Phase 5 covered scale 1.0 at all three widths. Owner-accepted limits: live browser 1.3 blocked; till 1.3 unverified; live timeout/unknown-outcome and simultaneous Close-vs-Review not injected. Queue/dialog 1.3 widget coverage is not live browser proof. Sidebar label truncation at 1440 was fixed by renaming it "Project requests" (verification: see plan); the Review wrap at 1100 was fixed 2026-11-09.

For repeat QA, run browser QA with the **agent-browser skill**, not ad hoc browser tooling. Cover widths **1440 / 1100 / 760** at text scales **1.0 / 1.3**, including keyboard/focus, scrollable list/dialog, long reasons, visible actions and status text not color alone. Record actual commands, results, screenshots and skips; automated goldens do not establish live large-text behavior.

| Probe | Expected invariant |
| --- | --- |
| Role fences / Admin twin | Manager and Admin can open sidebar Project requests at their respective routes; cashier/stocker cannot. Phase 5: Payables opens in all three shells but only Store Manager/Admin see a pay action; Storage locations is Admin-write, everyone-read; a Cashier has no Deliveries page and a foreign slip is 404. CPMS token cannot use staff actions (`403 CPMS_SCOPE`); staff cannot call integration endpoints. Retired approvals/generic writes stay unavailable. |
| PO by package | A PO line names its unit; "10 BAG at ₱250" receives 10 BAG and raises stock by 250 kg at ₱10/kg base landed cost. A quantity not exactly representable in two-decimal base stock is refused `RECEIPT_QUANTITY_UNREPRESENTABLE` with nothing written. Editing a referenced unit's factor does not re-measure existing orders. |
| Supplier bills and payments | Processing a positive-gross receipt writes exactly one bill; a zero-gross delivery writes none; a receipt processed before B2 has no bill. Partial payment reduces the balance and appears in the supplier total; overpay refuses `OVERPAYMENT`, a paid bill refuses `BILL_PAID`; the loser of two concurrent payments changes nothing. Bill POST and bill/payment PUT/PATCH/DELETE answer 405; payment POST is supported. |
| Delivery lifecycle | A till sale with Deliver shows address/contact/date/fee and the fee as a "Delivery charge" line; the fee is never discounted while the goods discount applies; VAT/change/utang/cheque all use the fee-inclusive total. Scheduled → Out for delivery → Delivered works; Failed requires a reason; a stale move reloads instead of retrying; no `POST /deliveries/`. The slip lists items and each pick-up point. |
| Stored at (bodega lite) | Product form preselects the default **Store**; details shows and can change it; the till line, receipt and delivery slip print the pick-up point. Admin adds/renames/deactivates a place; a deactivated place keeps labelling existing products and is excluded from new assignment; there is no DELETE. No per-location stock counts or transfers exist. |
| Queue, search and badge | Default WAITING, oldest-first. Create >50 disposable rows; search across all selected-status pages by request/CPMS id/project/contractor/requester. Badge counts all WAITING independently of search/filter and updates after a decision. Failed refresh must not assert zero or silently truncate a queue (>2000 selected rows fails loudly). |
| Import / retry / read | New import 201 WAITING, null line answers and amount. Same id retry 200 current stored status, including DECLINED, with no rewrite or second mutation. Read-back/close never echo token, per-unit price, stock or internal released amount. CPMS supplies the import token credential; that input is not a read-back leak. |
| Mixed Accept | Every line explicitly true/false; false needs reason, at least one true. All-false Accept refused; whole Decline is separate. Acceptance reserves no stock/debt. CPMS approver remains distinct from POS reviewer. False line reason remains visible at till and CPMS. |
| Full / partial / rescan | Fresh R1001 FULL; short eligible lines leave PARTIAL and same token works after restock. Open shift required, FIFO and unit rounding preserved. Completing only true lines produces RELEASED with no "return on same token" advice, even with false-line positive outstanding. No false-line stock/sale. |
| Whole Decline | Required trimmed reason; all lines false, token spent without cashier. Verify and Release return REQUISITION_DECLINED before generic used-token error; WAITING gives REQUISITION_WAITING. No stock/debt mutation. |
| CPMS withdrawal | WAITING close → CLOSED, amount stays null; accepted/partial close preserves quantities/debt and abandoned shortfall budget. DECLINED close is no-op with reasons; CANCELLED remains 409. Repeated close is mutation-safe, not a promise of frozen live-price response. |
| Stale / concurrent decision | Double tap/submission guard; two reviewers or review vs close yield one decision, loser 409/reload. Verify is advisory; concurrent Close/Release must not release after closure. Timeout/unknown outcome reloads detail before actions re-enable; failed refresh keeps actions blocked. Saved decision + list-refresh failure must not invite a second decision. |
| Whole units (1d) | Server `is_whole` flag rules everywhere: 1.5 BAG refused in till dialog ("Use a whole number for BAG"), and by API for sale/hold/return/release/quote/order/PO/receiving/adjustment with `WHOLE_UNIT_QUANTITY`; CPMS fractional push refused, nothing stored; stored-id retry still 200. KG to 2 decimals. |
| Packaging units (1d) | Tile Adhesive KG + BAG (25 kg) prices independent; mixed sale totals exact; return refunds by line. Add/remove extra unit from details; Remove hidden for base and any used unit; confirm names unit and says it cannot be undone. Base price field shows base-unit price. No opening stock in Add product. Shelf note remains device-only; Phase 5 Stored at is shared server metadata, not that local hint. |
| Budget vs debt | 10 at 10.00, release 4 → 40.00 payables; price remaining 6 at 12.00 → 112.00 budget. Payment changes payables only. Closed-after-accept keeps budget, not release permission. Round outstanding sum once HALF_UP. Historical unknown stays null after more release; UI says unavailable, not zero. |

## Out of bounds

- Dev or production writes, migrations, reseeds and resets without owner approval; no automatic flush or destructive cleanup. Dev is stopped: do not start it to "check something" without approval.
- CPMS repository changes, real external services/payments, outbound integration, new config/scripts or reconciliation tooling.
- Phase 5 live QA does not cover per-location stock counts or transfers (out of scope by decision), driver/vehicle routing, or supplier cheque clearing.
- Phase 5 owner closure is recorded, not a new QA pass: browser/native/physical printing, visual PDF legibility, genuine browser 1.3 text scaling, exhaustive keyboard traversal and non-sampled golden inspection remain **owner-accepted limits**, not passed checks. Phase 1d/1b limits and provisional contracts stay as recorded. Committed locally as `864a667` after BAG-fix verification; owner pushes; no push, deployment, dev startup/migration/reset or next phase authorized.
