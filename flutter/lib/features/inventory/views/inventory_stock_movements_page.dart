import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The type chips: the model's own words, so a chip and the badge on a row read
/// the same. "All types" is null, so the page holds one nullable field.
final _typeChips = <String, StockAdjustmentType?>{
  'All types': null,
  for (final type in StockAdjustmentType.values) type.displayName: type,
};

/// The period chips, keyed by their copy. The value is the filter's state.
final _periodChips = <String, InventoryDatePreset>{
  for (final preset in InventoryDatePreset.values) preset.label: preset,
};

/// One row of the list: the server's adjustment plus the names it does not
/// carry. `StockAdjustmentSerializer` sends a variant id, so the product and
/// variant names come from the catalogue, and the actor is an id too.
typedef _AdjustmentRow = ({
  StockAdjustment adjustment,
  String product,
  String variant,
  String unit,
});

/// Stock adjustments (D2): what was written off, damaged, corrected or sent
/// back, and nothing else.
///
/// This screen used to be "Stock Movements" with STOCK IN / STOCK OUT totals,
/// incoming and outgoing tabs and Previous / New columns. It reads
/// `GET /api/v1/adjustments/`, and an adjustment is only ever shrinkage, damage,
/// a count correction or a return to a supplier: sales and goods receipts never
/// appear here, and the server sends a delta rather than a before and after
/// pair. Renaming the screen to what it lists is the whole of the fix; a real
/// movement history needs a backend endpoint the refresh does not add (D19).
class InventoryStockMovementsPage extends StatefulWidget {
  const InventoryStockMovementsPage({super.key});

  @override
  State<InventoryStockMovementsPage> createState() =>
      _InventoryStockMovementsPageState();
}

class _InventoryStockMovementsPageState
    extends State<InventoryStockMovementsPage> {
  final _search = TextEditingController();
  InventoryDatePreset _datePreset = InventoryDatePreset.thisMonth;
  DateTimeRange? _customRange;
  String _query = '';
  StockAdjustmentType? _type;

  @override
  void initState() {
    super.initState();
    // F2: this screen read the store but never fetched it, so a refresh on
    // /inventory/stock-movements showed an empty period (zero adjustments and
    // "No stock movements match your filters.") before anything had been read.
    // Deferred past the first frame (`load()` notifies synchronously) and guarded
    // by `hasLoaded` because the store is app-scoped and another screen has
    // usually already fetched it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded) inventory.load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTimeRange get _range {
    final now = appClock.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_datePreset) {
      InventoryDatePreset.today => DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      InventoryDatePreset.thisWeek => DateTimeRange(
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today.add(Duration(days: 8 - today.weekday)),
      ),
      InventoryDatePreset.thisMonth => DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      ),
      InventoryDatePreset.custom =>
        _customRange ??
            DateTimeRange(
              start: today,
              end: today.add(const Duration(days: 1)),
            ),
    };
  }

  /// The chosen period in words (D6, D18: "to", never a dash).
  String get _rangeLabel {
    final range = _range;
    return '${formatDate(range.start)} to '
        '${formatDate(range.end.subtract(const Duration(days: 1)))}';
  }

  bool _inRange(DateTime timestamp) {
    final range = _range;
    return !timestamp.isBefore(range.start) && timestamp.isBefore(range.end);
  }

  Future<void> _changeDate(InventoryDatePreset value) async {
    if (value == InventoryDatePreset.custom) {
      final now = appClock.now();
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        // The "today" ring follows the app's clock, not the framework's own
        // `DateTime.now()`.
        currentDate: now,
        initialDateRange: _customRange,
      );
      if (selected == null || !mounted) return;
      setState(() {
        _datePreset = value;
        // The picker returns whole days; the range is half-open, so the end day
        // is included by moving the bound to the next midnight.
        _customRange = DateTimeRange(
          start: DateTime(
            selected.start.year,
            selected.start.month,
            selected.start.day,
          ),
          end: DateTime(
            selected.end.year,
            selected.end.month,
            selected.end.day + 1,
          ),
        );
      });
      return;
    }
    setState(() => _datePreset = value);
  }

  String _productName(InventoryViewmodel inventory, ProductVariant variant) {
    for (final product in inventory.products) {
      if (product.id == variant.productId) return product.baseName;
    }
    return 'Product not in the catalogue';
  }

  /// The adjustment as a row. A variant the catalogue no longer lists still
  /// belongs on the screen: the server recorded it, so it is reported, and the
  /// name says why it is missing instead of hiding the write-off.
  _AdjustmentRow _row(
    InventoryViewmodel inventory,
    StockAdjustment adjustment,
  ) {
    final variant = inventory.variantFor(adjustment.variantId);
    return (
      adjustment: adjustment,
      product: variant == null
          ? 'Product not in the catalogue'
          : _productName(inventory, variant),
      variant: variant?.variantName ?? 'Variant not in the catalogue',
      unit: variant?.baseUomCode ?? '',
    );
  }

  /// The adjustments in the period that pass the filters, newest first.
  List<_AdjustmentRow> _rows(InventoryViewmodel inventory) {
    return [
        for (final adjustment in inventory.adjustments)
          if (_inRange(adjustment.timestamp)) _row(inventory, adjustment),
      ].where((row) {
        if (_type != null && row.adjustment.adjustmentType != _type) {
          return false;
        }
        if (_query.isEmpty) return true;
        final text =
            '${row.product} ${row.variant} ${row.adjustment.remarks} '
                    'user ${row.adjustment.userId}'
                .toLowerCase();
        return text.contains(_query);
      }).toList()
      ..sort(
        (a, b) => b.adjustment.timestamp.compareTo(a.adjustment.timestamp),
      );
  }

  /// A quantity with thousands grouped, signed when it moved: `+1,234 BAG`,
  /// `-2 BAG`. The unit is dropped when the catalogue no longer lists it.
  ///
  /// The number itself is [formatQuantity] (FX4: one quantity format), and only
  /// the sign and the unit are this table's own.
  String _quantity(_AdjustmentRow row) {
    final value = row.adjustment.quantityAdjusted;
    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    final amount = '$sign${formatQuantity(value.abs())}';
    return row.unit.isEmpty ? amount : '$amount ${row.unit}';
  }

  StatusTone _tone(StockAdjustmentType type) => switch (type) {
    StockAdjustmentType.shrinkage => StatusTone.warning,
    StockAdjustmentType.damage => StatusTone.error,
    StockAdjustmentType.correction => StatusTone.info,
    StockAdjustmentType.returnToSupplier => StatusTone.neutral,
  };

  List<DataPanelColumn<_AdjustmentRow>> _columns() => [
    // The first column is a card's title under 720 px of panel width, so it is
    // the product rather than the date, and it takes the most room.
    DataPanelColumn(
      label: 'Product and variant',
      flex: 3,
      cell: (row) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.product,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            row.variant,
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
    DataPanelColumn(
      label: 'Type',
      flex: 2,
      cell: (row) => StatusBadge(
        label: row.adjustment.adjustmentType.displayName,
        tone: _tone(row.adjustment.adjustmentType),
      ),
    ),
    DataPanelColumn(
      label: 'Change',
      flex: 3,
      numeric: true,
      cell: (row) {
        final quantity = row.adjustment.quantityAdjusted;
        return Text(
          _quantity(row),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: quantity > 0
                ? AppColors.successText
                : (quantity < 0 ? AppColors.errorText : AppColors.textPrimary),
          ),
        );
      },
    ),
    DataPanelColumn(
      label: 'Reason',
      flex: 2,
      cell: (row) => Text(
        row.adjustment.remarks.isEmpty
            ? 'No reason given'
            : row.adjustment.remarks,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
    ),
    // The API sends the actor's id, not their name (StockAdjustmentSerializer
    // has `user`), so the row says what it has instead of inventing a name.
    DataPanelColumn(
      label: 'By',
      cell: (row) => Text(
        'User ${row.adjustment.userId}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
    ),
    DataPanelColumn(
      label: 'When',
      flex: 2,
      cell: (row) => Text(
        formatDateTime(row.adjustment.timestamp),
        // Two lines: at a raised text scale the time is one line too much for
        // this column, and "Nov 2, 2026, 10..." is a stamp with no time.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final rows = _rows(inventory);
    final failure = inventory.loadError;
    final pending = inventory.isLoading || !inventory.hasLoaded;
    // A failed fetch is not an empty period: rows kept from an earlier good load
    // stay visible under the banner, and with no rows at all the page states the
    // failure instead of a "nothing recorded" it cannot know.
    final staleRows = failure != null && rows.isNotEmpty;
    final failedWithNothing = failure != null && rows.isEmpty;
    final filtersActive = _query.isNotEmpty || _type != null;

    return InventorySkeletonLayout(
      title: 'Stock adjustments',
      subtitle: 'Losses, damage, count corrections and returns to suppliers.',
      selectedNavigationIndex: 4,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // A stock book records adjustments for years: the list builds its rows as
      // they scroll into view instead of laying every one out at once, which
      // needs the shell to hand the page the height under its header.
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterBar(
            searchController: _search,
            searchHint: 'Search product, variant, reason, or user',
            options: _periodChips.keys.toList(),
            selected: _datePreset.label,
            onSelected: (label) => _changeDate(_periodChips[label]!),
            onSearchChanged: (value) => setState(() {
              _query = value.trim().toLowerCase();
            }),
            extraOptions: _typeChips.keys.toList(),
            extraSelected: _type?.displayName ?? 'All types',
            onExtraSelected: (label) => setState(() {
              _type = _typeChips[label];
            }),
          ),
          // The chips show which period is chosen; a custom one also needs its
          // two dates, which no chip label can carry.
          if (_datePreset == InventoryDatePreset.custom)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Custom range: $_rangeLabel',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: inventory.load),
            ),
          Expanded(
            child: failedWithNothing
                // The banner above already says why: an empty state here would
                // claim nothing was recorded, which nobody has checked.
                ? const SizedBox.shrink()
                : DataPanel<_AdjustmentRow>(
                    columns: _columns(),
                    rows: rows,
                    emptyMessage: filtersActive
                        ? 'No adjustments match these filters.'
                        : 'No adjustments recorded for this period.',
                    // The spinner is for a first load with nothing to show:
                    // handing it to a reload would wipe rows, contradicting the
                    // banner that says they are kept (wave 1, I3).
                    isLoading: pending && rows.isEmpty,
                    error: staleRows ? null : failure,
                    onRetry: inventory.load,
                  ),
          ),
        ],
      ),
    );
  }
}
