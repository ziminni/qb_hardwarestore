import 'package:client/core/theme/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A table wider than its viewport, the shape of every data table in the app
/// (low stock, products, purchases...): a horizontal scroll view whose last
/// column — usually Actions — starts off-screen on a 1366px laptop.
Widget _wideTable(ScrollController controller, {ScrollBehavior? behavior}) {
  return MaterialApp(
    scrollBehavior: behavior,
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 200,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: const SizedBox(width: 1600, height: 100),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a MOUSE can drag a wide table sideways', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wideTable(controller, behavior: const AppScrollBehavior()),
    );

    await tester.dragFrom(
      const Offset(300, 50),
      const Offset(-250, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('the horizontal scrollbar is always shown, not only on hover', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wideTable(controller, behavior: const AppScrollBehavior()),
    );

    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar));
    expect(bars.any((bar) => bar.thumbVisibility == true), isTrue);
  });

  testWidgets('the stock behavior is what hid the Actions column', (
    tester,
  ) async {
    // Pins WHY the app needs its own behavior: Flutter's default ignores a mouse
    // drag, and a desktop mouse wheel scrolls vertically — so on web, with no
    // trackpad, a clerk had no way to reach the right-hand columns.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wideTable(controller));

    await tester.dragFrom(
      const Offset(300, 50),
      const Offset(-250, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
  });
}
