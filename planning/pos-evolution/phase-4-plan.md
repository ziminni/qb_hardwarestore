# Phase 4 — Front counter: VAT, discount, split + cheque, pager, barcode masterlist, area switcher

**Status:** 🟡 Executing 2026-11-11 on `feat/pos-evolution-phase-4` (off Phase 1d `c8ef41f`). Decision: [18 Panel feedback](./decisions/18-panel-feedback-2026-11.md). Next: [Phase 5](./phase-5-plan.md).

## Goal

Panel comments #1 (till), #2, #4, #5, #6, #10-lite answered in working software; #3 and #12 demoed/answered (already built).

## Rules that bind every task

- Server is the trust boundary: VAT, discount cap, approval, cheque state and role checks live in Django; Flutter is UX.
- Money: `Decimal`, 2 dp, `ROUND_HALF_UP` once at the end; Flutter shows `formatPeso`, never `toStringAsFixed`.
- A test counts only after it fails without the fix (RED first, show output).
- Migrations are tested on the Django test DB only. **Never restart `buildpro_backend`** (entrypoint auto-migrates dev); never touch `buildpro_db` data.
- Copy: sentence case, no em dashes, refusal sentences say what to do next. Unknown server codes still refuse and show detail.
- Flutter: shared widgets first (`DataPanel`, `AppDialog` family, `InfoBanner`, `StatusBadge`); `flutter test --concurrency=2`; goldens regenerated only for intended changes and inspected.

## Orchestration (owner: major phases, one whole-change review + one QA)

Two lanes, at most two builders: **backend lane sequential** (B1 → B2 → B3), **Flutter lane** (F1, F2 first; F3–F5 after their backend task). Controller re-runs each task's tests before ticking. One `hygiene-reviewer` over the whole diff and one `qa-tester` run on an isolated stack at the end (Task 9).

## Execution checklist

- [ ] **B1 — 🤖 Store settings, VAT breakdown, capped discount, net refunds (backend).**
  - `StoreSettings` singleton (⚙ in `apps/pos`): `vat_registered` (default true), `vat_rate` (12.00), `discount_cap_percent` (10.00). `GET /api/v1/store-settings/` any authenticated; `PATCH` Admin only; audited.
  - Checkout (`apps/pos/services.py` `process_sale`, shared by held-cart and release paths): optional `discount {kind: AMOUNT|PERCENT, value, reason}`; discount ≤ gross; reason required when > 0. Above cap needs `discount_approval` token from `POST /api/v1/discount-approvals/` (Store Manager/Admin username + password checked server-side, never stored; returns a one-time signed token valid 5 min bound to the percent approved; cashier cannot self-approve). Codes: `DISCOUNT_REASON_REQUIRED`, `DISCOUNT_OVER_CAP`, `DISCOUNT_APPROVAL_INVALID`, `INVALID_DISCOUNT`.
  - VAT: when registered, `vatable_sales = round(net / (1 + rate/100))`, `vat_amount = net − vatable_sales`, net = gross − discount; non-VAT → vatable 0, vat 0, flag on response. CPMS release sales get the breakdown too (no discount).
  - Returns: refund per line = line gross × (sale net ÷ sale gross), rounded once per return; cumulative refunds never exceed what the sale was paid + owed.
  - Reports: discount totals return to sales reports (supersedes D12).
  - Tests: `docker exec buildpro_backend python manage.py test apps.pos apps.reports --noinput`; then full backend + `makemigrations --check`.
- [ ] **B2 — 🤖 Split payment + cheque pending until cleared (backend).**
  - `Payment.Method.CHEQUE`; cheque fields (number, bank, cheque date) required for cheque; `status` PENDING/CLEARED/BOUNCED (other methods CLEARED). Cheque only with a named customer (`CHEQUE_NEEDS_CUSTOMER`).
  - A pending cheque does not count as paid: the amount posts to the customer's utang ledger (same path as underpayment) linked to the cheque; credit-limit rule applies as today.
  - `POST /api/v1/cheques/{id}/clear/` → applies a ledger payment; `/bounce/` with reason → stays owed. Store Manager/Admin only; once-only (`CHEQUE_ALREADY_DECIDED` 409); locks; audited. `GET /api/v1/cheques/?status=` list.
  - Same cheque option for utang payments (collectibles), replacing free-text method with the shared choice (keep old rows readable).
  - Split tenders: multiple `payments[]` already accepted; add tests for cash+GCash+cheque, overpay change from cash only.
  - Tests: `apps.pos apps.collectibles`; full backend + drift check.
- [ ] **B3 — 🤖 Several roles per account (backend).** User serializer adds `roles[]` (all groups as frontend codes, stable order) keeping `role` (first, for old clients). User admin endpoints accept `roles[]`; existing `USER_ADMIN_FORBIDDEN` / `LAST_ADMIN` guards apply to every role added or removed; CPMS Service never combinable with staff roles. Tests `apps.users`; full backend.
- [ ] **F1 — 🤖 Pager on shared tables.** `DataPanel` gains client-side paging, 25 rows (⚙), "1–25 of 340" with previous/next and keyboard focus; resets to page 1 when rows or filters change; count pill still means rows shown after filter. Off for lists ≤ 25. Widget tests + affected goldens.
- [ ] **F2 — 🤖 Barcode masterlist export.** Products screen action "Barcode list" (Stock Manager, Store Manager, Admin): filter category/active; PDF (A4, product, variant, unit, price, code, scannable Code 128/EAN image via `pdf` barcode widget) through `printing`; CSV download (web) / save (desktop). Uses `getAll`. Tests: document builder unit test (rows, codes), CSV escaping.
- [ ] **F3 — 🤖 Store settings screen + area switcher + multi-role user admin** (after B1, B3). Admin Settings page edits VAT on/rate and discount cap (server-backed, replaces static constants). Login: one role → straight in; several → area picker; header "Switch area" menu; routes stay role-fenced on the active area; remembered last area per device. User management assigns several roles with server refusals shown.
- [ ] **F4 — 🤖 Till: discount, split tenders, cheque, VAT on receipt** (after B1, B2). Payment dialog: discount (₱/%, reason) with live net; over cap → approval dialog (manager credentials → token); several tender rows with remaining balance; cheque fields; walk-in cheque blocked with reason. Sale-complete, sale sheet, 80 mm receipt and reports show Discount, Vatable sales, VAT (or "Non-VAT"). Returns preview shows net refund.
- [ ] **F5 — 🤖 Cheque clearing queue** (after B2). Store Manager/Admin: Receivables → Cheques tab (pending first, oldest first): Clear / Bounce with reason, refusal handling, count marker. Utang payment dialog offers cheque.
- [ ] **D1 — 🤖 Role flow docs.** `docs/ROLE-FLOWS.md`: one mermaid flow per role (Cashier, Stock Manager, Store Manager, Admin, CPMS service) plus multi-role switching; for the manuscript and the defense. Answers #3 (low stock flow) and #12 (Store Manager = sales).
- [ ] **Task 9 — 🤖 Close.** Whole-change `hygiene-reviewer`; full gates (backend full + drift, `flutter analyze`, `flutter test --concurrency=2`, goldens with `--dart-define=RUN_GOLDENS=true`); one `qa-tester` run on an isolated stack (recipe: [QA-PROFILE](../../docs/testing/QA-PROFILE.md)); README/ENDPOINTS/atlas/QA-PROFILE; owner closure.

## Out of scope

Senior/PWD statutory discount; line-level discounts; cheque clearing for supplier cheques; full merged multi-role interface (Phase 2); server-side paged tables; BIR-accredited receipt format; Phase 1c.
