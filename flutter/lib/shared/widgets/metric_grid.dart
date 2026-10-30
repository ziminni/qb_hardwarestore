import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Places [MetricTile]s in a row that is filled edge to edge.
///
/// A wrapping `Wrap` full of fixed 220 px boxes leaves a third of a desktop
/// row empty and hands every screen the job of picking a tile width. This grid
/// picks the column width from its own available width: as many columns of at
/// least [minTileWidth] as fit, all of them the same width, adding up to the
/// full width. A short last row keeps that width and stays left aligned.
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.spacing = 12,
  });

  final List<Widget> children;

  /// A tile never gets narrower than this; the column count follows from it.
  final double minTileWidth;

  /// Gap between tiles, both across and down.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Unbounded width (inside a horizontal scroller, say) has no row to
        // fill, so give every tile its minimum.
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : children.length * minTileWidth + spacing * (children.length - 1);

        final maxColumns = math.max(
          1,
          ((available + spacing) / (minTileWidth + spacing)).floor(),
        );
        // Fewer tiles than columns must not leave empty columns behind.
        final columns = math.min(maxColumns, children.length);
        final tileWidth = (available - spacing * (columns - 1)) / columns;

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final row = children.sublist(
            start,
            math.min(start + columns, children.length),
          );
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          // One row is as tall as its tallest tile, so a tile with a caption
          // does not leave its neighbour short.
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < row.length; index++) ...[
                    if (index > 0) SizedBox(width: spacing),
                    SizedBox(width: tileWidth, child: row[index]),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}
