import 'dart:typed_data';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/reports_excel_export.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_pdf.dart';
import 'package:client/features/reports/reports_shell.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/settings_side_layout.dart'
    show StoreInformationPanel;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

/// The ONE viewer every catalogue card opens.
///
/// Same shape for every report: date range on top, KPI tiles, the data table,
/// then Export PDF / Export Excel. Each report only contributes a mapping from
/// its model to [_ReportView], so a new endpoint costs a mapping function and
/// nothing else — the layout cannot drift report by report.
class ReportViewerPage extends StatelessWidget {
  const ReportViewerPage({
    super.key,
    required this.report,
    this.shell = ReportsShell.sales,
    this.repository,
  });

  final ReportDefinition report;
  final ReportsShell shell;

  /// Injected by tests so the viewer renders without a server.
  final ReportsRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ReportsShellScaffold(
      shell: shell,
      child: ReportViewerView(
        report: report,
        repository: repository,
        onBack: () => context.go(shell.cataloguePath),
      ),
    );
  }
}

/// The viewer body, without a shell, so it renders in any Reports shell and in a
/// test.
class ReportViewerView extends StatefulWidget {
  const ReportViewerView({
    super.key,
    required this.report,
    this.repository,
    this.initialRange,
    this.onBack,
  });

  final ReportDefinition report;
  final ReportsRepository? repository;

  /// Opens on this range instead of the server's default last 30 days.
  final DateTimeRange? initialRange;

  /// Shown as "All reports" when the host can go back to the catalogue.
  final VoidCallback? onBack;

  @override
  State<ReportViewerView> createState() => _ReportViewerViewState();
}

class _ReportViewerViewState extends State<ReportViewerView> {
  late final ReportsRepository _repository =
      widget.repository ?? ReportsRepository();

  late DateTimeRange _range = widget.initialRange ?? _lastThirtyDays();

  /// The loaded report, already shaped for the tiles and the table.
  _ReportView? _view;
  String? _error;
  bool _loading = true;

  static DateTimeRange _lastThirtyDays() {
    final now = appClock.now();
    final today = DateTime(now.year, now.month, now.day);
    // The server's own default (`DEFAULT_RANGE_DAYS = 30`): same window, so an
    // untouched viewer and a bare request report the same numbers.
    return DateTimeRange(
      start: today.subtract(const Duration(days: 30)),
      end: today,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.report.available) {
      setState(() => _loading = false);
      return;
    }
    final from = _isoDate(_range.start);
    final to = _isoDate(_range.end);
    try {
      final _ReportView view;
      switch (widget.report.id) {
        case 'sales-summary':
          view = _salesView(
            await _repository.fetchSalesSummary(from: from, to: to),
          );
        case 'vat-summary':
          view = _vatView(
            await _repository.fetchVatSummary(from: from, to: to),
          );
        case 'inventory-valuation':
          view = _valuationView(await _repository.fetchInventoryValuation());
        case 'stock-movements':
          view = _movementsView(
            await _repository.fetchStockMovements(from: from, to: to),
          );
        case 'requisition-history':
          view = _requisitionsView(await _repository.fetchRequisitionHistory());
        case 'item-wise':
          view = _salesByItemView(
            await _repository.fetchSalesByItem(from: from, to: to),
          );
        case 'hourly':
          view = _salesByHourView(
            await _repository.fetchSalesByHour(from: from, to: to),
          );
        case 'cashier':
          view = _salesByCashierView(
            await _repository.fetchSalesByCashier(from: from, to: to),
          );
        case 'bill-wise':
          view = _billWiseView(
            await _repository.fetchBillWise(from: from, to: to),
          );
        case 'returns':
          view = _returnsExchangesView(
            await _repository.fetchReturnsExchanges(from: from, to: to),
          );
        case 'discounts':
          view = _discountsView(
            await _repository.fetchDiscounts(from: from, to: to),
          );
        case 'voids':
          view = _voidsView(await _repository.fetchVoids(from: from, to: to));
        case 'grn':
          view = _grnView(await _repository.fetchGrn(from: from, to: to));
        case 'stn':
          view = _stnView(await _repository.fetchStn(from: from, to: to));
        case 'batch-age':
          view = _batchAgeView(await _repository.fetchBatchAge());
        case 'shrinkage':
          view = _shrinkageView(
            await _repository.fetchShrinkage(from: from, to: to),
          );
        case 'adjustments':
          view = _adjustmentsView(
            await _repository.fetchAdjustments(from: from, to: to),
          );
        case 'reorder':
          view = _reorderView(await _repository.fetchReorder());
        case 'dead-stock':
          view = _deadStockView(await _repository.fetchDeadStock());
        case 'fast-slow':
          view = _fastSlowView(
            await _repository.fetchFastSlow(from: from, to: to),
          );
        case 'cycle-count':
          view = _cycleCountView(
            await _repository.fetchCycleCount(from: from, to: to),
          );
        case 'expiry':
          view = _expiryView(await _repository.fetchExpiry());
        default:
          // No endpoint behind this id yet: the catalogue already disables the
          // card, and a typed address gets the same honest sentence.
          view = const _ReportView(
            kpis: [],
            columns: [],
            rows: [],
            emptyMessage: 'This report has no endpoint yet (planned P1).',
          );
      }
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } on ReportsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = appClock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      currentDate: now,
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    await _load();
  }

  Future<void> _exportExcel() async {
    final view = _view;
    final name = view?.excelName;
    final bytes = view?.excelBytes;
    if (name == null || bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel workbook', extensions: ['xlsx']),
        ],
      );
      if (location == null) return;
      final file = XFile.fromData(
        bytes(),
        name: name,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await file.saveTo(location.path);
      messenger.showSnackBar(SnackBar(content: Text('Exported $name')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export Excel report: $error')),
      );
    }
  }

  Future<void> _exportPdf() async {
    final view = _view;
    final build = view?.pdfBytes;
    if (view == null || build == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The account that pressed the button signs the paper.
      final generatedBy = context.read<AuthViewmodel>().user?.fullName ?? '';
      final bytes = await build(generatedBy);
      await Printing.sharePdf(
        bytes: bytes,
        filename: view.pdfName ?? 'report.pdf',
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export the PDF report: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final failure = _error;
    final excel = OutlinedButton.icon(
      key: const ValueKey('report-viewer-export-excel'),
      onPressed: view?.excelBytes == null ? null : _exportExcel,
      icon: const Icon(Icons.download_outlined, size: 18),
      label: const Text('Export Excel'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.onBack != null)
              TextButton.icon(
                key: const ValueKey('report-viewer-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('All reports'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('report-viewer-range'),
              onPressed: _pickRange,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                '${formatDate(_range.start)} to ${formatDate(_range.end)}',
              ),
            ),
            // A report that wired a letterhead builder exports a PDF
            // (decision 01-export-layout); the rest keep the button off and
            // say when it lands, rather than pressed into a no-op.
            Tooltip(
              message: view?.pdfBytes == null ? 'PDF export arrives in P3' : '',
              child: OutlinedButton.icon(
                key: const ValueKey('report-viewer-export-pdf'),
                onPressed: view?.pdfBytes == null ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Export PDF'),
              ),
            ),
            // Same rule for Excel: a report with a workbook builder exports, and
            // one without keeps the button off and says when it lands.
            if (view?.excelBytes != null)
              excel
            else
              Tooltip(message: 'Excel lands in P3', child: excel),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: CircularProgressIndicator(),
            ),
          )
        else if (failure != null)
          Align(
            alignment: Alignment.topCenter,
            child: ErrorBanner(message: failure, onRetry: _load),
          )
        else if (view != null) ...[
          if (view.kpis.isNotEmpty) ...[
            MetricGrid(
              children: [
                for (final kpi in view.kpis)
                  MetricTile(
                    label: kpi.label,
                    value: kpi.value,
                    caption: kpi.caption,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          // Graphs sit between the tiles and the table: the summary line first,
          // then what it is made of. A report that plots nothing passes no
          // charts and keeps the tiles + table layout it always had.
          if (view.charts != null) ...[
            if (view.charts!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'No data for this range',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              for (final chart in view.charts!) ...[
                chart,
                const SizedBox(height: AppSpacing.md),
              ],
          ],
          DataPanel<List<String>>(
            key: const ValueKey('report-viewer-table'),
            columns: [
              for (var index = 0; index < view.columns.length; index++)
                DataPanelColumn<List<String>>(
                  label: view.columns[index],
                  flex: index == 0 ? 3 : 1,
                  cell: (row) => Text(
                    row[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
            rows: view.rows,
            emptyMessage: view.emptyMessage,
          ),
        ],
      ],
    );
  }
}

/// One KPI tile's text, already formatted.
typedef _Kpi = ({String label, String value, String? caption});

/// Builds a report's letterhead PDF from the viewer's already-formatted
/// content, signed with the account that pressed Export.
typedef _PdfBuilder = Future<Uint8List> Function(String generatedBy);

/// A report reduced to what the shared layout draws: tiles, a table, and the
/// workbook and PDF bytes its export buttons write.
class _ReportView {
  const _ReportView({
    required this.kpis,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
    this.excelName,
    this.excelBytes,
    this.pdfName,
    this.pdfBytes,
    this.charts,
  });

  final List<_Kpi> kpis;
  final List<String> columns;
  final List<List<String>> rows;
  final String emptyMessage;

  /// Graphs drawn under the tiles and above the table. Null means the report
  /// has nothing plottable at all; an empty list means it does, but this range
  /// left nothing to draw — the viewer then says so in words.
  final List<Widget>? charts;
  final String? excelName;
  final Uint8List Function()? excelBytes;
  final String? pdfName;
  final _PdfBuilder? pdfBytes;
}

_ReportView _salesView(SalesSummary sales) {
  final kpis = <_Kpi>[
    (
      label: 'Transactions',
      value: formatCount(sales.totalTransactions),
      caption: 'Completed sales',
    ),
    (
      label: 'Invoice total',
      value: formatPeso(sales.totalGross),
      caption: 'After discounts and returns',
    ),
    (
      label: 'Discounts',
      value: formatPeso(sales.totalDiscounts),
      caption: null,
    ),
    (label: 'VAT', value: formatPeso(sales.totalVat), caption: null),
    // The three KPIs the catalogue's KPI section names, each shown with its own
    // sum so a number is never read without the arithmetic behind it.
    if (sales.abv != null)
      (
        label: 'Average bill value',
        value: formatPeso(sales.abv!),
        caption: 'Invoice total ÷ bills',
      ),
    if (sales.asp != null)
      (
        label: 'Average selling price',
        value: formatPeso(sales.asp!),
        caption: 'Net ÷ units sold',
      ),
    if (sales.markdownPercent != null)
      (
        label: 'Markdown',
        value: '${sales.markdownPercent!.toStringAsFixed(1)}%',
        caption: 'Discounts ÷ gross',
      ),
  ];
  const columns = ['Day', 'Transactions', 'Invoice total', 'Discounts', 'VAT'];
  final rows = <List<String>>[
    for (final day in sales.days)
      [
        _dateLabel(day.day),
        formatCount(day.transactions),
        formatPeso(day.gross),
        formatPeso(day.discounts),
        formatPeso(day.vat),
      ],
    if (sales.days.isNotEmpty)
      [
        'Total',
        formatCount(sales.totalTransactions),
        formatPeso(sales.totalGross),
        formatPeso(sales.totalDiscounts),
        formatPeso(sales.totalVat),
      ],
  ];
  final period = '${_dateLabel(sales.from)} to ${_dateLabel(sales.to)}';
  return _ReportView(
    kpis: kpis,
    columns: columns,
    rows: rows,
    emptyMessage: 'No sales in this range.',
    excelName: 'sales-report-${sales.from}-to-${sales.to}.xlsx',
    excelBytes: () => buildSalesReportXlsx(sales),
    pdfName: 'sales-summary-${sales.from}-to-${sales.to}.pdf',
    // Same tiles, columns and rows the screen drew: the paper and the viewer
    // cannot disagree about what the report said.
    pdfBytes: (generatedBy) => renderReportPdf(
      title: 'Sales summary',
      period: period,
      generatedBy: generatedBy,
      // shortcut: static store header until store details are user-editable.
      storeName: StoreInformationPanel.storeName,
      kpis: kpis,
      columns: columns,
      rows: rows,
    ),
    charts: [
      if (sales.days.isNotEmpty)
        GroupedBarTrendChart(
          key: const ValueKey('report-viewer-sales-trend'),
          title: 'Daily sales & profit',
          subtitle: sales.days.any((day) => day.cogs != null)
              ? 'Bars compare net sales (ex-VAT) vs. landed COGS; the line tracks gross profit.'
              : 'Daily invoice total across the reported dates.',
          primaryLabel: sales.days.any((d) => d.merchandiseNetExVat != null)
              ? 'Net sales (ex-VAT)'
              : 'Invoice total',
          secondaryLabel: 'COGS',
          lineLabel: 'Gross profit',
          height: 190,
          points: [
            for (final day in sales.days)
              TrendPoint(
                label: day.day.length >= 10 ? day.day.substring(5) : day.day,
                primary: day.merchandiseNetExVat ?? day.gross,
                secondary: day.cogs,
                lineValue: day.grossProfit,
              ),
          ],
        ),
      if (sales.categories.isNotEmpty)
        HorizontalComparisonChart(
          key: const ValueKey('report-viewer-category-chart'),
          title: 'Sales & cost by category',
          subtitle: 'Top categories by net merchandise sales vs. landed cost.',
          primaryLabel: 'Net sales',
          secondaryLabel: 'COGS',
          items: [
            for (final category in sales.categories.take(6))
              ComparisonBarItem(
                label: category.categoryName,
                primaryValue: category.netMerchandise,
                primaryText: formatPeso(category.netMerchandise),
                secondaryValue: category.cogs,
                secondaryText: category.cogs == null
                    ? null
                    : 'COGS ${formatPeso(category.cogs!)}',
              ),
          ],
        ),
    ],
  );
}

_ReportView _vatView(VatReportSummary report) => _ReportView(
  kpis: [
    (
      label: 'Whole VAT',
      value: formatPeso(report.totals.combined.vat),
      caption: 'Every completed sale',
    ),
    (
      label: 'OR-tagged VAT',
      value: formatPeso(report.totals.orBacked.vat),
      caption: 'BIR official receipts',
    ),
    (
      label: 'Untagged VAT',
      value: formatPeso(report.totals.untaggedOs.vat),
      caption: 'Order slips without an OR',
    ),
  ],
  columns: const ['Period', 'OR sales', 'OR VAT', 'Untagged VAT', 'Whole VAT'],
  rows: [
    for (final period in report.periods)
      [
        _dateLabel(period.period),
        formatPeso(period.orBackedSales),
        formatPeso(period.orBackedVat),
        formatPeso(period.untaggedVat),
        formatPeso(period.vat),
      ],
    if (report.periods.isNotEmpty)
      [
        'Total',
        formatPeso(report.totals.orBacked.grossSales),
        formatPeso(report.totals.orBacked.vat),
        formatPeso(report.totals.untaggedOs.vat),
        formatPeso(report.totals.combined.vat),
      ],
  ],
  emptyMessage: 'No sales recorded in this period.',
  excelName:
      'vat-or-report-${report.granularity}-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildVatReportXlsx(report),
);

_ReportView _valuationView(InventoryValuation valuation) => _ReportView(
  kpis: [
    (label: 'Batches', value: formatCount(valuation.batchCount), caption: null),
    (
      label: 'Units on hand',
      value: formatQuantity(valuation.totalUnits),
      caption: null,
    ),
    (
      label: 'Value at cost',
      value: formatPeso(valuation.totalCost),
      caption: 'Landed cost',
    ),
    (
      label: 'Value at retail',
      value: formatPeso(valuation.totalRetail),
      caption: 'Current selling price',
    ),
  ],
  columns: const ['Category', 'Batches', 'Units', 'At cost', 'At retail'],
  rows: [
    for (final category in valuation.categories)
      [
        category.name,
        formatCount(category.batchCount),
        formatQuantity(category.units),
        formatPeso(category.cost),
        formatPeso(category.retail),
      ],
    if (valuation.categories.isNotEmpty)
      [
        'Total',
        formatCount(valuation.batchCount),
        formatQuantity(valuation.totalUnits),
        formatPeso(valuation.totalCost),
        formatPeso(valuation.totalRetail),
      ],
  ],
  emptyMessage: 'No stock on hand.',
  excelName: 'inventory-valuation.xlsx',
  excelBytes: () => buildValuationReportXlsx(valuation),
);

_ReportView _movementsView(StockMovements movements) => _ReportView(
  kpis: [
    (
      label: 'Units in',
      value: formatQuantity(movements.totalIn),
      caption: 'Goods received',
    ),
    (
      label: 'Units adjusted',
      value: formatQuantity(movements.totalOut),
      caption: 'Written off or corrected',
    ),
  ],
  columns: const ['Day', 'Receipts', 'Quantity in'],
  rows: [
    for (final day in movements.receiptsByDay)
      [
        _dateLabel(day.date),
        formatCount(day.receipts),
        formatQuantity(day.qtyIn),
      ],
    if (movements.receiptsByDay.isNotEmpty)
      [
        'Total',
        formatCount(
          movements.receiptsByDay.fold(0, (sum, day) => sum + day.receipts),
        ),
        formatQuantity(movements.totalIn),
      ],
  ],
  // The endpoint reports goods received and adjustments only; sales and
  // releases never reach it, so the empty message says so instead of reading
  // as a stock figure of zero.
  emptyMessage: 'No goods received in this range. Sales are not included.',
  excelName: 'stock-movements-${movements.from}-to-${movements.to}.xlsx',
  excelBytes: () => buildMovementsReportXlsx(movements),
);

_ReportView _requisitionsView(RequisitionHistory history) => _ReportView(
  kpis: [
    (
      label: 'Requisitions',
      value: formatCount(history.requisitions.length),
      caption: null,
    ),
    for (final entry in history.countByStatus.entries)
      (label: entry.key, value: formatCount(entry.value), caption: null),
  ],
  columns: const [
    'Requisition',
    'Status',
    'Project',
    'Requested by',
    'Approved by',
  ],
  rows: [
    for (final row in history.requisitions)
      [
        row.reqNumber,
        row.status,
        row.project,
        row.requestedBy,
        row.approvedBy ?? 'Not approved',
      ],
  ],
  emptyMessage: 'No requisitions in this range.',
  excelName: 'requisition-history.xlsx',
  excelBytes: () => buildRequisitionsReportXlsx(history),
);

_ReportView _salesByItemView(SalesByItemReport report) => _ReportView(
  kpis: [
    (
      label: 'Selling units',
      value: formatCount(report.variantCount),
      caption: null,
    ),
    (
      label: 'Units sold',
      value: formatQuantity(report.totalQtyBase),
      caption: 'Base units',
    ),
    (
      label: 'Net merchandise',
      value: formatPeso(report.totalNet),
      caption: 'After discounts',
    ),
    if (report.totalGrossProfit != null)
      (
        label: 'Gross profit',
        value: formatPeso(report.totalGrossProfit!),
        caption: 'Net minus COGS',
      ),
  ],
  columns: const [
    'Item',
    'Units sold',
    'Net merchandise',
    'COGS',
    'Gross profit',
  ],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        formatQuantity(row.qtyBase),
        formatPeso(row.net),
        // No costed deduction: the cost is unknown, so it is not shown as ₱0.
        row.cogs == null ? 'No cost on file' : formatPeso(row.cogs!),
        row.grossProfit == null
            ? 'No cost on file'
            : formatPeso(row.grossProfit!),
      ],
  ],
  emptyMessage: 'No items sold in this range.',
  excelName: 'item-wise-sales-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildSalesByItemReportXlsx(report),
  charts: [
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-item-chart'),
        title: 'Net merchandise by item',
        subtitle: 'Best sellers first, each against its own landed cost.',
        primaryLabel: 'Net sales',
        secondaryLabel: 'COGS',
        items: [
          for (final row in report.page.rows.take(8))
            ComparisonBarItem(
              label: row.name,
              primaryValue: row.net,
              primaryText: formatPeso(row.net),
              secondaryValue: row.cogs,
              // A missing cost is words, never a ₱0.00 bar.
              secondaryText: row.cogs == null
                  ? 'No cost on file'
                  : 'COGS ${formatPeso(row.cogs!)}',
            ),
        ],
      ),
  ],
);

_ReportView _salesByHourView(SalesByHour report) => _ReportView(
  kpis: [
    (
      label: 'Transactions',
      value: formatCount(report.totalTransactions),
      caption: 'Completed sales',
    ),
    (
      label: 'Invoice total',
      value: formatPeso(report.totalInvoice),
      caption: 'After discounts and returns',
    ),
  ],
  columns: const ['Hour', 'Transactions', 'Invoice total'],
  rows: [
    for (final row in report.page.rows)
      [
        _hourLabel(row.hour),
        formatCount(row.transactions),
        formatPeso(row.invoiceTotal),
      ],
  ],
  emptyMessage: 'No sales in this range.',
  excelName: 'hourly-sales-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildSalesByHourReportXlsx(report),
);

_ReportView _salesByCashierView(SalesByCashier report) => _ReportView(
  kpis: [
    (
      label: 'Transactions',
      value: formatCount(report.totalTransactions),
      caption: 'Completed sales',
    ),
    (
      label: 'Invoice total',
      value: formatPeso(report.totalInvoice),
      caption: 'After discounts and returns',
    ),
    (
      label: 'Discounts',
      value: formatPeso(report.totalDiscounts),
      caption: null,
    ),
  ],
  columns: const [
    'Cashier',
    'Username',
    'Transactions',
    'Invoice total',
    'Discounts',
  ],
  rows: [
    for (final row in report.page.rows)
      [
        row.cashierName,
        row.username,
        formatCount(row.transactions),
        formatPeso(row.invoiceTotal),
        formatPeso(row.discounts),
      ],
  ],
  emptyMessage: 'No sales in this range.',
  excelName: 'cashier-performance-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildSalesByCashierReportXlsx(report),
  charts: [
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-cashier-chart'),
        title: 'Invoice total by cashier',
        subtitle: 'Each cashier’s takings, with the discounts they gave.',
        primaryLabel: 'Invoice total',
        secondaryLabel: 'Discounts',
        items: [
          for (final row in report.page.rows)
            ComparisonBarItem(
              label: row.cashierName,
              primaryValue: row.invoiceTotal,
              primaryText: formatPeso(row.invoiceTotal),
              secondaryValue: row.discounts,
              secondaryText: 'Discounts ${formatPeso(row.discounts)}',
            ),
        ],
      ),
  ],
);

_ReportView _billWiseView(BillWiseReport report) => _ReportView(
  kpis: [
    (
      label: 'Bills',
      value: formatCount(report.totalTransactions),
      caption: 'Completed sales',
    ),
    (
      label: 'Invoice total',
      value: formatPeso(report.totalGrand),
      caption: 'Signed: a return lowers it',
    ),
    (
      label: 'Discounts',
      value: formatPeso(report.totalDiscount),
      caption: null,
    ),
    (
      label: 'Tendered',
      value: _methodsLabel(report.totalMethods),
      caption: 'Per tender method',
    ),
  ],
  columns: const ['Bill', 'OR number', 'Date', 'Cashier', 'Tenders', 'Total'],
  rows: [
    for (final row in report.page.rows)
      [
        row.transactionNo,
        // A bill with no BIR receipt says so rather than printing a blank cell.
        row.orNumber.isEmpty ? 'No OR issued' : row.orNumber,
        _dateLabel(row.date),
        row.cashierName,
        _methodsLabel(row.methods),
        formatPeso(row.grandTotal),
      ],
  ],
  emptyMessage: 'No bills in this range.',
  excelName: 'bill-wise-sales-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildBillWiseReportXlsx(report),
  charts: [
    // No tender recorded leaves the list empty, so the viewer says there is no
    // data instead of an empty card.
    if (report.totalMethods.values.any((tendered) => tendered > 0))
      ShareSplitChart(
        key: const ValueKey('report-viewer-tender-split'),
        title: 'Payment breakdown',
        subtitle: 'How the range’s takings split across tender methods.',
        slices: [
          for (final entry in report.totalMethods.entries)
            ShareSlice(
              label: TenderMethod.labelFor(entry.key),
              value: entry.value,
              amountText: formatPeso(entry.value),
            ),
        ],
      ),
  ],
);

_ReportView _returnsExchangesView(ReturnsExchangesReport report) => _ReportView(
  kpis: [
    (label: 'Returns', value: formatCount(report.totalReturns), caption: null),
    (
      label: 'Exchanges',
      value: formatCount(report.totalExchanges),
      caption: 'No money moved',
    ),
    (
      label: 'Refunded',
      value: formatPeso(report.totalRefunded),
      caption: 'Handed back to the customer',
    ),
  ],
  columns: const ['Reversal', 'Date', 'Type', 'Original bill', 'Refunded'],
  rows: [
    for (final row in report.page.rows)
      [
        row.transactionNo,
        _dateLabel(row.date),
        row.source,
        row.originalTransactionNo.isEmpty
            ? 'No original bill'
            : row.originalTransactionNo,
        formatPeso(row.refunded),
      ],
  ],
  emptyMessage: 'No returns or exchanges in this range.',
  excelName: 'returns-exchanges-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildReturnsExchangesReportXlsx(report),
);

_ReportView _discountsView(DiscountsReport report) => _ReportView(
  kpis: [
    (
      label: 'Line discounts',
      value: formatPeso(report.totalLineDiscount),
      caption: 'Taken off one item',
    ),
    (
      label: 'Cart discounts',
      value: formatPeso(report.totalCartDiscount),
      caption: 'Taken off the whole bill',
    ),
    (
      label: 'Total discounts',
      value: formatPeso(report.totalDiscount),
      caption: 'Line + cart',
    ),
    (
      label: 'Approvals',
      value: formatCount(report.approvals),
      caption: 'Cart discounts a manager signed off',
    ),
  ],
  columns: const ['Type', 'Transactions', 'Discount', 'Approvals'],
  rows: [
    for (final row in report.page.rows)
      [
        row.type,
        formatCount(row.transactions),
        formatPeso(row.totalDiscount),
        row.approvals == null ? 'Not an approval' : formatCount(row.approvals!),
      ],
  ],
  emptyMessage: 'No discounts in this range.',
  excelName: 'discounts-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildDiscountsReportXlsx(report),
);

_ReportView _voidsView(VoidsReport report) => _ReportView(
  kpis: [
    (
      label: 'Voided bills',
      value: formatCount(report.totalTransactions),
      caption: null,
    ),
    (
      label: 'Voided total',
      value: formatPeso(report.totalVoided),
      caption: 'What the cancelled bills came to',
    ),
  ],
  columns: const ['Bill', 'Date', 'Cashier', 'Amount', 'Reason'],
  rows: [
    for (final row in report.page.rows)
      [
        row.transactionNo,
        _dateLabel(row.date),
        row.cashierName,
        formatPeso(row.voidedTotal),
        _reasonLabel(row.reason),
      ],
  ],
  emptyMessage: 'No voided bills in this range.',
  excelName: 'voids-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildVoidsReportXlsx(report),
);

// --- P2 inventory reports --------------------------------------------------
// Every one of them formats a missing peso value as words: an inventory figure
// with no batch history has no cost, and ₱0.00 would be a claim nobody made.

_ReportView _grnView(GrnReport report) => _ReportView(
  kpis: [
    (
      label: 'Receipts',
      value: formatCount(report.receipts),
      caption: 'Deliveries in this range',
    ),
    (
      label: 'Quantity received',
      value: formatQuantity(report.qty),
      caption: 'Base units',
    ),
    (
      label: 'Billed',
      value: formatCount(report.billed),
      caption: 'Supplier bill raised',
    ),
    (
      label: 'Unbilled',
      value: formatCount(report.unbilled),
      caption: 'No bill yet',
    ),
  ],
  columns: const ['Receipt', 'Date', 'Supplier', 'Items', 'Units', 'Bill'],
  rows: [
    for (final row in report.page.rows)
      [
        row.deliveryReceiptNo.isEmpty
            ? 'No receipt number'
            : row.deliveryReceiptNo,
        _dateLabel(row.date),
        row.supplier,
        formatCount(row.items),
        formatQuantity(row.qty),
        // A receipt nobody billed has no peso value, so it says that instead of
        // printing ₱0.00.
        row.billTotal == null ? 'Not billed' : formatPeso(row.billTotal!),
      ],
  ],
  emptyMessage: 'No goods received in this range.',
  excelName: 'goods-received-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildGrnReportXlsx(report),
);

_ReportView _stnView(StnReport report) => _ReportView(
  kpis: [
    (
      label: 'Transfers',
      value: formatCount(report.transfers),
      caption: 'Slips in this range',
    ),
    (
      label: 'Units moved',
      value: formatQuantity(report.qty),
      caption: 'Base units',
    ),
  ],
  columns: const ['Transfer', 'Date', 'From', 'To', 'Lines', 'Units'],
  rows: [
    for (final row in report.page.rows)
      [
        row.number,
        _dateLabel(row.date),
        row.fromLocationName,
        row.toLocationName,
        formatCount(row.lines),
        formatQuantity(row.qty),
      ],
  ],
  emptyMessage: 'No stock transfers in this range.',
  excelName: 'stock-transfers-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildStnReportXlsx(report),
);

_ReportView _batchAgeView(BatchAgeReport report) => _ReportView(
  kpis: [
    (
      label: 'Variants on hand',
      value: formatCount(report.variants),
      caption: 'As of ${_dateLabel(report.asOf)}',
    ),
    (
      label: '0-30 days',
      value: formatQuantity(report.qty0to30),
      caption: 'Fresh stock',
    ),
    (
      label: '31-90 days',
      value: formatQuantity(report.qty30to90),
      caption: 'Sitting a while',
    ),
    (
      label: '90+ days',
      value: formatQuantity(report.qty90plus),
      caption: 'Oldest stock first',
    ),
  ],
  columns: const [
    'Item',
    'Oldest batch',
    '0-30 days',
    '31-90 days',
    '90+ days',
    'On hand',
  ],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        '${formatCount(row.oldestAgeDays)} days',
        formatQuantity(row.qty0to30),
        formatQuantity(row.qty30to90),
        formatQuantity(row.qty90plus),
        formatQuantity(row.totalQty),
      ],
  ],
  emptyMessage: 'No stock on hand.',
  excelName: 'batch-age-${report.asOf}.xlsx',
  excelBytes: () => buildBatchAgeReportXlsx(report),
);

_ReportView _shrinkageView(ShrinkageReport report) => _ReportView(
  kpis: [
    (
      label: 'Quantity lost',
      value: formatQuantity(report.qty),
      caption: 'Shrinkage and damage',
    ),
    (
      label: 'Value lost',
      value: _costOrUnknown(report.totalValue),
      caption: 'At landed cost',
    ),
    (
      label: 'Shrinkage',
      value: _percentOrUnknown(report.shrinkagePercent, 'No stock to measure'),
      caption: 'Loss ÷ stock available',
    ),
    if (report.missingCostLines > 0)
      (
        label: 'Losses with no cost',
        value: formatCount(report.missingCostLines),
        caption: 'Left out of the value',
      ),
  ],
  columns: const ['Day', 'Quantity lost', 'Value lost', 'Adjustments'],
  rows: [
    for (final row in report.page.rows)
      [
        _dateLabel(row.date),
        formatQuantity(row.qty),
        _costOrUnknown(row.value),
        formatCount(row.adjustments),
      ],
  ],
  emptyMessage: 'No shrinkage or damage in this range.',
  excelName: 'shrinkage-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildShrinkageReportXlsx(report),
);

_ReportView _adjustmentsView(AdjustmentsReport report) => _ReportView(
  kpis: [
    (
      label: 'Adjustments',
      value: formatCount(report.adjustments),
      caption: 'Corrections and returns',
    ),
    (
      label: 'Quantity',
      value: formatSignedQuantity(report.qty),
      caption: 'Signed: a return lowers',
    ),
    (
      label: 'Value',
      value: _costOrUnknown(report.totalValue),
      caption: 'At landed cost',
    ),
    if (report.missingCostLines > 0)
      (
        label: 'Rows with no cost',
        value: formatCount(report.missingCostLines),
        caption: 'Left out of the value',
      ),
  ],
  columns: const [
    'Item',
    'Date',
    'Type',
    'Shelf',
    'Recorded by',
    'Quantity',
    'Value',
  ],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        _dateLabel(row.date),
        row.type,
        row.locationName,
        row.userName,
        formatSignedQuantity(row.qty),
        _costOrUnknown(row.value),
      ],
  ],
  emptyMessage: 'No stock adjustments in this range.',
  excelName: 'stock-adjustments-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildAdjustmentsReportXlsx(report),
);

_ReportView _reorderView(ReorderReport report) => _ReportView(
  kpis: [
    (
      label: 'To reorder',
      value: formatCount(report.variants),
      caption: 'At or below minimum stock',
    ),
    (
      label: 'On hand',
      value: formatQuantity(report.onHand),
      caption: 'Base units',
    ),
    (
      label: 'Shortfall',
      value: formatQuantity(report.gap),
      caption: 'What has to be bought',
    ),
  ],
  columns: const ['Item', 'On hand', 'Minimum', 'Shortfall', 'Shelves'],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        formatQuantity(row.onHand),
        formatQuantity(row.threshold),
        formatQuantity(row.gap),
        _shelfLabel(row.locations),
      ],
  ],
  emptyMessage: 'Nothing is at or below its minimum stock.',
  excelName: 'reorder-list.xlsx',
  excelBytes: () => buildReorderReportXlsx(report),
);

_ReportView _deadStockView(DeadStockReport report) => _ReportView(
  kpis: [
    (
      label: 'Variants with no sales',
      value: formatCount(report.variants),
      caption: 'In the last ${formatCount(report.days)} days',
    ),
    (
      label: 'Money tied up',
      value: formatPeso(report.landedValue),
      caption: 'At landed cost',
    ),
    (
      label: 'On hand',
      value: formatQuantity(report.onHand),
      caption: 'Base units',
    ),
  ],
  columns: const ['Item', 'On hand', 'Idle for', 'Money tied up'],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        formatQuantity(row.onHand),
        // Never sold is not the same fact as sold a long time ago.
        row.daysSinceLastSale == null
            ? 'Never sold'
            : '${formatCount(row.daysSinceLastSale!)} days',
        formatPeso(row.landedValue),
      ],
  ],
  emptyMessage: 'Every stocked item sold in this window.',
  excelName: 'dead-stock-${report.asOf}.xlsx',
  excelBytes: () => buildDeadStockReportXlsx(report),
);

_ReportView _fastSlowView(FastSlowReport report) => _ReportView(
  kpis: [
    (
      label: 'SKUs sold',
      value: formatCount(report.skusSold),
      caption: 'Ranked by base units',
    ),
    (label: 'Fast movers', value: formatCount(report.fast), caption: 'Top 20%'),
    (
      label: 'Slow movers',
      value: formatCount(report.slow),
      caption: 'Bottom 20% that still sold',
    ),
    (
      label: 'Units sold',
      value: formatQuantity(report.qtyBase),
      caption: 'Base units',
    ),
  ],
  columns: const ['Item', 'Band', 'Units sold', 'Net merchandise'],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        row.band,
        formatQuantity(row.qtyBase),
        formatPeso(row.netMerchandise),
      ],
  ],
  emptyMessage: 'No items sold in this range.',
  excelName: 'fast-slow-movers-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildFastSlowReportXlsx(report),
);

_ReportView _cycleCountView(CycleCountReport report) => _ReportView(
  kpis: [
    (
      label: 'Count corrections',
      value: formatCount(report.adjustments),
      caption: null,
    ),
    (
      label: 'Net variance',
      value: formatSignedQuantity(report.qty),
      caption: 'Signed: a shortfall lowers',
    ),
    (
      label: 'Shrinkage',
      value: _percentOrUnknown(report.shrinkagePercent, 'No stock to measure'),
      caption: 'Shortfall ÷ counted stock',
    ),
    (
      label: 'Value of variance',
      value: _costOrUnknown(report.totalValue),
      caption: 'At landed cost',
    ),
    if (report.missingCostLines > 0)
      (
        label: 'Rows with no cost',
        value: formatCount(report.missingCostLines),
        caption: 'Left out of the value',
      ),
  ],
  columns: const ['Item', 'Date', 'Shelf', 'Counted by', 'Variance', 'Value'],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        _dateLabel(row.date),
        row.locationName,
        row.userName,
        formatSignedQuantity(row.qty),
        _costOrUnknown(row.value),
      ],
  ],
  // A count that matched left no record: the server writes a CORRECTION only
  // when the shelf disagreed with the count.
  emptyMessage: 'No count corrections in this range.',
  excelName: 'cycle-count-${report.from}-to-${report.to}.xlsx',
  excelBytes: () => buildCycleCountReportXlsx(report),
);

_ReportView _expiryView(ExpiryReport report) => _ReportView(
  kpis: [
    (
      label: 'Batches expiring',
      value: formatCount(report.rowCount),
      caption: 'Expired or within 90 days',
    ),
    (
      label: 'Value at risk',
      value: formatPeso(report.value),
      caption: 'Already expired or expiring',
    ),
    (
      label: 'Near-expiry',
      value: _percentOrUnknown(report.nearExpiryPct, 'No stock on hand'),
      caption: 'In the next ${formatCount(report.days)} days',
    ),
    (
      label: 'Already expired',
      value: formatPeso(report.valueExpired),
      caption: 'Past its date on the shelf',
    ),
  ],
  columns: const ['Item', 'Shelf', 'Expires', 'Time left', 'Quantity', 'Value'],
  rows: [
    for (final row in report.page.rows)
      [
        row.name,
        row.location,
        _dateLabel(row.expiresOn),
        _expiryLabel(row.daysLeft),
        formatQuantity(row.qty),
        formatPeso(row.value),
      ],
  ],
  emptyMessage: 'Nothing is expired or expiring.',
  excelName: 'expiry-${report.asOf}.xlsx',
  excelBytes: () => buildExpiryReportXlsx(report),
);

/// A peso value the server could not cost: words, never ₱0.00.
String _costOrUnknown(double? value) =>
    value == null ? 'No cost on file' : formatPeso(value);

/// A percentage the server could not compute, said in the reason's own words
/// instead of a fake 0%.
String _percentOrUnknown(double? value, String reason) =>
    value == null ? reason : '${value.toStringAsFixed(1)}%';

/// The shelves holding what is left of a variant: `Store Floor 2 · Warehouse 1`.
String _shelfLabel(List<ReorderShelf> shelves) => shelves.isEmpty
    ? 'None on any shelf'
    : [
        for (final shelf in shelves)
          '${shelf.locationName} ${formatQuantity(shelf.qty)}',
      ].join(' · ');

/// How long a batch has left: `12 days left`, or `Expired 5 days ago`.
String _expiryLabel(int daysLeft) => daysLeft < 0
    ? 'Expired ${formatCount(-daysLeft)} days ago'
    : '${formatCount(daysLeft)} days left';

/// A store-local hour as a clock label: `14` becomes `2:00 PM`.
String _hourLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:00 ${hour < 12 ? 'AM' : 'PM'}';
}

/// The tenders of one bill or a whole range: `Cash ₱1,400.00 · GCash ₱100.00`.
String _methodsLabel(Map<String, double> methods) => methods.isEmpty
    ? 'No tender recorded'
    : [
        for (final entry in methods.entries)
          '${TenderMethod.labelFor(entry.key)} ${formatPeso(entry.value)}',
      ].join(' · ');

/// The reason on file, or the plain fact that nobody wrote one.
String _reasonLabel(String? reason) {
  final text = reason?.trim() ?? '';
  return text.isEmpty ? 'No reason recorded' : text;
}

/// A server date (`2026-10-29`) as `Oct 29, 2026`. An unparsable value keeps the
/// server's own word instead of showing a date nobody recorded.
String _dateLabel(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : formatDate(date);
}

/// The one shape the server's `from`/`to` query takes.
String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
