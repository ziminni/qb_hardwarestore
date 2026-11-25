import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Dedicated Cashier view of Store Manager sales orders.
///
/// Cashiers see Confirmed, Partially Fulfilled, Completed, and Cancelled orders
/// in one place, inspect all ordered lines & stock availability, and click
/// **Complete at Till** on open orders to load remaining lines straight into
/// the POS till cart for payment and receipt printing.
class PosSalesOrdersPage extends StatefulWidget {
  const PosSalesOrdersPage({
    super.key,
    this.posService,
    this.customerService,
    this.onCompleteAtTill,
  });

  /// Injectable in tests so the screen can load without hitting the network.
  final PosService? posService;

  /// Injectable customer directory so order rows show real customer names.
  final CustomerService? customerService;

  /// Optional test hook overriding navigation to the till.
  final void Function(PosOpenOrder order)? onCompleteAtTill;

  @override
  State<PosSalesOrdersPage> createState() => _PosSalesOrdersPageState();
}

class _PosSalesOrdersPageState extends State<PosSalesOrdersPage> {
  static const String _allStatus = 'All';
  static const List<String> _statusChips = <String>[
    _allStatus,
    'Confirmed',
    'Partial',
    'Completed',
    'Cancelled',
  ];

  late final PosService _posService = widget.posService ?? PosService();
  late final CustomerService _customerService =
      widget.customerService ?? CustomerService();

  List<PosOpenOrder> _orders = const [];
  Map<int, String> _customerNames = const {};
  bool _isLoading = true;
  String? _loadError;
  String _query = '';
  String _statusFilter = _allStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel?>();
      if (inventory != null && !inventory.hasLoaded && !inventory.isLoading) {
        inventory.load();
      }
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _posService.fetchAllSalesOrders(),
        _customerService
            .fetchCustomers()
            .catchError((_) => const <Customer>[]),
      ]);
      if (!mounted) return;
      final orders = results[0] as List<PosOpenOrder>;
      final customers = results[1] as List<Customer>;
      setState(() {
        _orders = orders;
        _customerNames = {for (final c in customers) c.id: c.name};
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '$error';
      });
    }
  }

  String _customerName(PosOpenOrder order) =>
      _customerNames[order.customerId] ?? 'Customer #${order.customerId}';

  String _statusLabel(String raw) => switch (raw.toUpperCase()) {
    'CONFIRMED' => 'Confirmed',
    'PARTIAL' => 'Partial',
    'COMPLETED' => 'Completed',
    'CANCELLED' => 'Cancelled',
    _ => raw,
  };

  StatusTone _statusTone(String raw) => switch (raw.toUpperCase()) {
    'COMPLETED' => StatusTone.success,
    'PARTIAL' => StatusTone.warning,
    'CANCELLED' => StatusTone.error,
    _ => StatusTone.neutral,
  };

  bool _canComplete(PosOpenOrder order) =>
      order.isOpen && order.lines.any((line) => line.remainingQty > 0);

  List<PosOpenOrder> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final order in _orders)
        if ((_statusFilter == _allStatus ||
                _statusLabel(order.status) == _statusFilter) &&
            (q.isEmpty ||
                '${order.number} ${_customerName(order)} ${order.notes ?? ''}'
                    .toLowerCase()
                    .contains(q)))
          order,
    ];
  }

  void _completeAtTill(PosOpenOrder order) {
    final override = widget.onCompleteAtTill;
    if (override != null) {
      override(order);
      return;
    }
    PosTransactionPage.pendingOrderToLoad = order;
    context.go(AppRoutes.posDashboard);
  }

  Future<void> _openSheet(PosOpenOrder order) async {
    final inventory = context.read<InventoryViewmodel?>();
    final canComplete = _canComplete(order);
    final action = await showSalesDocumentSheet(
      context,
      title: order.number,
      fields: [
        ('Customer', _customerName(order)),
        ('Status', _statusLabel(order.status)),
        if (order.createdAt != null) ('Order date', formatDate(order.createdAt!)),
        if ((order.notes ?? '').trim().isNotEmpty) ('Notes', order.notes!.trim()),
      ],
      lines: [
        for (final line in order.lines)
          SalesDocumentLine(
            name: variantUomName(inventory, line.variantUomId),
            qty: line.qty,
            unitPrice: line.unitPrice,
            fulfilledQty: line.fulfilledQty,
            remainingQty: line.remainingQty,
            availableQty: line.availableQty,
          ),
      ],
      total: canComplete ? order.remainingTotal : order.orderTotal,
      canCompleteAtTill: canComplete,
    );
    if (!mounted) return;
    if (action == SalesDocumentAction.completeAtTill && canComplete) {
      _completeAtTill(order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openOrders = _orders.where(_canComplete).toList();
    final openRemainingTotal = openOrders.fold<double>(
      0,
      (sum, o) => sum + o.remainingTotal,
    );
    final completedCount = _orders
        .where((o) => o.status.toUpperCase() == 'COMPLETED')
        .length;
    final cancelledCount = _orders
        .where((o) => o.status.toUpperCase() == 'CANCELLED')
        .length;
    final rows = _visible;
    final firstLoadFailed = _loadError != null && _orders.isEmpty;

    return DashboardShell(
      title: 'Sales Orders',
      subtitle:
          'View customer sales orders and load open orders into the till to accept payment and print receipts.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'pos.sales-orders',
        AppAreas.pos,
      ),
      navigationItems: posNavigationItems,
      scrollable: false,
      onNavigationSelected: (index) => navigatePos(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              _CashierOrderKpi(
                label: 'Ready for Till',
                value: '${openOrders.length}',
                accent: AppColors.primary,
              ),
              _CashierOrderKpi(
                label: 'Remaining to Collect',
                value: formatPeso(openRemainingTotal),
                accent: AppColors.warningText,
              ),
              _CashierOrderKpi(
                label: 'Completed',
                value: '$completedCount',
                accent: AppColors.successText,
              ),
              _CashierOrderKpi(
                label: 'Cancelled',
                value: '$cancelledCount',
                accent: AppColors.errorText,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilterBar(
                  searchHint: 'Search order # or customer',
                  onSearchChanged: (value) => setState(() => _query = value),
                  options: _statusChips,
                  selected: _statusFilter,
                  onSelected: (chip) => setState(() => _statusFilter = chip),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Refresh sales orders',
                onPressed: _isLoading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_loadError != null && !firstLoadFailed) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _loadError!, onRetry: _load),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, slot) {
                final cards =
                    slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
                return DataPanel<PosOpenOrder>(
                  columns: _columns(withAction: !cards),
                  rows: rows,
                  showPageSizePicker: !cards,
                  emptyMessage: _query.trim().isNotEmpty || _statusFilter != _allStatus
                      ? 'No sales orders match these filters.'
                      : 'No sales orders found.',
                  isLoading: _isLoading && _orders.isEmpty,
                  error: firstLoadFailed ? _loadError : null,
                  onRetry: _load,
                  onRowTap: _openSheet,
                  rowKey: (order) => ValueKey('pos-sales-order-${order.id}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<DataPanelColumn<PosOpenOrder>> _columns({required bool withAction}) {
    return [
      DataPanelColumn<PosOpenOrder>(
        label: 'Order',
        flex: 2,
        cell: (order) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            StatusBadge(
              label: _statusLabel(order.status),
              tone: _statusTone(order.status),
            ),
          ],
        ),
      ),
      DataPanelColumn<PosOpenOrder>(
        label: 'Customer',
        flex: 3,
        cell: (order) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _customerName(order),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            if (order.createdAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Ordered ${formatDate(order.createdAt!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      DataPanelColumn<PosOpenOrder>(
        label: 'Items',
        flex: 2,
        cell: (order) {
          final remainingLines =
              order.lines.where((l) => l.remainingQty > 0).length;
          final subtitle = switch (order.status.toUpperCase()) {
            'CANCELLED' => 'Order cancelled',
            'COMPLETED' => 'All ${order.lines.length} line(s) fulfilled',
            _ => '$remainingLines of ${order.lines.length} line(s) remaining',
          };
          return Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          );
        },
      ),
      DataPanelColumn<PosOpenOrder>(
        label: 'Amount',
        numeric: true,
        flex: 2,
        cell: (order) {
          final open = _canComplete(order);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPeso(open ? order.remainingTotal : order.orderTotal),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (open && order.remainingTotal != order.orderTotal)
                Text(
                  'of ${formatPeso(order.orderTotal)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          );
        },
      ),
      if (withAction)
        DataPanelColumn<PosOpenOrder>(
          label: 'Action',
          flex: 3,
          cell: (order) => Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => _openSheet(order),
                child: const Text('View'),
              ),
              if (_canComplete(order))
                FilledButton.tonalIcon(
                  key: ValueKey('pos-sales-order-complete-${order.id}'),
                  onPressed: () => _completeAtTill(order),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 16),
                  label: const Text('Complete at Till'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}

class _CashierOrderKpi extends StatelessWidget {
  const _CashierOrderKpi({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: p.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
