import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_movement_details_dialog.dart';
import 'package:client/features/inventory/widgets/inventory_movement_filters.dart';
import 'package:client/features/inventory/widgets/inventory_movement_summary_card.dart';
import 'package:client/features/inventory/widgets/inventory_movement_tabs.dart';
import 'package:client/features/inventory/widgets/inventory_movements_table.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/inventory/widgets/inventory_stock_balance_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryStockMovementsPage extends StatefulWidget {
  const InventoryStockMovementsPage({super.key});

  @override
  State<InventoryStockMovementsPage> createState() =>
      _InventoryStockMovementsPageState();
}

class _InventoryStockMovementsPageState
    extends State<InventoryStockMovementsPage> {
  final _search = TextEditingController();
  InventoryMovementView _view = InventoryMovementView.all;
  InventoryDatePreset _datePreset = InventoryDatePreset.thisMonth;
  DateTimeRange? _customRange;
  String _query = '';
  String? _category;
  InventoryMovementType? _type;
  bool _newestFirst = true;
  int _page = 1;
  int _rows = 10;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTimeRange get _range {
    final now = DateTime.now();
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

  String get _rangeLabel {
    final range = _range;
    String date(DateTime value) => '${value.month}/${value.day}/${value.year}';
    return '${date(range.start)}–${date(range.end.subtract(const Duration(days: 1)))}';
  }

  ({Product product, ProductVariant variant}) _record(
    InventoryViewmodel inventory,
    InventoryMovement movement,
  ) {
    final product = inventory.products.firstWhere(
      (item) => item.id == movement.productId,
    );
    return (
      product: product,
      variant: product.variants.firstWhere(
        (item) => item.id == movement.variantId,
      ),
    );
  }

  bool _inRange(InventoryMovement movement) {
    final range = _range;
    return !movement.timestamp.isBefore(range.start) &&
        movement.timestamp.isBefore(range.end);
  }

  Future<void> _changeDate(InventoryDatePreset value) async {
    if (value == InventoryDatePreset.custom) {
      final now = DateTime.now();
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _customRange,
      );
      if (selected == null || !mounted) return;
      setState(() {
        _datePreset = value;
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
        _page = 1;
      });
      return;
    }
    setState(() {
      _datePreset = value;
      _page = 1;
    });
  }

  void _viewHistory(Product product, ProductVariant variant) {
    final query = '${product.baseName} ${variant.variantName}';
    _search.text = query;
    setState(() {
      _query = query;
      _view = InventoryMovementView.all;
      _page = 1;
    });
  }

  void _showDetails(InventoryViewmodel inventory, InventoryMovement movement) {
    final record = _record(inventory, movement);
    showDialog<void>(
      context: context,
      builder: (_) => InventoryMovementDetailsDialog(
        movement: movement,
        product: record.product,
        variant: record.variant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final periodMovements = inventory.movements.where(_inRange).toList();
    final incomingCount = periodMovements
        .where((item) => item.isIncoming)
        .length;
    final outgoingCount = periodMovements
        .where((item) => item.isOutgoing)
        .length;
    final stockItemCount = inventory.stockRecords.length;

    final filtered =
        periodMovements.where((movement) {
          final record = _record(inventory, movement);
          final text =
              '${record.product.baseName} ${record.variant.variantName} ${record.variant.sku} ${movement.reference} ${movement.reason}'
                  .toLowerCase();
          final directionMatches = switch (_view) {
            InventoryMovementView.stockIn => movement.isIncoming,
            InventoryMovementView.stockOut => movement.isOutgoing,
            _ => true,
          };
          return directionMatches &&
              text.contains(_query.toLowerCase()) &&
              (_type == null || movement.type == _type) &&
              (_category == null || record.product.categoryName == _category);
        }).toList()..sort(
          (a, b) => _newestFirst
              ? b.timestamp.compareTo(a.timestamp)
              : a.timestamp.compareTo(b.timestamp),
        );

    final balances = <InventoryBalanceRecord>[];
    for (final record in inventory.stockRecords) {
      final searchText =
          '${record.product.baseName} ${record.variant.variantName} ${record.variant.sku}'
              .toLowerCase();
      if (!searchText.contains(_query.toLowerCase()) ||
          (_category != null && record.product.categoryName != _category)) {
        continue;
      }
      final history =
          inventory.movements
              .where((item) => item.variantId == record.variant.id)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final before = history.where(
        (item) => item.timestamp.isBefore(_range.start),
      );
      final within = history.where(_inRange).toList();
      final opening = before.isNotEmpty
          ? before.last.newStock
          : within.isNotEmpty
          ? within.first.previousStock
          : 0.0;
      final stockIn = within
          .where((item) => item.isIncoming)
          .fold<double>(0, (sum, item) => sum + item.quantityChange);
      final stockOut = within
          .where((item) => item.isOutgoing)
          .fold<double>(0, (sum, item) => sum + item.quantityChange.abs());
      final closing = opening + stockIn - stockOut;
      final status = closing <= 0
          ? InventoryStockStatus.outOfStock
          : closing <= record.variant.reorderLevel
          ? InventoryStockStatus.lowStock
          : InventoryStockStatus.inStock;
      balances.add((
        product: record.product,
        variant: record.variant,
        opening: opening,
        stockIn: stockIn,
        stockOut: stockOut,
        closing: closing,
        status: status,
      ));
    }

    final pages = (filtered.length / _rows).ceil().clamp(1, 999);
    _page = _page.clamp(1, pages);
    final start = (_page - 1) * _rows;
    final visible = filtered.skip(start).take(_rows).toList();
    final emptyMessage = switch (_view) {
      InventoryMovementView.stockIn =>
        'No incoming stock movements were found for this period.',
      InventoryMovementView.stockOut =>
        'No outgoing stock movements were found for this period.',
      _ => 'No stock movements match your filters.',
    };

    return InventorySkeletonLayout(
      title: 'Stock Movements',
      subtitle:
          'Track inventory coming in, going out, and current stock balances.',
      selectedNavigationIndex: 4,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.md;
              final columns = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: InventoryMovementSummaryCard(
                      label: 'STOCK IN',
                      value: '$incomingCount movements',
                      caption: _datePreset.label,
                      icon: Icons.south_west,
                      color: AppColors.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryMovementSummaryCard(
                      label: 'STOCK OUT',
                      value: '$outgoingCount movements',
                      caption: _datePreset.label,
                      icon: Icons.north_east,
                      color: AppColors.error,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryMovementSummaryCard(
                      label: 'TOTAL MOVEMENTS',
                      value: '${periodMovements.length}',
                      caption: _datePreset.label,
                      icon: Icons.swap_vert,
                      color: AppColors.info,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryMovementSummaryCard(
                      label: 'STOCK ITEMS',
                      value: '$stockItemCount',
                      caption: 'Tracked variants',
                      icon: Icons.inventory_2_outlined,
                      color: AppColors.brandGold,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryMovementTabs(
            selected: _view,
            onSelected: (value) => setState(() {
              _view = value;
              _page = 1;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          InventoryMovementFilters(
            view: _view,
            searchController: _search,
            type: _type,
            category: _category,
            datePreset: _datePreset,
            categories: inventory.categories,
            dateLabel: _rangeLabel,
            onSearch: (value) => setState(() {
              _query = value;
              _page = 1;
            }),
            onTypeChanged: (value) => setState(() {
              _type = value;
              _page = 1;
            }),
            onCategoryChanged: (value) => setState(() {
              _category = value;
              _page = 1;
            }),
            onDateChanged: _changeDate,
            onSort: () => setState(() => _newestFirst = !_newestFirst),
            newestFirst: _newestFirst,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_view == InventoryMovementView.balance)
            InventoryStockBalanceTable(
              records: balances,
              onViewHistory: _viewHistory,
            )
          else ...[
            InventoryMovementsTable(
              movements: visible,
              products: inventory.products,
              emptyMessage: emptyMessage,
              onView: (movement) => _showDetails(inventory, movement),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${filtered.isEmpty ? 0 : start + 1}–${start + visible.length} of ${filtered.length}',
                ),
                const SizedBox(width: AppSpacing.md),
                DropdownButton<int>(
                  value: _rows,
                  items: const [10, 20, 30]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value rows'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _rows = value ?? 10;
                    _page = 1;
                  }),
                ),
                IconButton(
                  onPressed: _page > 1 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_page of $pages'),
                IconButton(
                  onPressed: _page < pages
                      ? () => setState(() => _page++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
