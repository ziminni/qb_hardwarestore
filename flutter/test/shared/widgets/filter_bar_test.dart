import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// FilterBar is the search field plus chips that every list needs. The narrow
/// case is pumped at 360 px with six chips: that is where a Row used to
/// overflow.
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

  const chips = ['All', 'Cement', 'Steel bars', 'Plywood', 'Paint', 'Plumbing'];

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('shows the search field and the chips at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        FilterBar(
          searchHint: 'Search products',
          options: chips,
          selected: 'All',
          onSelected: (_) {},
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search products'), findsOneWidget);
      for (final chip in chips) {
        expect(find.text(chip), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports the chip that was tapped at $width px', (
      tester,
    ) async {
      final picked = <String>[];
      await pumpAt(
        tester,
        size,
        FilterBar(
          searchHint: 'Search products',
          options: chips,
          selected: 'All',
          onSelected: picked.add,
        ),
      );

      await tester.tap(find.text('Plywood'));
      await tester.pumpAndSettle();
      expect(picked, ['Plywood']);
    });

    testWidgets('fires onSearchChanged as the user types at $width px', (
      tester,
    ) async {
      final typed = <String>[];
      await pumpAt(
        tester,
        size,
        FilterBar(
          searchHint: 'Search products',
          options: chips,
          selected: 'All',
          onSelected: (_) {},
          onSearchChanged: typed.add,
        ),
      );

      await tester.enterText(find.byType(TextField), 'cement');
      await tester.pumpAndSettle();

      expect(typed, ['cement']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wraps six chips at 360 px without an overflow', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 900),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilterBar(
          searchHint: 'Search products',
          options: chips,
          selected: 'Cement',
          onSelected: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // Wrapped, so the chips do not sit on one line: the last chip is below the
    // first one.
    final first = tester.getTopLeft(find.text('All'));
    final last = tester.getTopLeft(find.text('Plumbing'));
    expect(last.dy, greaterThan(first.dy));
    // And nothing is clipped off the right edge.
    expect(
      tester.getTopRight(find.byType(FilterBar)).dx,
      lessThanOrEqualTo(360),
    );
  });

  testWidgets('marks the selected chip differently from the rest', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      FilterBar(
        searchHint: 'Search products',
        options: chips,
        selected: 'Cement',
        onSelected: (_) {},
      ),
    );

    Color? fillOf(String label) {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color;
    }

    expect(fillOf('Cement'), isNot(fillOf('All')));
  });
}
