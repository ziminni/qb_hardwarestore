# Merged sidebar for multi-role accounts

**Status:** Locked 2026-11-12 (by: me — owner answers; defaults marked *delegated*)
**Phase:** 2

## Context

Research (2026-11-12): each role has its own skeleton layout (`admin_/inventory_/sales_skeleton_layout.dart`, POS `DashboardShell`) over the one `AppShell`, with flat sidebar indices pinned by source-reading tests (`sidebar_index_consistency_test.dart`) and 12 sidebar goldens. Route fences in `AppRoutes.redirectFor` keep each role inside its prefix; `salesTwinOf` maps admin-only routes for Store Managers. Payables and Deliveries are already one page body with three shell wrappers; Reports, Staff and Project requests are shared content under twin routes. Phase 4 added `roles[]`, an area picker and a header area switcher.

## Decisions

1. **Shape: grouped by area.** A multi-role account gets one sidebar with a heading per assigned area (Till, Sales, Stock, Admin) and that area's usual items. Pages that exist in several areas (Payables, Deliveries, Reports, Project requests, Staff) appear **once**, in the widest assigned area. The landing page combines the "needs you" tiles of every assigned area. **Single-role users see exactly today's menus.** The area switcher is retired for merged accounts. (by: me)

## Delegated defaults (owner may override)

- **Order of headings:** Till, Sales, Stock, Admin (daily work first); "widest area" for de-duplication follows the server order admin > sales > inventory > pos.
- **Routes:** merged accounts may visit every route their assigned areas allow; route fences check the union of assigned areas instead of the single active area. The server is unchanged (it already authorises by any matching group).
- **Badges:** each item keeps its own badge (held carts, low stock, project requests, cheques).
- **Area picker** at login is skipped for merged accounts; the remembered active-area preference is ignored for them, kept for nothing else.
- **Narrow screens:** the same grouped list in the drawer; headings collapse to icons on the rail like today.

## Consequences

- Sidebar construction moves from per-role literal lists to a registry of destinations tagged by area; the existing per-role orders become derived lists (index tests rewritten to pin the derived order, not deleted).
- New goldens for merged combinations (e.g. Cashier + Store Manager, Stock Manager + Store Manager, Admin + Cashier).
