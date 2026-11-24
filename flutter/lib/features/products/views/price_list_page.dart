import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/core/widgets/async_view.dart';
import 'package:client/data/models/price_change.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/products/widgets/price_table_dialog.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum PriceListShell { inventory, sales }

/// Price list in the Stock Manager's shell (inventory sidebar index 17).
class InventoryPriceListPage extends StatelessWidget {
  const InventoryPriceListPage({
    super.key,
    this.productsRepository,
    this.priceHistoryLoader,
  });

  final ProductsRepository? productsRepository;
  final Future<List<PriceHistoryEntry>> Function(int variantUomId)?
      priceHistoryLoader;

  @override
  Widget build(BuildContext context) => _PriceListPageBody(
    shell: PriceListShell.inventory,
    productsRepository: productsRepository,
    priceHistoryLoader: priceHistoryLoader,
  );
}

/// Price list in the Store Manager's shell (sales sidebar index 13).
class SalesPriceListPage extends StatelessWidget {
  const SalesPriceListPage({
    super.key,
    this.productsRepository,
    this.priceHistoryLoader,
  });

  final ProductsRepository? productsRepository;
  final Future<List<PriceHistoryEntry>> Function(int variantUomId)?
      priceHistoryLoader;

  @override
  Widget build(BuildContext context) => _PriceListPageBody(
    shell: PriceListShell.sales,
    productsRepository: productsRepository,
    priceHistoryLoader: priceHistoryLoader,
  );
}

class _PriceListRow {
  const _PriceListRow({
    required this.product,
    required this.variant,
    required this.unit,
    required this.baseCost,
  });

  final Product product;
  final ProductVariant variant;
  final VariantUom unit;
  final double? baseCost;

  bool get isBase =>
      unit.uomId == variant.baseUomId && unit.conversionFactor == 1;

  double? get costPerUnit =>
      baseCost == null ? null : baseCost! * unit.conversionFactor;

  double? get marginPercent {
    final cost = costPerUnit;
    if (cost == null || unit.defaultSellingPrice <= 0) return null;
    return ((unit.defaultSellingPrice - cost) / unit.defaultSellingPrice) * 100;
  }
}

class _PriceListPageBody extends StatefulWidget {
  const _PriceListPageBody({
    required this.shell,
    this.productsRepository,
    this.priceHistoryLoader,
  });

  final PriceListShell shell;
  final ProductsRepository? productsRepository;
  final Future<List<PriceHistoryEntry>> Function(int variantUomId)?
      priceHistoryLoader;

  @override
  State<_PriceListPageBody> createState() => _PriceListPageBodyState();
}

class _PriceListPageBodyState extends State<_PriceListPageBody> {
  final _catalogueSearchController = TextEditingController();
  final _changesSearchController = TextEditingController();

  String _catalogueQuery = '';
  String? _selectedCategory;
  bool _packsOnly = false;

  late final ProductsRepository _repository =
      widget.productsRepository ?? ProductsRepository(ProductsService());

  bool _changesLoading = true;
  String? _changesError;
  List<StorePriceChange> _changes = const [];
  int _changesCount = 0;
  int _changesPage = 1;
  bool _changesHasMore = false;
  DateTime? _sinceDate;
  DateTime? _untilDate;
  String _changesQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded && !inventory.isLoading) {
        inventory.load();
      }
      _loadPriceChanges(page: 1);
    });
  }

  @override
  void dispose() {
    _catalogueSearchController.dispose();
    _changesSearchController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadPriceChanges({int page = 1}) async {
    setState(() {
      _changesLoading = true;
      _changesError = null;
    });
    try {
      final result = await _repository.fetchPriceChanges(
        since: _sinceDate == null ? null : _isoDate(_sinceDate!),
        until: _untilDate == null ? null : _isoDate(_untilDate!),
        query: _changesQuery,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _changes = result.items;
        _changesCount = result.total;
        _changesHasMore = result.hasMore;
        _changesPage = page;
        _changesLoading = false;
      });
    } on ProductsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _changesError = error.message;
        _changesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _changesError = 'Could not load recent price changes.';
        _changesLoading = false;
      });
    }
  }

  List<_PriceListRow> _buildRows(InventoryViewmodel inventory) {
    final rows = <_PriceListRow>[];
    for (final product in inventory.products) {
      if (!product.isActive) continue;
      for (final variant in product.variants) {
        if (!variant.isActive) continue;
        final baseCost = inventory.costFor(variant.id);
        for (final unit in variant.sellingUoms) {
          rows.add(
            _PriceListRow(
              product: product,
              variant: variant,
              unit: unit,
              baseCost: baseCost,
            ),
          );
        }
      }
    }
    rows.sort((a, b) {
      final byProduct = a.product.baseName.toLowerCase().compareTo(
        b.product.baseName.toLowerCase(),
      );
      if (byProduct != 0) return byProduct;
      final byVariant = a.variant.variantName.toLowerCase().compareTo(
        b.variant.variantName.toLowerCase(),
      );
      if (byVariant != 0) return byVariant;
      return a.unit.conversionFactor.compareTo(b.unit.conversionFactor);
    });
    return rows;
  }

  List<_PriceListRow> _filterRows(List<_PriceListRow> rows) {
    final q = _catalogueQuery.trim().toLowerCase();
    return rows
        .where((row) {
          if (_selectedCategory != null &&
              row.product.categoryName != _selectedCategory) {
            return false;
          }
          if (_packsOnly && row.isBase) return false;
          if (q.isEmpty) return true;
          return row.product.baseName.toLowerCase().contains(q) ||
              row.product.categoryName.toLowerCase().contains(q) ||
              row.product.brandName.toLowerCase().contains(q) ||
              row.variant.variantName.toLowerCase().contains(q) ||
              row.unit.uomCode.toLowerCase().contains(q) ||
              row.unit.uomName.toLowerCase().contains(q) ||
              row.unit.barcodeQr.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  void _openPriceHistory({
    required String title,
    required List<PriceHistoryUnit> units,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => PriceHistoryDialog(
        title: title,
        units: units,
        loader: widget.priceHistoryLoader,
      ),
    );
  }

  /// Every selling unit of [product], so one tap shows the product's whole
  /// price story instead of a single unit's.
  void _openProductPriceHistory(Product product) => _openPriceHistory(
    title: product.baseName,
    units: PriceHistoryUnit.forProduct(product),
  );

  Future<void> _pickDate({required bool isSince}) async {
    final now = appClock.now();
    final initial = isSince ? (_sinceDate ?? now) : (_untilDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      currentDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isSince) {
        _sinceDate = picked;
      } else {
        _untilDate = picked;
      }
    });
    await _loadPriceChanges(page: 1);
  }

  String _sourceLabel(String source) => switch (source) {
    'CATALOGUE' => 'Catalogue',
    'IMPORT' => 'Excel import',
    'ADMIN' => 'Admin',
    _ => source.isEmpty ? 'System' : source,
  };

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final body = DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.cardBackground,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(
                          key: ValueKey('price-list-tab'),
                          text: 'Price list',
                        ),
                        Tab(
                          key: ValueKey('recent-price-changes-tab'),
                          text: 'Recent price changes',
                        ),
                      ],
                    ),
                  ),
                  if (context.watch<AuthViewmodel>().hasAnyArea(const {
                    'inventory',
                    'sales',
                    'admin',
                  }))
                    OutlinedButton.icon(
                      key: const ValueKey('price-list-open-table'),
                      onPressed: () async {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => const PriceTableDialog(),
                        );
                        if (mounted) {
                          _loadPriceChanges(page: _changesPage);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit prices'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: TabBarView(
              children: [
                _buildPriceListTab(context),
                _buildRecentChangesTab(context),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.shell == PriceListShell.inventory) {
      return InventorySkeletonLayout(
        title: 'Price list',
        subtitle:
            'Selling prices, cost per unit, margins, and recent store-wide changes.',
        selectedNavigationIndex: AppDestinations.indexOf(
          AppDestinations.priceListId,
          AppAreas.inventory,
        ),
        onNavigationSelected: (index) => navigateInventory(context, index),
        scrollable: false,
        child: body,
      );
    }

    return SalesSkeletonLayout(
      title: 'Price list',
      subtitle:
          'Selling prices, cost per unit, margins, and recent store-wide changes.',
      selectedNavigationIndex: AppDestinations.indexOf(
        AppDestinations.priceListId,
        AppAreas.sales,
      ),
      onNavigationSelected: (index) => navigateSales(context, index),
      scrollable: false,
      child: body,
    );
  }

  Widget _buildPriceListTab(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    return AsyncView(
      isLoading: inventory.isLoading || !inventory.hasLoaded,
      error: inventory.loadError,
      isEmpty: false,
      emptyMessage: 'No selling units yet.',
      onRetry: inventory.load,
      builder: (context) {
        final allRows = _buildRows(inventory);
        final categories =
            allRows
                .map((r) => r.product.categoryName)
                .where((c) => c.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        if (_selectedCategory != null &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
        final visibleRows = _filterRows(allRows);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPanel(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchField = TextField(
                    key: const ValueKey('price-list-search'),
                    controller: _catalogueSearchController,
                    decoration: InputDecoration(
                      labelText: 'Search product, variant, unit, or barcode',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _catalogueQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _catalogueSearchController.clear();
                                setState(() => _catalogueQuery = '');
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _catalogueQuery = v),
                  );
                  final categoryField = DropdownButtonFormField<String?>(
                    key: ValueKey('price-list-cat-$_selectedCategory'),
                    isExpanded: true,
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All categories'),
                      ),
                      for (final c in categories)
                        DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategory = v),
                  );
                  final packsChip = FilterChip(
                    key: const ValueKey('price-list-packs-only'),
                    selected: _packsOnly,
                    label: const Text('Packs only'),
                    onSelected: (v) => setState(() => _packsOnly = v),
                  );
                  if (constraints.maxWidth >= 700) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: searchField),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 2, child: categoryField),
                        const SizedBox(width: AppSpacing.md),
                        packsChip,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: categoryField),
                          const SizedBox(width: AppSpacing.sm),
                          packsChip,
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Showing ${visibleRows.length} of ${allRows.length} selling units · tap a row for price history',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visibleRows.isEmpty
                  ? const AppPanel(
                      child: EmptyState(
                        icon: Icons.sell_outlined,
                        message: 'No selling units match your filter.',
                      ),
                    )
                  : Material(
                      color: AppPalette.of(context).cardBackground,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: AppPalette.of(context).border),
                        borderRadius: BorderRadius.circular(AppRadii.large),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (wide) _priceListHeader(),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: visibleRows.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final row = visibleRows[index];
                                    return wide
                                        ? _widePriceListRow(context, row)
                                        : _narrowPriceListCard(context, row);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _priceListHeader() {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.medium),
        ),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Product / Variant', style: style)),
          SizedBox(width: AppSpacing.sm),
          Expanded(flex: 2, child: Text('Unit', style: style)),
          SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 110,
            child: Text('Price', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 110,
            child: Text('Cost / unit', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 84,
            child: Text('Margin %', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(flex: 2, child: Text('Last changed', style: style)),
        ],
      ),
    );
  }

  Widget _widePriceListRow(BuildContext context, _PriceListRow row) {
    final cost = row.costPerUnit;
    final margin = row.marginPercent;
    final changed = row.unit.lastPriceChangedAt;
    return InkWell(
      key: ValueKey('price-list-row-${row.unit.id}'),
      onTap: () => _openProductPriceHistory(row.product),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.product.baseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${row.variant.variantName} · ${row.product.categoryName}',
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.isBase
                        ? '${row.unit.uomCode} (Base)'
                        : '${row.unit.uomCode} (×${formatQuantity(row.unit.conversionFactor)} ${row.variant.baseUomCode})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (row.unit.barcodeQr.isNotEmpty)
                    Text(
                      row.unit.barcodeQr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 110,
              child: Text(
                formatPeso(row.unit.defaultSellingPrice),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 110,
              child: Text(
                cost == null ? '—' : formatPeso(cost),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 84,
              child: Text(
                margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: margin == null
                      ? AppColors.textSecondary
                      : (margin < 0 ? AppColors.errorText : AppColors.successText),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: Text(
                changed == null ? '—' : formatDateTime(changed.toLocal()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _narrowPriceListCard(BuildContext context, _PriceListRow row) {
    final cost = row.costPerUnit;
    final margin = row.marginPercent;
    final changed = row.unit.lastPriceChangedAt;
    return InkWell(
      key: ValueKey('price-list-row-${row.unit.id}'),
      onTap: () => _openProductPriceHistory(row.product),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${row.product.baseName} · ${row.variant.variantName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  formatPeso(row.unit.defaultSellingPrice),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${row.isBase ? '${row.unit.uomCode} (Base)' : '${row.unit.uomCode} (×${formatQuantity(row.unit.conversionFactor)} ${row.variant.baseUomCode})'}'
              ' · Cost ${cost == null ? '—' : formatPeso(cost)}'
              ' · Margin ${margin == null ? '—' : '${margin.toStringAsFixed(1)}%'}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (changed != null)
              Text(
                'Last changed: ${formatDateTime(changed.toLocal())}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentChangesTab(BuildContext context) {
    final hasFilter =
        _sinceDate != null ||
        _untilDate != null ||
        _changesQuery.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  key: const ValueKey('recent-changes-search'),
                  controller: _changesSearchController,
                  decoration: InputDecoration(
                    labelText: 'Search product or barcode',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _changesSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _changesSearchController.clear();
                              setState(() => _changesQuery = '');
                              _loadPriceChanges(page: 1);
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    setState(() => _changesQuery = v);
                    _loadPriceChanges(page: 1);
                  },
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('recent-changes-since'),
                onPressed: () => _pickDate(isSince: true),
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  _sinceDate == null ? 'From date' : 'From: ${_isoDate(_sinceDate!)}',
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('recent-changes-until'),
                onPressed: () => _pickDate(isSince: false),
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _untilDate == null ? 'To date' : 'To: ${_isoDate(_untilDate!)}',
                ),
              ),
              FilledButton.tonal(
                key: const ValueKey('recent-changes-apply'),
                onPressed: () {
                  setState(() {
                    _changesQuery = _changesSearchController.text;
                  });
                  _loadPriceChanges(page: 1);
                },
                child: const Text('Filter'),
              ),
              if (hasFilter)
                TextButton(
                  key: const ValueKey('recent-changes-clear'),
                  onPressed: () {
                    _changesSearchController.clear();
                    setState(() {
                      _sinceDate = null;
                      _untilDate = null;
                      _changesQuery = '';
                    });
                    _loadPriceChanges(page: 1);
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '$_changesCount recorded price ${_changesCount == 1 ? 'change' : 'changes'} · tap a row for unit history',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            if (_changesPage > 1 || _changesHasMore) ...[
              TextButton(
                onPressed: _changesPage > 1 && !_changesLoading
                    ? () => _loadPriceChanges(page: _changesPage - 1)
                    : null,
                child: const Text('Previous'),
              ),
              Text('Page $_changesPage'),
              TextButton(
                onPressed: _changesHasMore && !_changesLoading
                    ? () => _loadPriceChanges(page: _changesPage + 1)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _changesLoading
              ? const Center(child: CircularProgressIndicator())
              : _changesError != null
              ? ErrorBanner(
                  message: _changesError!,
                  onRetry: () => _loadPriceChanges(page: _changesPage),
                )
              : _changes.isEmpty
              ? const AppPanel(
                  child: EmptyState(
                    icon: Icons.history,
                    message: 'No price changes found.',
                  ),
                )
              : Material(
                  color: AppPalette.of(context).cardBackground,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: AppPalette.of(context).border),
                    borderRadius: BorderRadius.circular(AppRadii.large),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    itemCount: _changes.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _changes[index];
                      final priceLine = item.oldPrice == null
                          ? 'Initial: ${formatPeso(item.newPrice)}'
                          : '${formatPeso(item.oldPrice!)} → ${formatPeso(item.newPrice)}';
                      final delta = _formatDelta(item);
                      final when = item.changedAt == null
                          ? ''
                          : formatDateTime(item.changedAt!.toLocal());
                      final who =
                          item.changedByName != null &&
                              item.changedByName!.isNotEmpty
                          ? 'by ${item.changedByName}'
                          : '';
                      final meta = [
                        _sourceLabel(item.source),
                        if (who.isNotEmpty) who,
                        if (when.isNotEmpty) when,
                      ].join(' · ');

                      return ListTile(
                        key: ValueKey('recent-change-row-${item.id}'),
                        onTap: () => _openPriceHistory(
                          title: '${item.productName} · ${item.variantName}',
                          units: [
                            PriceHistoryUnit(
                              variantUomId: item.variantUomId,
                              label: item.unitCode,
                            ),
                          ],
                        ),
                        title: Text(
                          '${item.productName} · ${item.variantName} (${item.unitCode})',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(meta),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              priceLine,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (delta != null)
                              Text(
                                delta,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (item.changeAmount ?? 0) >= 0
                                      ? AppColors.successText
                                      : AppColors.errorText,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String? _formatDelta(StorePriceChange item) {
    final amt = item.changeAmount;
    if (amt == null) return null;
    final sign = amt >= 0 ? '+' : '-';
    final amtText = '$sign${formatPeso(amt.abs())}';
    final pct = item.changePercent;
    if (pct == null) return amtText;
    final pctSign = pct >= 0 ? '+' : '-';
    return '$amtText ($pctSign${pct.abs().toStringAsFixed(1)}%)';
  }
}
