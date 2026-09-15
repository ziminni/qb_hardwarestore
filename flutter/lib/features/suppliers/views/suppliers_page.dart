import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:client/features/suppliers/widgets/suppliers_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _query = '';
  Future<void> _form([Supplier? supplier]) async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (_) => SuppliersFormDialog(supplier: supplier),
    );
    if (result == null || !mounted) return;
    context.read<SuppliersPurchasesViewmodel>().saveSupplier(result);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supplier saved in mock data.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    final suppliers = state.suppliers
        .where(
          (item) => '${item.companyName} ${item.contactPerson} ${item.email}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
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
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: _form,
                icon: const Icon(Icons.add),
                label: const Text('Add Supplier'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SuppliersTable(
            suppliers: suppliers,
            purchaseCount: (id) =>
                state.purchases.where((item) => item.supplierId == id).length,
            onEdit: _form,
            onToggle: state.toggleSupplier,
          ),
        ],
      ),
    );
  }
}
