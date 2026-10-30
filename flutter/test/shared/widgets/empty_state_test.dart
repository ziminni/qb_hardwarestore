import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// EmptyState replaces the bare "No ... found." text on every list.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('shows the icon and the message at $width px', (tester) async {
      await pumpAt(
        tester,
        size,
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'No products match this search.',
        ),
      );

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.text('No products match this search.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('runs the action when the button is tapped at $width px', (
      tester,
    ) async {
      var taps = 0;
      await pumpAt(
        tester,
        size,
        EmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'No products match this search.',
          actionLabel: 'Clear search',
          onAction: () => taps++,
        ),
      );

      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('has no action button when no action is given', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      const EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No products match this search.',
      ),
    );

    expect(find.byType(ButtonStyleButton), findsNothing);
  });
}
