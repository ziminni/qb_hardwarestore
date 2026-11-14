# POS evolution Phase 7 — sales-order lifecycle: build, gates, review and QA handoff

## Status

**Phase 7 🟡 In Progress — build, review, gates and isolated live QA complete; OWNER CLOSURE STILL PENDING.** Branch `feat/pos-evolution-phase-7`, from Phase 6 `f8071c2`. Decision [19 Sales-order lifecycle](../../planning/pos-evolution/decisions/19-sales-order-lifecycle.md); canonical plan/evidence [phase-7-plan.md](../../planning/pos-evolution/phase-7-plan.md). **No commit/push, no dev startup/migration/reset.**

## Scope delivered

An order became a promise with a status the client cannot write. `SalesOrder.Status` gained `PARTIAL`/`CANCELLED` (legacy `PROCESSING`/`READY` read as `CONFIRMED` via `effective_status`), with one transition table used as data: CONFIRMED → PARTIAL → COMPLETED, CONFIRMED → CANCELLED, PARTIAL → COMPLETED (cancel writes off the remainder). Every move is a server action under a `select_for_update` lock on the order row, atomic with one `SALES_ORDER` audit row. Managers edit (lines, notes, delivery) and cancel with a required reason; cashiers ring a CONFIRMED/PARTIAL order at the till through `process_sale` so every checkout guard runs unchanged, at the **order's agreed price**, with the **delivery fee charged once on the first fulfilment**. Two migrations: pos `0016_sales_order_lifecycle`, users `0006_sales_order_audit`. No new model class, route, VM or service file — two new widgets (`sales_order_cancel_dialog.dart`, `pos_open_order_dialog.dart`).

| Task | What it landed | RED evidence |
| --- | --- | --- |
| B1 | Status machine as data, `effective_status`, `cancel_*`/`fulfilled_qty`/`cancelled_qty`, `SalesItem.order_line`, `DiscountApproval.sales_order`, delivery check relaxed | legacy READY read as CONFIRMED; direct status write ignored |
| B2 | `guard_order_line_prices`: largest-line percent vs `discount_cap_percent`, token spent on the save, fresh token per edit | 6 failures — 50 %-below / bad-token / too-small-token saved 201 |
| B3 | `PATCH` edit (manager, CONFIRMED + nothing fulfilled, `reason` required) and `cancel/`; SCHEDULED slip → FAILED, held slip → 409 | 21 tests, 13F+9E — PATCH 405, cancel 404, no audit row |
| B4 | `fulfil/` through `process_sale` with `order_lines`; price from the order line, no sale-level discount, fee once, idempotent replay | 14 errors — 404 no-route pre-implementation |
| B5 | `available_qty` hint per line, walk-in order refusal, `DiscountApproval.sales_order`, ENDPOINTS rewrite | walk-in POST 201-vs-400; `KeyError available_qty` ×3 |
| F1 | Sales side: chips/badges for Partial/Cancelled, ordered/fulfilled/remaining + stock hint, manager Edit/Cancel, shared approval helper | controller re-witnessed via stash (missing-API errors) |
| F2 | Till side: open-order list, resumed-cart load with read-only prices and remaining cap, fee shown once, refusal codes inline | covered by the F2 widget suite |

## Gates (controller-owned, local + gitignored under `temp/p7/full/`)

| Gate | Result | Log |
| --- | --- | --- |
| Django full suite | **1138 tests OK** | `backend.log` |
| `manage.py check` | clean | `backend.log` |
| `makemigrations --check --dry-run` | **No changes detected** (no drift) | `backend.log` |
| `flutter analyze` | **No issues found!** | `analyze-final.log` |
| Flutter ordinary suite | **2039 passed / 241 skipped** | `flutter-final.log` |
| Goldens (`RUN_GOLDENS=true`) | **241 passed**, `GOLDEN=0` | `golden-final.log` |

**Ten golden captures changed, all inspected:** five `m3-orders-*` (order chips/labels gain Partial/Cancelled, legacy PROCESSING/READY badges now read Confirmed) and five `c1-*` (till header row only, 0.07–0.76 % diff). The other 231 are byte-identical.

## Review — CHANGES REQUIRED, then APPROVED after two fix rounds

`temp/p7/review/report.md` (round 1) found one **Important**: the delivery section was hidden in the order form's edit mode while `/deliveries/` is read-only for every role, so a wrong SCHEDULED fee could never be corrected though the backend already supported it. Fixed by exposing the section in edit mode and sending `delivery` from edit mode (RED `temp/p7/f1fix/red.log`). The second round fixed the QA Medium below. Verified clean at approval: lock ordering (order → items → slip, counter last), cancel-vs-fulfil serialising on the order row, fresh token per above-cap edit while the create-time approval stays spent, fee exactly once, and zero-write refusals.

**Retained, not fixed:** review Minors 2–5 — fulfil audit reads its before-state off the pre-lock snapshot; the edit path reads `order.deliveries.first()` without locking the slip (TOCTOU vs dispatch); a PATCH carrying `discount_approval` with no `items` silently ignores the token; `apps/users/models.py` carries ~120 lines of unrelated quote reformatting.

## Isolated live QA — 14/15 PASS, one Medium fixed and re-probed PASS

Ran on `buildpro_p1d_qa_{db,backend,web}` (`172.20.0.*`, API `:8001`, web `:8091`); pos `0016` / users `0006` applied to that isolated database only, dev containers stayed stopped, QA made no source edits and ran no suites. Report `temp/p7/qa/report.md`.

Passed: below-cap and above-cap order create; manager edit + cancel (CONFIRMED → CANCELLED and PARTIAL → COMPLETED); partial then final fulfilment with the fee on the first sale only and DB read-back of `fulfilled_qty`/status/Delivery links; split + cheque fulfilment; short-stock refusal writing nothing; a return of a fulfilment sale leaving the order COMPLETED; cashier and Stock Manager edit 403; walk-in order 400; archived unit 400; concurrent creates with distinct numbers; Phase 6 offline `Retry` proof at 1440/1100/760.

**The one FAIL was a Medium:** an above-cap create showed only inline text and never opened the manager approval dialog, though the direct API flow passed (two browser POSTs 400, no order created). Fixed by routing create and edit through one shared `_saveWithApproval` helper; **re-probe PASS** — 400 → approval dialog → exactly one 201 resubmit, `SO-20261113-0009` plus its CREATE audit row verified. **Accepted residual, not a defect:** the first-fulfilment payment preview omits the delivery fee while the server bills it once and the receipt is correct (the fee-404 preview residual).

## Retained warnings and limits

- `pos_service.dart fetchOrderDeliveryFee` catches every `DioException`, not just 404 — a server fault previews a 0 fee while the server still bills it.
- `_orderLineCaps` keyed by `variantUomId` — two order lines sharing a selling unit collide.
- The order-list prefetch lacks `items__variant_uom__uom`, so `available_qty` costs an extra query per line plus a batch aggregate per order (N+1).
- No DB CHECK on `fulfilled + cancelled ≤ qty` (deferred; needs pos 0017 — every writer holds the order lock).
- `flutter/lib/data/models/sale_transaction.dart` still documents `DELIVERY_NOT_SCHEDULED` where the order path answers `SALES_ORDER_NOT_EDITABLE` — doc drift noted for a follow-up fix.
- **Not covered, not claimed:** a live 1.3 text-scale run; golden inspection beyond the ten changed captures; inherited Phase 5 limits (browser/native printing, PDF legibility, browser 1.3, keyboard traversal) and the Phase 6 unverified rows (zero-stock badge, legacy null location / null PO-VAT); `[FULL-UI-E2E]` covered manager create/edit/cancel, cashier partial/final fulfilment and return, while split-cheque, short-stock and Stock Manager role checks were live API probes only.
- **Baseline diagnostics, not this phase's defects:** the pre-existing pyright noise in untouched files (atlas §6 records it) — do not read a green suite as a clean diagnostics verdict.

## Next

Owner closure (Phase 7 stays In Progress until then), then local commit only when told; owner pushes. Phases 8 → 9 → 3 → 2 follow in order.
