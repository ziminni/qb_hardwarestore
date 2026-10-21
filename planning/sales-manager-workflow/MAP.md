# Sales Manager Workflow MAP

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Sales Reports tab — wrap ReportsPage in SalesSkeletonLayout | ✅ D-01 locked | [ ] Pending |
| 2 | View buttons — read-only bottom sheet for quotations, orders, transactions | ✅ D-02 locked | [ ] Pending |
| 3 | Admin monitoring pages — wire live SalesSummary + InventoryValuation | ✅ D-03 locked | [ ] Pending |

## Destination

Every Store Manager (`sales` role) screen works end-to-end: the Reports tab in the sales sidebar reaches live report data, every "View" button on quotations/orders/transactions opens a read-only detail sheet, and the admin monitoring pages (reachable by Store Manager) replace their mock charts with live aggregates. Audit logs deferred (admin-only, separate epic).

## Notes & Invariants

- **Role key:** `sales` (Store Manager + Sales groups in Django). `redirectFor` already allows `sales` at `/admin/reports` and `/admin/requisitions` via the fence exception at `routes.dart:118`.
- **`ReportsPage` is layout-agnostic.** It wraps itself in `AdminSkeletonLayout` internally. Phase 1 needs a thin wrapper that provides `SalesSkeletonLayout` and delegates to `ReportsPage`'s content — OR refactors `ReportsPage` to accept a layout. Read the file before implementing.
- **`navigateSales` currently holds indices 0–5** (`flutter/lib/features/sales/widgets/sales_navigation.dart`). Reports is the sidebar's index 6. Phase 1 must add index 6 to the paths list.
- **`SalesSkeletonLayout.navigationSections` has 7 sections** (0=Dashboard, 1=Transactions, 2=Quotations, 3=Sales orders, 4=Receivables, 5=Returns, 6=Reports). No new sidebar entry needed — it already exists.
- **Bottom sheet for View buttons:** `SalesQuotation` Flutter model holds `number`, `customer`, `date`, `validUntil`, `total`, `status` only — no items list. The backend QuotationSerializer returns nested `items`. The view-model must either fetch single quotation detail on tap, or the list endpoint already returns items (it does — `items` is in `fields`). Same for `SalesOrderRecord` (no items in Flutter model), and `SaleTransaction` (already has `items` + `payments`). Transactions View is cheapest; Quotations/Orders need a detail fetch OR the list already includes items.
- **List already includes items:** `GET /api/v1/quotations/` returns full nested `items` because `QuotationSerializer.items = QuotationItemSerializer(many=True, required=False)` and there is no `fields` exclusion. Same for SalesOrders. No extra detail fetch needed. The Flutter models just need an `items` field added.
- **`IsManagerRole` check:** `backend_django/apps/reports/views.py` — all four report endpoints require IsManagerRole. Store Manager (`sales` role) maps to `is_manager=True` in the permission. Confirmed `sales` role is admitted.
- **Admin monitoring pages:** `SalesMonitoringPage` at `selectedNavigationIndex: 3`, `InventoryMonitoringPage` at `selectedNavigationIndex: 2`. Both use `AdminSkeletonLayout`. `ReportsRepository` already has `fetchSalesSummary` + `fetchInventoryValuation`. No new repository methods needed.
- **`AdminSalesChart`** widget in `SalesMonitoringPage` takes `values: List<double>` + `labels: List<String>`. `SalesSummary.days` has `SalesDay.day` (String) + `SalesDay.gross` (double) — direct fit. `InventoryMonitoringPage` uses `AdminInventorySummary(metrics: ...)` — check that widget's contract.
- **No backend changes.** All 3 phases are Flutter-only.
- **Audit logs:** Deferred to fog. Not Store Manager scope.

## Decisions So Far

- [D-01 Sales Reports tab routing](./decisions/01-reports-tab-routing.md): Wrap `ReportsPage` content in a new `/sales/reports` route inside `SalesSkeletonLayout`; navigate from `navigateSales` index 6. Manager stays in sales shell.
- [D-02 View buttons scope](./decisions/02-view-buttons-scope.md): Read-only bottom sheet on tap — shows full document (customer, items, totals, status). No new routes. No create/edit/delete.
- [D-03 Admin monitoring pages](./decisions/03-monitoring-pages.md): Wire `SalesMonitoringPage` to `SalesSummary` and `InventoryMonitoringPage` to `InventoryValuation` via `ReportsRepository`. Remove `AdminMockData` chart data.

## Active Frontier

*(empty — all decisions locked)*

## Blocked

*(empty)*

## Fog of War

- **Audit logs live wire** — backend `AuditLog` model exists; no Flutter service. Admin-only concern. Deferred.
- **Create / Edit quotation or sales order** — backend supports POST/PATCH on both. Scope not decided. No cashier-side create of quotations was discussed; future decision.
- **Quotation → Sales Order conversion** — `Quotation` backend has no `convert` action. Future backend work.

## Out of Scope

- Creating or editing quotations/sales orders from the Flutter client.
- Audit logs live wire (separate epic).
- Admin settings live wire.
- CPMS repo.

---

## Phase 1 — Sales Reports tab (Route + Wrapper)

### Files to create/edit

**`flutter/lib/routes/routes.dart`**
Add: `static const String salesReports = '/sales/reports';`
Add import: the new `SalesReportsPage`.
Add `GoRoute` after the `salesReturns` route:
```dart
GoRoute(
  path: salesReports,
  pageBuilder: (context, state) =>
      _transitionPage(state, const SalesReportsPage()),
),
```

**`flutter/lib/features/sales/widgets/sales_navigation.dart`**
Add `AppRoutes.salesReports` at index 6:
```dart
AppRoutes.salesReports,
```

**`flutter/lib/features/sales/views/sales_reports_page.dart`** (NEW)
```dart
/// Thin wrapper: puts the shared ReportsPage content inside the Sales shell
/// so the Store Manager never leaves their navigation context.
class SalesReportsPage extends StatelessWidget {
  const SalesReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminReportsViewmodel()..load(),
      child: const _SalesReportsView(),
    );
  }
}

class _SalesReportsView extends StatelessWidget {
  // Identical inner build to _ReportsView in reports_page.dart
  // but wrapped in SalesSkeletonLayout(title: 'Reports', selectedNavigationIndex: 6,
  // onNavigationSelected: (i) => navigateSales(context, i))
}
```

**Important:** `ReportsPage` wraps itself in `AdminSkeletonLayout` — do NOT reuse `ReportsPage` widget directly. Instead replicate `_ReportsView`'s inner content (the TabBar + tab panes) inside `SalesSkeletonLayout`. Both pages share the same `AdminReportsViewmodel`.

### Test (write RED first)
`flutter/test/features/sales/sales_reports_routing_test.dart`:
- `salesReports` constant = `/sales/reports`
- `navigateSales` covers index 6 → `salesReports`
- `SalesReportsPage` renders `Reports` title in `SalesSkeletonLayout` (not `AdminSkeletonLayout`)

### Commit
`feat(sales): Reports tab — SalesReportsPage wrapping live ReportsViewmodel in SalesSkeletonLayout`

---

## Phase 2 — View buttons (bottom sheet)

### What each document has on the wire

**Quotation (list already returns items):**
- `quotation_no`, `customer` (id), `status`, `valid_until`, `notes`, `created_at`
- `items[]`: `variant_uom`, `qty`, `unit_price` — **no `variant_name`** from QuotationItemSerializer (needs adding OR display variant_uom id)

**SalesOrder (list already returns items):**
- `order_no`, `customer`, `status`, `notes`, `created_at`
- `items[]`: `variant_uom`, `qty`, `unit_price` — same gap

**SaleTransaction (model already has items + payments):**
- Full data including `items`, `payments`, `customerName`, `cashierName`, `grandTotal`

### Decision detail

The `SalesQuotation` Flutter model currently lacks `items`. **Add an `items` field** to `SalesQuotation` and `SalesOrderRecord` models (or create a new `QuotationDetail` / `SalesOrderDetail` model). The viewmodel's `load()` already fetches `items` in the serializer response — just parse and store them.

For Quotation items display: `variant_uom` is an int id — not human-readable. Options:
- Add `variant_uom_code = CharField(source='variant_uom.uom.code')` to `QuotationItemSerializer` (one-line backend change) — **or** look up from the already-loaded `InventoryViewmodel` by id.
- Since `InventoryViewmodel` is app-scoped, the simpler path is reading `context.read<InventoryViewmodel>()` in the sheet to resolve variant name from `variant_uom_id`. No backend change needed.

### Files to create/edit

**`flutter/lib/data/models/sales_module.dart`**
- Add `items` field to `SalesQuotation` (list of `QuotationLineItem`)
- Add `items` field to `SalesOrderRecord` (list of `SalesOrderLineItem`)
- Add `QuotationLineItem` and `SalesOrderLineItem` classes with `variantUomId`, `qty`, `unitPrice`
- Update `fromJson` parsers

**`flutter/lib/features/sales/views/sales_quotations_page.dart`**
Replace `TextButton(onPressed: () {}, child: const Text('View'))` with:
```dart
TextButton(
  onPressed: () => _showQuotationSheet(context, viewmodel, quotation),
  child: const Text('View'),
),
```
Add `_showQuotationSheet` that calls `showModalBottomSheet`.

**`flutter/lib/features/sales/views/sales_orders_page.dart`**
Same pattern for orders.

**`flutter/lib/features/sales/views/sales_transactions_page.dart`**
Same pattern for transactions (simpler — model already has items).

### Test (write RED first)
`flutter/test/features/sales/view_buttons_test.dart`:
- Tapping 'View' on a quotation row opens a bottom sheet containing the quotation number
- Tapping 'View' on an order row opens a bottom sheet containing the order number
- Tapping 'View' on a transaction row opens a bottom sheet containing the transaction number

### Commit
`feat(sales): View buttons — read-only detail bottom sheet on quotations, orders, transactions`

---

## Phase 3 — Admin monitoring pages (live wire)

### SalesMonitoringPage
Replace mock chart data:
1. Remove `AdminMockData.salesValues` + `AdminMockData.salesLabels`
2. Provide `ReportsRepository` via `ChangeNotifierProvider`-style or a simple `FutureBuilder` with `ReportsRepository().fetchSalesSummary()`
3. Pass `summary.days.map((d) => d.gross).toList()` as `values` and `summary.days.map((d) => d.day).toList()` as `labels` to `AdminSalesChart`
4. Show loading + error states

### InventoryMonitoringPage
1. Replace `AdminMockData.inventoryMetrics`
2. Check `AdminInventorySummary` widget contract — what does `metrics` expect?
3. Wire via `ReportsRepository().fetchInventoryValuation()`

**File to check first:** `flutter/lib/features/admin/widgets/admin_inventory_summary.dart` — read the `metrics` parameter type.

### Test (write RED first)
`flutter/test/features/admin/admin_monitoring_pages_test.dart`:
- `SalesMonitoringPage` shows loading state when data pending
- `InventoryMonitoringPage` shows loading state when data pending
- Neither renders `AdminMockData` values

### Commit
`feat(admin): monitoring pages — live SalesSummary + InventoryValuation replacing mock charts`
