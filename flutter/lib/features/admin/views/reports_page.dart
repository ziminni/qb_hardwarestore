import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The ONE admin/manager Reports screen (decision 16, as amended).
///
/// Four tabs — Sales · Valuation · Movements · Requisitions — one report at a
/// time. Sales and movements take a from/to range; valuation and requisition
/// history do not. A failed tab names its failure without blanking the others.
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

  static const _tabs = ['Sales', 'Valuation', 'Movements', 'Requisitions'];

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<AdminReportsViewmodel>();
    return AdminSkeletonLayout(
      title: 'Reports',
      subtitle: 'Managerial reports over live operations data.',
      selectedNavigationIndex: 5,
      child: DefaultTabController(
        length: _tabs.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
              isScrollable: true,
              onTap: (index) => viewmodel.selectTab(index),
              tabs: [for (final tab in _tabs) Tab(text: tab)],
            ),
            const SizedBox(height: AppSpacing.md),
            // Fixed height, not Expanded: the admin shell lays its content out
            // in an unbounded vertical scrollable, where flex has no meaning.
            SizedBox(
              height: 900,
              child: TabBarView(
                children: [
                  _SalesTab(viewmodel: viewmodel),
                  _ValuationTab(viewmodel: viewmodel),
                  _MovementsTab(viewmodel: viewmodel),
                  _RequisitionsTab(viewmodel: viewmodel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small metric tile local to this screen.
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

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
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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

String _money(double amount) => '₱${amount.toStringAsFixed(2)}';

/// A failed tab names the failure. A loading tab spins. Anything else is the
/// caller's content — an error must never read as an empty report.
class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.isLoading,
    required this.error,
    required this.child,
  });

  final bool isLoading;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return child;
  }
}

class _RangeControls extends StatefulWidget {
  const _RangeControls({required this.onApply});

  final void Function(String? from, String? to) onApply;

  @override
  State<_RangeControls> createState() => _RangeControlsState();
}

class _RangeControlsState extends State<_RangeControls> {
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 180,
          child: TextField(
            key: const Key('reports-from'),
            controller: _from,
            decoration: const InputDecoration(
              labelText: 'From (YYYY-MM-DD)',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 180,
          child: TextField(
            key: const Key('reports-to'),
            controller: _to,
            decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => widget.onApply(_clean(_from), _clean(_to)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      isLoading: viewmodel.isLoadingTab(0) && viewmodel.sales == null,
      error: viewmodel.errorFor(0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RangeControls(
              onApply: (from, to) => viewmodel.setRange(from, to),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _Tile(
                  label: 'Transactions',
                  value: '${viewmodel.sales?.totalTransactions ?? 0}',
                ),
                _Tile(
                  label: 'Gross sales',
                  value: _money(viewmodel.sales?.totalGross ?? 0),
                ),
                _Tile(
                  label: 'VAT',
                  value: _money(viewmodel.sales?.totalVat ?? 0),
                ),
                _Tile(
                  label: 'Discounts',
                  value: _money(viewmodel.sales?.totalDiscounts ?? 0),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SalesRecordsTable(
              columns: const ['Day', 'Transactions', 'Gross', 'VAT', 'Discounts'],
              emptyMessage: 'No sales in this range.',
              rows: [
                for (final day in viewmodel.sales?.days ?? [])
                  [
                    Text(day.day),
                    Text('${day.transactions}'),
                    Text(_money(day.gross)),
                    Text(_money(day.vat)),
                    Text(_money(day.discounts)),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValuationTab extends StatelessWidget {
  const _ValuationTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      isLoading: viewmodel.isLoadingTab(1) && viewmodel.valuation == null,
      error: viewmodel.errorFor(1),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _Tile(
                  label: 'Batches',
                  value: '${viewmodel.valuation?.batchCount ?? 0}',
                ),
                _Tile(
                  label: 'Units on hand',
                  value: '${viewmodel.valuation?.totalUnits ?? 0}',
                ),
                _Tile(
                  label: 'Value at cost',
                  value: _money(viewmodel.valuation?.totalCost ?? 0),
                ),
                _Tile(
                  label: 'Value at retail',
                  value: _money(viewmodel.valuation?.totalRetail ?? 0),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SalesRecordsTable(
              columns: const [
                'Category',
                'Batches',
                'Units',
                'At cost',
                'At retail',
              ],
              emptyMessage: 'No stock on hand.',
              rows: [
                for (final category in viewmodel.valuation?.categories ?? [])
                  [
                    Text(category.name),
                    Text('${category.batchCount}'),
                    Text('${category.units}'),
                    Text(_money(category.cost)),
                    Text(_money(category.retail)),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsTab extends StatelessWidget {
  const _MovementsTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      isLoading: viewmodel.isLoadingTab(2) && viewmodel.movements == null,
      error: viewmodel.errorFor(2),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RangeControls(
              onApply: (from, to) => viewmodel.setRange(from, to),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _Tile(
                  label: 'Units in',
                  value: '${viewmodel.movements?.totalIn ?? 0}',
                ),
                _Tile(
                  label: 'Units out',
                  value: '${viewmodel.movements?.totalOut ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SalesRecordsTable(
              columns: const ['Day', 'Receipts', 'Qty in'],
              emptyMessage: 'No receipts in this range.',
              rows: [
                for (final day in viewmodel.movements?.receiptsByDay ?? [])
                  [
                    Text(day.date),
                    Text('${day.receipts}'),
                    Text('${day.qtyIn}'),
                  ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SalesRecordsTable(
              columns: const ['Type', 'Movements', 'Qty out'],
              emptyMessage: 'No adjustments in this range.',
              rows: [
                for (final type in viewmodel.movements?.adjustmentsByType ?? [])
                  [
                    Text(type.type),
                    Text('${type.movements}'),
                    Text('${type.qtyOut}'),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequisitionsTab extends StatelessWidget {
  const _RequisitionsTab({required this.viewmodel});

  final AdminReportsViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    final counts = viewmodel.history?.countByStatus ?? {};
    return _TabBody(
      isLoading: viewmodel.isLoadingTab(3) && viewmodel.history == null,
      error: viewmodel.errorFor(3),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in counts.entries)
                  Chip(label: Text('${entry.key}: ${entry.value}')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SalesRecordsTable(
              columns: const [
                'Requisition',
                'Status',
                'Project',
                'Requested by',
                'Approved by',
              ],
              emptyMessage: 'No requisitions in this range.',
              rows: [
                for (final row in viewmodel.history?.requisitions ?? [])
                  [
                    Text(row.reqNumber),
                    Text(
                      row.status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(row.project),
                    Text(row.requestedBy),
                    Text(row.approvedBy ?? '—'),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
