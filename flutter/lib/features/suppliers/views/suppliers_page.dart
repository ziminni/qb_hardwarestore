import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:client/features/suppliers/widgets/suppliers_table.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Suppliers screen (decision D-02, Phase 4 Task 4).
///
/// Add, edit and activate/deactivate all reach `/api/v1/suppliers/` and each one
/// reloads. The Phase 1 version could only READ: the Add button and the Edit
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

  /// The purchase form with this supplier already chosen, so a reader who needs
  /// more cement does not pick the vendor a second time.
  Future<void> _newOrderFor(Supplier supplier) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final inventory = context.read<InventoryViewmodel>();
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
        initialSupplierId: supplier.id,
      ),
    );
    if (result == null || !mounted) return;
    final error = await state.createPurchaseOrder(
      result.draft,
      place: result.place,
    );
    _announce(error ?? (result.place ? 'Order placed.' : 'Draft saved.'));
  }

  /// Purchase orders still in flight for a supplier: draft, ordered or partly
  /// received. Read off the PO book the shared viewmodel already loaded, so the
  /// count is the server's, not a guess.
  int _openOrdersFor(int supplierId) => context
      .read<SuppliersPurchasesViewmodel>()
      .purchases
      .where(
        (order) =>
            order.supplierId == supplierId &&
            (order.status == PurchaseStatus.draft ||
                order.status == PurchaseStatus.ordered ||
                order.status == PurchaseStatus.partial),
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    final suppliers = state.filteredSuppliers(query: _query);
    final failure = state.loadError;
    // A failed refresh keeps the rows it already had and says why above them.
    final staleRows = failure != null && suppliers.isNotEmpty;

    return InventorySkeletonLayout(
      title: 'Suppliers',
      subtitle: 'Manage vendors connected to purchase orders.',
      selectedNavigationIndex: 7,
      // The list owns the scrolling: rows build only as they come on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FilterBar(
                  searchHint: 'Search suppliers',
                  onSearchChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add supplier'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (staleRows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: state.load),
            ),
          Expanded(
            // DataPanel hugs its own empty and error states and fills the slot
            // once there are rows, so no page-level wrapper is needed here.
            child: SuppliersTable(
              suppliers: suppliers,
              openOrderCount: _openOrdersFor,
              onEdit: _openForm,
              onToggle: _toggle,
              onNewOrder: _newOrderFor,
              emptyMessage: _query.isEmpty
                  ? 'No suppliers yet.'
                  : 'No suppliers match this search.',
              isLoading: state.isLoading && suppliers.isEmpty,
              error: staleRows ? null : failure,
              onRetry: state.load,
            ),
          ),
        ],
      ),
    );
  }
}
