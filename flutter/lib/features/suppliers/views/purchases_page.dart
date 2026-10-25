import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Purchases screen (decision D-02, Phase 4 Task 4).
///
/// "New purchase order" creates a real order on the server with its lines nested
/// in the POST, and the row actions are the server's own transitions: `place/`
/// from DRAFT, `cancel/` while nothing has been received. Before this the button
/// was removed entirely because the dialog's Save could only have mutated a local
/// list — the `addPurchase` mock this screen deleted in Phase 1.
///
/// Status filtering stays client-side — the list is one page-set of the whole PO
/// book and a dropdown over it is cheaper than a round trip per keystroke.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  String _query = '';
  PurchaseStatus? _status;

  @override
  void initState() {
    super.initState();
    // Load on open; both tabs share one app-scoped viewmodel, so whichever opens
    // last refreshes both lists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuppliersPurchasesViewmodel>().load();
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newOrder() async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final inventory = context.read<InventoryViewmodel>();
    // The product picker is built from the shared catalogue, which this screen
    // does not own and never loaded. Fetch it first rather than opening a picker
    // with no rows and no explanation (F2 page sweep).
    if (!inventory.hasLoaded) {
      await inventory.load();
      if (!mounted) return;
    }
    final result = await showDialog<PurchaseOrderFormResult>(
      context: context,
      builder: (_) => PurchasesFormDialog(
        suppliers: state.suppliers,
        products: inventory.products,
        costFor: (variantId) => inventory.costFor(variantId) ?? 0,
      ),
    );
    if (result == null || !mounted) return;
    final error = await state.createPurchaseOrder(
      result.draft,
      place: result.place,
    );
    _announce(error ?? (result.place ? 'Order placed.' : 'Draft saved.'));
  }

  Future<void> _confirmCancel(PurchaseOrder order) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel PO-${order.id}?'),
        content: const Text(
          'A cancelled order cannot be received. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await state.cancelOrder(order);
    _announce(error ?? 'PO-${order.id} cancelled.');
  }

  Future<void> _place(PurchaseOrder order) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final error = await state.placeOrder(order);
    _announce(error ?? 'PO-${order.id} placed.');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    final orders = state.filteredPurchases(query: _query, status: _status);
    return InventorySkeletonLayout(
      title: 'Purchases',
      subtitle: 'Plan and monitor supplier purchase orders.',
      selectedNavigationIndex: 6,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search PO or supplier',
                  ),
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<PurchaseStatus?>(
                  initialValue: _status,
                  // `isExpanded` is load-bearing: "Partially Received" is wider
                  // than the 210px box, so without it the selected label
                  // overflows the decoration by ~109px.
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...PurchaseStatus.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _status = value),
                ),
              ),
              FilledButton.icon(
                onPressed: _newOrder,
                icon: const Icon(Icons.add),
                label: const Text('New purchase order'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (state.loadError case final error?)
            LiveLoadErrorBanner(message: error, onRetry: state.load)
          else
            PurchasesTable(
              orders: orders,
              onView: (order) => showDialog<void>(
                context: context,
                builder: (_) => PurchasesDetailsDialog(order: order),
              ),
              onPlace: _place,
              onCancel: _confirmCancel,
            ),
        ],
      ),
    );
  }
}
