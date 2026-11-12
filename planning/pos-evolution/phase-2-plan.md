# Phase 2 — Merged sidebar for multi-role accounts

**Status:** [ ] Planned 2026-11-12, not authorized. Builds last (order 6 → 7 → 8 → 9 → 3 → **2**). Decision: [24 Merged sidebar](./decisions/24-merged-sidebar.md). Same binding rules as [Phase 4](./phase-4-plan.md#rules-that-bind-every-task). Source references below were checked against `864a667` + working tree on 2026-11-12; Phases 6–9 and 3 add pages (sales-order fulfil/edit, supplier returns and credit notes, supplier cheques, per-location stock and transfers, catalogue import) and append sidebar items, so **every index, line and page list is re-verified at phase start (F0)** and the registry carries whatever exists then.

## Goal

An account with several roles gets one sidebar grouped by area (Till, Sales, Stock, Admin), shared pages once, and one landing page of every area's "needs you" tiles. Single-role users see exactly today's menus, indices, routes and goldens. Flutter only; the server already authorises by any matching group.

## Rules that bind every task

- RED first, with output. At most two Flutter lanes on disjoint files; no backend work, no migrations, **no dev DB start/migrate/reset**.
- The 12 existing sidebar goldens (`test/shared/widgets/sidebar_golden_test.dart:102-106`, 4 roles × 1440/1100/760) must pass **unchanged**; any diff there is a regression.
- Copy: sentence case, no em dashes.

## Source facts this plan relies on

- Four literal menus today: Admin `_navigationItems` + `groups` (`flutter/lib/core/layout/admin_skeleton_layout.dart:43,69`, index constant `projectRequestsIndex = 7` `:41`); Sales `navigationSections` (`sales_skeleton_layout.dart:45`, `projectRequestsIndex = 8` `:43`) with route order in `features/sales/widgets/sales_navigation.dart:7-29`; Stock `_navigationSections` (`inventory_skeleton_layout.dart:46`, `lowStockIndex = 5` `:44`) with `inventory_navigation.dart:18-35`; Till `DashboardShell.groups` (`features/dashboard/widget/dashboard_shell.dart:48`, `heldTransactionsIndex = 4` `:41`) with `pos_navigation.dart:25-31`.
- Rendering: `SharedSidebar`/`SharedSidebarSection`/`SharedSidebarDestination` (`shared/widgets/shared_sidebar.dart:6-42`, flat int `selectedIndex` and `markers`); `AppShell.loadMarkers` (`app_shell.dart:54`), header `AreaSwitcherMenu` (`app_shell.dart:515`, widget `features/auth/widget/area_switcher_menu.dart:14`).
- Badge loaders keyed by flat index: `cashierMarkers` (`dashboard_shell.dart:104`), `projectRequestsMarkers` (`sales_skeleton_layout.dart:178`; admin twin in `admin_skeleton_layout.dart`), `stockManagerMarkers` (`inventory_skeleton_layout.dart:167`).
- Routing: `AppRoutes.redirectFor` (`flutter/lib/routes/routes.dart:229`, prefix fences `:278-300`), `salesTwinOf` (`:174`), `dashboardForRole` (`:314`), `splashDestination` (`:202`). Areas: `AppAreas` (`core/constants/app_areas.dart:8-16`).
- Auth: `assignedAreas` (`features/auth/viewmodels/auth_viewmodel.dart:36`), `canSwitchArea` (`:49`), `activeArea` (`:57`), `needsAreaChoice` (`:67`), `roleName => activeArea` (`:76`), remembered area restore (`:149-153`). Picker: `features/auth/views/area_picker_page.dart:19`. 15 `roleName` call sites in `lib/` (e.g. `canExportBarcodeList` gate, `products_page.dart:336`) answer "which area am I in".
- Landing content: Sales `SalesNeedsYouTile` (`features/sales/views/sales_dashboard_page.dart:199-211`); Admin `AdminNeedsAttentionPanel` (`features/dashboard/widget/admin_needs_attention_panel.dart:32`); Stock `InventoryDashboardContent` panels (`inventory_dashboard_content.dart:34`); the Till's dashboard is the till itself (`routes.dart:552-555` → `PosTransactionPage`), so it has no tiles today.
- Pinning tests: `test/routes/sidebar_index_consistency_test.dart` (source-reading regexes over the navigation files, `:40-80`), `test/shared/sidebar_pattern_test.dart`, `test/routes/area_routing_test.dart`, `sales_twin_routing_test.dart`, `test/features/auth/area_switcher_test.dart`, `auth_area_test.dart`.

## Open items for the owner before F1

1. MAP says "area switcher stays as fallback"; decision 24 says it is retired for merged accounts. Since every multi-role account is merged, the plan hides the switcher whenever the merged sidebar is on and keeps its code (no delete). Confirm.
2. Till "needs you" tiles: recommendation is held carts (same count as the badge) and "no open shift" when the account holds Till.

## Execution file scope

- **F0:** this plan only (registry table appended below the checklist).
- **F1 registry:** new `flutter/lib/core/navigation/app_destinations.dart`; the four layout/navigation files above switch to derived lists; `sidebar_index_consistency_test.dart` rewrite + new `test/core/navigation/app_destinations_test.dart`.
- **F2 merged sidebar:** `shared_sidebar.dart` (string-id selection/markers alongside int), `app_shell.dart`, the four skeleton/shell files (merged branch), new `core/navigation/merged_sidebar.dart`; sidebar tests + new goldens in `test/shared/widgets/merged_sidebar_golden_test.dart`.
- **F3 routing/auth:** `routes.dart`, `auth_viewmodel.dart`, `area_picker_page.dart` (skip), `roleName` call sites switched to an area-membership helper; routing/auth tests.
- **F4 landing:** new `features/dashboard/views/combined_dashboard_page.dart` reusing the tile/panel widgets above, route in `routes.dart` (after F3 lands); tests + goldens.

## Execution checklist

- [ ] **F0 — 🤖 Re-verify the page list.** Read every navigation source and `routes.dart` at phase start (Phases 6–9 and 3 included); write the registry table: id, label, icon, per-area route, area tags, shared key, today's flat index per area, badge. Owner confirms the shared set (today: Payables, Deliveries, Reports, Project requests, Staff; plus any new page in two or more areas, e.g. supplier cheques or transfers if so placed).
- [ ] **F1 — 🤝 Destination registry + derived per-role lists.** One `const` list of destinations tagged by area with a per-area order and group heading; `menuFor(area)` derives each role's sections. RED: a test pinning today's four literal menus (label, icon, route, index, group starts) as expected constants fails against an empty registry, then passes. Rewrite `sidebar_index_consistency_test.dart` to read the registry and pin the **derived** order (same expectations it pins today, not deleted); index constants (`projectRequestsIndex`, `lowStockIndex`, `heldTransactionsIndex`) derived from ids. Existing 12 goldens unchanged; all routing tests unchanged.
- [ ] **F2 — 🤖 Merged sidebar (after F1).** When `assignedAreas.length > 1`: one list, headings in order Till, Sales, Stock, Admin (only assigned ones); a shared destination appears once, under the widest assigned area (admin > sales > inventory > pos) and links to that area's route; de-dup by shared key, never by label. Selection and badges keyed by destination id, so a page wrapped in any area's skeleton highlights its merged row; each badge loader runs once per assigned area that owns it. Narrow screens: same grouped list in the drawer, rail collapses headings to icons as today. Switcher hidden when merged. Tests: de-dup rule, heading order, selection from each skeleton, badges, rail/drawer. New goldens for **Cashier + Store Manager, Stock Manager + Store Manager, Admin + Cashier** at 1440/1100/760 (9 PNGs), inspected.
- [ ] **F3 — 🤝 Routing on the union of areas (parallel with F2, disjoint files).** `redirectFor`: with more than one assigned area, fences check `areas.contains(prefixArea)` instead of the active area; `/admin/*` for a merged account without Admin but with Sales goes through `salesTwinOf`; login/picker/unsupported go to the combined landing; protected single-area dashboards stay reachable for every assigned area. `needsAreaChoice` false and remembered area ignored for merged accounts (single-area accounts unchanged, preference kept). `roleName` consumers that gate actions use "holds area X" for merged accounts. RED tests in `area_routing_test.dart`/`sales_twin_routing_test.dart`: every prefix × the three combos, picker skipped, deep link via `splashDestination`, single-role cases unchanged.
- [ ] **F4 — 🤖 Combined landing (after F3).** Merged accounts land on one page: "Needs you" tiles of each assigned area in heading order, reusing `SalesNeedsYouTile`, `AdminNeedsAttentionPanel`, the inventory restock/waiting panels and the Till tiles; each section loads and fails on its own (a failed read shows its own retry, never a zero). Single-role users keep their own dashboards. Tests per combo + 3 goldens (1440).
- [ ] **Task close — 🤖** Whole-change review (`hygiene-reviewer`); full gates: Flutter analyze, `flutter test --concurrency=2`, goldens with only the new merged captures added and the 12 single-role sidebar captures byte-identical; backend suite + check + drift as a no-change confirmation on the isolated QA container. Isolated QA on the disposable stack (`docs/testing/QA-PROFILE.md`, re-verify `172.20.0.*`): create the three combo accounts there, log in, walk every merged item, deep links, badges, 760px drawer; one single-role account per area unchanged. Docs: `docs/SYSTEM_ATLAS.md` + `docs/system-atlas.html`, QA-PROFILE role flows, MAP status. Owner closure.

## Orchestration

F0 then F1 (single lane, blocks all). Then two lanes: A = F2, B = F3 → F4. Controller runs full suites and goldens.

## Out of scope

Server or permission changes; new roles; per-user sidebar customisation or reordering; deleting the area switcher or picker code; merging page bodies that are not already shared.
