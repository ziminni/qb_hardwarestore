import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_low_stock_table.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Status as the filter offers it: chips that add up to "all or one".
///
/// The values are the filter's state, the keys its copy. "All" is null so the
/// page holds one nullable field instead of an "all" enum member the stock
/// status model does not have.
const _statusChips = <String, InventoryStockStatus?>{
  'All': null,
  'Out of stock': InventoryStockStatus.outOfStock,
  // The row badge's word, not a shortening of it: one state, one word.
  'Low stock': InventoryStockStatus.lowStock,
};

const _showResolvedChip = 'Show resolved';

/// Low stock, live (Phase 4 Task 4).
///
/// Two controls that used to lie now work:
///
///  * **Reorder** opened "Future Purchasing connection" and now opens the real
///    New purchase order dialog, prefilled with that variant and a suggested
///    quantity (`max_stock_level − on hand` when positive, else the threshold).
///  * **Resolve** did not exist, so a cleared alert stayed open forever. It calls
///    `POST /alerts/{id}/resolve/` and shows who resolved it and when.
///
/// Membership still comes from the server's alerts, not from a client predicate
/// (decision 13): the list is what the server alerted, which is why it can be
/// shorter than the stock screen's own low-stock count. The page filters those
/// alerts and words the empty states; the table orders them by urgency and
/// renders them.
class InventoryLowStockPage extends StatefulWidget {
  const InventoryLowStockPage({super.key});
  @override
  State<InventoryLowStockPage> createState() => _InventoryLowStockPageState();
}

class _InventoryLowStockPageState extends State<InventoryLowStockPage> {
  String _query = '';
  bool _showResolved = false;
  InventoryStockStatus? _status;

  /// The chip that matches the current status. Always one: "All" is null.
  String get _statusChip =>
      _statusChips.entries.firstWhere((entry) => entry.value == _status).key;

  @override
  void initState() {
    super.initState();
    // F2: this screen read the store but never fetched it, so a refresh straight
    // onto /inventory/low-stock painted "No low-stock products match this
    // search." before anything had been read — and kept painting it, because
    // nothing ever fetched.
    //
    // Deferred past the first frame: `load()` notifies synchronously and marking
    // an element dirty mid-build throws. Guarded by `hasLoaded` because the store
    // is app-scoped and shared with the Stock, Products and dashboard screens —
    // the Retry button covers a stale list, and Resolve reloads anyway.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded) inventory.load();
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The server admits Stock Manager / Store Manager / Admin to `resolve/`
  /// (`IsInventoryRole`). Everyone else is not offered the button.
  ///
  /// `roleName` is the role CODE the server sends as `role.name` (`inventory`,
  /// `sales`, `admin`) — the same codes `AppRoutes.dashboardForRole` routes on.
  /// Comparing it to the display labels hid Resolve from every role live.
  bool _canResolve(BuildContext context) {
    final role = context.read<AuthViewmodel>().roleName;
    return const {'inventory', 'sales', 'admin'}.contains(role);
  }

  Future<void> _reorder(Product product, ProductVariant variant) async {
    final inventory = context.read<InventoryViewmodel>();
    final purchasing = context.read<SuppliersPurchasesViewmodel>();
    if (purchasing.suppliers.isEmpty) {
      // The suppliers list is app-scoped but only fetched by the screens that
      // read it. Ordering needs it, so fetch it before opening the dialog rather
      // than showing an empty supplier picker.
      await purchasing.load();
      if (!mounted) return;
    }
    final result = await showDialog<PurchaseOrderFormResult>(
      context: context,
      builder: (_) => PurchasesFormDialog(
        suppliers: purchasing.suppliers,
        products: inventory.products,
        costFor: (variantId) => inventory.costFor(variantId) ?? 0,
        initialVariantId: variant.id,
        initialQuantity: inventory.suggestedReorderQty(variant.id),
      ),
    );
    if (result == null || !mounted) return;
    final error = await purchasing.createPurchaseOrder(
      result.draft,
      place: result.place,
    );
    _announce(
      error ??
          (result.place
              ? 'Purchase order placed for ${product.baseName}.'
              : 'Draft purchase order saved for ${product.baseName}.'),
    );
  }

  Future<void> _resolve(SystemAlert alert) async {
    final inventory = context.read<InventoryViewmodel>();
    final error = await inventory.resolveAlert(alert.id);
    _announce(error ?? 'Alert resolved.');
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final canResolve = _canResolve(context);

    // Decision 13, rule 1: the low-stock screen READS the server's alerts.
    final visibleAlerts = inventory.alerts
        .where((alert) => _showResolved || !alert.isResolved)
        .toList(growable: false);
    final rows = <LowStockRow>[];
    for (final alert in visibleAlerts) {
      for (final record in inventory.stockRecords) {
        if (record.variant.id != alert.variantId) continue;
        final matchesQuery =
            '${record.product.baseName} '
                    '${record.variant.variantName} '
                    '${record.variant.barcode}'
                .toLowerCase()
                .contains(_query.toLowerCase());
        if (!matchesQuery) continue;
        if (_status != null &&
            inventory.statusForVariant(record.variant.id) != _status) {
          continue;
        }
        rows.add(
          LowStockRow(
            alert: alert,
            product: record.product,
            variant: record.variant,
          ),
        );
      }
    }

    final failure = inventory.loadError;
    final pending = inventory.isLoading || !inventory.hasLoaded;
    // A failed read keeps the alerts it already had and says why above them, in
    // one banner the page owns. With nothing to keep there is no list at all:
    // an empty panel would read as "the server flagged nothing", which is the
    // one thing a failed fetch has not established.
    final firstLoadFailed = failure != null && rows.isEmpty && !pending;
    final filtered = _query.trim().isNotEmpty || _status != null;

    return InventorySkeletonLayout(
      title: 'Low Stock',
      subtitle: 'Variants the server has alerted as low or out of stock.',
      selectedNavigationIndex: 5,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // FX3 (wave 3a fix pass): the sidebar badge is THIS page's own count, read
      // from the store the page resolves through, so Resolve clears it on the
      // screen it happened on. The shell's one-off read could not see a resolve
      // and left the badge at its mount-time number until another route mounted.
      // Before a successful read there is no marker at all: a blank badge beats
      // a false 0, and the banner above the table reports the failure.
      markers: inventory.hasLoaded && failure == null
          ? {
              InventorySkeletonLayout.lowStockIndex: inventory.alerts
                  .where((alert) => !alert.isResolved)
                  .length,
            }
          : const {},
      // The alert list can grow to one row per variant, so it builds its rows
      // lazily inside the panel's own slot instead of all at once in a page
      // scroll view. That needs a bounded body, hence `scrollable: false`.
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterBar(
            searchHint: 'Search low-stock items',
            options: _statusChips.keys.toList(),
            selected: _statusChip,
            onSearchChanged: (value) => setState(() => _query = value),
            onSelected: (label) =>
                setState(() => _status = _statusChips[label]),
            extraOptions: const [_showResolvedChip],
            extraSelected: _showResolved ? _showResolvedChip : null,
            onExtraSelected: (_) =>
                setState(() => _showResolved = !_showResolved),
          ),
          const SizedBox(height: AppSpacing.md),
          if (failure != null && !pending)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: inventory.load),
            ),
          Expanded(
            child: firstLoadFailed
                ? const SizedBox.shrink()
                : InventoryLowStockTable(
                    rows: rows,
                    inventory: inventory,
                    onReorder: _reorder,
                    onResolve: canResolve ? _resolve : null,
                    // Distinguish "nothing to fix" from "your filter hides it".
                    emptyMessage: filtered
                        ? 'No low-stock products match this search.'
                        : 'No low-stock alerts right now.',
                    // The spinner is for a first load with nothing to show. A
                    // reload over rows must not wipe them: the banner above
                    // already says the rows are the last good ones.
                    isLoading: pending && rows.isEmpty,
                  ),
          ),
        ],
      ),
    );
  }
}
