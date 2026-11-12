import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_list_content.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_order_form_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's sales orders screen: a shell only (card M3). The list,
/// the search, the status chips and the empty and error states live in
/// [SalesDocumentListContent], which the quotations screen shows too.
///
/// "New sales order" WAS gone (Phase 3 Task 0) because no backend existed. The
/// owner authorised create-only entry (Phase 5 F3 follow-up): this page can now
/// raise an order, and still cannot edit, delete, change status or fulfil one —
/// no such route exists in this build.
class SalesOrdersPage extends StatefulWidget {
  const SalesOrdersPage({super.key});

  @override
  State<SalesOrdersPage> createState() => _SalesOrdersPageState();
}

class _SalesOrdersPageState extends State<SalesOrdersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SalesModuleViewmodel>().load();
    });
  }

  /// Opens the read-only document sheet (decision D-02). Same seam as the
  /// quotations page: catalogue names when loaded, ids when not.
  void _showOrderSheet(BuildContext context, SalesOrderRecord item) {
    final inventory = context.read<InventoryViewmodel?>();
    showSalesDocumentSheet(
      context,
      title: item.number,
      fields: [
        ('Customer', item.customer),
        ('Status', _orderStatusLabel(item.status)),
        ('Order date', formatDate(item.date)),
        if ((item.notes ?? '').isNotEmpty) ('Notes', item.notes!),
      ],
      lines: [
        for (final line in item.items)
          SalesDocumentLine(
            name: variantUomName(inventory, line.variantUomId),
            qty: line.qty,
            unitPrice: line.unitPrice,
          ),
      ],
      total: item.total,
    );
  }

  /// Opens the create form and posts what it collected.
  ///
  /// The dialog posts through the viewmodel itself, because a refusal must land
  /// INSIDE the form with the input intact; only a success closes it, and then
  /// the viewmodel has already reloaded the list.
  Future<void> _openForm() async {
    final viewmodel = context.read<SalesModuleViewmodel>();
    final inventory = context.read<InventoryViewmodel?>();
    if (inventory != null && !inventory.hasLoaded) await inventory.load();
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => SalesOrderFormDialog(
        customers: viewmodel.customers,
        catalogue: inventory?.catalogue ?? const [],
        onSubmit: viewmodel.createOrder,
      ),
    );
    if (created != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sales order created.')));
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesModuleViewmodel>();
    final orders = viewmodel.orders;

    return SalesSkeletonLayout(
      title: 'Sales Orders',
      subtitle: 'Track confirmed orders from preparation through completion.',
      selectedNavigationIndex: 3,
      // The list owns the scrolling, so it builds only the rows on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('New sales order'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // The list takes the rest of the slot and scrolls its own rows.
          Expanded(
            child: SalesDocumentListContent(
              kind: SalesDocumentKind.order,
              rows: [for (final item in orders) _row(item)],
              isLoading: viewmodel.isLoading,
              loadError: viewmodel.loadError,
              onRetry: viewmodel.load,
            ),
          ),
        ],
      ),
    );
  }

  SalesDocumentRow _row(SalesOrderRecord item) {
    return SalesDocumentRow(
      number: item.number,
      customer: item.customer,
      date: item.date,
      total: item.total,
      statusLabel: _orderStatusLabel(item.status),
      tone: _orderTone(item.status),
      onOpen: () => _showOrderSheet(context, item),
    );
  }
}

StatusTone _orderTone(SalesOrderStatus status) {
  return switch (status) {
    SalesOrderStatus.completed => StatusTone.success,
    SalesOrderStatus.ready => StatusTone.info,
    SalesOrderStatus.processing => StatusTone.warning,
    SalesOrderStatus.confirmed => StatusTone.neutral,
  };
}

String _orderStatusLabel(SalesOrderStatus value) =>
    value.name[0].toUpperCase() + value.name.substring(1);
