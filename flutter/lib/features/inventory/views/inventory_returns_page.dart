import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/payables/widgets/supplier_return_dialog.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Stock Manager → Supplier Returns: full history of goods returned by the
/// hardware store back to suppliers (shrinkage, damaged deliveries, defects,
/// wrong items, expiry), plus `+ New supplier return` against any processed
/// delivery receipt.
class InventoryReturnsPage extends StatefulWidget {
  const InventoryReturnsPage({
    super.key,
    this.payablesService,
    this.inventoryService,
  });

  /// Injectable in tests so the history and create flow can run without a server.
  final PayablesService? payablesService;
  final InventoryService? inventoryService;

  @override
  State<InventoryReturnsPage> createState() => _InventoryReturnsPageState();
}

class _InventoryReturnsPageState extends State<InventoryReturnsPage> {
  static const String _allFilter = 'All';
  static const List<String> _filters = [
    _allFilter,
    'Open credit',
    'Credit used',
  ];

  late final PayablesService _payables =
      widget.payablesService ?? PayablesService();
  late final InventoryService _inventory =
      widget.inventoryService ?? InventoryService();

  List<SupplierReturn> _returns = const [];
  bool _isLoading = false;
  String? _loadError;
  String _query = '';
  String _creditFilter = _allFilter;

  bool get _filtered =>
      _query.trim().isNotEmpty || _creditFilter != _allFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final rows = await _payables.fetchReturns();
      if (!mounted) return;
      setState(() {
        _returns = rows;
        _loadError = null;
      });
    } on PayablesServiceException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<SupplierReturn> get _visible => [
    for (final item in _returns)
      if (_matchesCredit(item) && _matchesQuery(item)) item,
  ];

  bool _matchesCredit(SupplierReturn item) => switch (_creditFilter) {
    'Open credit' => (item.creditNoteRemaining ?? 0) > 0,
    'Credit used' =>
      (item.creditNoteTotal ?? 0) > 0 && (item.creditNoteRemaining ?? 0) <= 0,
    _ => true,
  };

  bool _matchesQuery(SupplierReturn item) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = [
      'sr-${item.id}',
      if (item.purchaseOrderId != null) 'po-${item.purchaseOrderId}',
      'gr-${item.receiptId}',
      item.supplierName,
      item.reason,
      item.creditNoteNumber ?? '',
      item.createdByName,
      for (final line in item.lines)
        '${line.productName} ${line.variantName} ${line.unitCode}',
    ].join(' ');
    return haystack.toLowerCase().contains(needle);
  }

  Future<void> _startNewReturn() async {
    final messenger = ScaffoldMessenger.of(context);
    final suppliersVm = context.read<SuppliersPurchasesViewmodel?>();
    if (suppliersVm != null &&
        suppliersVm.purchases.isEmpty &&
        !suppliersVm.isLoading) {
      await suppliersVm.load();
      if (!mounted) return;
    }

    List<GoodsReceiptRecord> processed;
    try {
      final allReceipts = await _inventory.fetchGoodsReceipts();
      processed = allReceipts.where((r) => r.isProcessed).toList();
    } on InventoryServiceException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    if (!mounted) return;
    if (processed.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No processed deliveries available to return yet. Receive a purchase order first.',
          ),
        ),
      );
      return;
    }

    final poById = <int, PurchaseOrder>{
      for (final po in suppliersVm?.purchases ?? const <PurchaseOrder>[])
        po.id: po,
    };

    // Group processed receipts by PO so the stocker picks the PO / supplier,
    // then selects the exact receipt and items in SupplierReturnDialog.
    final byPo = <int, List<GoodsReceiptRecord>>{};
    for (final r in processed) {
      byPo.putIfAbsent(r.poId, () => []).add(r);
    }
    final poIds = byPo.keys.toList()..sort((a, b) => b.compareTo(a));

    int? chosenPoId;
    if (poIds.length == 1) {
      chosenPoId = poIds.first;
    } else {
      chosenPoId = await showDialog<int>(
        context: context,
        builder: (ctx) => _PickPurchaseOrderDialog(
          poIds: poIds,
          byPo: byPo,
          poById: poById,
        ),
      );
    }
    if (chosenPoId == null || !mounted) return;

    final receipts = byPo[chosenPoId]!;
    final po = poById[chosenPoId];
    final supplierName = (po?.supplierName ?? '').isNotEmpty
        ? po!.supplierName
        : 'Supplier';

    final flow = SupplierReturnFlow(
      loadReceipts: () async => (receipts: receipts, error: null),
      loadReturnable: (receiptId) async {
        try {
          final lines = await _payables.fetchReturnable(receiptId);
          return (lines: lines, error: null);
        } on PayablesServiceException catch (error) {
          return (lines: const <SupplierReturnableLine>[], error: error.message);
        }
      },
      submit: (request) async {
        try {
          final recorded = await _payables.createReturn(
            receiptId: request.receiptId,
            reason: request.reason,
            lines: [
              for (final line in request.lines)
                {
                  'receipt_line': line.receiptLineId,
                  'qty': line.qty.toStringAsFixed(2),
                },
            ],
          );
          return (recorded: recorded, refusal: null);
        } on PayablesServiceException catch (error) {
          return (recorded: null, refusal: error.message);
        }
      },
    );

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => SupplierReturnDialog(
        receipts: receipts,
        purchaseOrderId: chosenPoId!,
        supplierName: supplierName,
        flow: flow,
      ),
    );
    if (created == true && mounted) {
      await _load();
    }
  }

  void _openDetails(SupplierReturn item) {
    showDialog<void>(
      context: context,
      builder: (_) => _SupplierReturnDetailsDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final totalUnits = _returns.fold<double>(
      0,
      (sum, r) => sum + r.lines.fold<double>(0, (s, l) => s + l.qty),
    );
    final totalCredit = _returns.fold<double>(
      0,
      (sum, r) => sum + (r.creditNoteTotal ?? 0),
    );
    final openCredit = _returns.fold<double>(
      0,
      (sum, r) => sum + (r.creditNoteRemaining ?? 0),
    );

    return InventorySkeletonLayout(
      title: 'Supplier Returns',
      subtitle:
          'Record goods returned to suppliers (shrinkage, damage, defects, expiry) and track credit notes.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'inventory.returns',
        AppAreas.inventory,
      ),
      scrollable: false,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                StitchKpiCard(
                  compact: true,
                  label: 'Supplier Returns',
                  value: formatCount(_returns.length),
                  subtitle: 'Recorded return slips',
                  icon: Icons.undo_rounded,
                  tone: StitchTone.primary,
                  pillLabel: 'Store → Supplier',
                  pillTone: StitchTone.primary,
                ),
                StitchKpiCard(
                  compact: true,
                  label: 'Units Returned',
                  value: _quantity(totalUnits),
                  subtitle: 'Deducted from FIFO stock',
                  icon: Icons.inventory_2_outlined,
                  tone: StitchTone.warning,
                  pillLabel: 'Shrinkage / Defect',
                  pillTone: StitchTone.warning,
                ),
                StitchKpiCard(
                  compact: true,
                  label: 'Credit Issued',
                  value: formatPeso(totalCredit),
                  subtitle: 'Supplier credit notes minted',
                  icon: Icons.receipt_long_outlined,
                  tone: StitchTone.success,
                  pillLabel: 'Credit value',
                  pillTone: StitchTone.success,
                ),
                StitchKpiCard(
                  compact: true,
                  label: 'Open Credit Left',
                  value: formatPeso(openCredit),
                  subtitle: 'Available to apply to future bills',
                  icon: Icons.account_balance_wallet_outlined,
                  tone: openCredit > 0 ? StitchTone.primary : StitchTone.neutral,
                  pillLabel: openCredit > 0 ? 'Applyable' : 'Settled',
                  pillTone: openCredit > 0
                      ? StitchTone.primary
                      : StitchTone.neutral,
                ),
              ];
              if (constraints.maxWidth >= 980) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      Expanded(child: cards[i]),
                      if (i < cards.length - 1)
                        const SizedBox(width: AppSpacing.md),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: constraints.maxWidth >= 560
                          ? (constraints.maxWidth - AppSpacing.sm) / 2
                          : constraints.maxWidth,
                      child: card,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FilterBar(
                  searchHint:
                      'Search supplier, PO #, credit note, reason, or item',
                  onSearchChanged: (value) => setState(() => _query = value),
                  options: _filters,
                  selected: _creditFilter,
                  onSelected: (chip) => setState(() => _creditFilter = chip),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('new-supplier-return-button'),
                onPressed: _startNewReturn,
                icon: const Icon(Icons.add),
                label: const Text('New supplier return'),
              ),
            ],
          ),
          if (_loadError != null && _returns.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _loadError!, onRetry: _load),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: DataPanel<SupplierReturn>(
              title: 'Supplier return history',
              count: rows.length,
              showPageSizePicker: true,
              columns: _columns,
              rows: rows,
              emptyMessage: _filtered
                  ? 'No supplier returns match these filters.'
                  : 'No supplier returns recorded yet.',
              isLoading: _isLoading && _returns.isEmpty,
              error: _returns.isEmpty ? _loadError : null,
              onRetry: _load,
              onRowTap: _openDetails,
              rowKey: (item) => ValueKey('SR-${item.id}'),
            ),
          ),
        ],
      ),
    );
  }

  List<DataPanelColumn<SupplierReturn>> get _columns => [
    DataPanelColumn<SupplierReturn>(
      label: 'Return',
      flex: 2,
      cell: (item) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SR-${item.id}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: StitchColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.createdAt == null ? '—' : formatDateTime(item.createdAt!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
    DataPanelColumn<SupplierReturn>(
      label: 'Supplier & PO',
      flex: 3,
      cell: (item) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.supplierName.isEmpty
                ? 'Supplier #${item.supplierId}'
                : item.supplierName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Text(
            item.purchaseOrderId != null
                ? 'PO-${item.purchaseOrderId} · GR #${item.receiptId}'
                : 'GR #${item.receiptId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
    DataPanelColumn<SupplierReturn>(
      label: 'Reason & Items',
      flex: 3,
      cell: (item) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.reason.isEmpty ? 'No reason recorded' : item.reason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          if (item.lines.isNotEmpty)
            Text(
              '${item.lines.first.displayName}'
              '${item.lines.length > 1 ? ' +${item.lines.length - 1} more' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    ),
    DataPanelColumn<SupplierReturn>(
      label: 'Credit note',
      flex: 2,
      cell: (item) {
        final cn = item.creditNoteNumber;
        if (cn == null || cn.isEmpty) {
          return const Text(
            'None',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          );
        }
        final remaining = item.creditNoteRemaining ?? 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            StatusBadge(
              label: remaining > 0 ? 'Open credit' : 'Applied',
              tone: remaining > 0 ? StatusTone.info : StatusTone.success,
            ),
          ],
        );
      },
    ),
    DataPanelColumn<SupplierReturn>(
      label: 'Credit value',
      flex: 2,
      numeric: true,
      cell: (item) {
        final total =
            item.creditNoteTotal ??
            item.lines.fold<double>(0, (s, l) => s + l.creditValue);
        return Text(
          formatPeso(total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    ),
  ];

  static String _quantity(double value) =>
      value % 1 == 0 ? formatCount(value.toInt()) : formatQuantity(value);
}

class _PickPurchaseOrderDialog extends StatelessWidget {
  const _PickPurchaseOrderDialog({
    required this.poIds,
    required this.byPo,
    required this.poById,
  });

  final List<int> poIds;
  final Map<int, List<GoodsReceiptRecord>> byPo;
  final Map<int, PurchaseOrder> poById;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.undo_rounded,
      title: 'Select purchase order to return from',
      subtitle:
          'Choose the delivered purchase order containing the damaged, shrunk, or defective goods.',
      width: 560,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final poId in poIds)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                key: ValueKey('pick-return-po-$poId'),
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(
                  'PO-$poId · ${(poById[poId]?.supplierName ?? '').isEmpty ? 'Supplier' : poById[poId]!.supplierName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${byPo[poId]!.length} processed ${byPo[poId]!.length == 1 ? 'delivery' : 'deliveries'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, poId),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierReturnDetailsDialog extends StatelessWidget {
  const _SupplierReturnDetailsDialog({required this.item});

  final SupplierReturn item;

  @override
  Widget build(BuildContext context) {
    final total =
        item.creditNoteTotal ??
        item.lines.fold<double>(0, (s, l) => s + l.creditValue);
    return AppDialog(
      icon: Icons.undo_rounded,
      title: 'Supplier Return SR-${item.id}',
      subtitle: item.supplierName.isEmpty
          ? 'Supplier #${item.supplierId}'
          : item.supplierName,
      width: 660,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DialogSectionLabel('Return details'),
          if (item.purchaseOrderId != null)
            DetailRow(label: 'Purchase order', value: 'PO-${item.purchaseOrderId}'),
          DetailRow(label: 'Goods receipt', value: 'GR #${item.receiptId}'),
          DetailRow(
            label: 'Date',
            value: item.createdAt == null
                ? 'Not recorded'
                : formatDateTime(item.createdAt!),
          ),
          DetailRow(
            label: 'Recorded by',
            value: item.createdByName.isEmpty ? 'Unknown' : item.createdByName,
          ),
          DetailRow(
            label: 'Reason',
            value: item.reason.isEmpty ? 'None' : item.reason,
          ),
          if (item.creditNoteNumber != null &&
              item.creditNoteNumber!.isNotEmpty) ...[
            DetailRow(label: 'Credit note', value: item.creditNoteNumber!),
            DetailRow(
              label: 'Remaining credit',
              value: formatPeso(item.creditNoteRemaining ?? 0),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          DialogSectionLabel('Returned items (${item.lines.length})'),
          for (final line in item.lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                line.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Returned ${formatQuantity(line.qty)}'
                '${line.unitCode.isNotEmpty ? ' ${line.unitCode}' : ''}'
                ' (${formatQuantity(line.baseQty)} base units)',
              ),
              trailing: Text(
                formatPeso(line.creditValue),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          TotalBar(label: 'Total credit value', amount: total),
        ],
      ),
    );
  }
}
