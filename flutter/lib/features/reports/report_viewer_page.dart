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
import 'package:client/shared/widgets/stitch_ui.dart';
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

enum _VatStreamFilter { consolidated, orOnly, osOnly }

class _ReportViewerViewState extends State<ReportViewerView> {
  late final ReportsRepository _repository =
      widget.repository ?? ReportsRepository();

  late DateTimeRange _range = widget.initialRange ?? _lastThirtyDays();
  final _searchController = TextEditingController();
  String _tableQuery = '';

  /// VAT Ledger interactive stream filter and period granularity.
  _VatStreamFilter _vatStream = _VatStreamFilter.consolidated;
  String _vatGranularity = 'day';
  VatReportSummary? _vatReport;

  /// The loaded report, already shaped for the tiles and the table.
  _ReportView? _view;
  String? _error;
  bool _loading = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyPreset(DateTimeRange next) {
    setState(() => _range = next);
    _load();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesRange(DateTimeRange target) =>
      _sameDay(_range.start, target.start) && _sameDay(_range.end, target.end);

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
          final vatSummary = await _repository.fetchVatSummary(
            from: from,
            to: to,
            granularity: _vatGranularity,
          );
          _vatReport = vatSummary;
          view = _vatView(vatSummary, stream: _vatStream);
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
    final now = appClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayRange = DateTimeRange(start: today, end: today);
    final weekRange = DateTimeRange(
      start: today.subtract(Duration(days: today.weekday - 1)),
      end: today,
    );
    final monthRange = DateTimeRange(
      start: DateTime(today.year, today.month, 1),
      end: today,
    );
    final thirtyRange = _lastThirtyDays();
    final query = _tableQuery.trim().toLowerCase();
    final filteredRows = view == null
        ? const <List<String>>[]
        : (query.isEmpty
              ? view.rows
              : view.rows
                    .where(
                      (row) =>
                          row.any((cell) => cell.toLowerCase().contains(query)),
                    )
                    .toList());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.report.id != 'vat-summary') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: StitchColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: StitchColors.cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: StitchColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.report.section == ReportSection.inventory
                        ? Icons.inventory_2_outlined
                        : Icons.analytics_outlined,
                    size: 20,
                    color: StitchColors.primaryDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            widget.report.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: StitchColors.ink,
                            ),
                          ),
                          StitchPill(
                            label: widget.report.section ==
                                    ReportSection.inventory
                                ? 'Inventory report'
                                : 'Sales report',
                            tone: StitchTone.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.report.description,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: StitchColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: StitchColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StitchColors.cardBorder),
          ),
          child: Wrap(
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
              ChoiceChip(
                key: const ValueKey('report-preset-today'),
                label: const Text('Today'),
                selected: _matchesRange(todayRange),
                onSelected: (_) => _applyPreset(todayRange),
              ),
              ChoiceChip(
                key: const ValueKey('report-preset-week'),
                label: const Text('This Week'),
                selected: _matchesRange(weekRange),
                onSelected: (_) => _applyPreset(weekRange),
              ),
              ChoiceChip(
                key: const ValueKey('report-preset-month'),
                label: const Text('This Month'),
                selected: _matchesRange(monthRange),
                onSelected: (_) => _applyPreset(monthRange),
              ),
              ChoiceChip(
                key: const ValueKey('report-preset-30d'),
                label: const Text('Last 30 Days'),
                selected: _matchesRange(thirtyRange),
                onSelected: (_) => _applyPreset(thirtyRange),
              ),
              OutlinedButton.icon(
                key: const ValueKey('report-viewer-range'),
                onPressed: _pickRange,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  '${formatDate(_range.start)} to ${formatDate(_range.end)}',
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('report-viewer-refresh'),
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
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
          if (widget.report.id == 'vat-summary' && _vatReport != null) ...[
            _VatLedgerHeroSection(
              report: _vatReport!,
              stream: _vatStream,
              granularity: _vatGranularity,
              onStreamChanged: (next) {
                setState(() {
                  _vatStream = next;
                  _view = _vatView(_vatReport!, stream: next);
                });
              },
              onGranularityChanged: (next) {
                if (next == _vatGranularity) return;
                setState(() => _vatGranularity = next);
                _load();
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (view.kpis.isNotEmpty) ...[
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
          if (view.rows.isNotEmpty) ...[
            SizedBox(
              width: 340,
              child: TextField(
                key: const ValueKey('report-viewer-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _tableQuery = value),
                decoration: InputDecoration(
                  hintText: 'Filter rows…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  suffixIcon: _tableQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear filter',
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _tableQuery = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          DataPanel<List<String>>(
            key: const ValueKey('report-viewer-table'),
            showPageSizePicker: true,
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
            rows: filteredRows,
            emptyMessage: query.isNotEmpty
                ? 'No rows match "$_tableQuery".'
                : view.emptyMessage,
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
      if (sales.merchandiseGross != null) ProfitBreakdownCard(sales: sales),
      // The trend is an area, and the dashed line over it is the landed cost
      // behind those same days: a fill for the money made, a comparison for
      // what it cost. The model carries no previous period, so nothing here
      // pretends to compare against one.
      if (sales.days.isNotEmpty)
        AreaTrendChart(
          key: const ValueKey('report-viewer-sales-trend'),
          title: 'Daily sales & the cost behind them',
          subtitle: sales.days.any((day) => day.cogs != null)
              ? 'The area is daily net sales (ex-VAT); the dashed line is the landed cost of what sold.'
              : 'Daily invoice total across the reported dates.',
          valueLabel: sales.days.any((d) => d.merchandiseNetExVat != null)
              ? 'Net sales (ex-VAT)'
              : 'Invoice total',
          previousLabel: sales.days.any((day) => day.cogs != null)
              ? 'Landed COGS'
              : null,
          height: 190,
          points: [
            for (final day in sales.days)
              TrendPoint(
                label: day.day.length >= 10 ? day.day.substring(5) : day.day,
                primary: day.merchandiseNetExVat ?? day.gross,
                previous: day.cogs,
              ),
          ],
        ),
      // Categories are parts of one total of net sales, so they read as a ring
      // rather than as bars: the money each one brought in, and its share.
      if (sales.categories.any((category) => category.netMerchandise > 0))
        DonutChart(
          key: const ValueKey('report-viewer-category-chart'),
          title: 'Net sales by category',
          subtitle:
              'How the range’s net merchandise divides across categories.',
          centerLabel: 'Net sales',
          centerValue: formatPeso(
            sales.categories.fold<double>(
              0,
              (sum, category) => sum + category.netMerchandise,
            ),
          ),
          slices: [
            for (final category in sales.categories.take(6))
              ShareSlice(
                label: category.categoryName,
                value: category.netMerchandise,
                amountText: formatPeso(category.netMerchandise),
              ),
          ],
        ),
    ],
  );
}

class _VatLedgerHeroSection extends StatelessWidget {
  const _VatLedgerHeroSection({
    required this.report,
    required this.stream,
    required this.granularity,
    required this.onStreamChanged,
    required this.onGranularityChanged,
  });

  final VatReportSummary report;
  final _VatStreamFilter stream;
  final String granularity;
  final ValueChanged<_VatStreamFilter> onStreamChanged;
  final ValueChanged<String> onGranularityChanged;

  @override
  Widget build(BuildContext context) {
    final totals = report.totals;
    final totalGross = totals.combined.grossSales;
    final orShare = totalGross > 0
        ? (totals.orBacked.grossSales / totalGross * 100)
        : 0.0;
    final osShare = totalGross > 0
        ? (totals.untaggedOs.grossSales / totalGross * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StitchSectionCard(
          key: const ValueKey('report-viewer-vat-hero'),
          icon: Icons.account_balance_outlined,
          overline: 'DUAL-STREAM TAX LEDGER',
          title: 'Official Receipt (OR) & Untagged Order Slip VAT Ledger',
          subtitle:
              'Real-time segregation of 12% Output VAT on OR-tagged invoices vs. internal untagged order slips.',
          trailing: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StitchSegmentedBar<_VatStreamFilter>(
                selected: stream,
                onSelected: onStreamChanged,
                items: const [
                  (
                    value: _VatStreamFilter.consolidated,
                    label: 'Consolidated (OR + OS)',
                    key: ValueKey('vat-stream-consolidated'),
                  ),
                  (
                    value: _VatStreamFilter.orOnly,
                    label: 'Official Receipt (OR) Only',
                    key: ValueKey('vat-stream-or-only'),
                  ),
                  (
                    value: _VatStreamFilter.osOnly,
                    label: 'Untagged Order Slips (OS) Only',
                    key: ValueKey('vat-stream-os-only'),
                  ),
                ],
              ),
              StitchSegmentedBar<String>(
                selected: granularity,
                onSelected: onGranularityChanged,
                items: const [
                  (value: 'day', label: 'Daily', key: ValueKey('vat-gran-day')),
                  (
                    value: 'week',
                    label: 'Weekly',
                    key: ValueKey('vat-gran-week'),
                  ),
                  (
                    value: 'month',
                    label: 'Monthly',
                    key: ValueKey('vat-gran-month'),
                  ),
                ],
              ),
            ],
          ),
          child: MetricGrid(
            minTileWidth: 230,
            children: [
              StitchKpiCard(
                label: 'Total Invoiced (All Streams)',
                value: formatPeso(totals.combined.grossSales),
                icon: Icons.payments_outlined,
                tone: StitchTone.primary,
                subtitle:
                    'Whole VAT ${formatPeso(totals.combined.vat)} · ${formatCount(totals.combined.transactions)} slips',
                pillLabel: 'Consolidated',
                pillTone: StitchTone.primary,
              ),
              StitchKpiCard(
                label: 'Official Receipt (OR) Sales',
                value: formatPeso(totals.orBacked.grossSales),
                icon: Icons.verified_outlined,
                tone: StitchTone.primary,
                subtitle:
                    '${formatCount(totals.orBacked.transactions)} OR invoices · ${orShare.toStringAsFixed(0)}% share',
                pillLabel: 'OR-Tagged',
                pillTone: StitchTone.primary,
              ),
              StitchKpiCard(
                label: '12% Output VAT (OR-Tagged)',
                value: formatPeso(totals.orBacked.vat),
                icon: Icons.account_balance_wallet_outlined,
                tone: StitchTone.success,
                valueColor: StitchColors.primaryDeep,
                subtitle:
                    'Vatable base ${formatPeso(totals.orBacked.vatableSales)}',
                pillLabel: 'OR-tagged VAT',
                pillTone: StitchTone.success,
              ),
              StitchKpiCard(
                label: 'Order Slip (OS) Internal',
                value: formatPeso(totals.untaggedOs.grossSales),
                icon: Icons.description_outlined,
                tone: StitchTone.neutral,
                subtitle:
                    'Untagged VAT ${formatPeso(totals.untaggedOs.vat)} · ${osShare.toStringAsFixed(0)}% share',
                pillLabel:
                    '${formatCount(totals.untaggedOs.transactions)} Order Slips',
                pillTone: StitchTone.neutral,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

_ReportView _vatView(
  VatReportSummary report, {
  _VatStreamFilter stream = _VatStreamFilter.consolidated,
}) {
  final columns = switch (stream) {
    _VatStreamFilter.consolidated => const [
      'Period',
      'OR Slips',
      'OR Sales',
      'OR VAT',
      'OS Slips',
      'OS Sales',
      'Untagged VAT',
      'Whole VAT',
    ],
    _VatStreamFilter.orOnly => const [
      'Period',
      'OR Slips',
      'OR Gross Sales',
      'Vatable Base',
      '12% Output VAT',
    ],
    _VatStreamFilter.osOnly => const [
      'Period',
      'OS Slips',
      'OS Gross Sales',
      'Vatable Base',
      'Untagged VAT',
    ],
  };

  final rows = <List<String>>[
    for (final period in report.periods)
      switch (stream) {
        _VatStreamFilter.consolidated => [
          _dateLabel(period.period),
          formatCount(period.orBackedTransactions),
          formatPeso(period.orBackedSales),
          formatPeso(period.orBackedVat),
          formatCount(period.untaggedTransactions),
          formatPeso(period.untaggedSales),
          formatPeso(period.untaggedVat),
          formatPeso(period.vat),
        ],
        _VatStreamFilter.orOnly => [
          _dateLabel(period.period),
          formatCount(period.orBackedTransactions),
          formatPeso(period.orBackedSales),
          formatPeso(period.orBackedVatable),
          formatPeso(period.orBackedVat),
        ],
        _VatStreamFilter.osOnly => [
          _dateLabel(period.period),
          formatCount(period.untaggedTransactions),
          formatPeso(period.untaggedSales),
          formatPeso(period.untaggedVatable),
          formatPeso(period.untaggedVat),
        ],
      },
    if (report.periods.isNotEmpty)
      switch (stream) {
        _VatStreamFilter.consolidated => [
          'Total',
          formatCount(report.totals.orBacked.transactions),
          formatPeso(report.totals.orBacked.grossSales),
          formatPeso(report.totals.orBacked.vat),
          formatCount(report.totals.untaggedOs.transactions),
          formatPeso(report.totals.untaggedOs.grossSales),
          formatPeso(report.totals.untaggedOs.vat),
          formatPeso(report.totals.combined.vat),
        ],
        _VatStreamFilter.orOnly => [
          'Total',
          formatCount(report.totals.orBacked.transactions),
          formatPeso(report.totals.orBacked.grossSales),
          formatPeso(report.totals.orBacked.vatableSales),
          formatPeso(report.totals.orBacked.vat),
        ],
        _VatStreamFilter.osOnly => [
          'Total',
          formatCount(report.totals.untaggedOs.transactions),
          formatPeso(report.totals.untaggedOs.grossSales),
          formatPeso(report.totals.untaggedOs.vatableSales),
          formatPeso(report.totals.untaggedOs.vat),
        ],
      },
  ];

  final hasVatData =
      report.totals.orBacked.vat > 0 || report.totals.untaggedOs.vat > 0;
  final periodLabel = '${_dateLabel(report.from)} to ${_dateLabel(report.to)}';
  final pdfKpis = <_Kpi>[
    (
      label: 'Whole VAT',
      value: formatPeso(report.totals.combined.vat),
      caption: 'Every completed sale',
    ),
    (
      label: 'OR-tagged VAT',
      value: formatPeso(report.totals.orBacked.vat),
      caption: 'Slips carrying an Official Receipt (OR)',
    ),
    (
      label: 'Untagged VAT',
      value: formatPeso(report.totals.untaggedOs.vat),
      caption: 'Order slips without an OR',
    ),
  ];

  return _ReportView(
    kpis: pdfKpis,
    columns: columns,
    rows: rows,
    emptyMessage: 'No sales recorded in this period.',
    excelName:
        'vat-or-report-${report.granularity}-${report.from}-to-${report.to}.xlsx',
    excelBytes: () => buildVatReportXlsx(report),
    pdfName:
        'vat-or-ledger-${report.granularity}-${report.from}-to-${report.to}.pdf',
    pdfBytes: (generatedBy) => renderReportPdf(
      title: 'Official Receipt (OR) & Order Slip VAT Ledger',
      period: periodLabel,
      generatedBy: generatedBy,
      storeName: StoreInformationPanel.storeName,
      kpis: pdfKpis,
      columns: columns,
      rows: rows,
    ),
    charts: [
      if (hasVatData && report.periods.isNotEmpty)
        GroupedBarTrendChart(
          key: const ValueKey('report-viewer-vat-trend'),
          title: 'OR-Tagged vs. Untagged Order Slip VAT by Period',
          subtitle:
              'Compares 12% Output VAT from Official Receipts (OR) against untagged internal order slips.',
          primaryLabel: 'OR-tagged VAT',
          primaryColor: StitchColors.primaryDeep,
          secondaryLabel: 'Untagged VAT',
          secondaryColor: const Color(0xFF93C5FD),
          height: 200,
          points: [
            for (final p in report.periods)
              TrendPoint(
                label: p.period.length >= 10 ? p.period.substring(5) : p.period,
                primary: p.orBackedVat,
                secondary: p.untaggedVat,
              ),
          ],
        ),
      if (hasVatData)
        ShareSplitChart(
          key: const ValueKey('report-viewer-vat-split'),
          title: 'Whole VAT vs OR-tagged',
          subtitle:
              'How the period’s VAT divides between OR-tagged slips and untagged order slips.',
          slices: [
            ShareSlice(
              label: 'OR-tagged VAT',
              value: report.totals.orBacked.vat,
              amountText: formatPeso(report.totals.orBacked.vat),
            ),
            ShareSlice(
              label: 'Untagged VAT',
              value: report.totals.untaggedOs.vat,
              amountText: formatPeso(report.totals.untaggedOs.vat),
            ),
          ],
        ),
    ],
  );
}

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
  charts: [
    if (valuation.categories.isNotEmpty)
      ShareSplitChart(
        key: const ValueKey('report-viewer-valuation-category-split'),
        title: 'Stock value by category',
        subtitle: 'Value at landed cost, split across the categories on hand.',
        slices: [
          for (final category in valuation.categories)
            ShareSlice(
              label: category.name,
              value: category.cost,
              amountText: formatPeso(category.cost),
            ),
        ],
      ),
    if (valuation.locations.isNotEmpty)
      ShareSplitChart(
        key: const ValueKey('report-viewer-valuation-location-split'),
        title: 'Stock value by location',
        subtitle: 'The same value at landed cost, split by where it sits.',
        slices: [
          for (final location in valuation.locations)
            ShareSlice(
              label: location.locationName,
              value: location.cost,
              amountText: formatPeso(location.cost),
            ),
        ],
      ),
  ],
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
  charts: [
    if (movements.receiptsByDay.isNotEmpty)
      GroupedBarTrendChart(
        key: const ValueKey('report-viewer-movements-chart'),
        title: 'Goods received by day',
        subtitle: 'Base units that came in, day by day.',
        primaryLabel: 'Units in',
        isCurrency: false,
        height: 180,
        points: _perDayPoints(
          movements.receiptsByDay,
          date: (day) => day.date,
          value: (day) => day.qtyIn,
        ),
      ),
    // The endpoint reports adjustments by reason, not by day: the daily axis
    // above covers receipts, and this covers what was written off.
    if (movements.adjustmentsByType.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-movement-types-chart'),
        title: 'Adjustments by reason',
        subtitle: 'Units written off or corrected, biggest reason first.',
        primaryLabel: 'Units out',
        items: [
          for (final type in movements.adjustmentsByType)
            ComparisonBarItem(
              label: type.type,
              primaryValue: type.qtyOut,
              primaryText: formatQuantity(type.qtyOut),
              badgeText: '${formatCount(type.movements)} movements',
            ),
        ],
      ),
  ],
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
  charts: [
    if (history.countByStatus.isNotEmpty)
      ShareSplitChart(
        key: const ValueKey('report-viewer-requisition-split'),
        title: 'Requisitions by status',
        subtitle: 'Where the range’s requests stand right now.',
        slices: [
          for (final entry in history.countByStatus.entries)
            ShareSlice(
              label: entry.key,
              value: entry.value.toDouble(),
              amountText: '${formatCount(entry.value)} requests',
            ),
        ],
      ),
  ],
);

_ReportView _salesByItemView(SalesByItemReport report) {
  // A column is one item's net sales split into what the goods cost and what
  // they earned. A loss has no profit segment to stack above its cost, so only
  // items sold above landed cost are stacked; the rest stay in the table.
  final stackable = [
    for (final row in report.page.rows)
      if (row.cogs != null && (row.grossProfit ?? row.net - row.cogs!) > 0) row,
  ].take(8).toList();
  return _ReportView(
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
      if (stackable.isNotEmpty)
        StackedColumnChart(
          key: const ValueKey('report-viewer-item-chart'),
          title: 'Net sales by item',
          subtitle:
              'Each column is an item’s net sales: landed cost at the bottom, the profit it earned on top.',
          valueLabel: 'Net sales',
          height: 190,
          series: const [
            StackedSeries(label: 'Landed COGS', color: AppColors.secondary),
            StackedSeries(label: 'Gross profit', color: AppColors.primary),
          ],
          points: [
            for (final row in stackable)
              StackedColumnPoint(
                label: row.name,
                values: [row.cogs!, row.grossProfit ?? row.net - row.cogs!],
              ),
          ],
        )
      // Nothing in the range carried a cost, so there is no split to stack: the
      // items still have net sales to compare, and keep the plain bars.
      else if (report.page.rows.isNotEmpty)
        HorizontalComparisonChart(
          key: const ValueKey('report-viewer-item-chart'),
          title: 'Net merchandise by item',
          subtitle: 'Best sellers first. No item in this range carried a cost.',
          primaryLabel: 'Net sales',
          items: [
            for (final row in report.page.rows.take(8))
              ComparisonBarItem(
                label: row.name,
                primaryValue: row.net,
                primaryText: formatPeso(row.net),
              ),
          ],
        ),
    ],
  );
}

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
  charts: [
    if (report.page.rows.isNotEmpty)
      TimeOfDayChart(
        key: const ValueKey('report-viewer-hourly-chart'),
        title: 'Sales by hour of day',
        subtitle:
            'Peak shopping hours: invoice total at each store-local hour.',
        valueLabel: 'Invoice total',
        height: 190,
        byHour: {
          for (final row in report.page.rows) row.hour: row.invoiceTotal,
        },
      ),
  ],
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
      DonutChart(
        key: const ValueKey('report-viewer-tender-split'),
        title: 'Payment breakdown',
        subtitle: 'How the range’s takings split across tender methods.',
        centerLabel: 'Tendered',
        centerValue: formatPeso(
          report.totalMethods.values.fold<double>(
            0,
            (sum, tendered) => sum + tendered,
          ),
        ),
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
  charts: [
    // A return hands money back and an exchange swaps goods: the split is by
    // reversals, and the refunded pesos ride along in the legend.
    if (report.totalReturns + report.totalExchanges > 0)
      ShareSplitChart(
        key: const ValueKey('report-viewer-returns-split'),
        title: 'Refunds vs exchanges',
        subtitle: 'Reversals in this range, and the money each kind moved.',
        slices: [
          ShareSlice(
            label: 'Returns (money back)',
            value: report.totalReturns.toDouble(),
            amountText:
                '${formatCount(report.totalReturns)} · ${formatPeso(report.totalRefunded)}',
          ),
          ShareSlice(
            label: 'Exchanges (swap)',
            value: report.totalExchanges.toDouble(),
            amountText: '${formatCount(report.totalExchanges)} reversals',
          ),
        ],
      ),
  ],
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
  charts: [
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-discounts-chart'),
        title: 'Discounts by type',
        subtitle: 'Where the money came off, and on how many bills.',
        primaryLabel: 'Discount given',
        items: [
          for (final row in report.page.rows)
            ComparisonBarItem(
              label: row.type,
              primaryValue: row.totalDiscount,
              primaryText: formatPeso(row.totalDiscount),
              badgeText: '${formatCount(row.transactions)} bills',
            ),
        ],
      ),
  ],
);

_ReportView _voidsView(VoidsReport report) {
  final byReason = _totalsByLabel(
    report.page.rows,
    label: (row) => _reasonLabel(row.reason),
    amount: (row) => row.voidedTotal,
  );
  final reasons = byReason.entries.toList()
    ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
  return _ReportView(
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
    charts: [
      if (reasons.isNotEmpty)
        HorizontalComparisonChart(
          key: const ValueKey('report-viewer-voids-chart'),
          title: 'Voided value by reason',
          subtitle: 'Biggest reason first. A blank note is its own reason.',
          primaryLabel: 'Voided value',
          items: [
            for (final reason in reasons)
              ComparisonBarItem(
                label: reason.key,
                primaryValue: reason.value.amount,
                primaryText: formatPeso(reason.value.amount),
                badgeText: '${formatCount(reason.value.count)} bills',
              ),
          ],
        ),
    ],
  );
}

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
  charts: [
    // A receipt carries its own date, so the page's rows make a real time axis:
    // units that came in each delivery day.
    if (report.page.rows.isNotEmpty)
      GroupedBarTrendChart(
        key: const ValueKey('report-viewer-grn-chart'),
        title: 'Units received by day',
        subtitle: 'Base units that came through the door, day by day.',
        primaryLabel: 'Units received',
        isCurrency: false,
        height: 180,
        points: _perDayPoints(
          report.page.rows,
          date: (row) => row.date,
          value: (row) => row.qty,
        ),
      ),
  ],
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
  charts: [
    if (report.page.rows.isNotEmpty)
      GroupedBarTrendChart(
        key: const ValueKey('report-viewer-stn-chart'),
        title: 'Units moved by day',
        subtitle: 'Base units transferred between shelves, day by day.',
        primaryLabel: 'Units moved',
        isCurrency: false,
        height: 180,
        points: _perDayPoints(
          report.page.rows,
          date: (row) => row.date,
          value: (row) => row.qty,
        ),
      ),
  ],
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
  charts: [
    // FIFO buckets are already totals on the report: three bars, no arithmetic.
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-batch-age-chart'),
        title: 'On-hand stock by age',
        subtitle: 'Base units, by how long the batch behind them has sat.',
        primaryLabel: 'Units on hand',
        items: [
          ComparisonBarItem(
            label: '0-30 days',
            primaryValue: report.qty0to30,
            primaryText: formatQuantity(report.qty0to30),
          ),
          ComparisonBarItem(
            label: '31-90 days',
            primaryValue: report.qty30to90,
            primaryText: formatQuantity(report.qty30to90),
          ),
          ComparisonBarItem(
            label: '90+ days',
            primaryValue: report.qty90plus,
            primaryText: formatQuantity(report.qty90plus),
          ),
        ],
      ),
  ],
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
  charts: [
    // The endpoint buckets losses by day, not by reason: the days plot, and the
    // shrinkage % already sits in a tile above.
    if (report.page.rows.isNotEmpty)
      GroupedBarTrendChart(
        key: const ValueKey('report-viewer-shrinkage-chart'),
        title: 'Lost stock by day',
        subtitle: 'Base units lost to shrinkage and damage, day by day.',
        primaryLabel: 'Units lost',
        isCurrency: false,
        height: 180,
        points: _perDayPoints(
          report.page.rows,
          date: (row) => row.date,
          value: (row) => row.qty,
        ),
      ),
  ],
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
  charts: [
    if (report.page.rows.isNotEmpty)
      ShareSplitChart(
        key: const ValueKey('report-viewer-adjustments-split'),
        title: 'Corrections vs supplier returns',
        subtitle:
            'How the adjusted quantity divides. A return lowers the shelf.',
        slices: [
          for (final entry in _totalsByLabel(
            report.page.rows,
            label: (row) => row.type,
            amount: (row) => row.qty.abs(),
          ).entries)
            ShareSlice(
              label: entry.key,
              value: entry.value.amount,
              amountText: formatQuantity(entry.value.amount),
            ),
        ],
      ),
  ],
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
  charts: [
    // The buying order: the biggest shortfalls are what get bought first.
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-reorder-chart'),
        title: 'Biggest shortfalls',
        subtitle: 'What has to be bought, against what is still on the shelf.',
        primaryLabel: 'Shortfall',
        secondaryLabel: 'On hand',
        items: [
          for (final row in report.page.rows.take(8))
            ComparisonBarItem(
              label: row.name,
              primaryValue: row.gap,
              primaryText: formatQuantity(row.gap),
              secondaryValue: row.onHand,
              secondaryText: 'On hand ${formatQuantity(row.onHand)}',
            ),
        ],
      ),
  ],
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
  charts: [
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-dead-stock-chart'),
        title: 'Money tied up in dead stock',
        subtitle: 'The worst offenders by pesos frozen at landed cost.',
        primaryLabel: 'Money tied up',
        items: [
          for (final row in report.page.rows.take(8))
            ComparisonBarItem(
              label: row.name,
              primaryValue: row.landedValue,
              primaryText: formatPeso(row.landedValue),
              badgeText: row.daysSinceLastSale == null
                  ? 'Never sold'
                  : '${formatCount(row.daysSinceLastSale!)} days idle',
            ),
        ],
      ),
  ],
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
  charts: [
    if (report.page.rows.isNotEmpty)
      ShareSplitChart(
        key: const ValueKey('report-viewer-fast-slow-split'),
        title: 'Fast vs slow movers',
        subtitle: 'How the range’s base units divide between the two bands.',
        slices: [
          for (final entry in _totalsByLabel(
            report.page.rows,
            label: (row) => _bandLabel(row.band),
            amount: (row) => row.qtyBase,
          ).entries)
            ShareSlice(
              label: entry.key,
              value: entry.value.amount,
              amountText: formatQuantity(entry.value.amount),
            ),
        ],
      ),
  ],
);

_ReportView _cycleCountView(CycleCountReport report) {
  final countedMore = report.page.rows
      .where((row) => row.qty > 0)
      .fold<double>(0, (sum, row) => sum + row.qty);
  final countedShort = report.page.rows
      .where((row) => row.qty < 0)
      .fold<double>(0, (sum, row) => sum - row.qty);
  return _ReportView(
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
        value: _percentOrUnknown(
          report.shrinkagePercent,
          'No stock to measure',
        ),
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
    charts: [
      // Matches write no row, so the honest split is the variance itself: stock
      // the count found extra against stock it found short.
      if (report.page.rows.isNotEmpty)
        ShareSplitChart(
          key: const ValueKey('report-viewer-cycle-count-split'),
          title: 'Counted more vs counted short',
          subtitle:
              'Base units of variance, split by which way the shelf moved.',
          slices: [
            ShareSlice(
              label: 'Counted more than the shelf',
              value: countedMore,
              amountText: formatQuantity(countedMore),
            ),
            ShareSlice(
              label: 'Counted short',
              value: countedShort,
              amountText: formatQuantity(countedShort),
            ),
          ],
        ),
    ],
  );
}

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
  charts: [
    // The server already buckets the value on hand: four bars, no arithmetic.
    if (report.page.rows.isNotEmpty)
      HorizontalComparisonChart(
        key: const ValueKey('report-viewer-expiry-chart'),
        title: 'Value at risk by expiry bucket',
        subtitle: 'Pesos on the shelf, by how soon the batch expires.',
        primaryLabel: 'Value at risk',
        items: [
          ComparisonBarItem(
            label: 'Already expired',
            primaryValue: report.valueExpired,
            primaryText: formatPeso(report.valueExpired),
          ),
          ComparisonBarItem(
            label: '0-30 days',
            primaryValue: report.value0to30,
            primaryText: formatPeso(report.value0to30),
          ),
          ComparisonBarItem(
            label: '31-60 days',
            primaryValue: report.value31to60,
            primaryText: formatPeso(report.value31to60),
          ),
          ComparisonBarItem(
            label: '61-90 days',
            primaryValue: report.value61to90,
            primaryText: formatPeso(report.value61to90),
          ),
        ],
      ),
  ],
);

/// Rows collapsed to one point per day, oldest first.
///
/// A per-ticket report (goods received, transfers, losses) carries a date on
/// every row; this turns those rows into the time axis the chart reads, and
/// shortens the date to the `MM-DD` label the sales trend already uses.
List<TrendPoint> _perDayPoints<T>(
  Iterable<T> rows, {
  required String Function(T row) date,
  required double Function(T row) value,
}) {
  final byDay = <String, double>{};
  for (final row in rows) {
    final raw = date(row);
    final day = raw.length >= 10 ? raw.substring(0, 10) : raw;
    byDay[day] = (byDay[day] ?? 0) + value(row);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final day in days)
      TrendPoint(
        label: day.length >= 10 ? day.substring(5, 10) : day,
        primary: byDay[day]!,
      ),
  ];
}

/// Rows collapsed by one label, summing an amount and counting the rows.
///
/// First-seen order is kept: a ranking chart sorts the entries it is given.
Map<String, ({int count, double amount})> _totalsByLabel<T>(
  Iterable<T> rows, {
  required String Function(T row) label,
  required double Function(T row) amount,
}) {
  final totals = <String, ({int count, double amount})>{};
  for (final row in rows) {
    final key = label(row);
    final current = totals[key];
    totals[key] = (
      count: (current?.count ?? 0) + 1,
      amount: (current?.amount ?? 0) + amount(row),
    );
  }
  return totals;
}

/// The mover band in words: `FAST` is `Fast movers`, anything else keeps the
/// server's own word.
String _bandLabel(String band) => switch (band) {
  'FAST' => 'Fast movers',
  'SLOW' => 'Slow movers',
  _ => band,
};

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
