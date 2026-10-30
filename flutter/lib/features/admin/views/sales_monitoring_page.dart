import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/widgets/admin_sales_chart.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';

/// Live sales & POS monitoring (decision D-03).
///
/// The chart used to be `AdminMockData.salesValues` — invented bars, in the
/// admin shell, next to screens showing real money. It now renders the same
/// `SalesSummary` the Reports tab reads, over the last seven days.
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
  late final ReportsRepository _repository =
      widget.repository ?? ReportsRepository();

  bool _isLoading = true;
  String? _error;
  SalesSummary? _summary;

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

  Future<void> _load() async {
    final now = DateTime.now();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summary = await _repository.fetchSalesSummary(
        // Last seven days inclusive of today (decision D-03).
        from: _stamp(now.subtract(const Duration(days: 6))),
        to: _stamp(now),
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } on ReportsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // Drop the old summary: painting last week's bars under this week's
        // error would claim data the load did not return.
        _summary = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Sales & POS Monitoring',
      subtitle: 'Review store sales and point-of-sale activity.',
      selectedNavigationIndex: 3,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return LiveLoadErrorBanner(message: error, onRetry: _load);
    }

    final summary = _summary;
    final days = summary?.days ?? const <SalesDay>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 7 days',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _Metric(
              label: 'Transactions',
              value: '${summary?.totalTransactions ?? 0}',
              valueKey: const Key('sales-monitoring-transactions'),
            ),
            _Metric(
              label: 'Gross sales',
              value: formatPeso(summary?.totalGross ?? 0),
              valueKey: const Key('sales-monitoring-gross'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        if (days.isEmpty)
          // AdminSalesChart calls `values.reduce`, which throws on an empty
          // list — an empty range must say so instead of crashing the screen.
          const Padding(
            key: Key('sales-monitoring-empty'),
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text('No data for this period.'),
          )
        else
          AdminSalesChart(
            values: [for (final day in days) day.gross],
            labels: [for (final day in days) day.day],
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                key: valueKey,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
