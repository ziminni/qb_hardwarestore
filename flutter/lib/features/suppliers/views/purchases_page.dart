import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  String _query = '';
  PurchaseStatus? _status;
  Future<void> _create() async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final order = await showDialog<PurchaseOrder>(
      context: context,
      builder: (_) => PurchasesFormDialog(
        suppliers: state.suppliers,
        products: context.read<InventoryViewmodel>().products,
      ),
    );
    if (order == null || !mounted) return;
    state.addPurchase(order);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draft purchase order created in mock data.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    final orders = state.purchases
        .where(
          (item) =>
              ('PO-${item.id} ${item.supplierName}').toLowerCase().contains(
                _query.toLowerCase(),
              ) &&
              (_status == null || item.status == _status),
        )
        .toList();
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
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Create Purchase Order'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
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
