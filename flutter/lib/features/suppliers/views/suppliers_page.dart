import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:client/features/suppliers/widgets/suppliers_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Suppliers screen (decision D-02, Phase 4 Task 4).
///
/// Add, edit and activate/deactivate all reach `/api/v1/suppliers/` now, and each
/// one reloads. The Phase 1 version could only READ: the Add button and the Edit
/// action were removed because the repository had no write method, and the
/// activate/deactivate chip toggled a session-local map that a reload threw away.
/// That map is gone — `_activeOverrides` existed precisely because nothing was
/// written down.
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

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm([Supplier? supplier]) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final result = await showDialog<Supplier>(
      context: context,
      builder: (_) => SuppliersFormDialog(supplier: supplier),
    );
    if (result == null || !mounted) return;
    final error = await state.saveSupplier(result);
    _announce(
      error ??
          '${result.companyName} ${supplier == null ? 'added' : 'updated'}.',
    );
  }

  Future<void> _toggle(Supplier supplier) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final error = await state.toggleSupplier(supplier);
    _announce(
      error ??
          '${supplier.companyName} '
              '${supplier.isActive ? 'deactivated' : 'activated'}.',
    );
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
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add supplier'),
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
              onEdit: _openForm,
              onToggle: _toggle,
            ),
        ],
      ),
    );
  }
}
