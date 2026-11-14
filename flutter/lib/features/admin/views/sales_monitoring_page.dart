import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/widgets/admin_sales_chart.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';

/// Live sales & POS monitoring (decision D-03, refreshed by card A3).
///
/// The chart used to be `AdminMockData.salesValues`, invented bars, in the
/// admin shell, next to screens showing real money. It now renders the same
/// `SalesSummary` the Reports tab reads.
///
/// The range is no longer fixed at seven days: the page reads thirty days ONCE
/// and the period chips narrow those loaded days, so switching periods is
/// instant and cannot disagree with the money already on screen. The caption
/// under the chips says that out loud, because a narrowed list that looks like a
/// fresh server total would be a claim nobody checked.
///
/// A local `StatefulWidget` rather than `AdminReportsViewmodel`: this screen is
/// ONE fetch and one panel, and dragging in the four-tab machinery to show a
/// chart would be more moving parts, not fewer.
class SalesMonitoringPage extends StatefulWidget {
  const SalesMonitoringPage({super.key, this.repository});

  /// Injected by tests so loading, error and empty states render without a
  /// server. Production builds its own.
  final ReportsRepository? repository;

  @override
  State<SalesMonitoringPage> createState() => _SalesMonitoringPageState();
}

class _SalesMonitoringPageState extends State<SalesMonitoringPage> {
  /// The chip labels, in display order.
  static const List<String> _periods = ['Today', 'Last 7 days', 'Last 30 days'];

  /// Said under the chips so a narrowed total is not mistaken for a new one.
  static const String _rangeCaption =
      'The chips and the search narrow the days this page already loaded, not '
      'a new fetch.';

  late final ReportsRepository _repository =
      widget.repository ?? ReportsRepository();

  bool _isLoading = true;
  String? _error;
  SalesSummary? _summary;

  /// Seven days by default: the range this screen showed before the chips.
  String _period = 'Last 7 days';

  /// Narrows the days on screen further than the chip does.
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Post-frame, not initState body: a load that completes synchronously in
    // initState would notify a tree that has not finished mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  static String _stamp(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// A day as the reader sees it, through the app's one date format (D6).
  static String _label(SalesDay day) => formatDate(DateTime.parse(day.day));

  Future<void> _load() async {
    final now = appClock.now();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summary = await _repository.fetchSalesSummary(
        // Thirty days in one read, so the widest chip needs no second request.
        from: _stamp(now.subtract(const Duration(days: 29))),
        to: _stamp(now),
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } on ReportsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // The summary is kept: a failed REFRESH leaves the rows it already read
        // under the banner, and only a failed first read leaves nothing.
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Days back from today the chip stands for; null means "every loaded day".
  static int? _daysBackFor(String period) => switch (period) {
    'Today' => 0,
    'Last 7 days' => 6,
    _ => null,
  };

  /// The loaded days the chip and the search leave visible, oldest first.
  List<SalesDay> _visibleDays(SalesSummary summary) {
    final daysBack = _daysBackFor(_period);
    final from = daysBack == null
        ? null
        : _stamp(appClock.now().subtract(Duration(days: daysBack)));
    final query = _query.trim().toLowerCase();
    final rows = [
      for (final day in summary.days)
        if ((from == null || day.day.compareTo(from) >= 0) &&
            (query.isEmpty || _label(day).toLowerCase().contains(query)))
          day,
    ]..sort((a, b) => a.day.compareTo(b.day));
    return rows;
  }

  /// The largest single day in the visible range, for the chart's money label.
  static double _peak(List<SalesDay> days) {
    var peak = 0.0;
    for (final day in days) {
      if (day.gross > peak) peak = day.gross;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Sales & POS Monitoring',
      subtitle: 'Review store sales and point-of-sale activity.',
      selectedNavigationIndex: 3,
      child: _body(),
    );
  }

  Widget _body() {
    final summary = _summary;
    final failure = _error;

    // Only a first read may replace the screen with a spinner; a refresh keeps
    // the numbers under its banner.
    if (_isLoading && summary == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // One failure, never two: a failed first read is the banner and nothing
    // else, because zeroed tiles under it would read as this read's numbers.
    if (failure != null && summary == null) {
      return ErrorBanner(message: failure, onRetry: _load);
    }

    final days = _visibleDays(summary!);
    final transactions = days.fold<int>(
      0,
      (total, day) => total + day.transactions,
    );
    final gross = days.fold<double>(0, (total, day) => total + day.gross);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: 'Day, e.g. Oct 19',
          onSearchChanged: (value) => setState(() => _query = value),
          options: _periods,
          selected: _period,
          onSelected: (chip) => setState(() => _period = chip),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          _rangeCaption,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        MetricGrid(
          children: [
            MetricTile(
              label: 'Transactions',
              value: formatCount(transactions),
              caption: 'In ${formatCount(days.length)} days',
            ),
            MetricTile(label: 'Gross sales', value: formatPeso(gross)),
            MetricTile(
              label: 'Average sale',
              // Nothing sold is no average at all: "None", because the read did
              // succeed and a peso zero would read as a free transaction.
              value: transactions == 0
                  ? 'None'
                  : formatPeso(gross / transactions),
              caption: 'Gross over transactions',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        AppPanel(
          title: 'Sales by day',
          // The chart's one money figure, through `formatPeso`: a "₱1141.0k"
          // axis label is a rounded number nobody can reconcile against the till.
          trailing: days.isEmpty
              ? null
              : Text(
                  'Highest day ${formatPeso(_peak(days))}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
          child: days.isEmpty
              ? Padding(
                  key: const Key('sales-monitoring-empty'),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Text(
                    // Two facts, two sentences: an empty range and a search
                    // that hides every day are not the same thing.
                    _query.trim().isNotEmpty
                        ? 'No day matches this search.'
                        : 'No data for this period.',
                  ),
                )
              : AdminSalesChart(
                  values: [for (final day in days) day.gross],
                  labels: [for (final day in days) _label(day)],
                ),
        ),
      ],
    );
  }
}
