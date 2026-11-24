import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/format/numeric_input.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_open_shift_dialog.dart';
import 'package:client/features/pos/widgets/pos_shift_cash_movement_dialog.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shift management (tab 6): the open shift, cash-in/out log, PHP denomination
/// audit calculator, Z-reading summary, and past shift history.
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

  void _openPastShiftSheet(BuildContext context, Shift shift) {
    final reading = shift.zReading;
    if (reading == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Shift #${shift.id} · ${shift.cashierName}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: PosZReadingSummary(
              reading: reading,
              title: shift.isOpen
                  ? 'Open shift (${formatDateTime(shift.openedAt.toLocal())})'
                  : 'Closed shift (${formatDateTime(shift.openedAt.toLocal())})',
              closingCount: shift.closingCount,
              cashLeftInDrawer: shift.cashLeftInDrawer,
              cashMovements: shift.cashMovements,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ShiftViewmodel>();
    final current = viewmodel.currentShift;
    final lastClosed = viewmodel.history
        .where((shift) => !shift.isOpen)
        .firstOrNull;
    final nothingLoaded = current == null && viewmodel.history.isEmpty;

    final runningReading = current?.zReading;
    final previousReading = current == null ? lastClosed?.zReading : null;
    final activeShift = current ?? lastClosed;
    final activeReading = runningReading ?? previousReading;
    final shiftUnknown = current == null && viewmodel.currentShiftError != null;

    return DashboardShell(
      title: 'Shifts',
      subtitle:
          'Open float, mid-shift cash in/out, denomination counts, and past Z-readings.',
      selectedNavigationIndex: 5,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            // 1. Hero Shift Status Card (3-block Stitch layout)
            _HeroShiftStatusCard(
              current: current,
              lastClosed: lastClosed,
              shiftUnknown: shiftUnknown,
              onOpen: () => showOpenShiftDialog(context, viewmodel),
              onClose: () => showShiftCloseDialog(context, viewmodel),
            ),

            // 2. Quick Actions & Cash Flow Timeline + Cash-Out Category Breakdown
            if (activeShift != null && activeReading != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _QuickActionsAndCashOutRow(
                isOpen: current != null,
                movements: activeShift.cashMovements,
                reading: activeReading,
                onCashIn: () => showShiftCashMovementDialog(
                  context,
                  viewmodel,
                  initialKind: ShiftCashMovement.cashInKind,
                ),
                onCashOut: () => showShiftCashMovementDialog(
                  context,
                  viewmodel,
                  initialKind: ShiftCashMovement.cashOutKind,
                ),
              ),
            ],

            // 3. Interactive PHP Denomination Counter Grid (when shift is open)
            if (current != null && runningReading != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _DenominationAuditCalculator(
                key: ValueKey('denom-calc-${current.id}'),
                expectedDrawer: runningReading.expectedDrawer,
                onCloseWithCount: (denominations) => showShiftCloseDialog(
                  context,
                  viewmodel,
                  initialDenominations: denominations,
                ),
              ),
            ],

            // 4. Running / Last Closed Shift Z-Reading Summary
            if (runningReading != null && current != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PosZReadingSummary(
                reading: runningReading,
                title: 'This shift so far',
                cashMovements: current.cashMovements,
              ),
            ] else if (previousReading != null && lastClosed != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PosZReadingSummary(
                reading: previousReading,
                title:
                    'Last closed shift (${formatDateTime(lastClosed.openedAt)})',
                closingCount: lastClosed.closingCount,
                cashLeftInDrawer: lastClosed.cashLeftInDrawer,
                cashMovements: lastClosed.cashMovements,
              ),
            ],

            // 5. Past Shifts & Z-Readings History Table
            if (!(nothingLoaded && viewmodel.loadError != null)) ...[
              const SizedBox(height: AppSpacing.lg),
              DataPanel<Shift>(
                title: 'Shift History & Z-Readings',
                count: viewmodel.history.length,
                columns: _historyColumns,
                rows: viewmodel.history,
                onRowTap: (shift) => _openPastShiftSheet(context, shift),
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

  static final List<DataPanelColumn<Shift>> _historyColumns = [
    DataPanelColumn<Shift>(
      label: 'Shift time',
      flex: 3,
      cell: (shift) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shift #${shift.id} · ${formatDateTime(shift.openedAt.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            shift.closedAt == null
                ? 'Still open'
                : 'Closed ${formatDateTime(shift.closedAt!.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    DataPanelColumn<Shift>(
      label: 'Cashier',
      flex: 2,
      cell: (shift) =>
          Text(shift.cashierName, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    DataPanelColumn<Shift>(
      label: 'Status',
      cell: (shift) => StatusBadge(
        label: shift.isOpen ? 'Open' : 'Closed',
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
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    DataPanelColumn<Shift>(
      label: 'Gross sales',
      numeric: true,
      flex: 2,
      cell: (shift) => shift.zReading == null
          ? const _MissingAmount('Not loaded')
          : Text(
              formatPeso(shift.zReading!.grossSales),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
    ),
    DataPanelColumn<Shift>(
      label: 'Cash counted',
      numeric: true,
      flex: 2,
      cell: (shift) => shift.closingCount == null
          ? const _MissingAmount('Not counted yet')
          : Text(
              formatPeso(shift.closingCount!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
    ),
    DataPanelColumn<Shift>(
      label: 'Cash difference',
      numeric: true,
      flex: 2,
      cell: (shift) {
        final variance = shift.zReading?.variance;
        if (variance == null) {
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
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    ),
  ];
}

class _MissingAmount extends StatelessWidget {
  const _MissingAmount(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
  );
}

/// 3-block Hero Shift Status Card adapted from Stitch.
class _HeroShiftStatusCard extends StatelessWidget {
  const _HeroShiftStatusCard({
    required this.current,
    required this.lastClosed,
    required this.shiftUnknown,
    required this.onOpen,
    required this.onClose,
  });

  final Shift? current;
  final Shift? lastClosed;
  final bool shiftUnknown;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final shift = current;
    final reading = shift?.zReading;

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
          LayoutBuilder(
            builder: (context, constraints) {
              final leftBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(label: label, tone: tone),
                      if (shift != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Shift #${shift.id}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (shift != null)
                    Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.sm,
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
                ],
              );

              final centerBlock = shift != null && reading != null
                  ? Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _miniMetric(
                            'Cash sales',
                            formatPeso(reading.cashSales),
                            AppColors.textPrimary,
                          ),
                          _miniMetric(
                            'Cash added',
                            '+${formatPeso(reading.cashIn)}',
                            AppColors.successText,
                          ),
                          _miniMetric(
                            'Cash drops / out',
                            '-${formatPeso(reading.cashOut)}',
                            AppColors.errorText,
                          ),
                        ],
                      ),
                    )
                  : null;

              final rightBlock = shift != null && reading != null
                  ? Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EXPECTED IN DRAWER',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatPeso(reading.expectedDrawer),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatCount(reading.transactionCount)} sales this shift',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null;

              if (constraints.maxWidth >= 900 &&
                  centerBlock != null &&
                  rightBlock != null) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: leftBlock),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 3, child: centerBlock),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: rightBlock),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  leftBlock,
                  if (centerBlock != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    centerBlock,
                  ],
                  if (rightBlock != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    rightBlock,
                  ],
                ],
              );
            },
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
                      icon: const Icon(Icons.lock_clock_outlined),
                      label: const Text('Close shift'),
                    )
                  : FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Open shift'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
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
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _miniMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Stitch Row 2: Quick Action Tiles + Recent Drawer Slips Timeline (Left) &
/// Cash-Out Category Breakdown Stacked Bar (Right).
class _QuickActionsAndCashOutRow extends StatelessWidget {
  const _QuickActionsAndCashOutRow({
    required this.isOpen,
    required this.movements,
    required this.reading,
    required this.onCashIn,
    required this.onCashOut,
  });

  final bool isOpen;
  final List<ShiftCashMovement> movements;
  final ZReading reading;
  final VoidCallback onCashIn;
  final VoidCallback onCashOut;

  static const _barColors = [
    Color(0xFF1E40AF),
    Color(0xFF0EA5E9),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
  ];

  @override
  Widget build(BuildContext context) {
    final leftPanel = AppPanel(
      title: 'Drawer Activity & Quick Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOpen) ...[
            Row(
              children: [
                Expanded(
                  child: _QuickActionTile(
                    key: const ValueKey('shift-quick-cash-in'),
                    title: 'Record Cash In',
                    subtitle: 'Add change float',
                    icon: Icons.south_west_rounded,
                    color: AppColors.successText,
                    bg: AppColors.success.withValues(alpha: 0.10),
                    onTap: onCashIn,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickActionTile(
                    key: const ValueKey('shift-quick-cash-out'),
                    title: 'Record Cash Out',
                    subtitle: 'Safe drop or expense',
                    icon: Icons.north_east_rounded,
                    color: AppColors.errorText,
                    bg: AppColors.error.withValues(alpha: 0.10),
                    onTap: onCashOut,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const Text(
            'RECENT DRAWER SLIPS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No mid-shift cash movements recorded yet.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            Column(
              children: [
                for (final m in movements.reversed.take(5))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            m.isCashOut
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                            size: 16,
                            color: m.isCashOut
                                ? AppColors.errorText
                                : AppColors.successText,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${ShiftCashMovement.displayCategory(m.category)} · ${m.reason}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  formatDateTime(m.createdAt.toLocal()),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${m.isCashOut ? '-' : '+'}${formatPeso(m.amount)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: m.isCashOut
                                  ? AppColors.errorText
                                  : AppColors.successText,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );

    final categories = reading.cashOutByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalOut = categories.fold<double>(0, (s, e) => s + e.value);

    final rightPanel = AppPanel(
      title: 'Cash-Out Category Split',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total cash out',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              Text(
                formatPeso(reading.cashOut),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (categories.isEmpty || totalOut <= 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No cash-out drops or expenses recorded for this shift.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < categories.length; i++)
                      Expanded(
                        flex: (categories[i].value * 100).round().clamp(1, 1000000),
                        child: Container(
                          color: _barColors[i % _barColors.length],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < categories.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _barColors[i % _barColors.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ShiftCashMovement.displayCategory(categories[i].key),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${((categories[i].value / totalOut) * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatPeso(categories[i].value),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftPanel),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: rightPanel),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leftPanel,
            const SizedBox(height: AppSpacing.md),
            rightPanel,
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45), width: 1.25),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: color),
        ],
      ),
    );
  }
}

/// Stitch Row 3: Interactive PHP Physical Cash Audit & Denomination Counter.
class _DenominationAuditCalculator extends StatefulWidget {
  const _DenominationAuditCalculator({
    super.key,
    required this.expectedDrawer,
    required this.onCloseWithCount,
  });

  final double expectedDrawer;
  final ValueChanged<Map<String, int>> onCloseWithCount;

  @override
  State<_DenominationAuditCalculator> createState() =>
      _DenominationAuditCalculatorState();
}

class _DenominationAuditCalculatorState
    extends State<_DenominationAuditCalculator> {
  final Map<String, TextEditingController> _controllers = {
    for (final d in ShiftCashMovement.phpDenominations)
      d.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> get _counts {
    final map = <String, int>{};
    for (final d in ShiftCashMovement.phpDenominations) {
      final cnt = int.tryParse(_controllers[d.key]!.text.trim()) ?? 0;
      if (cnt > 0) map[d.key] = cnt;
    }
    return map;
  }

  double get _totalCounted {
    var sum = 0.0;
    for (final d in ShiftCashMovement.phpDenominations) {
      final cnt = int.tryParse(_controllers[d.key]!.text.trim()) ?? 0;
      if (cnt > 0) sum += d.value * cnt;
    }
    return sum;
  }

  void _clear() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final banknotes = ShiftCashMovement.phpDenominations
        .where((d) => d.value >= 20)
        .toList();
    final coins = ShiftCashMovement.phpDenominations
        .where((d) => d.value < 20)
        .toList();
    final counted = _totalCounted;
    final hasInput = _counts.isNotEmpty;
    final variance = counted - widget.expectedDrawer;

    return AppPanel(
      title: 'PHP Physical Cash Audit & Denomination Calculator',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final billsCol = _denomGroup('Banknotes', banknotes);
              final coinsCol = _denomGroup('Coins', coins);
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: billsCol),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: coinsCol),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  billsCol,
                  const SizedBox(height: AppSpacing.md),
                  coinsCol,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _footerStat('Counted cash', formatPeso(counted), AppColors.textPrimary),
                    _footerStat(
                      'Expected drawer',
                      formatPeso(widget.expectedDrawer),
                      AppColors.textSecondary,
                    ),
                    _footerStat(
                      'Variance (Counted − Expected)',
                      hasInput
                          ? '${posVarianceText(variance)} (${posVarianceWord(variance)})'
                          : 'Enter bills/coins to calculate',
                      hasInput
                          ? posVarianceColor(variance)
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (hasInput)
                      TextButton(
                        onPressed: _clear,
                        child: const Text('Clear count'),
                      ),
                    FilledButton.icon(
                      key: const ValueKey('shift-close-with-denom-button'),
                      onPressed: hasInput
                          ? () => widget.onCloseWithCount(_counts)
                          : null,
                      icon: const Icon(Icons.lock_clock_outlined, size: 18),
                      label: const Text('Close shift with count'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _denomGroup(
    String heading,
    List<({String key, String label, double value})> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final d in items) _denomRow(d),
      ],
    );
  }

  Widget _denomRow(({String key, String label, double value}) d) {
    final cnt = int.tryParse(_controllers[d.key]!.text.trim()) ?? 0;
    final sub = cnt * d.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              d.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Text('×', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: TextField(
              key: ValueKey('shift-audit-denom-${d.key}'),
              controller: _controllers[d.key],
              keyboardType: TextInputType.number,
              inputFormatters: integerInputFormatters(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              formatPeso(sub),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: cnt > 0 ? FontWeight.w700 : FontWeight.w400,
                color: cnt > 0
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
