# D-03 Admin Settings

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

`SettingsPage` imports `AdminMockData` for `storeName/storeEmail/storePhone`. No settings backend API exists (no Django model, no endpoint). What should replace the mock dependency?

## Decision: Inline constants, remove AdminMockData import

Move the three store-info values to compile-time `const` strings directly in `SettingsPage` (and `inventory_settings_page.dart` which also imports `AdminMockData` for the same fields). Remove the import. Once all consumers are gone, **delete `admin_mock_data.dart`** entirely.

## Affected files

1. `flutter/lib/features/admin/views/settings_page.dart` — remove `AdminMockData` import, inline const strings
2. `flutter/lib/features/inventory/views/inventory_settings_page.dart` — same (also imports `AdminMockData` for store fields)
3. `flutter/lib/features/admin/viewmodels/admin_mock_data.dart` — **delete** after confirming zero remaining consumers

## Consumer audit (verified 2026-10-22 before Phase 3)

After phases 1 (audit logs) and 2 (suppliers/POs) are built:
- `audit_logs_page.dart` → `AdminMockData.auditLogs` ← removed by Phase 1
- `sales_monitoring_page.dart` → comment lines only (no runtime use) ← already removed by sales-manager Phase 3
- `inventory_monitoring_page.dart` → comment lines only ← same
- `settings_page.dart` → `storeName/storeEmail/storePhone` ← removed by Phase 3
- `inventory_settings_page.dart` → `storeName/storeEmail/storePhone` ← removed by Phase 3

After Phase 3 all runtime consumers are gone → delete the file.

## Hardcoded values to inline

These exact values appear in `AdminMockData` now:
```dart
static const storeName = 'QB Hardware & Construction Supplies';
static const storeEmail = 'qbhardware@gmail.com';
static const storePhone = '+63 912 345 6789';
```
Copy verbatim — do not invent new values.

## Cost if wrong

Store info shows outdated values until a real Settings API is built. Acceptable for capstone — settings are read-only display anyway (Save button is a no-op per D-03 of stocker-workflow).
