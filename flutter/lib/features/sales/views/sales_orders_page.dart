import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_list_content.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_order_cancel_dialog.dart';
import 'package:client/features/sales/widgets/sales_order_form_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's sales orders screen: a shell only (card M3). The list,
/// the search, the status chips and the empty and error states live in
/// [SalesDocumentListContent], which the quotations screen shows too.
///
/// "New sales order" WAS gone (Phase 3 Task 0) because no backend existed; the
/// owner authorised create-only entry (Phase 5 F3 follow-up). Phase 7 F1 makes
/// the promise correctable: a Store Manager or Admin gets **Edit** and **Cancel**
/// on an order the shop has not started keeping, and the sheet says what has been
/// fulfilled and what is left. DELETE stays gone for orders — cancellation
/// replaces it (decision 19). Cashiers and the Stock Manager get neither: their
/// work happens at the till, through the fulfilment flow (F2).
class SalesOrdersPage extends StatefulWidget {
  const SalesOrdersPage({super.key, this.approvalService});

  /// Injected by tests so an above-cap create or edit can be approved without a
  /// server.
  final DiscountApprovalService? approvalService;

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

  /// Opens the document sheet (decision D-02). Same seam as the quotations page:
  /// catalogue names when loaded, ids when not.
  ///
  /// The lifecycle actions are the PAGE's to offer: the sheet is a view, so it
  /// closes with the choice and this method opens the dialog that acts.
  Future<void> _showOrderSheet(
    BuildContext context,
    SalesOrderRecord item,
  ) async {
    final inventory = context.read<InventoryViewmodel?>();
    final manager = _mayManage(context);
    final action = await showSalesDocumentSheet(
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
            fulfilledQty: line.fulfilledQty,
            remainingQty: line.remainingQty,
            availableQty: line.availableQty,
          ),
      ],
      total: item.total,
      canEdit: manager && _canEdit(item),
      canCancel: manager && _canCancel(item),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SalesDocumentAction.edit:
        await _openEditForm(item);
      case SalesDocumentAction.cancel:
        await _openCancelDialog(item);
    }
  }

  /// Whether this account may edit or cancel at all.
  ///
  /// The role CODE decides (Phase 4 lesson: labels lie), and the SERVER still
  /// decides what is allowed — `IsManagerRole` on PATCH and `cancel/` answers 403
  /// whatever this returns. Same comparison as the unlinked-return action.
  ///
  /// `read`, not `watch`: this runs from a tap, and a role does not change under
  /// a screen that is already open.
  bool _mayManage(BuildContext context) {
    final role = context.read<AuthViewmodel?>()?.roleName;
    return role == 'sales' || role == 'admin';
  }

  /// Decision 19 #4: editable only while nothing has been fulfilled. Past that,
  /// the lines are the record of what was promised.
  static bool _canEdit(SalesOrderRecord order) =>
      order.status == SalesOrderStatus.confirmed &&
      order.items.every((line) => line.fulfilledQty == 0);

  /// The remainder can be written off until the order is over.
  static bool _canCancel(SalesOrderRecord order) =>
      order.status == SalesOrderStatus.confirmed ||
      order.status == SalesOrderStatus.partial;

  /// Opens the form in EDIT mode and patches what it collected.
  ///
  /// The dialog posts through the viewmodel itself: a refusal (a price above the
  /// cap, an order a fulfilment got to first) must land INSIDE the form with the
  /// numbers intact, and only a success closes it.
  Future<void> _openEditForm(SalesOrderRecord order) async {
    final viewmodel = context.read<SalesModuleViewmodel>();
    final inventory = context.read<InventoryViewmodel?>();
    if (inventory != null && !inventory.hasLoaded) await inventory.load();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SalesOrderFormDialog(
        customers: viewmodel.customers,
        catalogue: inventory?.catalogue ?? const [],
        order: order,
        onSubmitEdit: (edit) => viewmodel.updateOrder(order.id, edit),
        approvalService: widget.approvalService,
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sales order updated.')));
  }

  /// Asks for the reason and writes the order off.
  Future<void> _openCancelDialog(SalesOrderRecord order) async {
    final viewmodel = context.read<SalesModuleViewmodel>();
    final cancelled = await showDialog<bool>(
      context: context,
      builder: (_) => SalesOrderCancelDialog(
        orderNumber: order.number,
        onSubmit: (reason) => viewmodel.cancelOrder(order.id, reason: reason),
      ),
    );
    if (cancelled != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sales order cancelled.')));
  }

  /// Opens the create form and posts what it collected.
  ///
  /// The dialog posts through the viewmodel itself, because a refusal must land
  /// INSIDE the form with the input intact; only a success closes it, and then
  /// the viewmodel has already reloaded the list. [approvalService] rides along
  /// because a create is guarded exactly like an edit: an above-cap price asks a
  /// manager in place (decision 19 #1 — the same rule for every role).
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
        approvalService: widget.approvalService,
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
          // A failed load left no customers to name and no fresh rows behind it,
          // so the form is offered only once the page has read what it needs.
          if (viewmodel.loadError == null)
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
    SalesOrderStatus.partial => StatusTone.warning,
    SalesOrderStatus.cancelled => StatusTone.error,
    SalesOrderStatus.confirmed => StatusTone.neutral,
  };
}

String _orderStatusLabel(SalesOrderStatus value) =>
    value.name[0].toUpperCase() + value.name.substring(1);
