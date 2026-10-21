# Stocker-Workflow Map

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Returns tab — read-only RETURN transactions | ✅ D-01 locked | [ ] Pending |
| 2 | Reports tab — inventory-role view (Valuation + Movements) | ✅ D-02 locked | [ ] Pending |
| 3 | Settings tab — non-crashing static form | ✅ D-03 locked | [ ] Pending |
| 4 | Dashboard action buttons — Add product & Export | ✅ D-04 locked | [ ] Pending |

---

## Destination

Every tab in the stocker's (`inventory` role) sidebar opens a working screen with no
crash or no-op. No new backend logic is required; all gaps are routing, role-permission,
and minor UI wiring defects on the Flutter side.

---

## Notes & Invariants

- **Role key:** `inventory` (Stock Manager group in Django). `IsPOSOrReadOnly` grants
  `inventory` role **read** (GET) on all POS endpoints including transactions.
- **Reports backend is `IsManagerRole`-only** (Store Manager + Admin). A `stocker`
  hitting `/api/v1/reports/*` gets 403. The stocker's Reports tab must therefore show
  inventory-safe data only (Valuation + Movements) **or** be redirected to the admin
  reports page if the user has Store Manager+ role. The existing `ReportsPage` lives at
  `/admin/reports` and uses `AdminSkeletonLayout` — it cannot be dropped into the
  stocker shell as-is.
- **Settings has no backend API** — it is a static form backed by `AdminMockData`.
  The stocker should see their own store info but cannot save it; the form is read-only
  or "Save" is a no-op. No backend work needed.
- **`InventoryActionButton` `onPressed` defaults to `() {}`** — "Add product" and
  "Export" are silent no-ops today.
- **Returns tab index 9 has no route constant** `inventoryReturns` and
  `navigateInventory` switch falls through to `null` → silent no-op.
- **Sales returns page** (`/sales/returns`, `SalesReturnsPage`) already shows
  `source=RETURN` transactions and is Live. Stocker's Returns tab will reuse this page
  inside an `InventorySkeletonLayout` wrapper.
- **File structure:** Original `ui/frontend-progress` folder layout is preserved.
  You added 42 files; deleted only 19 orphan/mock files. Teammate will recognise all
  their original folders untouched.

---

## Decisions So Far

- [D-01 Stocker Returns scope](./decisions/01-returns-scope.md): Read-only list of RETURN-source transactions reusing `SalesTransactionViewSet` (already readable by `inventory` role via `IsPOSOrReadOnly`). Option C (initiate return form) deferred to fog.
- [D-02 Stocker Reports scope](./decisions/02-reports-scope.md): Show **Valuation** and **Movements** tabs only (both `IsManagerRole`-gated 403 for stocker), surfacing a friendly "Manager access required" banner inside the inventory shell — no new backend endpoint needed.
- [D-03 Stocker Settings](./decisions/03-settings-scope.md): Static read-only form reusing `AdminSettingsForm` with hardcoded store info inside `InventorySkeletonLayout`; "Save" button removed (stocker cannot change store settings); no backend needed.
- [D-04 Dashboard action buttons](./decisions/04-dashboard-buttons.md): "Add product" navigates to `/inventory/products` (Products page already live). "Export" is removed — no export endpoint exists and the Products page has no export either.

---

## Active Frontier (Open & Unblocked)

_Empty — all four decisions locked. Ready to hand off for BUILD._

---

## Blocked

_None._

---

## Fog of War (Not Yet Specified)

- **Stocker initiate-return form** (Option C from D-01): stocker records a return against an existing transaction with a reason code. Needs a `process_return` backend flow check and a form dialog. Deferred until a later epic or the cashier story revisits returns.
- **Inventory Reports live data for stocker**: Valuation + Movements are `IsManagerRole`-gated. A future decision could open them to `inventory` role or add a read-only inventory-specific report endpoint.
- **Settings save for admin**: `AdminSettingsForm` "Save" button is a no-op even for admin. Out of scope here but recorded as a known dead button.

---

## Out of Scope

- Suppliers & Purchases pages wiring (separate epic — needs supplier endpoint + PO creation flow).
- Categories live wiring (mock-seeded; endpoint exists but uncalled).
- Stock movements partial live wiring cleanup.
- Any CPMS repo work.

---

## Implementation Roadmap

All four phases are independent and can be built sequentially in one session.

### Phase 1 — Returns tab (Route + Page)

**Files to create/edit:**
- `flutter/lib/routes/routes.dart` — add `static const inventoryReturns = '/inventory/returns';`
- `flutter/lib/features/inventory/widgets/inventory_navigation.dart` — add `case 9 => AppRoutes.inventoryReturns`
- `flutter/lib/features/inventory/views/inventory_returns_page.dart` — **NEW**: thin wrapper rendering `SalesTransactionViewSet` RETURN list inside `InventorySkeletonLayout` at `selectedNavigationIndex: 9`
- `flutter/lib/core/layout/inventory_skeleton_layout.dart` — verify tab index 9 label is "Returns" (already present)

**Reuse:** `InventorySalesViewmodel` already fetches `?source=RETURN` — the same VM that `SalesReturnsPage` uses.

**Tests:**
- `flutter/test/features/inventory/inventory_navigation_routing_test.dart` — add case: tapping Returns tab navigates to `/inventory/returns`
- Sidebar consistency test: posOrder length 10

**Gate:** `flutter test` full + `flutter analyze` clean.

---

### Phase 2 — Reports tab (Route + Friendly 403 page)

**Files to create/edit:**
- `flutter/lib/routes/routes.dart` — add `static const inventoryReports = '/inventory/reports';`
- `flutter/lib/features/inventory/widgets/inventory_navigation.dart` — add `case 10 => AppRoutes.inventoryReports`
- `flutter/lib/features/inventory/views/inventory_reports_page.dart` — **NEW**: `InventorySkeletonLayout` at index 10, body is a `ManagerAccessRequired` banner ("Reports are available to Store Managers and above. Contact your manager for a summary.") with an icon — no API call, no viewmodel needed.
- `flutter/lib/core/layout/inventory_skeleton_layout.dart` — verify tab index 10 label is "Reports"

**Tests:**
- Navigation test: tapping Reports tab navigates to `/inventory/reports`
- Widget test: page renders the access banner (no crash, no spinner)

**Gate:** full flutter + analyze clean.

---

### Phase 3 — Settings tab (Route + Static form)

**Files to create/edit:**
- `flutter/lib/routes/routes.dart` — add `static const inventorySettings = '/inventory/settings';`
- `flutter/lib/features/inventory/widgets/inventory_navigation.dart` — add `case 11 => AppRoutes.inventorySettings`
- `flutter/lib/features/inventory/views/inventory_settings_page.dart` — **NEW**: `InventorySkeletonLayout` at index 11, body reuses `AdminSettingsForm` with hardcoded store values (same as `AdminMockData`) but **no Save button** (stocker cannot change settings).
- `flutter/lib/core/layout/inventory_skeleton_layout.dart` — verify tab index 11 label is "Settings"

**Tests:**
- Navigation test: tapping Settings navigates to `/inventory/settings`
- Widget test: form renders store name field, no Save button present

**Gate:** full flutter + analyze clean.

---

### Phase 4 — Dashboard action buttons

**Files to edit:**
- `flutter/lib/features/dashboard/widget/inventory_dashboard_content.dart` — wire "Add product" `onPressed` to `context.go(AppRoutes.inventoryProducts)`; **delete** the "Export" `InventoryActionButton` (no endpoint, no-op).

**Tests:**
- Widget test: tapping "Add product" triggers navigation to `/inventory/products`
- Assert "Export" button is absent from the widget tree

**Gate:** full flutter + analyze clean.
