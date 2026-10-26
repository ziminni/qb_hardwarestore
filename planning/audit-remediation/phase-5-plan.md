# Phase 5 Plan — Store Manager / Admin

**Spec:** [MAP](./MAP.md) row 5. **Branch:** `feature/backend-integration`. **Baseline:** backend 456/456, flutter 741/741 (post overflow fix `42b6f77`), analyze clean.
**Grill (locked 2026-10-26):** user edit = deactivate/reactivate + role change only · unlinked return = manager action on Sales Returns page, role-gated · dashboard totals = server summary endpoint.
**Research defaults (no grill):** overdue = client-side filter chips over loaded ledgers via `LedgerEntry.statusAt` (no new endpoint) · simulator = delete (unit conversion is server-side since Phase 1).

## Destination & Scope

Store Manager and Admin close the remaining P1 gaps: user deactivation + role repair, overdue-debt visibility, manager-only unlinked returns, and dashboard tiles that stay correct past 2,000 transactions. Simulator mock deleted.

**Out of scope:** Phase 6 barcode/QR, discounts/VAT, thermal printing, production secrets/HTTPS (`planning/04-cleanup.md`), CPMS.

## Locked Decisions

- **User edit (grill):** UI offers deactivate/reactivate (`PATCH is_active`) + assign/remove role only. No name/email edit. Server `LAST_ADMIN` guard stays authoritative; UI pre-warns when target is the last admin.
- **Unlinked return (grill, follows [Returns policy](./decisions/05-returns-policy.md)):** `Unlinked return` button on `SalesReturnsPage`, rendered only for Store Manager/Admin; cashier gets 403 `UNLINKED_RETURN_FORBIDDEN` from server. Mandatory reason, audited; restock + debt-first money rules unchanged.
- **Dashboard totals (grill):** tiles read `GET /reports/sales-summary/` (+ `ledgers/aging/` + alerts) through `ReportsRepository` like Admin monitoring; stop folding `fetchTransactions` for totals. Transaction tables keep paged lists.
- **Overdue filter (research):** chips All / Overdue / Due soon filter loaded `_entries` by `statusAt(now)`; tile and rows share the source so they cannot disagree. No `?status=` param.
- **Simulator (research):** delete `products_inventory_simulator_dialog.dart` + toolbar opener; no replacement.

## Domain & File Impact

- **Users:** `backend_django/apps/users/views.py` (already `IsAdminRole` + `LAST_ADMIN`; verify, no new endpoint), `flutter/lib/data/services/user_service.dart` (update/deactivate/assign/remove), `flutter/lib/features/admin/viewmodels/admin_users_viewmodel.dart` (deactivate + role actions, reload from server), `flutter/lib/features/admin/views/admin_user_management_page.dart` + `admin_user_filters.dart` (actions, confirm dialogs, role codes not labels — Phase 4 lesson).
- **Returns:** `flutter/lib/features/sales/views/sales_returns_page.dart` (manager-only button + dialog: lines of variant-UOM + qty + reason → POST unlinked), backend `apps/pos/{views,services}.py` `process_return` unlinked path (verify manager-only + reason required + audit row).
- **Dashboards:** `flutter/lib/features/sales/viewmodels/inventory_sales_viewmodel.dart` + sales dashboard + `dashboard/viewmodels/admin_overview_viewmodel.dart` (tiles via `ReportsRepository`; tables unchanged).
- **Receivables:** `flutter/lib/features/sales/viewmodels/sales_receivables_viewmodel.dart` + `sales_receivables_page.dart` (filter chips only).
- **Simulator:** delete dialog + `ProductsToolbar.onOpenSimulator` path.
- **Contract:** `ENDPOINTS.md` (user PATCH actions, unlinked return, dashboard summary source).

## Phased Execution Checklist

- [ ] Task 1 (backend verify + tests): `LAST_ADMIN` on deactivate + role-drop, cashier user-PATCH → 403, unlinked return cashier → 403 / manager without reason → 400, audit rows for role/deactivate/unlinked. RED first.
- [ ] Task 2 (Flutter users): deactivate/reactivate + role change with confirm, role-code comparison, reload-from-server, route-wiring tests.
- [ ] Task 3 (Flutter returns + receivables + dashboards + simulator deletion): manager-gated unlinked dialog, filter chips, summary tiles, simulator gone (grep test).
- [ ] Gate: backend `--noinput` + `check` + `makemigrations --check`, `flutter analyze` + full `flutter test`; hygiene-reviewer ×2; qa-tester API probes + browser E2E (manager deactivates + role-repairs groupless account, posts unlinked return with reason, filters overdue, dashboard matches summary; cashier unlinked → refused; regression sale).
- [ ] Close: MAP row 5 ✅, `ENDPOINTS.md`, session note, AGENTS pointer. Then Phase 6 grill ([Barcode concept](./decisions/10-barcode-concept.md)).
