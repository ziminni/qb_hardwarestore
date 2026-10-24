---
date: 2026-10-24
slug: audit-remediation-phase-2
---

# 2026-10-24 — Audit remediation Phase 2: access control & audit

## Focus

Build Phase 2 of `planning/audit-remediation/MAP.md` from `phase-2-plan.md`: Admin group authority, role-scoped sales/receivables/held-cart data, alert resolution, append-only business audit — plus every security gap found while researching it. expressive-dev (deepseek-v4.1-flash) coded, hygiene-reviewer (glm-5.3-flash) reviewed, qa-tester (gpt-6-luna) probed live.

## What Was Built / Changed

| Commit | Change |
|---|---|
| `cc5b702` | `IsAdminUser` → `IsAdminRole` on register/users/audit; `is_staff` read-only via API; `DELETE /users/` 405; `LAST_ADMIN` guard |
| `db0627a` | `SalesReadPOSWrite` / receivables readers; cashier sees own transactions/payments/receipts (404 otherwise); held carts POS-only; ledgers read-only; ledger-payments create/read only; `CREDIT_LIMIT_FORBIDDEN`; customer delete manager-only (`CUSTOMER_IN_USE` 409) |
| `2117b82` | Material-token secrecy (requisitions/tokens/req-items readable by manager/admin + own foreman only; token null for others); verify needs POS role; `SELF_APPROVAL`; `REQUISITION_LOCKED` after DRAFT |
| `db79b8b` | Alerts read-only + `resolve` for inventory role with `resolved_by`/`resolved_at` (migration `inventory.0004`); `ALERT_ALREADY_RESOLVED` |
| `cd6f704` | Append-only `AuditLog` (save/delete/queryset update/delete raise; admin read-only; `user` PROTECT; `username_snapshot`, migration `apps_users.0002`); 20 action types written in-transaction for every business event |
| `8906dce` | Login lockout (5 fails / 15 min per identifier+IP → 429 `LOGIN_LOCKED`); `token_blacklist` installed; logout revokes the caller's refresh; rotation reuse 401 |
| `c7c86c6` | Flutter: persist rotated refresh token, logout sends refresh, lockout + self-approval messages |
| `5c0423d` | Review fix pass: completed sales immutable (no PUT/PATCH/DELETE — was Critical), requisition `status` action-only, last-admin guard under `select_for_update`, cashier returns only own originals, req-items parent ownership |

Docs: `ENDPOINTS.md` role matrix + auth/shift rows, `decisions/02-data-scoping.md` as-built note, MAP Phase 2 ✅.

## Mistakes & Gotchas (Do Not Repeat)

- **The worst hole was not on the audit list:** `SalesTransactionViewSet` was a full `ModelViewSet`, so any POS user could PATCH a completed sale's total or DELETE it. Every money-record viewset now declares `http_method_names` explicitly.
- `BLACKLIST_AFTER_ROTATION=True` silently did nothing until `rest_framework_simplejwt.token_blacklist` was installed. Once it works, Flutter **must** persist the rotated refresh token, or the second refresh logs the user out (fixed in `c7c86c6`; refresh now uses the shared `dio`, so it is testable).
- App label is `apps_users`, not `users`: `makemigrations apps_users`.
- After an interrupted run, `manage.py test` prompts to delete the leftover test DB → `EOFError`. Use `--noinput`; `--keepdb` reuses a pre-migration DB and fails spuriously (qa-tester hit `errors=36`).
- `login_view` is `AllowAny`: audit helpers must take the validated user explicitly, or LOGIN rows get no actor.
- `GenericIPAddressField` rejects `''`; store `None`.
- simplejwt 5.5.1 already refuses a deactivated user's refresh (401) — no custom serializer needed.
- LocMem cache is per process: the lockout counter needs a shared cache in production.
- Plan said stocker sees RETURN transactions only, but the built stocker Sales tab reads all sales → ruled: inventory role reads all sales, not receivables.

## Decisions

Rulings (full list in `.superpowers/sdd/audit-remediation/progress.md`, `P2` lines): stocker reads all sales; token secrecy, money-record immutability, credit-limit write restriction, requisition lock, user delete disabled, login lockout + revocation added as research findings; alert resolve uses `IsInventoryRole`; reject-own requisition allowed; alert-resolve UI deferred to Phase 4.

Deferred minors: lockout username/email alias = 2 buckets; quotation/sales-order `status` writable; `seed_demo` prints a token UUID; `AuditLog.objects.bulk_create` bypass; login timing difference; PO/batch cost prices readable by any authenticated user; alert feed readable by foreman; 3 collectibles fixtures keep literal passwords.

## Wins & Next Step

- Gate: backend **333/333** (`--noinput`), `check` + `makemigrations --check` clean, flutter **565/565**, analyze clean. QA live A–J PASS: 6 roles × 15 endpoints, cashier scoping, token handoff, self-approval, locks, immutability, alerts, audit rows (no secrets), lockout, revocation. Live re-check: cashier PATCH/PUT/DELETE `/transactions/{id}/` → 405.
- LAST_ADMIN is unit-proven only (the superuser admin is always present live).
- QA left demo rows (users `qa_*` ids 7–13, requisitions 6–8, transactions 45–47, customer 5, an open shift 7). Re-seed for a clean demo.
- **Next:** `git push` (user). Then write `phase-3-plan.md` and BUILD Phase 3 (Cashier: release attaches shift, held-cart close advisory, till Returns tab + debt-first refunds).
