import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Purchases screen (decision D-02).
///
/// Reads the live purchase orders. The **Create Purchase Order** button is
/// gone, not greyed: the repository has no write method this pass, so the
/// dialog's Save would have been the `addPurchase` mock this rewrite deleted.
///
/// Status filtering stays client-side — the list is one page-set of the whole
/// PO book and a dropdown over it is cheaper than a round trip per keystroke.
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
    // Load on open; see SuppliersPage. Both tabs share one app-scoped
    // viewmodel, so whichever opens last refreshes both lists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuppliersPurchasesViewmodel>().load();
    });
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
            ),
        ],
      ),
    );
  }
}
