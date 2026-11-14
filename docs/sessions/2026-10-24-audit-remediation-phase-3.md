---
date: 2026-10-24
slug: audit-remediation-phase-3
---

# 2026-10-24 — Audit remediation Phase 3: Cashier

## Focus

Build Phase 3 of `planning/audit-remediation/MAP.md` from `phase-3-plan.md`, plus two problems the user reported: the admin staff list failing with `missing required object field "role"`, and buttons that do nothing. expressive-dev (deepseek-v4.1-flash) coded, hygiene-reviewer (glm-5.3-flash) reviewed, and qa-tester (gpt-6-luna) probed the API and drove the Flutter web build in a real browser.

## What Was Built / Changed

| Commit | Change |
|---|---|
| `2703b7a` | `User.role` nullable → a role-less account shows a "No role" badge, not a failed list. Dead controls removed (New quotation / sales order / customer return) or wired (returns View sheet, Forgot-password dialog, shared read-only Notifications sheet, period label). Action buttons with no callback render disabled. `no_dead_controls_test.dart` added |
| `159032a` | Material release requires and attaches the cashier's OPEN shift (400 `NO_OPEN_SHIFT`, nothing written); counts in Z gross, not the drawer |
| `cf82154` | `held_cart_count` on shift current/close/Z (advisory, close not blocked) |
| `3c1ed1e` | Returns policy: shift, linked-only for cashiers (`UNLINKED_RETURN_FORBIDDEN`), reason, per-selling-unit qty cap under a lock on the original row, `RELEASE_NOT_RETURNABLE`/`RETURN_OF_RETURN`/`ORIGINAL_NOT_COMPLETED`. Debt-first refunds (`RETURN_CREDIT` ledger payment, cash only for the excess) with `refund_summary`. `?q=` lookup and `returnable/` |
| `8ad794f` | Till **Returns** tab `/pos/returns` (index 6); release page Go-to-Shifts; close-dialog held-cart advisory |
| `fec0fca` | Dead-control guard hardened: multi-line, async, arrow, comment-only bodies, any `on*` callback |
| `9dbb85e`, `0d40da7` | Shifts tab can open a shift; shows "This shift so far" instead of the last closed reading. The open-shift dialog now carries its viewmodel |
| `19c832b` | CORS allows `Idempotency-Key`; the browser preflight was blocking every web checkout |
| `b3af484` | `TenderMethod` enum — the till sends `CASH`/`GCASH`/`CARD`, not display labels |
| `bb483a7` | Migration `pos.0010` normalises legacy `'Cash'` rows; ledger payment method validated (`INVALID_PAYMENT_METHOD`) |
| `ccc9383` | A resumed held cart completes via `held-carts/{id}/complete/` (unchanged) or `transactions` + delete (edited); it can no longer be sold twice |
| `71ab5fb` | An underpaid receipt shows "Balance due (utang)", not negative change |

## Mistakes & Gotchas (Do Not Repeat)

- **Since Phase 1 the browser till could not sell at all.** Two latent defects stacked: the payment dialog sent `'Cash'`, which Phase 1's strict validation rejects, and CORS didn't allow `Idempotency-Key`. Phase 1 QA used curl with correct codes, and widget tests passed `'CASH'` directly. **Every phase gate now includes a browser E2E that rings a real sale.**
- A test harness that hoists a provider above `MaterialApp` hides `ProviderNotFoundException` in dialogs, because pushed routes can't see page-scoped providers. Mirror `main.dart` in test harnesses, and pass page viewmodels into dialogs explicitly.
- `pkill -f <pattern>` kills your own shell when the pattern appears in the command line. Kill by PID.
- Interrupted test runs leave a crashed `manage.py test` holding test-DB locks. Use `--noinput`, and kill stale processes in the container.
- Long subagent runs died on network errors twice. Split gate work into smaller agents (backend/Flutter review, API/UI QA).
- Flutter web semantics: enable them with real pointer events on `flt-semantics-placeholder`. A JS `.click()` does nothing. Use a 1920×1080 viewport.

## Decisions

Rulings are in `.superpowers/sdd/audit-remediation/progress.md` (`P3` lines): a groupless account is legitimate, so the role field is nullable. A reason is required on every return. The qty cap is per selling unit (pre-linkage sales had no cap). Debt reduction is recorded as `RETURN_CREDIT`. Resume completes via `complete/` only when the basket is unchanged.

Deferred minors: holding a resumed cart leaves the original parked cart; stale receipt line "Inventory quantities were updated in the current app session."; `PosCheckoutResult` is defined twice; `held_cart_count` N+1 on the shift list; a 1280×576 viewport clips far-right actions; the categories page is still mock (Phase 4); no per-row assign-role UI (Phase 5).

## Wins & Next Step

- Gate: backend **383/383** (`--noinput`), check + makemigrations clean, flutter **694/694**, analyze clean. Hygiene APPROVED (backend + Flutter). API QA A1–A6 PASS. Final browser E2E all PASS: open shift → CASH + GCASH sales → credit sale → debt-first return (314 debt / 1 cash) → release → held cart unchanged + edited → Z matched API, variance 0. The manager recorded a payment. Every tab and control for all 4 roles was clicked: no dead button, and the staff list shows "No role".
- The dev DB holds QA rows (transactions up to `TRX-20261024-0042`, requisitions 6–11, customers 5–6, carts). The cashier has open shift 18 (₱500). Re-seed for a clean demo.
- **Next:** `git push` (user). Then write `phase-4-plan.md` and BUILD Phase 4 (Stock Manager: live product/category CRUD, low-stock on sale/release + dedup, goods-receipt history, alert resolve UI, persisted supplier toggle).
