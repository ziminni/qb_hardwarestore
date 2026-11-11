import 'dart:ui' show PointerDeviceKind;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpShell(
    WidgetTester tester, {
    double width = 1440,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
          home: AppShell(
            title: 'Products',
            subtitle: 'Catalogue',
            fallbackUserName: 'Jane Doe',
            fallbackRoleLabel: 'Stock Manager',
            sections: const [
              SharedSidebarSection(
                label: 'Stock',
                destinations: [
                  SharedSidebarDestination(
                    label: 'Products',
                    icon: Icons.inventory_2,
                  ),
                  SharedSidebarDestination(
                    label: 'Receiving',
                    icon: Icons.move_to_inbox,
                  ),
                ],
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            child: const Text('BODY'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide header shows the pinned local date; compact hides it', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.text('Thu, Oct 15, 2026'), findsOneWidget);
    await pumpShell(tester, width: 760);
    expect(find.text('Thu, Oct 15, 2026'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full sidebar account has readable initials in a hexagon', (
    tester,
  ) async {
    await pumpShell(tester);
    final initials = find.text('JD');
    expect(initials, findsOneWidget);
    final clip = tester.widget<ClipPath>(
      find.ancestor(of: initials, matching: find.byType(ClipPath)),
    );
    expect(clip.clipper, isA<HexagonClipper>());
    // WCAG AA for 12px text: the rendered ink on the rendered fill.
    final fill = tester
        .widget<ColoredBox>(
          find.ancestor(of: initials, matching: find.byType(ColoredBox)).first,
        )
        .color;
    final ink = tester.widget<Text>(initials).style!.color!;
    final lf = fill.computeLuminance(), li = ink.computeLuminance();
    final ratio =
        (lf > li ? lf + 0.05 : li + 0.05) / (lf > li ? li + 0.05 : lf + 0.05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    expect(find.byTooltip('Log out'), findsOneWidget);
  });

  testWidgets(
    'hover makes an unselected destination white and restores it on exit',
    (tester) async {
      await pumpShell(tester);
      final label = find.text('Receiving');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).style?.color, AppColors.brandWhite);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).style?.color, AppColors.chromeText);
    },
  );

  testWidgets('active bar skips its entry animation with reduced motion', (
    tester,
  ) async {
    await pumpShell(tester, reducedMotion: true);
    final tween = find.ancestor(
      of: find.byKey(const ValueKey('sidebar-active-bar')),
      matching: find.byWidgetPredicate(
        (widget) => widget is TweenAnimationBuilder<double>,
      ),
    );
    expect(tween, findsOneWidget);
    expect(
      tester.widget<TweenAnimationBuilder<double>>(tween).duration,
      Duration.zero,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('sidebar-active-bar'))).width,
      3,
    );
  });
}
