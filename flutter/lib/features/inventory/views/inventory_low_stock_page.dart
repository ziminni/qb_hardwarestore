import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_low_stock_table.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Low stock, live (Phase 4 Task 4).
///
/// Two controls that used to lie now work:
///
///  * **Reorder** opened "Future Purchasing connection — will connect to the
///    Purchasing module in a future implementation". It now opens the real New
///    purchase order dialog, prefilled with that variant and a suggested
///    quantity (`max_stock_level − on hand` when positive, else the threshold).
///  * **Resolve** did not exist, so a cleared alert stayed open forever. It calls
///    `POST /alerts/{id}/resolve/` and shows who resolved it and when — and only
///    the roles the server admits (Stock Manager / Admin) see it at all.
///
/// Membership still comes from the server's alerts, not from a client predicate
/// (decision 13): the list is what the server alerted, which is why it can be
/// shorter than the stock screen's own low-stock count.
class InventoryLowStockPage extends StatefulWidget {
  const InventoryLowStockPage({super.key});
  @override
  State<InventoryLowStockPage> createState() => _InventoryLowStockPageState();
}

class _InventoryLowStockPageState extends State<InventoryLowStockPage> {
  String _query = '';
  bool _showResolved = false;

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
  bool _canResolve(BuildContext context) {
    final role = context.read<AuthViewmodel>().roleName;
    return role == 'Stock Manager' ||
        role == 'Store Manager' ||
        role == 'Admin';
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
        if (!'${record.product.baseName} ${record.variant.variantName} ${record.variant.barcode}'
            .toLowerCase()
            .contains(_query.toLowerCase())) {
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

    return InventorySkeletonLayout(
      title: 'Low Stock',
      subtitle: 'Variants the server has alerted as low or out of stock.',
      selectedNavigationIndex: 5,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // Loading, then error, then data — the precedence `AsyncView` documents.
      // Nothing is claimed here before the first attempt finishes, and a failed
      // attempt is never reported as an empty result: see F2.
      child: pending
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (failure != null)
                  LiveLoadErrorBanner(
                    message: failure,
                    onRetry: inventory.load,
                  ),
                Row(
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search low-stock items',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    FilterChip(
                      label: const Text('Show resolved'),
                      selected: _showResolved,
                      onSelected: (value) =>
                          setState(() => _showResolved = value),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                // A failed load with nothing retained shows the banner INSTEAD of
                // the table, so the table's "no low-stock products" copy cannot
                // speak for a fetch that never succeeded. Rows kept from an
                // earlier good load stay visible under the banner.
                if (failure == null || rows.isNotEmpty)
                  InventoryLowStockTable(
                    rows: rows,
                    inventory: inventory,
                    onReorder: _reorder,
                    onResolve: canResolve ? _resolve : null,
                  ),
              ],
            ),
    );
  }
}
