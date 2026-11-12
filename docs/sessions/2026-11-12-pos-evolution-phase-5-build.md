# POS evolution Phase 5 — build and verification handoff

## Status

**Phase 5 ✅ Done — owner-closed 2026-11-12; BAG validation-text fix reviewed and freshly widget-verified.** Branch `feat/pos-evolution-phase-5`, based on Phase 4 closeout `9828b9b`. No Phase 5 commit or push performed. Current task/evidence status belongs in [the Phase 5 plan](../../planning/pos-evolution/phase-5-plan.md); this note records the verification checkpoint, not approval to deploy.

B1–B4 and F1/F2/F4 are implemented and reviewed. F3's till/held-cart/queue/slip scope is reviewed, and the 2026-11-12 owner decisions resolved the sales-order gate: **a create-only sales-order form is now built** (named customer, active catalogue lines, optional Deliver; no edit, delete, status change or fulfil-to-sale UI, and the View sheet stays read-only). The same decisions **confirmed the delivery-fee rules** (zero fee allowed; the discount cap and return refund exclude the fee; a fee is not refunded; a sales-order fee lives only on its Delivery row) and **accepted the recorded verification limits** rather than passing them. **Superseding owner decision (2026-11-12):** close Phase 5, keep sales-order line unit prices editable with catalogue defaults, fix truncated BAG validation text, then commit locally after verification; do not push. Fresh BAG-fix verification is complete; committed locally as `864a667`. Earlier owner gates below are historical, not current blockers. No dev startup/migration/reset or next phase authorized.

## Implemented scope

- Package-unit PO lines and receiving; stock converts to base units, cost converts per base unit. Unrepresentable base quantities refuse before writes; cost rounding is unchanged.
- Supplier terms, PO discount/VAT snapshots, receipt-created immutable bills, partial payments, history and supplier summaries. Supplier cheques are paid on issue, unlike pending customer cheques. No retroactive bills for previously processed receipts.
- Delivery fee after goods discount, server-authoritative VAT/change/debt, goods-only refunds; forward-only delivery actions, cashier own-slip reads, queue and generated-slip UI.
- Admin-managed Store/Bodega location metadata; product picker/details and till/receipt/slip pickup labels. Existing inactive assignments remain readable; inactive new assignments/defaults refuse. No per-location stock or transfers.

## Final verification — BAG follow-up complete

Quantity `InputDecoration.errorMaxLines: 4` fixes the truncation. Expressive-dev added a real **760 / 1.3** layout regression asserting `RenderParagraph.didExceedMaxLines == false`, witnessed **RED: expected false, actual true** before the fix, then **GREEN: 18 focused / 200 sales** tests. Independent hygiene reviewer `bfce393e` **APPROVED**, no blockers.

Fresh controller reruns: backend **1027 OK (851.654s)**; `manage.py check` clean; `makemigrations --check --dry-run`: **No changes detected**; Flutter analyze clean; ordinary **1987 passed / 241 skipped**; separate goldens **241 passed unchanged**. Local, gitignored logs: `temp/p5/closeout/{backend,analyze,flutter,golden}.log`. This is **widget verification, not fresh browser QA or printing verification**; accepted limits remain unchanged.

## Historical verification checkpoint

Historical pre-BAG-fix controller commands and complete logs are local, gitignored evidence; these gates do not verify the requested follow-up:

| Gate | Result | Evidence |
| --- | --- | --- |
| Django full suite, isolated QA backend | 1,027 tests OK | `temp/p5/full/backend.log` |
| Django system check / migration drift | clean / no changes | Phase 5 full gate evidence |
| Flutter analyzer | no issues | `temp/p5/full/analyze-final.log` |
| Flutter ordinary suite | 1,986 passed, 241 goldens skipped | `temp/p5/full/flutter-final.log` |
| Separate golden comparisons | 241 passed; the sales-order form changed exactly 5 `m3-orders-*` captures, all 5 inspected | `temp/p5/goldens/final-compare.log` |
| Create-only sales-order live QA | Controller API probes 12/12 PASS; browser QA all PASS, one Low cosmetic | `temp/p5/qa/order-form/{probe_api.py,browser-report.md}` |
| Final source review | APPROVED implemented scope, no blocking source defects | `temp/p5/review/report.md` |

Four stale full-suite expectations were corrected **test-only**. Route loops now cover appended destinations, and the reorder fixture uses selling-unit ID501 distinct from variant ID8/base-UOM ID1. Add-product golden fixtures now supply active Store/Bodega and assert the picker is enabled with Store selected. Both fixes have reported RED/GREEN evidence and controller full-suite verification.

Exactly 52 golden captures changed against the backed-up masters. Controller visually sampled four distinct changed captures: Add product760/1.3, PO form1366, PO details760/1.3, Admin sidebar1440. This is **not** inspection of every capture. The create-only sales-order form later changed exactly five `m3-orders-*` captures, and **all five were inspected**. Masters and backup are gitignored/local, not committed or available automatically on another machine.

## Isolated live QA

Both initial lanes reported **no confirmed defects**:

- Buying/payables: browser package PO, partial receiving, bills/history, role fences, invalid payments, supplier cheque and concurrent overpayment guard. Controller independently reconciled three bills: total2400, paid880, balance1520. Evidence: `temp/p5/qa/buy/{report.md,controller-reconciliation.md}` plus screenshots.
- Delivery/locations: browser location lifecycle/sidebar and till receipt; API held-cart, cheque/utang, goods-only refund, status/role/ownership guards. Controller parsed48 initial sanitized HTTP entries (zero5xx) and independently asserted sale233.75, discount11.25, fee20, VAT25.04, change16.25 and refund213.75. Evidence: `temp/p5/qa/delivery/{report.md,controller-reconciliation.md,api/live.jsonl}` plus screenshots.

**Follow-up complete with print limit:** default Store deactivation/implicit-create refusal was verified with zero product/audit writes and Store restored active in `finally`; device-only shelf hint remained distinct from unchanged server location. Browser slip-print trigger produced no captured preview/download. Controller separately called the production OpenSans PDF builder using the recorded live delivery7 response: one test passed, generating an11,830-byte one-page80mm PDF whose required document/date/contact/address/quantity/unit/pickup/fee text passed extraction assertions. Installed PyPDF2 warned about indirect font widths, so extraction assertions normalize whitespace; this is not visual PDF legibility proof. Evidence: `temp/p5/qa/delivery/pdf-controller-verification.md`. **Owner-accepted limits, not passed checks:** browser/native/physical printing, visual PDF legibility, genuine browser1.3 text scaling and exhaustive keyboard/focus traversal.

### Create-only sales-order form (owner decision 2026-11-12)

Built in Flutter only; the backend was unchanged. The Store Manager sales-orders page gained a **New sales order** button opening `sales/widgets/sales_order_form_dialog.dart`: a named customer (walk-in excluded), lines of active catalogue products only (archived product/variant hidden, as at the till), a unit menu reading “Product · UNIT (Name)”, a whole-unit pre-check from the server's `uom_is_whole`, an editable unit price defaulted from the catalogue price (later owner-confirmed at closure), and an optional Deliver section (address, contact, phone, date defaulting to tomorrow, fee ≥ 0 at two decimals). It posts `POST /api/v1/sales-orders/` with no `status` (server `CONFIRMED`); the order and delivery are atomic. No new route, VM class or service file: new methods on `SalesService.createSalesOrder` and `SalesModuleViewmodel.createOrder`. Writers are Cashier/Store Manager/Admin by the server rule; the button lives in the Store Manager shell and a Stock Manager POST answers 403. Order View stays read-only; quotations still have no create UI.

Review APPROVED (twice, including three QA-found fixes — archived product offered/preselected, unit menu without product names, stale line heading — all fixed RED-first). Controller gates: analyzer clean, full Flutter **1,986 passed / 241 goldens skipped**, separate goldens **241 pass**, exactly 5 `m3-orders-*` captures changed and all 5 inspected. Live QA on the isolated stack: controller API probes **12/12 PASS** (`temp/p5/qa/order-form/probe_api.py`) and browser QA all PASS with no confirmed defect (`temp/p5/qa/order-form/browser-report.md`, screenshots and sanitized `api/*.jsonl`). It created `SO-20261112-0006` CONFIRMED (2 BAG × ₱275 + 2.5 KG × ₱12 = ₱580) with slip `DEL-20261112-0009` SCHEDULED (fee 30.00), refused a fractional BAG, blank delivery fields and a 3-decimal fee with no request, sent exactly one POST on a double-click, kept the View sheet read-only, and fitted at 760 with a recorded Tab order. **Historical Low cosmetic:** the whole-unit inline error truncated (“Enter a …”); owner-requested fix is now widget-verified in the final record above, not rechecked in a browser. **Known pre-existing gap:** the server still accepts an order or quotation line naming an archived product's unit if called directly; the client filters. Evidence is local and uncommitted under `temp/p5/qa/order-form/`.

## Recovery and environment boundary

Host/daemon interruption stopped containers and lost worker handles and `/tmp` transcripts; preserved files were inspected and bounded replacement workers completed B4/F4. B4 recovery fixed inactive implicit Store, specific name-constraint race mapping and sale-list N+1 lookups before final review/gates.

Only `buildpro_p1d_qa_{db,backend,web}` on `buildpro_p1d_qa_net` was restored; its backend entrypoint was confirmed to be `sleep infinity`. The five Phase 5 migrations were applied there only. QA API8001/web8091 were refreshed to current source before live probes. `runserver --noreload` needs an exact-process refresh after future source changes; see [QA profile](../testing/QA-PROFILE.md).

**Dev `buildpro_backend`/`buildpro_db` remain stopped. Do not start them without owner approval:** the backend entrypoint auto-migrates. Last known dev schema is Phase4; seed/data state is unverified. No dev reset, migration, reseed or restart, no CPMS edits, no cleanup and no next-phase work authorized/performed by this continuation. Pre-existing CPMS working-tree changes are unrelated and must not be staged with POS work.

## Docs and next action

README, role flows, QA profile and both atlases were refreshed. Controller independently re-derived48 routes,23 VM classes/24 VM files,23 ApiClient services/29 service files,15 feature directories,42 Django models and33 router registrations; inline atlas JS syntax and diff whitespace checks passed. HTML DOM/Mermaid rendering is not verified.

Controller corrected documentation-only errors in payment POST permissions, first-bill settlement arithmetic, zero-gross receipt billing and stale dev-schema/sidebar wording. Baseline framework-metadata/host-import diagnostic debt was not used as a reason for unrelated production refactoring.

Owner closed Phase 5 on 2026-11-12, confirmed editable sales-order line prices with catalogue defaults, requested the BAG validation-text fix and authorized a local commit after fresh verification, not push. The historical sections above remain evidence for the pre-fix scope only; the final BAG verification is recorded separately; fee rules and accepted verification limits are unchanged.

**Controller next action:** Task 9 complete; committed `864a667`. Committed locally as `864a667`; owner pushes. Dev startup/migrations/reset, deployment and next-phase work remain unauthorized; printing/scaling and other accepted missing checks remain unverified.
