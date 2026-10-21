import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/suppliers_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Suppliers screen (decision D-02).
///
/// Reads the live vendor list. Two things are gone rather than greyed:
///
///  * the **Add Supplier** button — the repository has no write method this
///    pass, so the button would open a dialog whose Save did nothing;
///  * the **Edit** action on each row, for the same reason. Deactivate stays
///    because the viewmodel still owns that flag locally and the chip visibly
///    changes.
///
/// The search box still filters client-side: `SupplierViewSet` configures no
/// `SearchFilter`, so a server-side search would silently match nothing.
class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load on open. The viewmodel is app-scoped (shared with the Purchases tab),
    // so this also refreshes a list another tab may have left stale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuppliersPurchasesViewmodel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    final suppliers = state.filteredSuppliers(query: _query);
    return InventorySkeletonLayout(
      title: 'Suppliers',
      subtitle: 'Manage vendors connected to purchase orders.',
      selectedNavigationIndex: 7,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  width: 330,
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search suppliers',
                    ),
                  ),
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
            SuppliersTable(
              suppliers: suppliers,
              purchaseCount: (id) =>
                  state.purchases.where((item) => item.supplierId == id).length,
              onEdit: null,
              onToggle: state.toggleSupplier,
            ),
        ],
      ),
    );
  }
}
