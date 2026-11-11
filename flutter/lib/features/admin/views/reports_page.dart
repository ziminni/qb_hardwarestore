import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/section_heading.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The ONE admin/manager Reports screen (decision 16, as amended).
///
/// Four tabs: Sales, Valuation, Movements and Requisitions, one report at a
/// time. A failed tab names its failure without blanking the other three.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  ///
  /// The page otherwise builds its own viewmodel. Same seam shape as the
  /// receivables page: a widget test cannot put the screen into a failed-load
  /// state without it.
  final AdminReportsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? AdminReportsViewmodel())..load(),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Reports',
      subtitle: 'Managerial reports over live operations data.',
      // 4, not 5: Requisitions left the admin sidebar (decision 01), so
      // Reports moved up one. A stale number here highlights Audit logs.
      selectedNavigationIndex: 4,
      child: ReportsContent(),
    );
  }
}

/// The four-tab report body, **layout-agnostic on purpose**.
///
/// It reads the `AdminReportsViewmodel` its host provides and renders nothing
/// else: no shell, no sidebar. Two shells show these reports: the admin one
/// ([ReportsPage]) and the sales one (`SalesReportsPage`, decision D-01).
/// Keeping the body here is what stops the second shell from becoming a copy of
/// four reports that drifts the first time one of them changes.
///
/// The chosen period lives here, not in the viewmodel, because it is the same
/// two dates for both ranged reports (Sales and Movements): switching tabs must
/// not silently re-scope the numbers the reader is comparing.
class ReportsContent extends StatefulWidget {
  const ReportsContent({super.key});

  static const tabs = ['Sales', 'Valuation', 'Movements', 'Requisitions'];

  @override
  State<ReportsContent> createState() => _ReportsContentState();
}

/// The periods a report can cover, in the order the menu lists them.
enum _ReportPeriod {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  last30Days('Last 30 days'),

  /// Two days the reader picks; [boundsFor] cannot compute them.
  custom('Custom range');

  const _ReportPeriod(this.label);

  final String label;

  /// The two dates this period covers at [now], inclusive, or null for
  /// [custom].
  ///
  /// Last 30 days is the server's own default (`DEFAULT_RANGE_DAYS = 30`:
  /// `to` minus 30 days up to `to`), so leaving the period untouched and
  /// choosing it ask for the same window.
  DateTimeRange? boundsFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      // Weeks start on Monday, the way the sales screens count them.
      _ReportPeriod.today => DateTimeRange(start: today, end: today),
      _ReportPeriod.thisWeek => DateTimeRange(
        start: today.subtract(Duration(days: now.weekday - 1)),
        end: today,
      ),
      _ReportPeriod.thisMonth => DateTimeRange(
        start: DateTime(now.year, now.month),
        end: today,
      ),
      _ReportPeriod.last30Days => DateTimeRange(
        start: today.subtract(const Duration(days: 30)),
        end: today,
      ),
      _ReportPeriod.custom => null,
    };
  }
}

class _ReportsContentState extends State<ReportsContent> {
  _ReportPeriod _period = _ReportPeriod.last30Days;

  /// The days the picker returned, kept so the control can name them.
  DateTimeRange? _pickedRange;

  /// The two days the report on screen covers.
  DateTimeRange get _bounds => _period == _ReportPeriod.custom
      ? (_pickedRange ?? _ReportPeriod.thisMonth.boundsFor(appClock.now())!)
      : _period.boundsFor(appClock.now())!;

  void _choose(_ReportPeriod period) {
    setState(() => _period = period);
    _send(period.boundsFor(appClock.now())!);
  }

  Future<void> _chooseCustomRange() async {
    final now = appClock.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      // The "today" ring follows the app's clock, not the framework's own
      // `DateTime.now()`, so the picker cannot disagree with the range it opens
      // on.
      currentDate: now,
      // Opens on the range already applied: the reader always sees what they
      // are narrowing, and Save with no taps is a valid choice.
      initialDateRange: _period == _ReportPeriod.custom
          ? _pickedRange
          : _period.boundsFor(now),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _period = _ReportPeriod.custom;
      _pickedRange = selected;
    });
    _send(selected);
  }

  void _send(DateTimeRange range) {
    context.read<AdminReportsViewmodel>().setRange(
      _isoDate(range.start),
      _isoDate(range.end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<AdminReportsViewmodel>();
    final periodControl = _PeriodControl(
      period: _period,
      rangeLabel: _period == _ReportPeriod.custom
          ? '${formatDate(_bounds.start)} to ${formatDate(_bounds.end)}'
          : null,
      onSelected: _choose,
      onCustom: _chooseCustomRange,
    );

    return DefaultTabController(
      length: ReportsContent.tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            isScrollable: true,
            onTap: (index) => viewmodel.selectTab(index),
            tabs: [for (final tab in ReportsContent.tabs) Tab(text: tab)],
          ),
          const SizedBox(height: AppSpacing.md),
          // No TabBarView: it demands a height of its own, and both shells hand
          // the page an unbounded column inside their scroll view. The old
          // fixed 900 px box was the answer to that, and it clipped the short
          // reports. Only the selected tab is built, exactly like TabBarView.
          switch (viewmodel.selectedTab) {
            1 => _ValuationTab(viewmodel: viewmodel),
            2 => _MovementsTab(
              viewmodel: viewmodel,
              periodControl: periodControl,
            ),
            3 => _RequisitionsTab(viewmodel: viewmodel),
            _ => _SalesTab(viewmodel: viewmodel, periodControl: periodControl),
          },
        ],
      ),
    );
  }
}

/// The period the two ranged reports cover: a menu of presets plus a date range
/// picker for anything else.
///
/// One menu rather than a row of chips: `FilterBar` owns the chip look but it
/// always renders a search field, and there is nothing to search in a table of
/// daily totals (a5 report, "Differences from the plan").
class _PeriodControl extends StatelessWidget {
  const _PeriodControl({
    required this.period,
    required this.rangeLabel,
    required this.onSelected,
    required this.onCustom,
  });

  final _ReportPeriod period;

  /// The two picked days in words, when [period] is custom.
  final String? rangeLabel;

  final ValueChanged<_ReportPeriod> onSelected;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final label = rangeLabel ?? period.label;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<_ReportPeriod>(
        key: const Key('reports-period'),
        tooltip: 'Report period',
        initialValue: period,
        // The five periods are on screen together or the last one is a promise
        // the reader cannot press: the stock menu reveals itself by growing its
        // Material's height, so for the first ~290 ms of its 300 ms open the
        // fifth item is clipped out of the panel (QA wave 3b reported exactly
        // that sliver at 1440 x 900). A filter menu has nothing to stage.
        popUpAnimationStyle: AnimationStyle.noAnimation,
        onSelected: (value) =>
            value == _ReportPeriod.custom ? onCustom() : onSelected(value),
        itemBuilder: (context) => [
          for (final option in _ReportPeriod.values)
            PopupMenuItem<_ReportPeriod>(
              value: option,
              child: Text(option.label),
            ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab's report, with the two rules every tab shares: a failed FIRST load is
/// one banner and nothing else (a row of ₱0.00 tiles would read as a month
/// nobody sold anything in), and a failed REFRESH keeps the numbers it already
/// had and says why above them.
class _ReportTab<T> extends StatelessWidget {
  const _ReportTab({
    required this.value,
    required this.error,
    required this.onRetry,
    required this.builder,
  });

  final T? value;
  final String? error;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final data = value;
    final failure = error;
    if (data == null) {
      if (failure != null) {
        return Align(
          alignment: Alignment.topCenter,
          child: ErrorBanner(message: failure, onRetry: onRetry),
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: onRetry),
          const SizedBox(height: AppSpacing.md),
        ],
        builder(context, data),
      ],
    );
  }
}

/// One day of sales, or the period's total: the total is a row of the same table
/// so the money columns stay lined up down the decimal point.
typedef _SalesRow = ({
  String label,
  int transactions,
  double gross,
  double vat,
  bool isTotal,
});

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.viewmodel, required this.periodControl});

  final AdminReportsViewmodel viewmodel;
  final Widget periodControl;

  List<DataPanelColumn<_SalesRow>> get _columns => [
    DataPanelColumn<_SalesRow>(
      label: 'Day',
      flex: 3,
      cell: (row) => _cell(row.label, bold: row.isTotal),
    ),
    DataPanelColumn<_SalesRow>(
      label: 'Transactions',
      numeric: true,
      cell: (row) => _cell(formatCount(row.transactions), bold: row.isTotal),
    ),
    DataPanelColumn<_SalesRow>(
      label: 'Gross',
      numeric: true,
      cell: (row) => _cell(formatPeso(row.gross), bold: row.isTotal),
    ),
    DataPanelColumn<_SalesRow>(
      label: 'VAT',
      numeric: true,
      cell: (row) => _cell(formatPeso(row.vat), bold: row.isTotal),
    ),
  ];

  List<_SalesRow> _rows(SalesSummary sales) => [
    for (final day in sales.days)
      (
        label: _dateLabel(day.day),
        transactions: day.transactions,
        gross: day.gross,
        vat: day.vat,
        isTotal: false,
      ),
    if (sales.days.isNotEmpty)
      (
        label: 'Total',
        transactions: sales.totalTransactions,
        gross: sales.totalGross,
        vat: sales.totalVat,
        isTotal: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return _ReportTab<SalesSummary>(
      value: viewmodel.sales,
      error: viewmodel.errorFor(0),
      onRetry: viewmodel.reload,
      builder: (context, sales) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          periodControl,
          const SizedBox(height: AppSpacing.md),
          // D12: no Discounts tile. Checkout hard-zeroes the discount, so the
          // tile could only ever read ₱0.00 and advertise a feature the system
          // does not have.
          MetricGrid(
            children: [
              MetricTile(
                label: 'Transactions',
                value: formatCount(sales.totalTransactions),
                caption: 'Completed sales',
              ),
              MetricTile(
                label: 'Gross sales',
                value: formatPeso(sales.totalGross),
              ),
              MetricTile(label: 'VAT', value: formatPeso(sales.totalVat)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<_SalesRow>(
            columns: _columns,
            rows: _rows(sales),
            emptyMessage: 'No sales in this range.',
          ),
        ],
      ),
    );
  }
}

/// One category's valuation, or the total across every category on hand.
typedef _ValuationRow = ({
  String label,
  int batches,
  double units,
  double cost,
  double retail,
  bool isTotal,
});

class _ValuationTab extends StatelessWidget {
  const _ValuationTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  List<DataPanelColumn<_ValuationRow>> get _columns => [
    DataPanelColumn<_ValuationRow>(
      label: 'Category',
      flex: 3,
      cell: (row) => _cell(row.label, bold: row.isTotal),
    ),
    DataPanelColumn<_ValuationRow>(
      label: 'Batches',
      numeric: true,
      cell: (row) => _cell(formatCount(row.batches), bold: row.isTotal),
    ),
    DataPanelColumn<_ValuationRow>(
      label: 'Units',
      numeric: true,
      cell: (row) => _cell(formatQuantity(row.units), bold: row.isTotal),
    ),
    DataPanelColumn<_ValuationRow>(
      label: 'At cost',
      numeric: true,
      cell: (row) => _cell(formatPeso(row.cost), bold: row.isTotal),
    ),
    DataPanelColumn<_ValuationRow>(
      label: 'At retail',
      numeric: true,
      cell: (row) => _cell(formatPeso(row.retail), bold: row.isTotal),
    ),
  ];

  List<_ValuationRow> _rows(InventoryValuation valuation) => [
    for (final category in valuation.categories)
      (
        label: category.name,
        batches: category.batchCount,
        units: category.units,
        cost: category.cost,
        retail: category.retail,
        isTotal: false,
      ),
    if (valuation.categories.isNotEmpty)
      (
        label: 'Total',
        batches: valuation.batchCount,
        units: valuation.totalUnits,
        cost: valuation.totalCost,
        retail: valuation.totalRetail,
        isTotal: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return _ReportTab<InventoryValuation>(
      value: viewmodel.valuation,
      error: viewmodel.errorFor(1),
      onRetry: viewmodel.reload,
      builder: (context, valuation) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricGrid(
            children: [
              MetricTile(
                label: 'Batches',
                value: formatCount(valuation.batchCount),
              ),
              MetricTile(
                label: 'Units on hand',
                value: formatQuantity(valuation.totalUnits),
              ),
              MetricTile(
                label: 'Value at cost',
                value: formatPeso(valuation.totalCost),
              ),
              MetricTile(
                label: 'Value at retail',
                value: formatPeso(valuation.totalRetail),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<_ValuationRow>(
            columns: _columns,
            rows: _rows(valuation),
            emptyMessage: 'No stock on hand.',
          ),
        ],
      ),
    );
  }
}

/// One day of goods received, or the period's total.
typedef _ReceiptRow = ({
  String label,
  int receipts,
  double qtyIn,
  bool isTotal,
});

/// One adjustment type, or the period's total.
typedef _AdjustmentRow = ({
  String label,
  int movements,
  double quantity,
  bool isTotal,
});

class _MovementsTab extends StatelessWidget {
  const _MovementsTab({required this.viewmodel, required this.periodControl});

  final AdminReportsViewmodel viewmodel;
  final Widget periodControl;

  /// Says out loud what the server's "out" total counts. Sales and releases
  /// never reach this endpoint, so an unlabelled total would read as the whole
  /// stock movement.
  static const String _note = 'Sales and releases are not included.';

  List<DataPanelColumn<_ReceiptRow>> get _receiptColumns => [
    DataPanelColumn<_ReceiptRow>(
      label: 'Day',
      flex: 3,
      cell: (row) => _cell(row.label, bold: row.isTotal),
    ),
    DataPanelColumn<_ReceiptRow>(
      label: 'Receipts',
      numeric: true,
      cell: (row) => _cell(formatCount(row.receipts), bold: row.isTotal),
    ),
    DataPanelColumn<_ReceiptRow>(
      label: 'Quantity in',
      numeric: true,
      cell: (row) => _cell(formatQuantity(row.qtyIn), bold: row.isTotal),
    ),
  ];

  List<DataPanelColumn<_AdjustmentRow>> get _adjustmentColumns => [
    DataPanelColumn<_AdjustmentRow>(
      label: 'Type',
      flex: 3,
      cell: (row) => _cell(row.label, bold: row.isTotal),
    ),
    DataPanelColumn<_AdjustmentRow>(
      label: 'Adjustments',
      numeric: true,
      cell: (row) => _cell(formatCount(row.movements), bold: row.isTotal),
    ),
    DataPanelColumn<_AdjustmentRow>(
      label: 'Quantity adjusted',
      numeric: true,
      cell: (row) => _cell(formatQuantity(row.quantity), bold: row.isTotal),
    ),
  ];

  List<_ReceiptRow> _receipts(StockMovements movements) => [
    for (final day in movements.receiptsByDay)
      (
        label: _dateLabel(day.date),
        receipts: day.receipts,
        qtyIn: day.qtyIn,
        isTotal: false,
      ),
    if (movements.receiptsByDay.isNotEmpty)
      (
        label: 'Total',
        receipts: movements.receiptsByDay.fold(0, (sum, d) => sum + d.receipts),
        qtyIn: movements.totalIn,
        isTotal: true,
      ),
  ];

  List<_AdjustmentRow> _adjustments(StockMovements movements) => [
    for (final type in movements.adjustmentsByType)
      (
        label: _adjustmentLabel(type.type),
        movements: type.movements,
        quantity: type.qtyOut,
        isTotal: false,
      ),
    if (movements.adjustmentsByType.isNotEmpty)
      (
        label: 'Total',
        movements: movements.adjustmentsByType.fold(
          0,
          (sum, t) => sum + t.movements,
        ),
        quantity: movements.totalOut,
        isTotal: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return _ReportTab<StockMovements>(
      value: viewmodel.movements,
      error: viewmodel.errorFor(2),
      onRetry: viewmodel.reload,
      builder: (context, movements) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          periodControl,
          const SizedBox(height: AppSpacing.md),
          MetricGrid(
            children: [
              MetricTile(
                label: 'Units in',
                value: formatQuantity(movements.totalIn),
                caption: 'Goods received',
              ),
              MetricTile(
                label: 'Adjustments',
                value: formatQuantity(movements.totalOut),
                caption: 'Stock written off or corrected',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            _note,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionHeading(title: 'Goods received'),
          DataPanel<_ReceiptRow>(
            columns: _receiptColumns,
            rows: _receipts(movements),
            emptyMessage: 'No receipts in this range.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeading(title: 'Adjustments by type'),
          DataPanel<_AdjustmentRow>(
            columns: _adjustmentColumns,
            rows: _adjustments(movements),
            emptyMessage: 'No adjustments in this range.',
          ),
        ],
      ),
    );
  }
}

class _RequisitionsTab extends StatelessWidget {
  const _RequisitionsTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  /// Widths measured at 1100 px: the requisition number, the status badge and
  /// the two names hold their text, and the project name, the one long value in
  /// the row, takes the rest of the width.
  List<DataPanelColumn<RequisitionHistoryRow>> get _columns => [
    DataPanelColumn<RequisitionHistoryRow>(
      label: 'Requisition',
      flex: 4,
      cell: (row) => _cell(row.reqNumber),
    ),
    DataPanelColumn<RequisitionHistoryRow>(
      label: 'Status',
      flex: 4,
      cell: (row) => StatusBadge(
        label: _statusLabel(row.status),
        tone: _statusTone(RequisitionStatus.fromApiValue(row.status)),
      ),
    ),
    DataPanelColumn<RequisitionHistoryRow>(
      label: 'Project',
      flex: 10,
      cell: (row) => _cell(row.project),
    ),
    DataPanelColumn<RequisitionHistoryRow>(
      label: 'Requested by',
      flex: 3,
      cell: (row) => _cell(row.requestedBy),
    ),
    DataPanelColumn<RequisitionHistoryRow>(
      label: 'Approved by',
      flex: 3,
      // D18: a word, not a lone dash, for "nobody approved this".
      cell: (row) => _cell(row.approvedBy ?? 'Not approved'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _ReportTab<RequisitionHistory>(
      value: viewmodel.history,
      error: viewmodel.errorFor(3),
      onRetry: viewmodel.reload,
      builder: (context, history) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.countByStatus.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in history.countByStatus.entries)
                  StatusBadge(
                    label:
                        '${_statusLabel(entry.key)}: '
                        '${formatCount(entry.value)}',
                    tone: _statusTone(
                      RequisitionStatus.fromApiValue(entry.key),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          DataPanel<RequisitionHistoryRow>(
            columns: _columns,
            rows: history.requisitions,
            emptyMessage: 'No requisitions in this range.',
          ),
        ],
      ),
    );
  }
}

/// A table cell that shortens instead of pushing its row wider; the total row
/// leans on weight alone, so no row grows a background stripe.
Widget _cell(String text, {bool bold = false}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: 13,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: AppColors.textPrimary,
  ),
);

/// `2026-10-19` (the server's day) as `Oct 19, 2026` (D6). An unparsable day
/// keeps the server's own word instead of showing a date nobody recorded.
String _dateLabel(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : formatDate(date);
}

/// The one shape the server's `from`/`to` query takes.
String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The server's adjustment type as words. A type the client has not been taught
/// keeps the server's own token rather than being filed under a guess.
String _adjustmentLabel(String type) {
  for (final known in StockAdjustmentType.values) {
    if (known.apiValue == type) return known.displayName;
  }
  return type;
}

/// A requisition status in words; an unknown status keeps the server's token.
String _statusLabel(String apiValue) {
  final status = RequisitionStatus.fromApiValue(apiValue);
  return status == RequisitionStatus.unknown ? apiValue : status.label;
}

StatusTone _statusTone(RequisitionStatus status) => switch (status) {
  // Phase 1b (decision 13): a pushed request WAITS for the store's answer, so it reads
  // as work outstanding; ACCEPTED is the store's promise that the till will serve it;
  // DECLINED is a dead end. APPROVED keeps its old positive tone for legacy rows.
  RequisitionStatus.waiting => StatusTone.warning,
  RequisitionStatus.accepted => StatusTone.success,
  RequisitionStatus.declined => StatusTone.error,
  RequisitionStatus.submitted => StatusTone.warning,
  RequisitionStatus.approved => StatusTone.info,
  // Partly released: stock still owes the project, so it reads as work outstanding.
  RequisitionStatus.partial => StatusTone.warning,
  RequisitionStatus.released => StatusTone.success,
  RequisitionStatus.rejected => StatusTone.error,
  // Closed is a finished, quiet state: CPMS shut the remainder, nothing to chase.
  RequisitionStatus.closed ||
  RequisitionStatus.cancelled ||
  RequisitionStatus.draft ||
  RequisitionStatus.unknown => StatusTone.neutral,
};
