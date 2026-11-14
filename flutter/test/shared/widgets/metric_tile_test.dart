import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MetricTile is placed in a wrapping grid by the page; it must fit whatever
/// width the wrap gives it and read label, value, caption and trend.
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

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('renders label, value, caption and trend at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        const SizedBox(
          width: 220,
          child: MetricTile(
            label: 'Today sales',
            value: '₱1,234,567.89',
            caption: '42 transactions',
            trend: '+8.4%',
          ),
        ),
      );

      expect(find.text('Today sales'), findsOneWidget);
      expect(find.text('₱1,234,567.89'), findsOneWidget);
      expect(find.text('42 transactions'), findsOneWidget);
      expect(find.text('+8.4%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('works without a caption or trend at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        const SizedBox(
          width: 220,
          child: MetricTile(label: 'Open shifts', value: '2'),
        ),
      );

      expect(find.text('Open shifts'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a wrapping grid of tiles does not overflow at 760 px', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(760, 900),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final label in ['One', 'Two', 'Three', 'Four'])
              SizedBox(
                width: 220,
                child: MetricTile(label: label, value: '₱9,000.00'),
              ),
          ],
        ),
      ),
    );

    expect(find.byType(MetricTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
