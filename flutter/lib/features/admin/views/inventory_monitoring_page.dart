import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/widgets/admin_inventory_summary.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';

/// Live inventory monitoring (decision D-03).
///
/// The four tiles used to be `AdminMockData.inventoryMetrics` — invented
/// numbers. They now come from the same `InventoryValuation` the Reports tab
/// reads, so the admin shell has one source of truth for stock value.
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

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final valuation = await _repository.fetchInventoryValuation();
      if (!mounted) return;
      setState(() => _valuation = valuation);
    } on ReportsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // Same reason as the sales page: stale tiles under a failure message
        // would read as this load's numbers.
        _valuation = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    final valuation = _valuation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Inventory overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        AdminInventorySummary(
          metrics: [
            ('Total items', (valuation?.totalUnits ?? 0).toStringAsFixed(0)),
            ('Total cost value', formatPeso(valuation?.totalCost ?? 0)),
            ('Total retail value', formatPeso(valuation?.totalRetail ?? 0)),
            ('Batches', '${valuation?.batchCount ?? 0}'),
          ],
        ),
      ],
    );
  }
}
