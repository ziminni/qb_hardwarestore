import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/inventory/widgets/inventory_stock_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryStockPage extends StatefulWidget {
  const InventoryStockPage({super.key});
  @override
  State<InventoryStockPage> createState() => _InventoryStockPageState();
}

class _InventoryStockPageState extends State<InventoryStockPage> {
  String _query = '';
  String? _category;
  InventoryStockStatus? _status;
  String? _location;
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    // F2: the stock screen had no load trigger and no loading or error state, so
    // a refresh on this route answered "No stock records match these filters."
    // before anything had been fetched. Deferred past the first frame (`load()`
    // notifies synchronously) and guarded by `hasLoaded` because the store is
    // app-scoped: another screen has usually already fetched it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded) inventory.load();
    });
  }

  Future<void> _adjust(Product product, ProductVariant variant) async {
    final inventory = context.read<InventoryViewmodel>();
    final result = await showDialog<InventoryAdjustStockResult>(
      context: context,
      builder: (_) => InventoryAdjustStockDialog(
        product: product,
        variant: variant,
        currentStock: inventory.stockOnHandFor(variant.id),
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // A real write now: the viewmodel POSTs to /api/v1/adjustments/ and re-reads,
    // so both the stock figure and the movement row come from the server. The
    // snackbar no longer claims the change lives in mock data.
    final recorded = await inventory.adjustStock(
      variantId: variant.id,
      newQuantity: result.quantity,
      reason: result.reason,
      notes: result.notes,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          recorded
              ? 'Adjustment recorded on the server.'
              : inventory.loadError ?? 'The adjustment could not be recorded.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final locations =
        inventory.stockRecords
            .map((item) => inventory.locationHintFor(item.variant.id))
            .where((location) => location.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final records =
        inventory.stockRecords.where((record) {
          final search =
              '${record.product.baseName} ${record.variant.variantName} ${record.variant.barcode}'
                  .toLowerCase();
          return search.contains(_query.toLowerCase()) &&
              (_category == null || record.product.categoryName == _category) &&
              (_status == null ||
                  inventory.statusForVariant(record.variant.id) == _status) &&
              (_location == null ||
                  inventory.locationHintFor(record.variant.id) == _location);
        }).toList()..sort(
          (a, b) => _ascending
              ? a.product.baseName.compareTo(b.product.baseName)
              : b.product.baseName.compareTo(a.product.baseName),
        );
    final failure = inventory.loadError;
    final pending = inventory.isLoading || !inventory.hasLoaded;

    return InventorySkeletonLayout(
      title: 'Stock',
      subtitle: 'Current quantity for every product variant.',
      selectedNavigationIndex: 3,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // Loading outranks error, error outranks empty (the rule `AsyncView`
      // documents): a failed fetch must never be dressed as an empty stock book.
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
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search product, variant, or SKU',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _category,
                        // Load-bearing, like the Purchases filter: the selected label
                        // plus the arrow does not fit the fixed 180px box without it,
                        // and an overflowing Row clips the label.
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All categories'),
                          ),
                          ...inventory.categories.map(
                            (item) => DropdownMenuItem(
                              value: item.name,
                              child: Text(item.name),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<InventoryStockStatus?>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Stock status',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All statuses'),
                          ),
                          ...InventoryStockStatus.values.map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _location,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All locations'),
                          ),
                          ...locations.map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _location = value),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _ascending = !_ascending),
                      icon: const Icon(Icons.sort_by_alpha),
                      label: Text(_ascending ? 'Name A–Z' : 'Name Z–A'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                // Withhold the table when the load failed and nothing was retained, so
                // its empty copy cannot speak for a fetch that never succeeded.
                if (failure == null || records.isNotEmpty)
                  InventoryStockTable(
                    records: records,
                    inventory: inventory,
                    onAdjust: _adjust,
                  ),
              ],
            ),
    );
  }
}
