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

/// The word that carries the sign's meaning without relying on colour, for a
/// cashier who cannot tell the red from the green.
String posVarianceWord(double variance) {
  if (variance > 0) return 'Over';
  if (variance < 0) return 'Short';
  return 'Exact';
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
/// Z-reading says. Variance is called out on its own line because it is the one
/// number that means "count the drawer again".
///
/// [title] says WHICH shift the figures belong to. The Shifts tab shows a live
/// shift's running totals or the last closed shift's, and an unlabelled block of
/// money was read as the live drawer.
class PosZReadingSummary extends StatelessWidget {
  const PosZReadingSummary({
    super.key,
    required this.reading,
    this.title = 'Z-READING',
  });

  final ZReading reading;

  /// The heading above the figures, e.g. `This shift so far`.
  final String title;

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
            MetricTile(label: 'Cash', value: formatPeso(reading.cashSales)),
          ]),
          const SizedBox(height: AppSpacing.md),
          _tileRow([
            MetricTile(label: 'Card', value: formatPeso(reading.cardSales)),
            MetricTile(label: 'GCash', value: formatPeso(reading.gcashSales)),
            MetricTile(
              label: 'Expected drawer',
              value: formatPeso(reading.expectedDrawer),
            ),
          ]),
          if (variance != null) ...[
            const SizedBox(height: AppSpacing.md),
            _VarianceCallout(variance: variance),
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

/// The one line a cashier acts on: how far the counted cash is from the
/// expected drawer, in words, in colour and with a sign, so the three possible
/// answers (short, over, exact) cannot be mistaken for each other.
class _VarianceCallout extends StatelessWidget {
  const _VarianceCallout({required this.variance});

  final double variance;

  @override
  Widget build(BuildContext context) {
    final color = posVarianceColor(variance);
    final tint = variance == 0
        ? AppColors.background
        : (variance > 0 ? AppColors.successTint : AppColors.errorTint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Variance',
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
    );
  }
}
