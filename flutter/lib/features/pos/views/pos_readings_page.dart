import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/printing/escpos.dart';
import 'package:client/core/printing/raw_printer.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Cashier Daily X/Z-Reading & Sales Summary (Till sidebar index 10).
///
/// Built on existing [ShiftViewmodel] / [Shift] / [ZReading] data:
/// - Mid-shift X-reading snapshots are generated on demand from the live open
///   shift without resetting shift counters.
/// - Closed shifts populate the Daily Z-Readings (EOD) ledger and Monthly
///   Summary analytics.
/// - Every reading opens an 80mm monospace thermal slip preview with clipboard
///   copy and thermal roll printing.
class PosReadingsPage extends StatefulWidget {
  const PosReadingsPage({super.key, this.viewmodel});

  /// Injectable for widget tests, matching [PosShiftPage].
  final ShiftViewmodel? viewmodel;

  @override
  State<PosReadingsPage> createState() => _PosReadingsPageState();
}

enum _ReadingsTab { all, xReadings, zReadings, monthly }

enum _ReadingStatusFilter { all, balanced, variance }

/// Unified row model for both mid-shift X-readings and closed-shift Z-readings.
class PosReadingEntry {
  const PosReadingEntry({
    required this.code,
    required this.isXReading,
    required this.shiftId,
    required this.cashierName,
    required this.timestamp,
    required this.openedAt,
    required this.closedAt,
    required this.openingFloat,
    required this.transactionCount,
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.cashSales,
    required this.gcashSales,
    required this.cardSales,
    required this.bankSales,
    required this.chequeSales,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
    required this.denominationCounts,
  });

  factory PosReadingEntry.fromClosedShift(Shift shift) {
    final z = shift.zReading;
    final gross = z?.grossSales ?? 0;
    return PosReadingEntry(
      code: 'Z-${shift.id}',
      isXReading: false,
      shiftId: shift.id,
      cashierName: shift.cashierName,
      timestamp: (shift.closedAt ?? shift.openedAt).toLocal(),
      openedAt: shift.openedAt.toLocal(),
      closedAt: shift.closedAt?.toLocal(),
      openingFloat: shift.openingFloat,
      transactionCount: z?.transactionCount ?? 0,
      grossSales: gross,
      discounts: 0,
      netSales: gross,
      cashSales: z?.cashSales ?? 0,
      gcashSales: z?.gcashSales ?? 0,
      cardSales: z?.cardSales ?? 0,
      bankSales: 0,
      chequeSales: 0,
      cashIn: z?.cashIn ?? 0,
      cashOut: z?.cashOut ?? 0,
      expectedCash: z?.expectedDrawer ?? shift.openingFloat,
      countedCash: shift.closingCount,
      variance: z?.variance,
      denominationCounts: z?.denominationCounts ?? const {},
    );
  }

  factory PosReadingEntry.fromXReading(ShiftXReading reading) {
    final z = reading.snapshot;
    final localTakenAt = reading.takenAt.toLocal();
    return PosReadingEntry(
      code: reading.readingNumber,
      isXReading: true,
      shiftId: reading.shiftId,
      cashierName: reading.cashierName,
      timestamp: localTakenAt,
      openedAt: localTakenAt,
      closedAt: null,
      openingFloat: z.openingFloat,
      transactionCount: z.transactionCount,
      grossSales: z.grossSales,
      discounts: z.discounts,
      netSales: z.grossSales,
      cashSales: z.cashSales,
      gcashSales: z.gcashSales,
      cardSales: z.cardSales,
      bankSales: z.bankSales,
      chequeSales: z.chequeSales,
      cashIn: z.cashIn,
      cashOut: z.cashOut,
      expectedCash: z.expectedDrawer,
      countedCash: null,
      variance: null,
      denominationCounts: z.denominationCounts,
    );
  }

  factory PosReadingEntry.xSnapshot(
    Shift shift, {
    required int sequence,
    required DateTime takenAt,
  }) {
    final z = shift.zReading;
    final gross = z?.grossSales ?? 0;
    return PosReadingEntry(
      code: 'X-$sequence',
      isXReading: true,
      shiftId: shift.id,
      cashierName: shift.cashierName,
      timestamp: takenAt,
      openedAt: shift.openedAt.toLocal(),
      closedAt: null,
      openingFloat: shift.openingFloat,
      transactionCount: z?.transactionCount ?? 0,
      grossSales: gross,
      discounts: z?.discounts ?? 0,
      netSales: gross,
      cashSales: z?.cashSales ?? 0,
      gcashSales: z?.gcashSales ?? 0,
      cardSales: z?.cardSales ?? 0,
      bankSales: z?.bankSales ?? 0,
      chequeSales: z?.chequeSales ?? 0,
      cashIn: z?.cashIn ?? 0,
      cashOut: z?.cashOut ?? 0,
      expectedCash: z?.expectedDrawer ?? shift.openingFloat,
      countedCash: null,
      variance: null,
      denominationCounts: z?.denominationCounts ?? const {},
    );
  }

  final String code;
  final bool isXReading;
  final int shiftId;
  final String cashierName;
  final DateTime timestamp;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final int transactionCount;
  final double grossSales;
  final double discounts;
  final double netSales;
  final double cashSales;
  final double gcashSales;
  final double cardSales;
  final double bankSales;
  final double chequeSales;
  final double cashIn;
  final double cashOut;
  final double expectedCash;
  final double? countedCash;
  final double? variance;
  final Map<String, int> denominationCounts;

  bool get isBalanced => variance != null && variance!.abs() < 0.005;
  bool get hasVariance => variance != null && variance!.abs() >= 0.005;
}

class _PosReadingsPageState extends State<PosReadingsPage> {
  late final ShiftViewmodel _viewmodel = widget.viewmodel ?? ShiftViewmodel();
  final TextEditingController _searchController = TextEditingController();

  _ReadingsTab _activeTab = _ReadingsTab.all;
  _ReadingStatusFilter _statusFilter = _ReadingStatusFilter.all;
  String _searchQuery = '';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _monthPinnedByUser = false;

  Future<void> _reloadAll() async {
    await _viewmodel.load();
    if (!mounted) return;
    await _viewmodel.loadXReadings();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _reloadAll();
      if (!mounted || _monthPinnedByUser) return;
      final latest = _viewmodel.history.firstOrNull;
      if (latest != null) {
        final d = (latest.closedAt ?? latest.openedAt).toLocal();
        setState(() => _selectedMonth = DateTime(d.year, d.month));
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.viewmodel == null) _viewmodel.dispose();
    super.dispose();
  }

  Future<void> _generateInstantXReading() async {
    if (_viewmodel.isTakingXReading) return;
    final current = _viewmodel.currentShift;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No open shift found. Open a shift in the Shifts tab to take an X-reading.',
          ),
        ),
      );
      return;
    }
    final created = await _viewmodel.takeXReading();
    if (!mounted) return;
    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'X-Reading ${created.readingNumber} captured for Shift #${created.shiftId}.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewmodel.actionError ??
                'Could not capture X-reading. Please try again.',
          ),
        ),
      );
    }
  }

  void _openActiveThermalSlip() {
    PosReadingEntry? target;
    if (_viewmodel.xReadings.isNotEmpty) {
      target = PosReadingEntry.fromXReading(_viewmodel.xReadings.first);
    } else if (_viewmodel.currentShift != null) {
      target = PosReadingEntry.xSnapshot(
        _viewmodel.currentShift!,
        sequence: 0,
        takenAt: DateTime.now(),
      );
    } else {
      final lastClosed = _viewmodel.history
          .where((s) => !s.isOpen)
          .firstOrNull;
      if (lastClosed != null) {
        target = PosReadingEntry.fromClosedShift(lastClosed);
      }
    }

    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No open or closed shift available to preview.'),
        ),
      );
      return;
    }
    showThermalReadingSlipDialog(context, target);
  }

  void _navigateToShifts() {
    context.go(AppRoutes.posShifts);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ShiftViewmodel>.value(
      value: _viewmodel,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.f7):
              _generateInstantXReading,
          const SingleActivator(LogicalKeyboardKey.f10): _openActiveThermalSlip,
        },
        child: Focus(
          autofocus: true,
          child: Consumer<ShiftViewmodel>(
            builder: (context, viewmodel, _) {
              final closedShifts = viewmodel.history
                  .where((shift) => !shift.isOpen)
                  .toList();
              final xEntries = [
                for (final reading in viewmodel.xReadings)
                  PosReadingEntry.fromXReading(reading),
              ];
              final zEntries = [
                for (final shift in closedShifts)
                  PosReadingEntry.fromClosedShift(shift),
              ];
              final allEntries = <PosReadingEntry>[...xEntries, ...zEntries];

              final nothingLoaded =
                  viewmodel.currentShift == null &&
                  viewmodel.history.isEmpty &&
                  viewmodel.xReadings.isEmpty;
              final bannerError =
                  viewmodel.loadError ?? viewmodel.xReadingsError;

              return DashboardShell(
                title: 'Daily X/Z-Reading & Sales Summary',
                subtitle:
                    'Live mid-shift X-readings, end-of-day Z-reading ledger, and 80mm thermal slip preview.',
                selectedNavigationIndex: 10,
                navigationItems: posNavigationItems,
                onNavigationSelected: (i) => navigatePos(context, i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bannerError != null) ...[
                      ErrorBanner(
                        message: bannerError,
                        onRetry: _reloadAll,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _buildActionBar(viewmodel),
                    const SizedBox(height: AppSpacing.md),
                    _buildReadingGuideStrip(),
                    const SizedBox(height: AppSpacing.md),
                    if (viewmodel.currentShift != null ||
                        zEntries.isNotEmpty) ...[
                      _buildStitchSummaryAndFormula(
                        currentShift: viewmodel.currentShift,
                        latestClosed: zEntries.firstOrNull,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _buildSubTabBar(
                      xCount: xEntries.length,
                      zCount: zEntries.length,
                      hasOpenShift: viewmodel.currentShift != null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (viewmodel.isLoading && nothingLoaded)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      switch (_activeTab) {
                        _ReadingsTab.all => _buildAllReadingsTab(allEntries),
                        _ReadingsTab.xReadings => _buildTodayXReadingsTab(
                          viewmodel.currentShift,
                          xEntries,
                          isTakingXReading: viewmodel.isTakingXReading,
                        ),
                        _ReadingsTab.zReadings => _buildDailyZReadingsTab(
                          zEntries,
                        ),
                        _ReadingsTab.monthly => _buildMonthlySummaryTab(
                          closedShifts,
                        ),
                      },
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStitchSummaryAndFormula({
    required Shift? currentShift,
    required PosReadingEntry? latestClosed,
  }) {
    final activeEntry = currentShift != null
        ? PosReadingEntry.xSnapshot(
            currentShift,
            sequence: 0,
            takenAt: DateTime.now(),
          )
        : latestClosed;
    if (activeEntry == null) return const SizedBox.shrink();
    final nonDrawer =
        activeEntry.gcashSales +
        activeEntry.cardSales +
        activeEntry.bankSales +
        activeEntry.chequeSales;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          minTileWidth: 230,
          children: [
            StitchKpiCard(
              label: 'Gross Sales',
              value: formatPeso(activeEntry.grossSales),
              icon: Icons.trending_up_rounded,
              tone: StitchTone.primary,
              subtitle:
                  '${formatCount(activeEntry.transactionCount)} slips · Shift #${activeEntry.shiftId}',
              pillLabel: currentShift != null ? 'Live Shift' : 'Last Closed',
              pillTone: currentShift != null
                  ? StitchTone.success
                  : StitchTone.neutral,
            ),
            StitchKpiCard(
              label: 'Audited Net Sales',
              value: formatPeso(activeEntry.netSales),
              icon: Icons.receipt_long_outlined,
              tone: StitchTone.primary,
              subtitle: 'Discounts: ${formatPeso(activeEntry.discounts)}',
            ),
            StitchKpiCard(
              label: 'Expected Drawer Cash',
              value: formatPeso(activeEntry.expectedCash),
              icon: Icons.payments_outlined,
              tone: StitchTone.success,
              subtitle:
                  'Float ${formatPeso(activeEntry.openingFloat)} + Cash ${formatPeso(activeEntry.cashSales)}',
              pillLabel: activeEntry.variance == null
                  ? 'Accumulating'
                  : (activeEntry.isBalanced
                        ? 'Exact match'
                        : posVarianceText(activeEntry.variance!)),
              pillTone: activeEntry.variance == null
                  ? StitchTone.primary
                  : (activeEntry.isBalanced
                        ? StitchTone.success
                        : StitchTone.danger),
            ),
            StitchKpiCard(
              label: 'Non-Drawer Intake',
              value: formatPeso(nonDrawer),
              icon: Icons.account_balance_outlined,
              tone: StitchTone.neutral,
              subtitle:
                  'GCash ${formatPeso(activeEntry.gcashSales)} · Bank/Cheque/Card',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        StitchSectionCard(
          overline: 'DRAWER CASH FORMULA ARITHMETIC',
          title: 'Expected Drawer Reconciliation (Shift #${activeEntry.shiftId})',
          subtitle:
              'Opening Float + Cash Sales + Cash In − Cash Out = Expected Drawer',
          icon: Icons.calculate_outlined,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StitchPill(
                label: 'Float ${formatPeso(activeEntry.openingFloat)}',
                tone: StitchTone.neutral,
              ),
              const Text('+', style: TextStyle(fontWeight: FontWeight.w700)),
              StitchPill(
                label: 'Cash Sales ${formatPeso(activeEntry.cashSales)}',
                tone: StitchTone.primary,
              ),
              const Text('+', style: TextStyle(fontWeight: FontWeight.w700)),
              StitchPill(
                label: 'Cash In ${formatPeso(activeEntry.cashIn)}',
                tone: StitchTone.success,
              ),
              const Text('−', style: TextStyle(fontWeight: FontWeight.w700)),
              StitchPill(
                label: 'Cash Out ${formatPeso(activeEntry.cashOut)}',
                tone: StitchTone.danger,
              ),
              const Text('=', style: TextStyle(fontWeight: FontWeight.w800)),
              StitchPill(
                label: 'Expected ${formatPeso(activeEntry.expectedCash)}',
                tone: StitchTone.primary,
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(ShiftViewmodel viewmodel) {
    final current = viewmodel.currentShift;
    return AppPanel(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                label: current != null
                    ? 'Register Active · Shift #${current.id}'
                    : 'No Shift Open',
                tone: current != null ? StatusTone.success : StatusTone.neutral,
              ),
              if (current != null)
                Text(
                  'Cashier: ${current.cashierName} · Expected ${formatPeso(current.zReading?.expectedDrawer ?? current.openingFloat)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('readings-generate-x'),
                onPressed: viewmodel.isTakingXReading
                    ? null
                    : _generateInstantXReading,
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      viewmodel.isTakingXReading
                          ? 'Capturing X-Reading…'
                          : 'Generate Instant X-Reading',
                    ),
                    const SizedBox(width: 6),
                    const _ShortcutTag(label: 'F7', onPrimary: true),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('readings-print-slip'),
                onPressed: _openActiveThermalSlip,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Print Reading Slip (80mm)'),
                    SizedBox(width: 6),
                    _ShortcutTag(label: 'F10'),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('readings-reconcile-till'),
                onPressed: _navigateToShifts,
                icon: const Icon(Icons.balance_outlined, size: 18),
                label: Text(
                  current != null ? 'Reconcile Till / Close Shift' : 'Open Shift',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingGuideStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final xCard = _GuideCard(
          badge: 'X',
          title: 'X-Reading (Mid-Shift Audit)',
          tag: 'Non-Resetting',
          description:
              'Captures a live sales and drawer snapshot anytime during shift handover or cash checks without resetting shift totals.',
          accent: AppColors.brandGoldText,
          tint: AppColors.selected,
        );
        final zCard = _GuideCard(
          badge: 'Z',
          title: 'Z-Reading (End-of-Day Close)',
          tag: 'Final Close',
          description:
              'Generated when a shift is counted and closed. Locks final sales totals, cash variance, and denomination counts.',
          accent: AppColors.successText,
          tint: AppColors.successTint,
        );
        if (constraints.maxWidth >= 780) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: xCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: zCard),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            xCard,
            const SizedBox(height: AppSpacing.sm),
            zCard,
          ],
        );
      },
    );
  }

  Widget _buildSubTabBar({
    required int xCount,
    required int zCount,
    required bool hasOpenShift,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _SubTabButton(
            key: const ValueKey('readings-tab-all'),
            label: 'All Readings',
            selected: _activeTab == _ReadingsTab.all,
            onTap: () => setState(() => _activeTab = _ReadingsTab.all),
          ),
          _SubTabButton(
            key: const ValueKey('readings-tab-x'),
            label: "Today's X-Readings",
            badgeText: xCount > 0
                ? '$xCount'
                : (hasOpenShift ? 'Live' : null),
            selected: _activeTab == _ReadingsTab.xReadings,
            onTap: () => setState(() => _activeTab = _ReadingsTab.xReadings),
          ),
          _SubTabButton(
            key: const ValueKey('readings-tab-z'),
            label: 'Daily Z-Readings (EOD)',
            badgeText: zCount > 0 ? '$zCount' : null,
            selected: _activeTab == _ReadingsTab.zReadings,
            onTap: () => setState(() => _activeTab = _ReadingsTab.zReadings),
          ),
          _SubTabButton(
            key: const ValueKey('readings-tab-monthly'),
            label: 'Monthly Summary',
            selected: _activeTab == _ReadingsTab.monthly,
            onTap: () => setState(() => _activeTab = _ReadingsTab.monthly),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Tab 1

  Widget _buildAllReadingsTab(List<PosReadingEntry> allEntries) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = allEntries.where((entry) {
      if (_statusFilter == _ReadingStatusFilter.balanced && !entry.isBalanced) {
        return false;
      }
      if (_statusFilter == _ReadingStatusFilter.variance &&
          !entry.hasVariance) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack =
            '${entry.code} shift #${entry.shiftId} ${entry.cashierName}'
                .toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _FilterPill(
                    key: const ValueKey('readings-filter-all'),
                    label: 'All',
                    selected: _statusFilter == _ReadingStatusFilter.all,
                    onTap: () => setState(
                      () => _statusFilter = _ReadingStatusFilter.all,
                    ),
                  ),
                  _FilterPill(
                    key: const ValueKey('readings-filter-balanced'),
                    label: 'Balanced',
                    selected: _statusFilter == _ReadingStatusFilter.balanced,
                    onTap: () => setState(
                      () => _statusFilter = _ReadingStatusFilter.balanced,
                    ),
                  ),
                  _FilterPill(
                    key: const ValueKey('readings-filter-variance'),
                    label: 'Variance',
                    selected: _statusFilter == _ReadingStatusFilter.variance,
                    onTap: () => setState(
                      () => _statusFilter = _ReadingStatusFilter.variance,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  key: const ValueKey('readings-search-field'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search reading #, cashier, shift…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close, size: 16),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<PosReadingEntry>(
          title: 'Reading Ledger',
          count: filtered.length,
          rows: filtered,
          showPageSizePicker: true,
          columns: _readingColumns(actionLabel: 'Thermal Slip'),
          emptyMessage: allEntries.isEmpty
              ? 'No X-readings or Z-readings recorded yet.'
              : 'No readings match the current filter.',
        ),
      ],
    );
  }

  List<DataPanelColumn<PosReadingEntry>> _readingColumns({
    required String actionLabel,
  }) {
    return [
      DataPanelColumn<PosReadingEntry>(
        label: 'Reading',
        flex: 2,
        cell: (entry) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: entry.isXReading
                    ? AppColors.selected
                    : AppColors.successTint,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.isXReading ? 'X-Reading' : 'Z-Reading',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: entry.isXReading
                      ? AppColors.brandGoldText
                      : AppColors.successText,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '#${entry.code}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Date & Shift',
        flex: 3,
        cell: (entry) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDateTime(entry.timestamp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            Text(
              'Shift #${entry.shiftId}',
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
      DataPanelColumn<PosReadingEntry>(
        label: 'Cashier',
        flex: 2,
        cell: (entry) => Text(
          entry.cashierName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Sales',
        numeric: true,
        cell: (entry) => Text(formatCount(entry.transactionCount)),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Gross Sales',
        numeric: true,
        flex: 2,
        cell: (entry) => Text(
          formatPeso(entry.grossSales),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Discounts',
        numeric: true,
        cell: (entry) => Text(formatPeso(entry.discounts)),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Net Sales',
        numeric: true,
        flex: 2,
        cell: (entry) => Text(
          formatPeso(entry.netSales),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Expected Cash',
        numeric: true,
        flex: 2,
        cell: (entry) => Text(formatPeso(entry.expectedCash)),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Counted Cash',
        numeric: true,
        flex: 2,
        cell: (entry) => entry.countedCash == null
            ? const Text(
                'Live',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              )
            : Text(formatPeso(entry.countedCash!)),
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Variance',
        numeric: true,
        flex: 2,
        cell: (entry) {
          final v = entry.variance;
          if (v == null) {
            return const Text(
              'Not counted',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                posVarianceText(v),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: posVarianceColor(v),
                ),
              ),
              Text(
                v == 0
                    ? 'Exact'
                    : (v > 0 ? 'Over' : 'Short'),
                style: TextStyle(
                  fontSize: 11,
                  color: posVarianceColor(v),
                ),
              ),
            ],
          );
        },
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Status',
        cell: (entry) {
          if (entry.isXReading || entry.variance == null) {
            return const StatusBadge(label: 'Live X', tone: StatusTone.neutral);
          }
          if (entry.isBalanced) {
            return const StatusBadge(
              label: 'Balanced',
              tone: StatusTone.success,
            );
          }
          return StatusBadge(
            label: entry.variance! > 0 ? 'Over' : 'Short',
            tone: entry.variance! > 0 ? StatusTone.warning : StatusTone.error,
          );
        },
      ),
      DataPanelColumn<PosReadingEntry>(
        label: 'Slip',
        flex: 2,
        cell: (entry) => OutlinedButton.icon(
          key: ValueKey('reading-slip-btn-${entry.code}'),
          onPressed: () => showThermalReadingSlipDialog(context, entry),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 34),
            textStyle: const TextStyle(fontSize: 12),
          ),
          icon: const Icon(Icons.receipt_outlined, size: 15),
          label: Text(actionLabel),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------ Tab 2

  Widget _buildTodayXReadingsTab(
    Shift? current,
    List<PosReadingEntry> xEntries, {
    required bool isTakingXReading,
  }) {
    final liveEntry = current == null
        ? null
        : PosReadingEntry.xSnapshot(
            current,
            sequence: 0,
            takenAt: DateTime.now(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current == null)
          AppPanel(
            title: 'Live Open Shift X-Reading',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No shift is currently open on this terminal. Open a shift first to capture live mid-shift X-readings.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _navigateToShifts,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Go to Shifts to Open'),
                ),
              ],
            ),
          )
        else
          AppPanel(
            title: 'Live Open Shift · Shift #${current.id}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cashier: ${current.cashierName}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Opened ${formatDateTime(current.openedAt.toLocal())} · Opening float ${formatPeso(current.openingFloat)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('x-tab-take-snapshot'),
                          onPressed: isTakingXReading
                              ? null
                              : _generateInstantXReading,
                          icon: const Icon(Icons.add_chart_outlined, size: 18),
                          label: Text(
                            isTakingXReading
                                ? 'Capturing…'
                                : 'Take Mid-Shift X-Reading',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('x-tab-view-tape'),
                          onPressed: () =>
                              showThermalReadingSlipDialog(context, liveEntry!),
                          icon: const Icon(Icons.receipt_long_outlined, size: 18),
                          label: const Text('View Slip Tape'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _kpiRow([
                  MetricTile(
                    label: 'Transactions',
                    value: formatCount(liveEntry!.transactionCount),
                  ),
                  MetricTile(
                    label: 'Gross Sales',
                    value: formatPeso(liveEntry.grossSales),
                  ),
                  MetricTile(
                    label: 'Cash Sales',
                    value: formatPeso(liveEntry.cashSales),
                  ),
                  MetricTile(
                    label: 'Expected Cash',
                    value: formatPeso(liveEntry.expectedCash),
                  ),
                ]),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        DataPanel<PosReadingEntry>(
          title: "Today's Captured X-Readings",
          count: xEntries.length,
          rows: xEntries,
          showPageSizePicker: true,
          columns: _readingColumns(actionLabel: 'Thermal Slip'),
          emptyMessage:
              'No mid-shift X-reading snapshots recorded yet. Press Generate Instant X-Reading (F7) to capture one.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ Tab 3

  Widget _buildDailyZReadingsTab(List<PosReadingEntry> zEntries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End-of-Day Z-Readings',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Every closed shift generates a permanent Z-reading with counted cash and variance.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('z-tab-open-shifts'),
                onPressed: _navigateToShifts,
                icon: const Icon(Icons.lock_clock_outlined, size: 18),
                label: const Text('Open Shifts to Close'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<PosReadingEntry>(
          title: 'Closed Shifts Z-Reading Ledger',
          count: zEntries.length,
          rows: zEntries,
          showPageSizePicker: true,
          columns: _readingColumns(actionLabel: 'Inspect Slip'),
          emptyMessage: 'No closed shifts yet.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ Tab 4

  Widget _buildMonthlySummaryTab(List<Shift> closedShifts) {
    final monthShifts = closedShifts.where((shift) {
      final d = (shift.closedAt ?? shift.openedAt).toLocal();
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }).toList();

    final mtdGross = monthShifts.fold<double>(
      0,
      (sum, s) => sum + (s.zReading?.grossSales ?? 0),
    );
    final mtdNet = mtdGross;
    final totalShifts = monthShifts.length;
    final balancedShifts = monthShifts
        .where(
          (s) => s.zReading?.variance != null && s.zReading!.variance!.abs() < 0.005,
        )
        .length;
    final balancedRate = totalShifts == 0
        ? 0.0
        : (balancedShifts / totalShifts) * 100.0;

    // Group by calendar day for Top Revenue Days
    final byDay = <DateTime, ({double gross, int shifts, int txCount})>{};
    for (final shift in monthShifts) {
      final local = (shift.closedAt ?? shift.openedAt).toLocal();
      final dayKey = DateTime(local.year, local.month, local.day);
      final prev = byDay[dayKey];
      byDay[dayKey] = (
        gross: (prev?.gross ?? 0) + (shift.zReading?.grossSales ?? 0),
        shifts: (prev?.shifts ?? 0) + 1,
        txCount: (prev?.txCount ?? 0) + (shift.zReading?.transactionCount ?? 0),
      );
    }
    final topDays = byDay.entries.toList()
      ..sort((a, b) => b.value.gross.compareTo(a.value.gross));
    final maxDayGross = topDays.isEmpty ? 1.0 : math.max(1.0, topDays.first.value.gross);

    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthLabel =
        '${monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Sales & Reconciliation Roll-Up',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Aggregated from closed shift Z-readings for the selected month.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() {
                  _monthPinnedByUser = true;
                  _selectedMonth = DateTime(
                    _selectedMonth.year,
                    _selectedMonth.month - 1,
                  );
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() {
                  _monthPinnedByUser = true;
                  _selectedMonth = DateTime(
                    _selectedMonth.year,
                    _selectedMonth.month + 1,
                  );
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _kpiRow([
          MetricTile(label: 'MTD Gross Sales', value: formatPeso(mtdGross)),
          MetricTile(label: 'MTD Net Sales', value: formatPeso(mtdNet)),
          MetricTile(label: 'Total Shifts', value: formatCount(totalShifts)),
          MetricTile(
            label: 'Balanced Rate',
            value: '${balancedRate.toStringAsFixed(0)}%',
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          title: 'Top Revenue Days',
          child: topDays.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No closed shifts recorded for this month.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < math.min(topDays.length, 7); i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      _TopDayRow(
                        rank: i + 1,
                        date: topDays[i].key,
                        gross: topDays[i].value.gross,
                        shifts: topDays[i].value.shifts,
                        txCount: topDays[i].value.txCount,
                        ratio: (topDays[i].value.gross / maxDayGross).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _kpiRow(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

// ============================================================================
// 80mm Thermal Slip Preview Dialog & Monospace Formatter
// ============================================================================

/// Builds a crisp 80mm monospace register tape string for [entry].
String buildThermalReadingSlipText(PosReadingEntry entry) {
  const width = 42;
  String line(String left, String right) {
    final gap = width - left.length - right.length;
    if (gap >= 1) return '$left${' ' * gap}$right';
    return '$left $right';
  }

  String center(String text) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return '${' ' * pad}$text';
  }

  final divider = '-' * width;
  final heavy = '=' * width;
  final vatableSales = entry.netSales / 1.12;
  final vatAmount = entry.netSales - vatableSales;

  final buf = StringBuffer()
    ..writeln(heavy)
    ..writeln(center('QB HARDWARE POS'))
    ..writeln(
      center(
        entry.isXReading
            ? '*** X-READING (MID-SHIFT AUDIT) ***'
            : '*** Z-READING (END-OF-DAY) ***',
      ),
    )
    ..writeln(heavy)
    ..writeln(line('Reading #:', entry.code))
    ..writeln(line('Shift #:', '${entry.shiftId}'))
    ..writeln(line('Cashier:', entry.cashierName))
    ..writeln(line('Printed:', formatDateTime(entry.timestamp)))
    ..writeln(divider)
    ..writeln('SALES SUMMARY')
    ..writeln(line('Transactions', formatCount(entry.transactionCount)))
    ..writeln(line('Gross Sales', formatPesoForPrint(entry.grossSales)))
    ..writeln(line('Discounts', formatPesoForPrint(entry.discounts)))
    ..writeln(line('Vatable Sales', formatPesoForPrint(vatableSales)))
    ..writeln(line('12% VAT', formatPesoForPrint(vatAmount)))
    ..writeln(line('NET SALES', formatPesoForPrint(entry.netSales)))
    ..writeln(divider)
    ..writeln('TENDER BREAKDOWN')
    ..writeln(line('Cash', formatPesoForPrint(entry.cashSales)))
    ..writeln(line('GCash', formatPesoForPrint(entry.gcashSales)))
    ..writeln(line('Card', formatPesoForPrint(entry.cardSales)))
    ..writeln(line('Bank Transfer', formatPesoForPrint(entry.bankSales)))
    ..writeln(line('Cheque', formatPesoForPrint(entry.chequeSales)))
    ..writeln(divider)
    ..writeln('DRAWER RECONCILIATION')
    ..writeln(line('Opening Float', formatPesoForPrint(entry.openingFloat)))
    ..writeln(line('Cash Sales', formatPesoForPrint(entry.cashSales)))
    ..writeln(line('Cash In', '+${formatPesoForPrint(entry.cashIn)}'))
    ..writeln(line('Cash Out', '-${formatPesoForPrint(entry.cashOut)}'))
    ..writeln(line('Expected Cash', formatPesoForPrint(entry.expectedCash)))
    ..writeln(
      line(
        'Counted Cash',
        entry.countedCash == null
            ? 'NOT COUNTED'
            : formatPesoForPrint(entry.countedCash!),
      ),
    )
    ..writeln(
      line(
        'Variance',
        entry.variance == null
            ? 'LIVE SHIFT'
            : '${posVarianceText(entry.variance!).replaceFirst('₱', 'PHP ')} (${entry.isBalanced ? 'EXACT' : (entry.variance! > 0 ? 'OVER' : 'SHORT')})',
      ),
    );

  if (entry.denominationCounts.isNotEmpty) {
    buf
      ..writeln(divider)
      ..writeln('DENOMINATION SUMMARY');
    for (final d in ShiftCashMovement.phpDenominations) {
      final qty = entry.denominationCounts[d.key] ?? 0;
      if (qty <= 0) continue;
      final label = '${d.label.replaceFirst('₱', 'PHP ')} x $qty';
      buf.writeln(line(label, formatPesoForPrint(d.value * qty)));
    }
  }

  buf
    ..writeln(heavy)
    ..writeln(center('--- END OF READING SLIP ---'));
  return buf.toString();
}

/// Opens the reusable 80mm thermal slip preview dialog for [entry].
Future<void> showThermalReadingSlipDialog(
  BuildContext context,
  PosReadingEntry entry,
) {
  final slipText = buildThermalReadingSlipText(entry);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _ThermalReadingSlipDialog(entry: entry, slipText: slipText),
  );
}

class _ThermalReadingSlipDialog extends StatefulWidget {
  const _ThermalReadingSlipDialog({
    required this.entry,
    required this.slipText,
  });

  final PosReadingEntry entry;
  final String slipText;

  @override
  State<_ThermalReadingSlipDialog> createState() =>
      _ThermalReadingSlipDialogState();
}

class _ThermalReadingSlipDialogState extends State<_ThermalReadingSlipDialog> {
  bool _printing = false;

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: widget.slipText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reading slip copied to clipboard.')),
    );
  }

  Future<void> _printSlip() async {
    setState(() => _printing = true);
    try {
      final saved = await RollPrinter.saved();
      if (saved == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No receipt printer configured. Use Copy Monospace Text or choose a printer in Settings.',
            ),
          ),
        );
        return;
      }
      final job = EscPosJob();
      for (final line in widget.slipText.split('\n')) {
        if (line.trim().isEmpty) continue;
        job.text(line);
      }
      await RollPrinter().print(job.finish(), job: widget.entry.code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent ${widget.entry.code} to ${saved.name}.')),
      );
    } on PrinterException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reach thermal printer. Use Copy Monospace Text instead.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('thermal-slip-dialog'),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '80mm Thermal Slip · ${widget.entry.code}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF7),
              borderRadius: BorderRadius.circular(AppRadii.small),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              widget.slipText,
              key: const ValueKey('thermal-slip-text'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          key: const ValueKey('slip-copy-btn'),
          onPressed: _copyText,
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copy Monospace Text'),
        ),
        FilledButton.icon(
          key: const ValueKey('slip-print-btn'),
          onPressed: _printing ? null : _printSlip,
          icon: const Icon(Icons.print_outlined, size: 16),
          label: Text(_printing ? 'Printing…' : 'Print / Share'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ============================================================================
// Private UI Helpers
// ============================================================================

class _ShortcutTag extends StatelessWidget {
  const _ShortcutTag({required this.label, this.onPrimary = false});

  final String label;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: onPrimary
            ? Colors.white.withValues(alpha: 0.2)
            : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: onPrimary ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.badge,
    required this.title,
    required this.tag,
    required this.description,
    required this.accent,
    required this.tint,
  });

  final String badge;
  final String title;
  final String tag;
  final String description;
  final Color accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  const _SubTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeText,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: selected ? Border.all(color: AppColors.border) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? AppColors.selected : AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.selected : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.brandGold : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.brandGoldText : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TopDayRow extends StatelessWidget {
  const _TopDayRow({
    required this.rank,
    required this.date,
    required this.gross,
    required this.shifts,
    required this.txCount,
    required this.ratio,
  });

  final int rank;
  final DateTime date;
  final double gross;
  final int shifts;
  final int txCount;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.selected,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#$rank',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGoldText,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${formatWeekdayDate(date)} · $shifts ${shifts == 1 ? 'shift' : 'shifts'} · ${formatCount(txCount)} sales',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatPeso(gross),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.surfaceSunken,
            color: AppColors.brandGold,
          ),
        ),
      ],
    );
  }
}
