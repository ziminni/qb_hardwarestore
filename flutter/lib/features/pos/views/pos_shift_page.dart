import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_open_shift_dialog.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shift management (tab 5): the open shift, its Z-reading once closed, and the
/// cashier's history. See decision 06.
class PosShiftPage extends StatefulWidget {
  const PosShiftPage({super.key, this.viewmodel});

  /// Injectable for tests, same convention as [PosHeldTransactionsPage].
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
    final shiftUnknown = current == null && viewmodel.currentShiftError != null;

    return DashboardShell(
      title: 'Shifts',
      subtitle: 'Your open shift, end-of-shift readings and past shifts.',
      selectedNavigationIndex: 5,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One banner for the whole page: a failed first load is a single
          // failure with a Retry, never an empty history printed underneath it.
          if (viewmodel.loadError != null) ...[
            ErrorBanner(message: viewmodel.loadError!, onRetry: viewmodel.load),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (viewmodel.isLoading && nothingLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _ShiftStatusPanel(
              current: current,
              shiftUnknown: shiftUnknown,
              onOpen: () => showOpenShiftDialog(context, viewmodel),
              onClose: () => showShiftCloseDialog(context, viewmodel),
            ),
            if (runningReading != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PosZReadingSummary(
                reading: runningReading,
                title: 'This shift so far',
              ),
            ] else if (previousReading != null && lastClosed != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PosZReadingSummary(
                reading: previousReading,
                title:
                    'Last closed shift (${formatDateTime(lastClosed.openedAt)})',
              ),
            ],
            // Nothing loaded AND the read failed: the banner above is the whole
            // answer, and an empty table under it would read as "no shifts".
            if (!(nothingLoaded && viewmodel.loadError != null)) ...[
              const SizedBox(height: AppSpacing.lg),
              DataPanel<Shift>(
                columns: _historyColumns,
                rows: viewmodel.history,
                emptyMessage: viewmodel.loadError != null
                    ? 'Shifts could not be loaded.'
                    : 'No shifts yet.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Six columns with the text ones weighted: a cashier's name and the opened
  /// date need room, and every money column is wide enough for a 7 digit
  /// amount without ellipsizing at 1100 px.
  static final List<DataPanelColumn<Shift>> _historyColumns = [
    DataPanelColumn<Shift>(
      label: 'Opened',
      flex: 2,
      cell: (shift) => Text(
        formatDate(shift.openedAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    DataPanelColumn<Shift>(
      label: 'Cashier',
      flex: 3,
      cell: (shift) =>
          Text(shift.cashierName, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    DataPanelColumn<Shift>(
      label: 'Status',
      cell: (shift) => StatusBadge(
        label: shift.status,
        // Same colour language as the panel above: green while the drawer is
        // live, neutral once it is a record.
        tone: shift.isOpen ? StatusTone.success : StatusTone.neutral,
      ),
    ),
    DataPanelColumn<Shift>(
      label: 'Float',
      numeric: true,
      flex: 2,
      cell: (shift) => Text(
        formatPeso(shift.openingFloat),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    DataPanelColumn<Shift>(
      label: 'Closing count',
      numeric: true,
      flex: 2,
      // An unset count is a FACT about the row ("nobody has counted this
      // drawer yet"), so it is a word, not a dash.
      cell: (shift) => shift.closingCount == null
          ? const _MissingAmount('Not counted yet')
          : Text(
              formatPeso(shift.closingCount!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    ),
    DataPanelColumn<Shift>(
      label: 'Variance',
      numeric: true,
      flex: 2,
      cell: (shift) {
        final variance = shift.zReading?.variance;
        if (variance == null) {
          // An open row has no count yet; a CLOSED row without a reading is a
          // read that did not arrive. Two different facts, two words (D18).
          return _MissingAmount(
            shift.isOpen ? 'Not counted yet' : 'Not loaded',
          );
        }
        return Text(
          posVarianceText(variance),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: posVarianceColor(variance),
            fontWeight: FontWeight.w600,
          ),
        );
      },
    ),
  ];
}

/// The word an unset money cell reads as, so there is no dash and no
/// misleading zero.
class _MissingAmount extends StatelessWidget {
  const _MissingAmount(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: AppColors.textSecondary),
  );
}

/// The state of the drawer, the one action it allows, and the two facts that
/// belong to it. Replaces the 300 px metric card whose big value was the raw
/// word OPEN, and repeats the till header's green chip so the two screens say
/// the same thing.
class _ShiftStatusPanel extends StatelessWidget {
  const _ShiftStatusPanel({
    required this.current,
    required this.shiftUnknown,
    required this.onOpen,
    required this.onClose,
  });

  final Shift? current;

  /// The current-shift read failed, so nobody knows whether a drawer is open.
  final bool shiftUnknown;

  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final shift = current;
    // Three answers, three words: a live drawer, no drawer, and "nobody knows"
    // (a failed read says nothing about whether one is open).
    final String label;
    final StatusTone tone;
    if (shift != null) {
      label = 'Shift open';
      tone = StatusTone.success;
    } else if (shiftUnknown) {
      label = 'Shift not known';
      tone = StatusTone.warning;
    } else {
      label = 'No shift open';
      tone = StatusTone.neutral;
    }
    return AppPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(label: label, tone: tone),
          ),
          const SizedBox(height: AppSpacing.md),
          if (shift != null)
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _fact('Opened at', formatDateTime(shift.openedAt)),
                _fact('Opening float', formatPeso(shift.openingFloat)),
              ],
            )
          else
            Text(
              shiftUnknown
                  ? 'Retry to check whether a shift is open.'
                  : 'No shift open. Open one to start selling.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          if (shift != null || !shiftUnknown) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: shift != null
                  ? FilledButton.icon(
                      onPressed: onClose,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Close shift'),
                    )
                  // The SAME flow the till gate uses - one shared form, so the
                  // float rule and the server's refusal messages cannot drift.
                  : FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Open shift'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
