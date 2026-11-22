import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';

/// The drawer difference as money: `-₱50.00` short, `+₱25.50` over, `₱0.00`
/// exact. Through [formatPeso] so an amount here can never drift from the same
/// amount on any other screen.
String posVarianceText(double variance) =>
    variance > 0 ? '+${formatPeso(variance)}' : formatPeso(variance);

/// The sign's meaning in words, for a cashier who cannot tell red from green.
String posVarianceWord(double variance) {
  if (variance > 0) return 'Over expected cash';
  if (variance < 0) return 'Short of expected cash';
  return 'Matches expected cash';
}

/// Red for money missing, green for money over, plain for a drawer that counts.
/// Zero is neither a warning nor a win, so it stays neutral.
Color posVarianceColor(double variance) {
  if (variance > 0) return AppColors.successText;
  if (variance < 0) return AppColors.errorText;
  return AppColors.textSecondary;
}

/// The end-of-shift summary a cashier reads at the drawer.
///
/// One widget for both places it appears (the Shifts tab and the confirmation
/// after closing from the till), so the two can never disagree about what a
/// Z-reading says. The drawer difference is called out on its own line because
/// it is the one number that means "count the drawer again".
///
/// [title] says WHICH shift the figures belong to. The Shifts tab shows a live
/// shift's running totals or the last closed shift's, and an unlabelled block of
/// money was read as the live drawer.
///
/// [closingCount] is the cash the cashier counted, when the caller has it; it
/// turns the difference into the subtraction that produced it. The wire key is
/// untouched — this is the shift's own `closing_count`.
class PosZReadingSummary extends StatelessWidget {
  const PosZReadingSummary({
    super.key,
    required this.reading,
    this.title = 'Z-READING',
    this.closingCount,
    this.cashLeftInDrawer,
    this.cashMovements = const [],
  });

  final ZReading reading;

  /// The heading above the figures, e.g. `This shift so far`.
  final String title;

  /// Cash counted at the close, or null while the shift is still open.
  final double? closingCount;

  /// What the close said STAYS in the drawer (owner ruling, drawer carry), or
  /// null when it was not recorded - which is not the same as `0.00`.
  final double? cashLeftInDrawer;

  /// Mid-shift cash withdrawals and additions recorded on the shift.
  final List<ShiftCashMovement> cashMovements;

  @override
  Widget build(BuildContext context) {
    final variance = reading.variance;
    return AppPanel(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiles, not a column of label/value lines: the figures are compared
          // sideways (cash against card against GCash).
          //
          // THREE PER LINE, not MetricGrid: this summary also opens inside the
          // AlertDialog that follows a close, and AlertDialog measures its
          // content with intrinsics, which MetricGrid's LayoutBuilder refuses.
          // Fixed rows of Expanded tiles size themselves either way.
          _tileRow([
            MetricTile(
              label: 'Transactions',
              value: formatCount(reading.transactionCount),
            ),
            MetricTile(
              label: 'Gross sales',
              value: formatPeso(reading.grossSales),
            ),
            MetricTile(
              label: 'Cash sales',
              value: formatPeso(reading.cashSales),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          _tileRow([
            MetricTile(label: 'Card', value: formatPeso(reading.cardSales)),
            MetricTile(label: 'GCash', value: formatPeso(reading.gcashSales)),
            MetricTile(
              label: 'Expected cash',
              value: formatPeso(reading.expectedDrawer),
            ),
          ]),
          if (reading.cashOut > 0 || reading.cashIn > 0) ...[
            const SizedBox(height: AppSpacing.md),
            _tileRow([
              MetricTile(
                label: 'Cash taken out',
                value: formatPeso(reading.cashOut),
              ),
              MetricTile(
                label: 'Cash added',
                value: formatPeso(reading.cashIn),
              ),
            ]),
          ],
          // Owner ruling (drawer carry): what stayed behind for the next shift
          // and what was carried to the safe. Shown only when the server had the
          // facts - a null is "not recorded", never printed as 0.00.
          if (cashLeftInDrawer != null || reading.cashTakenOut != null) ...[
            const SizedBox(height: AppSpacing.md),
            _tileRow([
              MetricTile(
                label: 'Left in drawer',
                value: cashLeftInDrawer == null
                    ? 'Not recorded'
                    : formatPeso(cashLeftInDrawer!),
              ),
              MetricTile(
                label: 'Deposit',
                value: reading.cashTakenOut == null
                    ? 'Not recorded'
                    : formatPeso(reading.cashTakenOut!),
              ),
            ]),
          ],
          if (reading.openingDifference != null &&
              reading.openingDifference != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Started ${posVarianceText(reading.openingDifference!)} against '
              'what the previous close left in the drawer.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (cashMovements.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _CashMovementsList(
              movements: cashMovements,
              cashOutByCategory: reading.cashOutByCategory,
            ),
          ],
          if (reading.denominationCounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _DenominationBreakdown(counts: reading.denominationCounts),
          ],
          if (variance != null) ...[
            const SizedBox(height: AppSpacing.md),
            _CashDifferenceCallout(
              variance: variance,
              closingCount: closingCount,
              expectedDrawer: reading.expectedDrawer,
            ),
          ],
          // Advisory (Phase 3 Task 3): parked carts are NOT part of the drawer
          // arithmetic and never block a close, so the line appears only when
          // there are some. Printing "0" on every Z-reading would put a number
          // next to the money that has nothing to do with it.
          if (reading.heldCartCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Held carts',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.warningText,
                    ),
                  ),
                ),
                Text(
                  formatCount(reading.heldCartCount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warningText,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One line of equal tiles. IntrinsicHeight so a tile with a longer label does
  /// not leave its neighbour's border short.
  Widget _tileRow(List<Widget> tiles) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: tiles[index]),
          ],
        ],
      ),
    );
  }
}

class _CashMovementsList extends StatelessWidget {
  const _CashMovementsList({
    required this.movements,
    this.cashOutByCategory = const {},
  });

  final List<ShiftCashMovement> movements;
  final Map<String, double> cashOutByCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drawer cash movements',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          if (cashOutByCategory.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in cashOutByCategory.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${ShiftCashMovement.displayCategory(entry.key)}: ${formatPeso(entry.value)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          for (final movement in movements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  if (movement.isCashOut) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        ShiftCashMovement.displayCategory(movement.category),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      '${movement.isCashOut ? "Cash out" : "Cash in"} · ${movement.reason}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${movement.isCashOut ? "-" : "+"}${formatPeso(movement.amount)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: movement.isCashOut
                          ? AppColors.errorText
                          : AppColors.successText,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _DenominationBreakdown extends StatelessWidget {
  const _DenominationBreakdown({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, int qty, double subtotal})>[
      for (final d in ShiftCashMovement.phpDenominations)
        if ((counts[d.key] ?? 0) > 0)
          (
            label: d.label,
            qty: counts[d.key]!,
            subtotal: d.value * counts[d.key]!,
          ),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('z-reading-denominations'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Counted PHP bills & coins',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${e.label} × ${e.qty} = ${formatPeso(e.subtotal)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one line a cashier acts on: how far the cash counted is from the cash
/// the shift should hold, in words, in colour and with a sign, so the three
/// answers (short, over, matching) cannot be mistaken for each other.
class _CashDifferenceCallout extends StatelessWidget {
  const _CashDifferenceCallout({
    required this.variance,
    required this.closingCount,
    required this.expectedDrawer,
  });

  final double variance;

  /// Cash counted at the close, when the caller has the shift that owns it.
  final double? closingCount;

  final double expectedDrawer;

  @override
  Widget build(BuildContext context) {
    final color = posVarianceColor(variance);
    final tint = variance == 0
        ? AppColors.background
        : (variance > 0 ? AppColors.successTint : AppColors.errorTint);
    final counted = closingCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cash difference',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      posVarianceWord(variance),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                posVarianceText(variance),
                style: TextStyle(
                  fontFamily: AppTextStyles.cinzelFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // The subtraction itself, so the sign can be checked against the drawer.
          Text(
            counted == null
                ? 'Cash counted minus expected cash.'
                : 'Cash counted ${formatPeso(counted)} minus expected '
                      '${formatPeso(expectedDrawer)}.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
