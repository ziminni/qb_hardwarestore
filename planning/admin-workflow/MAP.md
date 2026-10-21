# Admin Workflow MAP

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Audit logs — live paginated list replacing mock rows | ✅ D-01 locked | [ ] Pending |
| 2 | Suppliers + Purchase Orders — live read-only list | ✅ D-02 locked | [ ] Pending |
| 3 | Admin Settings — inline constants, delete AdminMockData | ✅ D-03 locked | [ ] Pending |

## Destination

Every Admin (`admin` role) screen shows either live API data or an honest static value — zero `AdminMockData` consumers remain, all three remaining mock pages (`audit_logs_page`, `settings_page`, `suppliers_page`/`purchases_page`) are replaced. Suppliers/POs fix the Stocker Purchasing tabs as a side-effect. No new backend work.

## Notes & Invariants

- **Role gates (verified):**
  - `AuditLogViewSet` → `IsAdminUser` (admin-only read).
  - `SupplierViewSet` + `PurchaseOrderViewSet` → `_CatalogBaseViewSet`: read=`IsAuthenticated`, write=`IsInventoryRole`.
- **`admin_mock_data.dart` remaining consumers (verified 2026-10-22):**
  - `audit_logs_page.dart` → `AdminMockData.auditLogs`
  - `settings_page.dart` → `AdminMockData.storeName/storeEmail/storePhone`
  - Phase 3 comment lines in `sales_monitoring_page.dart` + `inventory_monitoring_page.dart` (comments only — no runtime use post Phase 3 of sales-manager build)
  - After Phase 3 all consumers gone → **delete `admin_mock_data.dart`**.
- **Flutter `Supplier` model** (`flutter/lib/data/models/supplier.dart`) has no `fromJson` — must add before wiring service.
- **Flutter `PurchaseOrder` model** (`flutter/lib/data/models/supplier.dart`) has no `fromJson` — must add. Backend returns `supplier` as int id but also no `supplier_name` field in `PurchaseOrderSerializer`; resolve by joining supplier name via loaded suppliers list, OR add `supplier_name` to the serializer (one-line backend change). **Decision: no backend changes** — join from loaded suppliers in viewmodel.
- **`AdminAuditLogTable` widget** contract: `rows: List<List<String>>` — each inner list is `[time, user, action, description]`. New live data must map to this shape.
- **`InventoryService`** already calls `/api/v1/purchase-orders/` at `GET /api/v1/purchase-orders/` (receiving page uses it). New `SupplierService` / supplier fetch can follow the same pattern.
- **`Paged<T>`** envelope wrapper already exists at `flutter/lib/core/network/paged.dart` — use for paginated audit-log fetch.
- **No backend changes.** All 3 phases are Flutter-only.
- **Phase order:** Phases 1–3 share no files except the eventual deletion of `admin_mock_data.dart` (Phase 3 last step). Can run sequentially in one agent.

## Decisions So Far

- [D-01 Audit logs scope](./decisions/01-audit-logs-scope.md): Paginated list, latest-first, load-on-open. New `AuditLogService` + `AuditLogRepository`. Page 1 of 50 rows. Error banner + retry. No filter.
- [D-02 Suppliers and Purchase Orders scope](./decisions/02-suppliers-pos-scope.md): Read-only live list replacing hardcoded viewmodel data. `Supplier.fromJson` + `PurchaseOrder.fromJson` added. Supplier name resolved from loaded suppliers list in viewmodel (no backend change). Mock snackbars removed.
- [D-03 Admin Settings](./decisions/03-admin-settings.md): Inline `storeName/storeEmail/storePhone` as const strings in `SettingsPage`. Remove `AdminMockData` import. Delete `admin_mock_data.dart` after all consumers gone.

## Active Frontier

*(empty — all decisions locked)*

## Blocked

*(empty)*

## Fog of War

- **Supplier create/edit via API** — `SuppliersFormDialog` and `PurchasesFormDialog` exist; POST endpoints exist. Future pass when write scope is decided.
- **Audit log filter by action type** — deferred; single list view sufficient for demo.
- **Settings live API** — no Django model or endpoint exists. Future backend work if needed.

## Out of Scope

- Creating or editing suppliers/POs from the Flutter client.
- Audit log action-type filtering.
- Any new Django models, migrations, or endpoints.

---

## Phase 1 — Audit Logs (live wire)

### Files to create

**`flutter/lib/data/models/audit_log.dart`** (NEW)
```dart
class AuditLog {
  const AuditLog({required this.id, required this.userEmail,
      required this.actionType, required this.description,
      required this.ipAddress, required this.timestamp});
  final int id;
  final String userEmail;   // user_email from serializer
  final String actionType;  // LOGIN | LOGOUT | CREATE | UPDATE | DELETE | SALE | STOCK_ADJUST | RECEIPT | PAYMENT
  final String description;
  final String? ipAddress;
  final DateTime timestamp;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as int,
    userEmail: json['user_email'] as String? ?? '(deleted)',
    actionType: json['action_type'] as String,
    description: json['description'] as String,
    ipAddress: json['ip_address'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}
```

**`flutter/lib/data/services/audit_log_service.dart`** (NEW)
- `fetchAuditLogs({int page = 1})` → `GET /api/v1/audit-logs/?page=<page>`
- Returns `Paged<AuditLog>` (uses existing `Paged<T>` envelope)
- Maps connection errors to "Cannot connect" text, 403 to "No permission"

**`flutter/lib/data/repositories/audit_log_repository.dart`** (NEW)
- Policy-free pass-through: `fetchAuditLogs({int page}) → _service.fetchAuditLogs(page: page)`

### Files to edit

**`flutter/lib/features/admin/views/audit_logs_page.dart`**
- Convert to `StatefulWidget(repository?)`
- `initState` post-frame → `_load()`
- `_load()` calls `repository.fetchAuditLogs(page: 1)` and maps each `AuditLog` to `[_formatTime(log.timestamp), log.userEmail, log.actionType, log.description]` for `AdminAuditLogTable`
- `_formatTime`: `'${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}'`
- Show `CircularProgressIndicator` while loading; `LiveLoadErrorBanner` on error with retry; empty state "No audit logs recorded."

### Test (write RED first)

`flutter/test/features/admin/audit_logs_live_test.dart`:
- Stub `AuditLogRepository` returning 2 fixed log rows
- `AuditLogsPage(repository: stub)` renders both rows' userEmail + actionType
- Error path: shows retry banner
- Empty path: shows "No audit logs recorded."

### Commit message

`feat(admin): audit logs — live paginated list via AuditLogService replacing mock rows`

---

## Phase 2 — Suppliers + Purchase Orders (live wire)

### Files to edit

**`flutter/lib/data/models/supplier.dart`**
Add `fromJson` to `Supplier`:
```dart
factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
  id: json['id'] as int,
  companyName: json['company_name'] as String,
  contactPerson: json['contact_person'] as String? ?? '',
  phone: json['phone'] as String? ?? '',
  email: json['email'] as String? ?? '',
  address: json['address'] as String? ?? '',
  isActive: json['is_active'] as bool? ?? true,
);
```
Add `fromJson` to `PurchaseOrder` (reads `supplier` int id; no `supplier_name` in backend serializer — viewmodel resolves name from loaded suppliers):
```dart
factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
  id: json['id'] as int,
  supplierId: json['supplier'] as int,
  supplierName: '',   // resolved by viewmodel after suppliers load
  orderDate: DateTime.parse(json['order_date'] as String),
  expectedDelivery: json['expected_delivery'] != null
      ? DateTime.parse(json['expected_delivery'] as String)
      : null,
  status: _statusFromString(json['status'] as String),
  notes: json['notes'] as String? ?? '',
  items: (json['items'] as List<dynamic>)
      .map((i) => PurchaseItem.fromJson(i as Map<String, dynamic>))
      .toList(),
);
```
Also add `PurchaseItem.fromJson` reading `variant`, `variant_name`, `ordered_qty`, `unit_cost`, `received_qty`.

**`flutter/lib/data/services/supplier_service.dart`** (NEW)
- `fetchSuppliers()` → `GET /api/v1/suppliers/` (no pagination — small list)
- `fetchPurchaseOrders()` → `GET /api/v1/purchase-orders/`
- Both return `List<T>` via `ApiClient.getList`

**`flutter/lib/data/repositories/supplier_repository.dart`** (NEW)
- Pass-through for both methods

**`flutter/lib/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart`**
- Replace hardcoded `_suppliers` / `_purchases` lists with `List<Supplier> _suppliers = []` / `List<PurchaseOrder> _purchases = []`
- Add `bool isLoading`, `String? loadError`
- Add `Future<void> load()` — fetches suppliers then POs, resolves `supplierName` on each PO by matching `supplierId` against loaded suppliers
- Keep `toggleSupplier` (local optimistic — or wire PATCH `/api/v1/suppliers/{id}/` in a future pass)
- Remove `saveSupplier` (mock create — dead code once reads are live)
- Remove `addPurchase` (mock create — dead code once reads are live)
- Keep filter helpers (`filteredPurchases`, `totalSpend`, etc.) — they operate on the list in-memory regardless of source

**`flutter/lib/features/suppliers/views/suppliers_page.dart`**
- Remove `Supplier saved in mock data.` snackbar → call `context.read<SuppliersPurchasesViewmodel>().load()` in `initState` post-frame
- Show `LiveLoadErrorBanner` on `loadError`
- Remove `_form` dialog trigger or keep as dead UI (no write scope → simplest: remove the Add Supplier button, or grey it out)

**`flutter/lib/features/suppliers/views/purchases_page.dart`**
- Remove `Draft purchase order created in mock data.` snackbar
- Load via viewmodel, show loading/error states
- Remove the New Purchase Order FAB or grey it out (no write scope)

### Test (write RED first)

`flutter/test/features/suppliers/suppliers_live_test.dart`:
- Stub `SupplierRepository` returning 2 fixed suppliers
- `SuppliersPage` renders supplier company names (not mock fixture names)
- Error path shows retry banner

### Commit message

`feat(inventory): suppliers + purchase orders — live read-only list replacing hardcoded viewmodel`

---

## Phase 3 — Admin Settings cleanup

### Files to edit

**`flutter/lib/features/admin/views/settings_page.dart`**
- Remove `import admin_mock_data.dart`
- Inline constants:
```dart
const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';
```
- Pass directly to `AdminSettingsForm(storeName: _storeName, email: _storeEmail, phone: _storePhone)`

**`flutter/lib/features/admin/viewmodels/admin_mock_data.dart`**
- After Phase 3, verify zero remaining consumers via grep
- **Delete the file** if confirmed zero consumers

**`flutter/lib/features/inventory/views/inventory_settings_page.dart`**
- Check if it still imports `admin_mock_data.dart` → it does (storeName/storeEmail/storePhone) — apply same inline-const treatment

### Test (write RED first)

`flutter/test/features/admin/settings_no_mock_test.dart`:
- `SettingsPage` renders without any `AdminMockData` reference (assert compile + render)
- After `admin_mock_data.dart` deletion: `flutter analyze` clean

### Commit message

`refactor(admin): settings — inline store constants, delete AdminMockData`
