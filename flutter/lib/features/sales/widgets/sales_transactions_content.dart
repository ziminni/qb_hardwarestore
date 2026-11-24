import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Which role is reading the transaction list.
enum SalesTransactionsRole {
  /// The cashier's remodeled transaction history (KPI strip, multi-facet filters,
  /// separated Transaction & OS # and OR # columns, and void / attach OR actions).
  cashier,

  /// The store manager's transactions: Source is shown, and the row keeps a
  /// View action (the rows are also tappable).
  storeManager,

  /// The stock manager's sales: units out is the number that matters, money
  /// moves into the details sheet.
  stockManager,
}

/// The shared transaction list used by Cashier, Store Manager, and Stock Manager.
class SalesTransactionsContent extends StatefulWidget {
  const SalesTransactionsContent({
    super.key,
    required this.role,
    required this.sales,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.now,
    this.orTracking = false,
    this.onAttachOr,
    this.onVoidSale,
  });

  final SalesTransactionsRole role;
  final List<InventorySale> sales;
  final bool isLoading;
  final String? loadError;
  final VoidCallback? onRetry;
  final DateTime Function()? now;

  /// Groups rows by OR tagging on the dedicated OR-Tagged tab.
  final bool orTracking;

  /// Opens the Attach OR dialog.
  final VoidCallback? onAttachOr;

  /// Opens the Void Transaction dialog for an eligible completed sale.
  final ValueChanged<InventorySale>? onVoidSale;

  @override
  State<SalesTransactionsContent> createState() =>
      _SalesTransactionsContentState();
}

class _SalesTransactionsContentState extends State<SalesTransactionsContent> {
  static const String _anyStatus = 'All';
  static const List<String> _statusChips = [
    _anyStatus,
    'Completed',
    'Utang / Credit',
    'Pending Pickup',
    'Refunded',
    'Void',
  ];

  static const List<String> _orChips = [_anyStatus, 'OR-tagged', 'Untagged'];
  static const String _anyDate = 'All dates';
  static const String _customDate = 'Custom range';
  static const List<String> _dateChips = [
    _anyDate,
    'Today',
    'Yesterday',
    'This week',
    'This month',
    _customDate,
  ];

  static const String _anyTender = 'All tenders';
  static const List<String> _tenderOptions = [
    _anyTender,
    'Cash',
    'GCash',
    'Cheque',
    'Utang / Credit',
  ];

  static const List<int> _pageSizeOptions = [10, 25, 50, 100];

  static const String _anyOrFilter = 'All OR';
  static const List<String> _orFilterOptions = [
    _anyOrFilter,
    'OR Attached',
    'No OR',
  ];

  static const String _dateCaption =
      'Date ranges count only the transactions already loaded.';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _status = _anyStatus;
  String _or = _anyStatus;
  String _date = _anyDate;
  String _tender = _anyTender;
  String _orFilter = _anyOrFilter;
  DateTimeRange? _customRange;
  int _pageSize = 10;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static bool _isTagged(InventorySale sale) =>
      sale.invoiceNo != null && sale.invoiceNo!.trim().isNotEmpty;

  bool get _isCashierRemodel =>
      widget.role == SalesTransactionsRole.cashier && !widget.orTracking;

  bool get _dateFiltered => _date != _anyDate;

  bool get _filtered =>
      _query.isNotEmpty ||
      _status != _anyStatus ||
      _dateFiltered ||
      _tender != _anyTender ||
      _orFilter != _anyOrFilter ||
      (widget.orTracking && _or != _anyStatus);

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = _anyStatus;
      _or = _anyStatus;
      _date = _anyDate;
      _tender = _anyTender;
      _orFilter = _anyOrFilter;
      _customRange = null;
      _currentPage = 1;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final now = widget.now?.call() ?? appClock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      currentDate: now,
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(const Duration(days: 7)),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _date = _customDate;
    });
  }

  List<InventorySale> _dateScopedSales(DateTime now) {
    if (!_dateFiltered) return widget.sales;
    return [
      for (final sale in widget.sales)
        if (_matchesDate(sale, now)) sale,
    ];
  }

  List<InventorySale> get _visible {
    final now = widget.now?.call() ?? appClock.now();
    return [
      for (final sale in widget.sales)
        if (_matchesQuery(sale) &&
            _matchesStatus(sale) &&
            _matchesOr(sale) &&
            _matchesOrDropdown(sale) &&
            _matchesTender(sale) &&
            _matchesDate(sale, now))
          sale,
    ];
  }

  bool _matchesQuery(InventorySale sale) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = switch (widget.role) {
      SalesTransactionsRole.stockManager =>
        '${sale.transactionNo} ${sale.orNumber} ${sale.invoiceNo ?? ''} ${sale.customer} '
            '${sale.lines.map((line) => '${line.sku} ${line.productName}').join(' ')}',
      SalesTransactionsRole.cashier || SalesTransactionsRole.storeManager =>
        '${sale.transactionNo} ${sale.orNumber} ${sale.invoiceNo ?? ''} ${sale.customer} '
            '${sale.paymentMethod} ${sale.cashier} '
            '${sale.lines.map((line) => '${line.productName} ${line.sku}').join(' ')}',
    };
    return haystack.toLowerCase().contains(query);
  }

  bool _matchesStatus(InventorySale sale) => switch (_status) {
    'Completed' =>
      sale.status == InventorySaleStatus.completed && !sale.isAwaitingBodega,
    'Utang / Credit' =>
      sale.creditSale && sale.status == InventorySaleStatus.completed,
    'Pending Pickup' => sale.isAwaitingBodega,
    'Refunded' => sale.status == InventorySaleStatus.refunded,
    'Void' => sale.status == InventorySaleStatus.voided,
    _ => true,
  };

  bool _matchesOr(InventorySale sale) => switch (_or) {
    'OR-tagged' => _isTagged(sale),
    'Untagged' => !_isTagged(sale),
    _ => true,
  };

  bool _matchesOrDropdown(InventorySale sale) => switch (_orFilter) {
    'OR Attached' => _isTagged(sale),
    'No OR' => !_isTagged(sale),
    _ => true,
  };

  bool _matchesTender(InventorySale sale) {
    if (_tender == _anyTender) return true;
    if (_tender == 'Utang / Credit') return sale.creditSale;
    final target = _tender.toLowerCase();
    if (sale.paymentMethod.toLowerCase().contains(target)) return true;
    return sale.payments.any((p) => p.method.toLowerCase().contains(target));
  }

  bool _matchesDate(InventorySale sale, DateTime now) {
    final localDate = sale.date.toLocal();
    final localNow = now.toLocal();
    return switch (_date) {
      'Today' => _sameDay(localDate, localNow),
      'Yesterday' => _sameDay(
        localDate,
        DateTime(
          localNow.year,
          localNow.month,
          localNow.day,
        ).subtract(const Duration(days: 1)),
      ),
      'This week' => _inWeekOf(localDate, localNow),
      'This month' =>
        localDate.year == localNow.year && localDate.month == localNow.month,
      _customDate => _inCustomRange(localDate),
      _ => true,
    };
  }

  bool _inCustomRange(DateTime localDate) {
    final range = _customRange;
    if (range == null) return true;
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _inWeekOf(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return !date.isBefore(monday) && date.isBefore(nextMonday);
  }

  bool _canVoid(InventorySale sale) =>
      widget.onVoidSale != null &&
      sale.id != null &&
      sale.status == InventorySaleStatus.completed &&
      sale.source != 'Requisition' &&
      sale.source != 'Return';

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? appClock.now();
    final rows = _visible;
    final scoped = _dateScopedSales(now);

    if (_isCashierRemodel) {
      return _buildCashierRemodel(context, scoped: scoped, rows: rows);
    }

    final showDateFilters = widget.role == SalesTransactionsRole.storeManager;
    final chipLabel = widget.orTracking ? 'OR' : 'Status';
    final chips = widget.orTracking ? _orChips : _statusChips;
    final chipSelected = widget.orTracking ? _or : _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: switch (widget.role) {
            SalesTransactionsRole.stockManager =>
              'Transaction, OS #, customer, or SKU',
            SalesTransactionsRole.cashier ||
            SalesTransactionsRole.storeManager =>
              'Transaction, OS #, OR #, customer, or payment',
          },
          onSearchChanged: (value) => setState(() => _query = value),
          optionsLabel: chipLabel,
          options: chips,
          selected: chipSelected,
          onSelected: (chip) => setState(() {
            if (widget.orTracking) {
              _or = chip;
            } else {
              _status = chip;
            }
          }),
          extraOptionsLabel: showDateFilters ? 'Date' : null,
          extraOptions: showDateFilters ? _dateChips : const <String>[],
          extraSelected: _date,
          onExtraSelected: (chip) {
            if (chip == _customDate) {
              _pickCustomDateRange();
            } else {
              setState(() => _date = chip);
            }
          },
        ),
        if (showDateFilters) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildDateCaptionRow(rows.length),
        ],
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: LayoutBuilder(
            builder: (context, slot) {
              final cards =
                  slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
              return DataPanel<InventorySale>(
                title: 'Transactions',
                count: rows.length,
                columns: _columns(withAction: !cards),
                rows: rows,
                emptyMessage: _filtered
                    ? 'No transactions match these filters.'
                    : 'No transactions found.',
                isLoading: widget.isLoading && widget.sales.isEmpty,
                error: widget.loadError,
                onRetry: widget.onRetry,
                onRowTap: (sale) => _openDocument(context, sale),
                rowKey: (sale) => ValueKey(sale.transactionNo),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCashierRemodel(
    BuildContext context, {
    required List<InventorySale> scoped,
    required List<InventorySale> rows,
  }) {
    final totalCount = scoped.length;
    final grossVolume = scoped
        .where((s) => s.status != InventorySaleStatus.voided)
        .fold<double>(0, (sum, s) => sum + s.amountDue);

    final completedList = scoped
        .where((s) => s.status == InventorySaleStatus.completed)
        .toList();
    final settledPct = totalCount == 0
        ? 0.0
        : (completedList.length / totalCount) * 100;

    final creditList = scoped
        .where((s) => s.creditSale && s.status == InventorySaleStatus.completed)
        .toList();
    final creditVolume = creditList.fold<double>(
      0,
      (sum, s) => sum + s.amountDue,
    );

    final reversedList = scoped
        .where(
          (s) =>
              s.status == InventorySaleStatus.voided ||
              s.status == InventorySaleStatus.refunded,
        )
        .toList();
    final reversedVolume = reversedList.fold<double>(
      0,
      (sum, s) => sum + s.amountDue,
    );

    final statusCounts = <String, int>{
      _anyStatus: scoped.length,
      'Completed': scoped
          .where(
            (s) =>
                s.status == InventorySaleStatus.completed &&
                !s.isAwaitingBodega,
          )
          .length,
      'Utang / Credit': creditList.length,
      'Pending Pickup': scoped.where((s) => s.isAwaitingBodega).length,
      'Refunded': scoped
          .where((s) => s.status == InventorySaleStatus.refunded)
          .length,
      'Void': scoped
          .where((s) => s.status == InventorySaleStatus.voided)
          .length,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 4-Card KPI Summary Strip (adapted from Stitch)
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _KpiCard(
                label: 'Total Transactions',
                value: formatCount(totalCount),
                subtitle: '${formatPeso(grossVolume)} active volume',
                icon: Icons.receipt_long_rounded,
                iconBg: AppColors.primary.withValues(alpha: 0.10),
                iconColor: AppColors.primary,
              ),
              _KpiCard(
                label: 'Completed / Settled',
                value: formatCount(completedList.length),
                subtitle: '${settledPct.toStringAsFixed(1)}% of listed sales',
                icon: Icons.check_circle_outline_rounded,
                iconBg: AppColors.success.withValues(alpha: 0.12),
                iconColor: AppColors.success,
              ),
              _KpiCard(
                label: 'Utang / Credit',
                value: formatCount(creditList.length),
                subtitle: '${formatPeso(creditVolume)} credit sales',
                icon: Icons.account_balance_wallet_outlined,
                iconBg: AppColors.warning.withValues(alpha: 0.14),
                iconColor: AppColors.warning,
              ),
              _KpiCard(
                label: 'Voided & Returned',
                value: formatCount(reversedList.length),
                subtitle: '${formatPeso(reversedVolume)} reversed',
                icon: Icons.assignment_return_outlined,
                iconBg: AppColors.error.withValues(alpha: 0.12),
                iconColor: AppColors.error,
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
            if (constraints.maxWidth >= 560) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: cards[2]),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  cards[i],
                  if (i < cards.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),

        // 2. Multi-Faceted Filter Card (Search + Segmented Status Pills + Dropdowns)
        Container(
          key: const ValueKey('cashier-history-filter-bar'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 260,
                      maxWidth: 420,
                    ),
                    child: TextField(
                      key: const ValueKey('cashier-history-search'),
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded, size: 16),
                              )
                            : null,
                        hintText:
                            'Search by Transaction, OS #, OR #, customer, or item...',
                        hintStyle: const TextStyle(fontSize: 13),
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final chip in _statusChips)
                          _SegmentedStatusPill(
                            label: chip,
                            count: statusCounts[chip] ?? 0,
                            selected: _status == chip,
                            onTap: () => setState(() => _status = chip),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _FilterDropdownPill(
                        icon: Icons.calendar_today_outlined,
                        value: _date,
                        items: _dateChips,
                        onChanged: (value) {
                          if (value == null) return;
                          if (value == _customDate) {
                            _pickCustomDateRange();
                          } else {
                            setState(() {
                              _date = value;
                              _customRange = null;
                            });
                          }
                        },
                      ),
                      _FilterDropdownPill(
                        icon: Icons.payments_outlined,
                        value: _tender,
                        items: _tenderOptions,
                        onChanged: (value) {
                          if (value != null) setState(() => _tender = value);
                        },
                      ),
                      _FilterDropdownPill(
                        icon: Icons.receipt_outlined,
                        value: _orFilter,
                        items: _orFilterOptions,
                        onChanged: (value) {
                          if (value != null) setState(() => _orFilter = value);
                        },
                      ),
                      if (_date == _customDate && _customRange != null) ...[
                        Text(
                          '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        TextButton(
                          onPressed: _pickCustomDateRange,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Change'),
                        ),
                      ],
                    ],
                  ),
                  if (_filtered)
                    TextButton.icon(
                      key: const ValueKey('cashier-history-clear-filters'),
                      onPressed: _clearAllFilters,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                      label: const Text('Clear Filters'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 3. Remodeled Transaction Table (separate Transaction & OS # and OR # columns)
        Expanded(
          child: Builder(
            builder: (context) {
              final totalRows = rows.length;
              final totalPages = totalRows == 0
                  ? 1
                  : (totalRows + _pageSize - 1) ~/ _pageSize;
              final safePage = _currentPage.clamp(1, totalPages);
              final startIdx = (safePage - 1) * _pageSize;
              final endIdx = (startIdx + _pageSize).clamp(0, totalRows);
              final pageRows = totalRows == 0
                  ? const <InventorySale>[]
                  : rows.sublist(startIdx, endIdx);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, slot) {
                        final cards =
                            slot.maxWidth - AppPanel.chrome <
                            DataPanel.cardBreakpoint;
                        return DataPanel<InventorySale>(
                          title: 'Transactions',
                          count: totalRows,
                          columns: _columns(withAction: !cards),
                          rows: pageRows,
                          emptyMessage: _filtered
                              ? 'No transactions match these filters.'
                              : 'No transactions found.',
                          isLoading: widget.isLoading && widget.sales.isEmpty,
                          error: widget.loadError,
                          onRetry: widget.onRetry,
                          onRowTap: (sale) => _openDocument(context, sale),
                          rowKey: (sale) => ValueKey(sale.transactionNo),
                        );
                      },
                    ),
                  ),
                  if (totalRows > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _PaginationFooter(
                      totalRows: totalRows,
                      startRow: startIdx + 1,
                      endRow: endIdx,
                      currentPage: safePage,
                      totalPages: totalPages,
                      pageSize: _pageSize,
                      pageSizeOptions: _pageSizeOptions,
                      onPageChanged: (page) =>
                          setState(() => _currentPage = page),
                      onPageSizeChanged: (size) => setState(() {
                        _pageSize = size;
                        _currentPage = 1;
                      }),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateCaptionRow(int shownCount) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _date == _customDate && _customRange != null
              ? 'Custom range: ${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)} ($shownCount shown)'
              : _dateCaption,
          style: TextStyle(
            fontSize: 12,
            fontWeight: _date == _customDate && _customRange != null
                ? FontWeight.w600
                : FontWeight.w400,
            color: _date == _customDate && _customRange != null
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        if (_date == _customDate && _customRange != null) ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _pickCustomDateRange,
            child: const Text('Change dates'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() {
              _date = _anyDate;
              _customRange = null;
            }),
            child: const Text('Clear range'),
          ),
        ],
      ],
    );
  }

  List<DataPanelColumn<InventorySale>> _columns({required bool withAction}) {
    if (_isCashierRemodel) {
      return [
        _cashierTxnOsColumn(),
        _orColumn(),
        _customerColumn(flex: 2),
        _itemsSummaryColumn(),
        _paymentColumn(flex: 2),
        _statusColumn(),
        _totalColumn(flex: 2),
        if (withAction) _cashierActionsColumn(),
      ];
    }

    return switch (widget.role) {
      SalesTransactionsRole.cashier => [
        _transactionColumn(),
        _orColumn(),
        _dateColumn(),
        _customerColumn(),
        _paymentColumn(),
        _totalColumn(),
        if (widget.onAttachOr != null)
          DataPanelColumn<InventorySale>(
            label: 'Action',
            flex: 1,
            cell: (sale) => _isTagged(sale)
                ? const SizedBox.shrink()
                : TextButton(
                    key: ValueKey('attach-or-${sale.transactionNo}'),
                    onPressed: widget.onAttachOr,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Attach'),
                  ),
          ),
      ],
      SalesTransactionsRole.storeManager => [
        _transactionColumn(),
        _dateColumn(),
        _customerColumn(withSource: true, withPayment: true, flex: 3),
        _totalColumn(),
        if (withAction)
          DataPanelColumn<InventorySale>(
            label: 'Action',
            flex: 1,
            cell: (sale) => Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _openDocument(context, sale),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View'),
              ),
            ),
          ),
      ],
      SalesTransactionsRole.stockManager => [
        _transactionColumn(),
        _dateColumn(),
        DataPanelColumn<InventorySale>(
          label: 'Items',
          cell: (sale) => _text(formatCount(sale.lines.length)),
        ),
        DataPanelColumn<InventorySale>(
          label: 'Units out',
          numeric: true,
          cell: (sale) => _text(
            _quantity(sale.totalQuantity),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    };
  }

  /// Cashier remodeled column 1: Transaction #, OS #, and timestamp.
  DataPanelColumn<InventorySale> _cashierTxnOsColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Transaction & OS #',
      flex: 3,
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sale.transactionNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: sale.status == InventorySaleStatus.voided
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              decoration: sale.status == InventorySaleStatus.voided
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          if (sale.orNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sale.orNumber.toUpperCase().startsWith('OS')
                  ? sale.orNumber
                  : 'OS ${sale.orNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            formatDateTime(sale.date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Dedicated OR # column showing the actual OR number or `None`.
  DataPanelColumn<InventorySale> _orColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'OR #',
      flex: 2,
      cell: (sale) {
        final hasOr = _isTagged(sale);
        if (!hasOr) {
          return const Text(
            'None',
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: sale.invoiceNo!.trim(),
            tone: StatusTone.info,
          ),
        );
      },
    );
  }

  /// Items summary column for cashier table.
  DataPanelColumn<InventorySale> _itemsSummaryColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Items',
      flex: 2,
      cell: (sale) {
        final lineCount = sale.lines.length;
        final unitCount = _quantity(sale.totalQuantity);
        final first = sale.lines.isEmpty ? null : sale.lines.first.productName;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(
              '$lineCount ${lineCount == 1 ? 'item' : 'items'} · $unitCount qty',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (first != null && first.isNotEmpty) ...[
              const SizedBox(height: 2),
              _caption(lineCount > 1 ? '$first +${lineCount - 1} more' : first),
            ],
          ],
        );
      },
    );
  }

  /// Dedicated Status column for cashier table.
  DataPanelColumn<InventorySale> _statusColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Status',
      flex: 2,
      cell: (sale) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          StatusBadge(
            label: sale.displayStatusLabel,
            tone: _displayTone(sale),
          ),
          if (sale.bodegaBadgeLabel != null)
            StatusBadge(
              label: sale.bodegaBadgeLabel!,
              tone: sale.isBodegaReleased
                  ? StatusTone.success
                  : StatusTone.warning,
            ),
        ],
      ),
    );
  }

  /// Compact row actions for cashier table: View, Attach OR, Void.
  DataPanelColumn<InventorySale> _cashierActionsColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Actions',
      flex: 2,
      cell: (sale) {
        final canAttach =
            widget.onAttachOr != null &&
            !_isTagged(sale) &&
            sale.status == InventorySaleStatus.completed;
        final canVoid = _canVoid(sale);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'View details',
              child: IconButton(
                key: ValueKey('view-sale-${sale.transactionNo}'),
                onPressed: () => _openDocument(context, sale),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
            ),
            if (canAttach)
              Tooltip(
                message: 'Attach OR #',
                child: IconButton(
                  key: ValueKey('attach-or-${sale.transactionNo}'),
                  onPressed: widget.onAttachOr,
                  icon: const Icon(
                    Icons.note_add_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                ),
              ),
            if (canVoid)
              Tooltip(
                message: 'Void transaction',
                child: IconButton(
                  key: ValueKey('void-sale-${sale.transactionNo}'),
                  onPressed: () => widget.onVoidSale!(sale),
                  icon: const Icon(
                    Icons.block_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  DataPanelColumn<InventorySale> _transactionColumn({int flex = 2}) {
    return DataPanelColumn<InventorySale>(
      label: 'Transaction',
      flex: flex,
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sale.transactionNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (sale.orNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sale.orNumber.toUpperCase().startsWith('OS') ||
                      sale.orNumber.toUpperCase().startsWith('OR')
                  ? sale.orNumber
                  : 'OS ${sale.orNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              StatusBadge(
                label: sale.displayStatusLabel,
                tone: _displayTone(sale),
              ),
              if (!widget.orTracking && _isTagged(sale))
                StatusBadge(
                  label: 'OR ${sale.invoiceNo}',
                  tone: StatusTone.info,
                ),
              if (sale.bodegaBadgeLabel != null)
                StatusBadge(
                  label: sale.bodegaBadgeLabel!,
                  tone: sale.isBodegaReleased
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  DataPanelColumn<InventorySale> _dateColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Date and time',
      flex: 2,
      cell: (sale) => _text(formatDateTime(sale.date), maxLines: 2),
    );
  }

  DataPanelColumn<InventorySale> _customerColumn({
    bool withSource = false,
    bool withPayment = false,
    int flex = 2,
  }) {
    return DataPanelColumn<InventorySale>(
      label: 'Customer',
      flex: flex,
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(sale.customer, maxLines: 2),
          if (!withSource && !_isCashierRemodel && sale.lines.isNotEmpty) ...[
            const SizedBox(height: 2),
            _caption(
              '${formatCount(sale.lines.length)} item${sale.lines.length == 1 ? '' : 's'}'
              '${sale.cashier.isNotEmpty ? ' · ${sale.cashier}' : ''}',
            ),
          ] else if (_isCashierRemodel && sale.cashier.isNotEmpty) ...[
            const SizedBox(height: 2),
            _caption(sale.cashier),
          ],
          if (withSource) ...[const SizedBox(height: 2), _caption(sale.source)],
          if (withPayment) ...[
            const SizedBox(height: 2),
            _caption(_paymentOf(sale)),
          ],
        ],
      ),
    );
  }

  DataPanelColumn<InventorySale> _paymentColumn({int flex = 2}) {
    return DataPanelColumn<InventorySale>(
      label: 'Payment',
      flex: flex,
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(_paymentOf(sale)),
          if (sale.discountAmount > 0) ...[
            const SizedBox(height: 2),
            _caption('Discount -${formatPeso(sale.discountAmount)}'),
          ] else if (sale.creditSale) ...[
            const SizedBox(height: 2),
            _caption('Utang / credit price'),
          ],
        ],
      ),
    );
  }

  String _paymentOf(InventorySale sale) =>
      sale.payments.isEmpty ? 'No payment' : sale.paymentMethod;

  DataPanelColumn<InventorySale> _totalColumn({int flex = 2}) {
    return DataPanelColumn<InventorySale>(
      label: 'Total',
      numeric: true,
      flex: flex,
      cell: (sale) => _text(
        formatPeso(sale.total),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: sale.status == InventorySaleStatus.voided
              ? AppColors.textSecondary
              : AppColors.textPrimary,
          decoration: sale.status == InventorySaleStatus.voided
              ? TextDecoration.lineThrough
              : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _text(String value, {int maxLines = 1, TextStyle? style}) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          style ?? const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  Widget _caption(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }

  StatusTone _displayTone(InventorySale sale) {
    if (sale.isAwaitingBodega) return StatusTone.warning;
    return switch (sale.status) {
      InventorySaleStatus.completed => StatusTone.success,
      InventorySaleStatus.refunded => StatusTone.warning,
      InventorySaleStatus.voided => StatusTone.error,
    };
  }

  String _quantity(double value) =>
      value % 1 == 0 ? formatCount(value.toInt()) : salesQty(value);

  void _openDocument(BuildContext context, InventorySale initialSale) {
    showModalBottomSheet<SalesDocumentAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        InventorySalesViewmodel? vm;
        try {
          vm = Provider.of<InventorySalesViewmodel>(sheetContext);
        } on ProviderNotFoundException {
          vm = null;
        }
        final sale =
            vm?.sales
                .where((s) => s.transactionNo == initialSale.transactionNo)
                .firstOrNull ??
            initialSale;
        return SalesDocumentSheet(
          title: sale.transactionNo,
          fields: [
            if (sale.orNumber.isNotEmpty) ('Order Slip (OS)', sale.orNumber),
            ('OR #', _isTagged(sale) ? sale.invoiceNo!.trim() : 'None'),
            ('Date', formatDateTime(sale.date)),
            ('Customer', sale.customer),
            ('Cashier', sale.cashier),
            if (widget.role == SalesTransactionsRole.storeManager)
              ('Source', sale.source),
            ('Items', formatCount(sale.lines.length)),
            ('Units out', _quantity(sale.totalQuantity)),
            for (final payment in sale.payments)
              (
                'Payment (${TenderMethod.labelFor(payment.method)})',
                formatPeso(payment.amount),
              ),
            if (sale.creditSale) ('Pricing', 'Credit price (utang)'),
            if (sale.bodegaDetailLabel != null)
              ('Bodega pickup', sale.bodegaDetailLabel!),
            if (sale.discountAmount > 0)
              (
                sale.discountReason.trim().isEmpty
                    ? 'Discount'
                    : 'Discount (${sale.discountReason})',
                formatPeso(sale.discountAmount),
              ),
            if (sale.paymentFee > 0)
              ('Payment fee', formatPeso(sale.paymentFee)),
            if (sale.vatRegistered) ...[
              ('Vatable sales', formatPeso(sale.vatableSales)),
              ('VAT', formatPeso(sale.vatAmount)),
            ] else
              ('VAT', 'Non-VAT'),
            ('Status', sale.displayStatusLabel),
            if (sale.notes.trim().isNotEmpty) ('Notes', sale.notes.trim()),
          ],
          lines: [
            for (final line in sale.lines)
              SalesDocumentLine(
                name: line.productName,
                qty: line.quantity,
                unitPrice: line.unitPrice,
              ),
          ],
          total: sale.amountDue,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedStatusPill extends StatelessWidget {
  const _SegmentedStatusPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _FilterDropdownPill extends StatelessWidget {
  const _FilterDropdownPill({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              items: [
                for (final item in items)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.totalRows,
    required this.startRow,
    required this.endRow,
    required this.currentPage,
    required this.totalPages,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  final int totalRows;
  final int startRow;
  final int endRow;
  final int currentPage;
  final int totalPages;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;

  List<int?> _pageNumbers() {
    if (totalPages <= 7) {
      return [for (var i = 1; i <= totalPages; i++) i];
    }
    final pages = <int?>[1];
    if (currentPage > 3) pages.add(null);
    final start = (currentPage - 1).clamp(2, totalPages - 1);
    final end = (currentPage + 1).clamp(2, totalPages - 1);
    for (var i = start; i <= end; i++) {
      pages.add(i);
    }
    if (currentPage < totalPages - 2) pages.add(null);
    pages.add(totalPages);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('cashier-history-pagination'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Showing $startRow–$endRow of ${formatCount(totalRows)} transactions',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Per page:',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const ValueKey('cashier-history-page-size'),
                        value: pageSize,
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        items: [
                          for (final size in pageSizeOptions)
                            DropdownMenuItem(value: size, child: Text('$size')),
                        ],
                        onChanged: (value) {
                          if (value != null) onPageSizeChanged(value);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('cashier-history-prev-page'),
                onPressed: currentPage > 1
                    ? () => onPageChanged(currentPage - 1)
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Previous', style: TextStyle(fontSize: 12)),
              ),
              for (final page in _pageNumbers())
                if (page == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '…',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  InkWell(
                    key: ValueKey('cashier-history-page-$page'),
                    onTap: () => onPageChanged(page),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: page == currentPage
                            ? AppColors.primary
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: page == currentPage
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '$page',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: page == currentPage
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              OutlinedButton(
                key: const ValueKey('cashier-history-next-page'),
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Next', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
