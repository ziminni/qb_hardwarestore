import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The shell follows the window: full sidebar, icon rail, then a drawer.
/// Every role shell wraps the same AppShell, so the POS shell stands in for
/// all of them here.
void main() {
  Future<List<int>> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final taps = <int>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          home: DashboardShell(
            title: 'Point of Sale',
            subtitle: 'New transaction',
            selectedNavigationIndex: 0,
            navigationItems: posNavigationItems,
            onNavigationSelected: taps.add,
            child: const Text('BODY'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return taps;
  }

  testWidgets('a wide window shows the full sidebar with labels', (
    tester,
  ) async {
    final taps = await pumpShell(tester, const Size(1400, 900));

    expect(find.text('Transaction history'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsNothing);
    await tester.tap(find.text('Transaction history'));
    expect(taps, [1]);
  });

  testWidgets('a resized window collapses the sidebar to an icon rail', (
    tester,
  ) async {
    final taps = await pumpShell(tester, const Size(1000, 800));

    // The label moves into a tooltip; the icon is still the way to navigate.
    expect(find.text('Transaction history'), findsNothing);
    expect(find.byTooltip('Transaction history'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsNothing);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    expect(taps, [1]);
  });

  testWidgets('a half-screen window moves the menu into a drawer', (
    tester,
  ) async {
    final taps = await pumpShell(tester, const Size(800, 700));

    expect(find.text('Transaction history'), findsNothing);
    expect(find.byTooltip('Transaction history'), findsNothing);
    expect(find.text('BODY'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction history'), findsOneWidget);

    await tester.tap(find.text('Transaction history'));
    await tester.pumpAndSettle();
    expect(taps, [1]);
    // Choosing a destination closes the drawer.
    expect(find.text('Transaction history'), findsNothing);
  });

  testWidgets('no width between phone and wide desktop overflows the shell', (
    tester,
  ) async {
    for (final width in [600.0, 899.0, 900.0, 1199.0, 1200.0, 1920.0]) {
      await pumpShell(tester, Size(width, 700));
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}
