import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One variant as a row of the low/out list.
typedef _StockRow = ({Product product, ProductVariant variant, double onHand});

/// One variant as a row of the highest-value list.
typedef _ValueRow = ({
  Product product,
  ProductVariant variant,
  double onHand,
  double value,
});

/// Live inventory monitoring (decision D-03, refreshed by card A3).
///
/// Two authorities, on purpose:
///   * the money and unit totals come from `GET /reports/inventory-valuation/`,
///     the same server summary the Reports tab reads, and
///   * which rows are low or out, and what each variant is worth at landed cost,
///     come from `InventoryViewmodel`, the one derivation the stock screens and
///     the stock dashboards use, so this page cannot contradict them about the
///     same row.
///
/// Before card A3 the page was four tiles and a lot of empty space: the stock the
/// company owns was loaded and no screen said what was about to run out.
class InventoryMonitoringPage extends StatefulWidget {
  const InventoryMonitoringPage({super.key, this.repository});

  /// Injected by tests so loading, error and loaded states render without a
  /// server. Production builds its own.
  final ReportsRepository? repository;

  @override
  State<InventoryMonitoringPage> createState() =>
      _InventoryMonitoringPageState();
}

class _InventoryMonitoringPageState extends State<InventoryMonitoringPage> {
  /// How many rows each list shows. The admin is read-only here: the full,
  /// actionable lists belong to the Stock Manager.
  static const int _rowLimit = 10;

  late final ReportsRepository _repository =
      widget.repository ?? ReportsRepository();

  bool _isLoading = true;
  String? _error;
  InventoryValuation? _valuation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  /// Reads both sources. A retry re-reads the stock rows too: the banner covers
  /// both reads, so a button that fixed only one of them would fail again.
  Future<void> _load() async {
    final stock = context.read<InventoryViewmodel>();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final stockLoad = stock.load();
    InventoryValuation? valuation;
    String? failure;
    try {
      valuation = await _repository.fetchInventoryValuation();
    } on ReportsServiceException catch (error) {
      failure = error.message;
    }
    await stockLoad;
    if (!mounted) return;
    setState(() {
      // Dropped on failure: zeroed tiles under a failure message would read as
      // this load's numbers.
      _valuation = valuation;
      _error = failure;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Inventory Monitoring',
      subtitle: 'Monitor product availability and inventory health.',
      selectedNavigationIndex: 2,
      child: _body(),
    );
  }

  Widget _body() {
    final stock = context.watch<InventoryViewmodel>();
    final failure = _error ?? stock.loadError;
    // Stock counts are only facts once the stock load has succeeded: before it,
    // the viewmodel holds bundled rows (or nothing), and rendering their count
    // as data would present invented numbers.
    final stockReady = stock.hasLoaded && stock.loadError == null;
    final valuation = _valuation;
    final pending = _isLoading || (stock.isLoading && !stock.hasLoaded);

    if (pending && valuation == null && !stockReady) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // A failed FIRST load is ONE failure: the banner and its retry. An empty
    // list under it would claim a fact the failed read never established.
    if (failure != null && valuation == null && !stockReady) {
      return ErrorBanner(message: failure, onRetry: _load);
    }

    final lowOut = stockReady ? _lowAndOut(stock) : const <_StockRow>[];
    final byValue = stockReady ? _highestValue(stock) : const <_ValueRow>[];
    final outCount = lowOut.where((row) => row.onHand <= 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A refresh that failed under rows already read: the banner says so
        // above them, because the rows themselves are still true.
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        MetricGrid(
          children: [
            MetricTile(
              label: 'Total items',
              value: valuation == null
                  ? 'Not loaded'
                  : formatQuantity(valuation.totalUnits),
              caption: valuation == null
                  ? null
                  : '${formatCount(valuation.batchCount)} batches',
            ),
            MetricTile(
              label: 'Total cost value',
              value: valuation == null
                  ? 'Not loaded'
                  : formatPeso(valuation.totalCost),
            ),
            MetricTile(
              label: 'Total retail value',
              value: valuation == null
                  ? 'Not loaded'
                  : formatPeso(valuation.totalRetail),
            ),
            MetricTile(
              label: 'Low stock',
              value: stockReady
                  ? formatCount(lowOut.length - outCount)
                  : 'Not loaded',
              caption: 'Below their own level',
            ),
            MetricTile(
              label: 'Out of stock',
              value: stockReady ? formatCount(outCount) : 'Not loaded',
              caption: 'Nothing on the shelf',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _sectionHeading(
          'Low and out of stock',
          'Out of stock first, then the shortest against its own level.',
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<_StockRow>(
          key: const Key('admin-monitoring-low-out'),
          rows: lowOut,
          emptyMessage: stock.products.isEmpty
              ? 'No products in the catalogue yet.'
              : 'Nothing is low or out of stock.',
          rowKey: (row) =>
              ValueKey('admin-monitoring-low-out.${row.variant.id}'),
          columns: [
            DataPanelColumn<_StockRow>(
              label: 'Product',
              // The row's reason to exist, so it takes the largest share.
              flex: 3,
              cell: (row) => _productCell(row.product, row.variant),
            ),
            DataPanelColumn<_StockRow>(
              label: 'On hand',
              numeric: true,
              flex: 2,
              cell: (row) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatQuantity(row.onHand),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    row.variant.minStockThreshold > 0
                        ? 'left of '
                              '${formatQuantity(row.variant.minStockThreshold)}'
                        : 'No level set',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            DataPanelColumn<_StockRow>(
              label: 'Status',
              flex: 2,
              cell: (row) => row.onHand <= 0
                  ? const StatusBadge(
                      label: 'Out of stock',
                      tone: StatusTone.error,
                    )
                  : const StatusBadge(
                      label: 'Low stock',
                      tone: StatusTone.warning,
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _sectionHeading(
          'Highest value stock',
          'What the shelf is worth at landed cost, from the loaded batches.',
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<_ValueRow>(
          key: const Key('admin-monitoring-value'),
          rows: byValue,
          emptyMessage: 'No stock on hand yet.',
          rowKey: (row) => ValueKey('admin-monitoring-value.${row.variant.id}'),
          columns: [
            DataPanelColumn<_ValueRow>(
              label: 'Product',
              flex: 3,
              cell: (row) => _productCell(row.product, row.variant),
            ),
            DataPanelColumn<_ValueRow>(
              label: 'On hand',
              numeric: true,
              flex: 2,
              cell: (row) => Text(
                formatQuantity(row.onHand),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn<_ValueRow>(
              label: 'Value at cost',
              numeric: true,
              flex: 2,
              cell: (row) => Text(
                formatPeso(row.value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeading(String title, String caption) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTextStyles.cinzelFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          caption,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _productCell(Product product, ProductVariant variant) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.baseName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          variant.variantName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// Every variant that is low or out, out of stock first, then the shortest
  /// against its own level (2 of 10 before 12 of 30: both are low, the first is
  /// closer to nothing), then by name so the order is stable.
  List<_StockRow> _lowAndOut(InventoryViewmodel stock) {
    final rows =
        <_StockRow>[
          for (final record in stock.stockRecords)
            if (stock.statusForVariant(record.variant.id) !=
                InventoryStockStatus.inStock)
              (
                product: record.product,
                variant: record.variant,
                onHand: stock.stockOnHandFor(record.variant.id),
              ),
        ]..sort((a, b) {
          final empty = _emptyRank(a).compareTo(_emptyRank(b));
          if (empty != 0) return empty;
          final fill = _fill(a).compareTo(_fill(b));
          if (fill != 0) return fill;
          final name = a.product.baseName.compareTo(b.product.baseName);
          return name != 0
              ? name
              : a.variant.variantName.compareTo(b.variant.variantName);
        });
    return rows.take(_rowLimit).toList(growable: false);
  }

  int _emptyRank(_StockRow row) => row.onHand <= 0 ? 0 : 1;

  /// How much of the reorder level is still on the shelf, 0 to 1. A variant with
  /// no level set counts as full: there is nothing to be short of.
  double _fill(_StockRow row) {
    if (row.onHand <= 0) return 0;
    final threshold = row.variant.minStockThreshold;
    if (threshold <= 0) return 1;
    return (row.onHand / threshold).clamp(0, 1).toDouble();
  }

  /// Stock on hand per variant, valued at the landed cost of each batch it is
  /// still in (the same sum the stock dashboards show), largest first.
  List<_ValueRow> _highestValue(InventoryViewmodel stock) {
    final named = <int, ({Product product, ProductVariant variant})>{
      for (final record in stock.stockRecords) record.variant.id: record,
    };
    final onHand = <int, double>{};
    final value = <int, double>{};
    for (final batch in stock.batches) {
      onHand[batch.variantId] =
          (onHand[batch.variantId] ?? 0) + batch.currentQty;
      value[batch.variantId] =
          (value[batch.variantId] ?? 0) +
          batch.currentQty * batch.unitCostLanded;
    }
    final rows = <_ValueRow>[
      for (final entry in value.entries)
        if (named[entry.key] != null && entry.value > 0)
          (
            product: named[entry.key]!.product,
            variant: named[entry.key]!.variant,
            onHand: onHand[entry.key] ?? 0,
            value: entry.value,
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return rows.take(_rowLimit).toList(growable: false);
  }
}
