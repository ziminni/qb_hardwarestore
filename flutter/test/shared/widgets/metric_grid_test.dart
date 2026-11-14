import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MetricGrid places MetricTiles so a row is FILLED: every tile in a row has
/// the same width, they add up to the available width, and a short last row
/// keeps the column width instead of stretching.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Widget> tiles(int count) => [
    for (var i = 0; i < count; i++)
      MetricTile(
        label: 'Metric $i',
        value: '₱${i}00.00',
        caption: i.isEven ? '$i records' : null,
      ),
  ];

  double widthOf(WidgetTester tester, int index) =>
      tester.getSize(find.byType(MetricTile).at(index)).width;

  testWidgets('at 1440 px four tiles fill one row exactly', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      SizedBox(width: 1440, child: MetricGrid(children: tiles(4))),
    );

    const expected = (1440 - 3 * 12) / 4;
    for (var i = 0; i < 4; i++) {
      expect(
        (widthOf(tester, i) - expected).abs(),
        lessThanOrEqualTo(1),
        reason: 'tile $i width',
      );
      expect(
        tester.getTopLeft(find.byType(MetricTile).at(i)).dy,
        tester.getTopLeft(find.byType(MetricTile).at(0)).dy,
        reason: 'tile $i is on the first row',
      );
    }
    // No leftover gap: the row ends on the right edge.
    expect(
      (tester.getTopRight(find.byType(MetricTile).at(3)).dx - 1440).abs(),
      lessThanOrEqualTo(1),
    );
  });

  testWidgets('at 760 px three fit per row and the orphan keeps that width', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(760, 900),
      SizedBox(width: 760, child: MetricGrid(children: tiles(4))),
    );

    const expected = (760 - 2 * 12) / 3;
    for (var i = 0; i < 3; i++) {
      expect((widthOf(tester, i) - expected).abs(), lessThanOrEqualTo(1));
    }

    // The fourth tile starts a second row, left aligned, same width.
    final firstTile = tester.getTopLeft(find.byType(MetricTile).at(0));
    final orphan = tester.getTopLeft(find.byType(MetricTile).at(3));
    expect(orphan.dy, greaterThan(firstTile.dy));
    expect(orphan.dx, firstTile.dx);
    expect((widthOf(tester, 3) - expected).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('tiles in one row share the tallest height', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      SizedBox(
        width: 1440,
        child: MetricGrid(
          children: const [
            MetricTile(
              label: 'With a caption',
              value: '₱1,234,567.89',
              caption: '26 transactions',
            ),
            MetricTile(label: 'Without a caption', value: '2'),
          ],
        ),
      ),
    );

    final tall = tester.getSize(find.byType(MetricTile).at(0)).height;
    final short = tester.getSize(find.byType(MetricTile).at(1)).height;
    expect(short, tall);
  });

  testWidgets('at 360 px one tile per row and no overflow', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 900),
      SizedBox(width: 360, child: MetricGrid(children: tiles(4))),
    );

    for (var i = 0; i < 4; i++) {
      expect((widthOf(tester, i) - 360).abs(), lessThanOrEqualTo(1));
      if (i > 0) {
        expect(
          tester.getTopLeft(find.byType(MetricTile).at(i)).dy,
          greaterThan(tester.getTopLeft(find.byType(MetricTile).at(i - 1)).dy),
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty grid renders nothing', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      SizedBox(width: 1440, child: MetricGrid(children: const [])),
    );

    expect(find.byType(MetricTile), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
