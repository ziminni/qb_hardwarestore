# D-01 Sales Reports Tab Routing

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

The Sales sidebar has a Reports tab at index 6, but `navigateSales` only covers indices 0–5 so tapping Reports is a silent no-op. The live `ReportsPage` already exists at `/admin/reports` and the Store Manager (`sales` role) is already admitted there via the `redirectFor` fence exception. Where should tapping Reports take the manager?

## Options Considered

**A — Navigate directly to `/admin/reports`:** Zero new files; admin sidebar replaces sales sidebar — manager visually "switches shells".

**B — Wrap ReportsPage content in `/sales/reports` inside SalesSkeletonLayout:** Thin wrapper page; manager stays in sales shell with correct sidebar highlight. ~30 lines, no new backend.

**C — `context.go(adminReports)` from the sales nav switch:** Same admin-layout issue as A, no wrapper file.

## Decision: Option B

Wrap `ReportsPage`'s inner content (the TabBar + four tab panes) in a new `SalesReportsPage` that uses `SalesSkeletonLayout(selectedNavigationIndex: 6)`. The shared `AdminReportsViewmodel` is provided by `SalesReportsPage` itself via `ChangeNotifierProvider`.

**Important implementation note:** `ReportsPage` wraps itself in `AdminSkeletonLayout` — do NOT reuse `ReportsPage` as a widget directly. Replicate `_ReportsView`'s inner tab content inside `SalesSkeletonLayout`. Both views can share the same viewmodel type.

## Files affected

- `flutter/lib/routes/routes.dart` — add `salesReports = '/sales/reports'` constant + GoRoute
- `flutter/lib/features/sales/widgets/sales_navigation.dart` — add index 6 → `salesReports`
- `flutter/lib/features/sales/views/sales_reports_page.dart` (NEW)

## Cost if wrong

Store Manager sees the sales sidebar disappear on the Reports tab (they'd land in admin shell) — visually confusing but functionally correct. Easily corrected by re-routing.
