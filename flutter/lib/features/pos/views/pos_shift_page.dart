import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_open_shift_dialog.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shift management (tab 5): the open shift, its Z-reading once closed, and the
/// cashier's history. See decision 06.
class PosShiftPage extends StatefulWidget {
  const PosShiftPage({super.key, this.viewmodel});

  /// Injectable for tests — same convention as [PosHeldTransactionsPage].
  final ShiftViewmodel? viewmodel;

  @override
  State<PosShiftPage> createState() => _PosShiftPageState();
}

class _PosShiftPageState extends State<PosShiftPage> {
  late final ShiftViewmodel _viewmodel = widget.viewmodel ?? ShiftViewmodel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewmodel.load();
    });
  }

  @override
  void dispose() {
    // Only dispose the one we own; an injected viewmodel belongs to the caller.
    if (widget.viewmodel == null) _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ShiftViewmodel>.value(
      value: _viewmodel,
      child: const _PosShiftView(),
    );
  }
}

class _PosShiftView extends StatelessWidget {
  const _PosShiftView();

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ShiftViewmodel>();
    final current = viewmodel.currentShift;
    final lastClosed = viewmodel.history
        .where((shift) => !shift.isOpen)
        .firstOrNull;
    final nothingLoaded = current == null && viewmodel.history.isEmpty;

    // A running reading belongs to the OPEN shift: `GET /shifts/current/` returns
    // the same derived summary with no variance yet (there is no closing count).
    final runningReading = current?.zReading;
    // The previous shift's reading is shown ONLY when nothing is open. Showing
    // it under a live drawer made a cashier read stale money as "now" (live QA).
    final previousReading = current == null ? lastClosed?.zReading : null;

    // "Open a shift" is offered only for a REAL "none": a failed current-shift
    // read says nothing either way, and opening a second shift on top of a live
    // drawer is what the server refuses.
    final canOpen = current == null && viewmodel.currentShiftError == null;

    return DashboardShell(
      title: 'Shifts',
      subtitle: 'Your open shift, end-of-shift readings and past shifts.',
      selectedNavigationIndex: 5,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          if (viewmodel.isLoading && nothingLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: 300,
                  child: SalesDashboardMetricCard(
                    label: 'Shift status',
                    value: current == null ? 'CLOSED' : current.status,
                    caption: current == null
                        ? (canOpen
                              ? 'No shift open — open one to start selling'
                              : 'The open shift could not be checked')
                        : 'Opened ${_timestamp(current.openedAt)}',
                    icon: Icons.access_time,
                    color: current == null
                        ? AppColors.textSecondary
                        : AppColors.success,
                  ),
                ),
                if (current != null)
                  SizedBox(
                    width: 300,
                    child: SalesDashboardMetricCard(
                      label: 'Opening float',
                      value: '₱${current.openingFloat.toStringAsFixed(2)}',
                      caption: 'Counted when the shift opened',
                      icon: Icons.savings_outlined,
                      color: AppColors.info,
                    ),
                  ),
              ],
            ),
            if (canOpen) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                // The SAME flow the till gate uses - one shared form, so the
                // float rule and the server's refusal messages cannot drift.
                onPressed: () => showOpenShiftDialog(context, viewmodel),
                child: const Text('Open shift'),
              ),
            ],
            if (current != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => showShiftCloseDialog(context, viewmodel),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Close shift'),
              ),
            ],
            if (runningReading != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PosZReadingSummary(
                reading: runningReading,
                title: 'This shift so far',
              ),
            ] else if (previousReading != null && lastClosed != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PosZReadingSummary(
                reading: previousReading,
                title: 'Last closed shift (${_timestamp(lastClosed.openedAt)})',
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SalesRecordsTable(
              columns: const [
                'Opened',
                'Cashier',
                'Status',
                'Float',
                'Closing count',
                'Variance',
              ],
              emptyMessage: viewmodel.loadError != null
                  ? 'Shifts could not be loaded.'
                  : 'No shifts yet.',
              rows: viewmodel.history.map(_row).toList(),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _row(Shift shift) {
    final variance = shift.zReading?.variance;
    return <Widget>[
      Text(_timestamp(shift.openedAt)),
      Text(shift.cashierName),
      Text(shift.status),
      Text('₱${shift.openingFloat.toStringAsFixed(2)}'),
      Text(
        shift.closingCount == null
            ? '—'
            : '₱${shift.closingCount!.toStringAsFixed(2)}',
      ),
      Text(variance == null ? '—' : '₱${variance.toStringAsFixed(2)}'),
    ];
  }

  String _timestamp(DateTime value) =>
      '${value.year}-${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}
