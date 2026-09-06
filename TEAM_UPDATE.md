# Backend Update — Update Summary

> Date: 2026-09-06 · Branches: contract hardening, role permissions, reports, tests, seed data, POS underpayment fix

---

## 1. Endpoint map: `ENDPOINTS.md` (repo root)
Answers "which backend endpoint does my feature use?" — start with **Section 2**, the table matching your Flutter features to backend apps.

⚠️ Heads-up: collectible (utang) payments moved to `/api/v1/ledger-payments/` (was conflicting with POS payments).

## 2. The API now enforces roles
Before: any logged-in user could call anything — role screens were cosmetic.
Now: a Cashier account literally cannot approve requisitions or edit products; the server rejects it. Frontend route guards are now backed by real server-side enforcement.

Role → power map:
| Role | Can do |
|---|---|
| Admin / System Administrator | Everything |
| Store Manager (`manager`) | Approve/reject requisitions, reports, ledger, users |
| Stock Manager (`stocker`) | Inventory writes (products, POs, receipts, adjustments) |
| Cashier (`cashier`) | POS transactions, customers, token release, utang payments |
| Site Foreman (`foreman`) | Create requisitions & projects |

## 3. Reports are live
All 4 report types on your Reports page now exist under `/api/v1/reports/` (sales-summary, inventory-valuation, stock-movements, requisition-history), date-filterable, Store Manager/Admin only.

## 4. Demo data — the big one 🎉
Run once:
```
docker compose exec backend python manage.py seed_demo
```
Fills the DB with a realistic hardware store: 5 users (one per role), products with stock batches, customers, completed sales, an unpaid utang, and requisitions in every stage — including an **APPROVED requisition with a printed token** for testing the POS token-release flow end-to-end. Safe to re-run (idempotent).

**Logins (password for all: `demo1234`):** `admin`, `manager`, `stocker`, `cashier`, `foreman`

## 5. User Management page gets real data for free
- `GET /api/v1/users/stats/` → exactly the 4 numbers on your metric cards (total / active / inactive / roles assigned)
- User search now covers username too
- Swapping `AdminMockData.users` for `GET /api/v1/users/` should be close to a drop-in replacement (shared User/Role model shapes)

## 6. Fixed along the way
- Underpaid walk-in sales now automatically post the shortfall to the utang ledger (OPEN, due +30 days) — same behavior as requisition releases. Fully-paid sales are unaffected.
- Registration now requires a role (prevents a crash in `User.fromJson` for role-less accounts)
- POS daily report excludes voided/non-completed transactions

## 7. Still open
- Settings page stays mock-only for now (agreed deferral)
- `.pyc` cache file keeps showing as modified for everyone — fix is in the GitHub issues (add `__pycache__/` to `.gitignore`)

## 8. Process
All work went through feature branches + PRs per CONTRIBUTING.md. When reviewing, the PRs to expect: contract hardening (#11 ✅ merged), role permissions (#18 ✅ merged), reports endpoints (#4), tests (#5), seed demo (#6), POS underpayment fix (refs #5).
