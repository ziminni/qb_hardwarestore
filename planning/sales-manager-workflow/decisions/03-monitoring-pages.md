# D-03 Admin Monitoring Pages

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

`SalesMonitoringPage` reads `AdminMockData.salesValues` + `AdminMockData.salesLabels` (fake chart data). `InventoryMonitoringPage` reads `AdminMockData.inventoryMetrics` (fake summary cards). Both are live in the Admin shell at indices 3 and 2. What should replace the mock data?

## Options Considered

**A — Wire to live ReportsRepository data:** `fetchSalesSummary` + `fetchInventoryValuation` already exist. Real numbers.

**B — Delete the monitoring sidebar tabs.**

**C — Static access banner pointing to Reports tab.**

## Decision: Option A (live wire)

Replace mock chart data with live aggregates from `ReportsRepository`. Both endpoints are `IsManagerRole`-gated — admin + sales roles both admitted.

## Data mapping

**SalesMonitoringPage (`AdminSalesChart`):**
- Widget contract: `AdminSalesChart(values: List<double>, labels: List<String>)`
- Source: `SalesSummary.days` (List<SalesDay>) from `fetchSalesSummary(from, to)`
- Map: `values = days.map((d) => d.gross).toList()`, `labels = days.map((d) => d.day).toList()`
- Default range: last 7 days. Use `DateTime.now()` for `to`, `now.subtract(Duration(days: 6))` for `from`, formatted `YYYY-MM-DD`.
- Loading state: show `CircularProgressIndicator`; error state: `LiveLoadErrorBanner`.
- Add summary row above chart: `totalTransactions`, `totalGross` from `SalesSummary.totalTransactions` + `SalesSummary.totalGross`.

**InventoryMonitoringPage (`AdminInventorySummary`):**
- Widget contract: `AdminInventorySummary(metrics: List<(String, String)>)`
- Source: `InventoryValuation` from `fetchInventoryValuation()`
- Map to metric tuples: `[('Total items', valuation.totalUnits.toStringAsFixed(0)), ('Total cost value', '₱${valuation.totalCost.toStringAsFixed(2)}'), ('Total retail value', '₱${valuation.totalRetail.toStringAsFixed(2)}'), ('Batch count', '${valuation.batchCount}')]`
- Loading + error states required.

## Implementation approach

Use a `StatefulWidget` with `initState` triggering `_load()` via `postFrameCallback`, keeping `_isLoading`, `_error`, and the data object as state. A lightweight approach without a full viewmodel since these pages are simple single-fetch displays.

Alternatively reuse `AdminReportsViewmodel` with `selectTab` — but that brings the full 4-tab machinery into a 1-panel page. **Simpler: local `FutureBuilder` or minimal `StatefulWidget` with `setState`.**

## Files affected

- `flutter/lib/features/admin/views/sales_monitoring_page.dart` — replace mock → live `SalesSummary`
- `flutter/lib/features/admin/views/inventory_monitoring_page.dart` — replace mock → live `InventoryValuation`
- `flutter/lib/data/repositories/reports_repository.dart` — already has both methods; no change needed
- `flutter/lib/data/services/reports_service.dart` — already has both methods; no change needed

## Invariants

- `AdminMockData.salesValues`, `AdminMockData.salesLabels`, `AdminMockData.inventoryMetrics` must be removed from these two pages (they are the last consumers of those three fields in `admin_mock_data.dart`).
- If all three fields are removed, check if `admin_mock_data.dart` has remaining consumers before deleting the file. `storeName`, `storeEmail`, `storePhone` are still used by the inventory settings page.
- Empty `days` list (no sales in range) → empty chart, not crash. Show "No data for this period."

## Cost if wrong

Chart renders with fewer bars than expected if default range has sparse data — cosmetic. Loading state prevents a blank chart from looking like "no data" during fetch.
