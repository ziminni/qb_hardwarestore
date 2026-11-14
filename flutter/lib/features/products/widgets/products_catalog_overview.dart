import 'package:client/core/format/format.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';

/// The catalogue's four numbers, above the toolbar.
///
/// Laid out by [MetricGrid], so the tiles fit the width they are given (four
/// across at 1440 px, two at 760 px) instead of a hand-built grid with a fixed
/// 150 px minimum height and a "Click a metric to view related records" line
/// that competed with the heading for room on a narrow window.
class ProductsCatalogOverview extends StatelessWidget {
  const ProductsCatalogOverview({
    super.key,
    required this.totalProducts,
    required this.totalVariants,
    required this.archivedProducts,
    required this.categoryCount,
    required this.brandCount,
    required this.lowStockVariants,
    required this.outOfStockVariants,
    required this.onShowAll,
    required this.onShowLowStock,
  });

  final int totalProducts;
  final int totalVariants;
  final int archivedProducts;
  final int categoryCount;
  final int brandCount;
  final int lowStockVariants;
  final int outOfStockVariants;

  /// Clears the filters, so the tiles that count the catalogue show it whole.
  final VoidCallback onShowAll;

  /// Opens the low stock screen. The two stock numbers are the only ones with a
  /// place to go.
  final VoidCallback onShowLowStock;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _tappable(
        onTap: onShowAll,
        child: MetricTile(
          label: 'TOTAL PRODUCTS',
          value: formatCount(totalProducts),
          caption:
              '${formatCount(categoryCount)} categories, '
              '${formatCount(brandCount)} brands',
        ),
      ),
      _tappable(
        onTap: onShowAll,
        child: MetricTile(
          label: 'CATEGORIES',
          value: formatCount(categoryCount),
          caption: '${formatCount(totalProducts)} catalog products',
        ),
      ),
      _tappable(
        onTap: onShowLowStock,
        child: MetricTile(
          label: 'PRODUCT VARIANTS',
          value: formatCount(totalVariants),
          caption:
              '${formatCount(lowStockVariants)} low stock, '
              '${formatCount(outOfStockVariants)} out of stock',
        ),
      ),
      _tappable(
        onTap: onShowAll,
        child: MetricTile(
          label: 'ARCHIVED',
          value: formatCount(archivedProducts),
          caption: archivedProducts == 0
              ? 'Archive is empty'
              : 'Not shown in the catalogue',
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Four tiles in a row when four comfortable tiles fit, otherwise two:
        // the shared grid picks its own column count from this minimum, and a
        // minimum between the two leaves one tile stranded on its own line.
        // Four tiles plus three 12 px gaps need `4 * 235 + 36` of width.
        final width = constraints.maxWidth;
        final minTileWidth = width >= 4 * 235 + 36 ? 235.0 : (width - 12) / 2;
        return MetricGrid(minTileWidth: minTileWidth, children: tiles);
      },
    );
  }

  /// A tile is a number first; the tap only adds the way to the records behind
  /// it, so the tile keeps no button and no ripple of its own.
  Widget _tappable({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(onTap: onTap, child: child);
  }
}
